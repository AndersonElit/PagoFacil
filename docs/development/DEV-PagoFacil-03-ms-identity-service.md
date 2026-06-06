# Etapa 3 — Microservicio: identity-service

**Proyecto:** PagoFacil | **Bounded Context:** BC-01 Identity | **Puerto local:** 8081  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Contexto y Responsabilidad

**Bounded context:** BC-01 Identity — gestión completa del ciclo de vida de la cuenta de usuario.

**Responsabilidad principal:**
- Registro de usuarios con validación de unicidad de email y documento.
- Coordinación del proceso KYC con el proveedor externo (a través de `integration-service`).
- Autenticación multifactor (TOTP, SMS, email) y emisión de JWT vía AWS Cognito.
- Gestión del ciclo de vida: `PENDIENTE_KYC → ACTIVA → SUSPENDIDA / BLOQUEADA`.
- Recuperación segura de contraseñas con token de uso único.

**Dependencias de otros microservicios:**

| Dirección | Servicio | Protocolo | Propósito |
|---|---|---|---|
| Saliente (REST) | `integration-service` | mTLS | Coordinar validación KYC |

**Dependencias de infraestructura:**

| Recurso | Tipo | Propósito |
|---|---|---|
| `pagofacil_identity_service` | PostgreSQL R2DBC | Write side — estado de cuentas |
| `pagofacil.identity.*` | Kafka Producer (Outbox) | Eventos de dominio BC-01 |
| AWS Cognito | OAuth2 / OIDC | Emisión y validación de JWT |

---

## 2. Prerrequisitos

- Etapa 2b completa (CI/CD configurado).
- Secret `pagofacil/dev/identity-service` existe en floci.
- Migraciones Liquibase de `db/identity-service/` aplicadas contra `pagofacil_identity_service`.
- `integration-service` disponible o simulado con WireMock para el flujo de KYC.

---

## 3. Ciclo de Desarrollo Incremental en K3d dev

Con la Etapa 2b completa, cada commit que pasa el pipeline CI despliega automáticamente este servicio en K3d dev vía ArgoCD.

**Condición mínima para el primer despliegue:**
- El contexto Spring arranca sin errores (`Started IdentityServiceApplication in X seconds`).
- `/actuator/health/readiness` responde `{"status":"UP"}` (`readinessProbe` del Helm chart pasa).
- Secret `pagofacil/dev/identity-service` existe en floci.

Esta condición se cumple con el esqueleto generado por el scaffold más la configuración del `application.yml`. No requiere ningún caso de uso implementado.

```
Implementar caso de uso → mvn test (local, Red → Green)
    → git push → Jenkins pipeline (build + tests + quality gate + imagen + bumpImageTag)
    → ArgoCD sync → K3d dev → endpoint disponible
```

> **Regla TDD:** la prueba de cada capa se escribe y se ve **fallar (Red)** ANTES de implementar el código de producción. Las secciones 4 a 7 describen QUÉ implementar; la Sección 8 especifica la prueba que precede a cada elemento.

---

## 4. Capa de Dominio (`domain`) — _test-first_

### Entidades

| Entidad | Campos clave | Reglas de negocio |
|---|---|---|
| `User` | `userId (UUID)`, `tenantId (UUID)`, `email (Email VO)`, `fullName`, `documentType`, `documentNumber`, `accountStatus` | Email único; documento (tipo+número) único; `accountStatus` solo puede transicionar por métodos explícitos del aggregate |
| `KycRegistration` | `kycId`, `userId`, `providerReference`, `result (KycResult)`, `documentData (JsonNode)`, `submittedAt`, `resolvedAt` | Inmutable una vez `result = APROBADO` o `RECHAZADO`; no permite UPDATE |
| `AuthenticationCredentials` | `credentialId`, `userId`, `passwordHash`, `failedAttempts`, `lockedAt` | Hash Argon2/bcrypt; bloqueo tras N intentos fallidos (N configurable); desbloqueo solo por admin |
| `MfaConfig` | `mfaId`, `userId`, `mfaType (MfaType)`, `isActive`, `secretEnc` | `secretEnc` cifrado en capa de aplicación; un MFA activo por tipo por usuario |
| `ActiveSession` | `sessionId`, `userId`, `cognitoSub`, `ipAddress`, `userAgent`, `expiresAt`, `invalidatedAt` | Sesión inválida si `invalidatedAt IS NOT NULL` o `expiresAt < now()` |

### Value Objects

| VO | Regla de validación |
|---|---|
| `Email` | Formato RFC 5322; longitud ≤ 320 |
| `DocumentNumber` | No vacío; longitud ≤ 50 |
| `PasswordHash` | No puede ser texto plano; requiere prefijo de algoritmo (Argon2 o bcrypt) |
| `MfaCode` | Longitud exacta 6; solo dígitos |

### Eventos de dominio

| Evento | Payload mínimo | Topic Kafka |
|---|---|---|
| `UsuarioRegistrado` | `userId`, `email`, `tenantId`, `createdAt` | `pagofacil.identity.usuario-registrado` |
| `CuentaActivada` | `userId`, `tenantId`, `activatedAt` | `pagofacil.identity.cuenta-activada` |
| `SesionIniciada` | `userId`, `sessionId`, `ipAddress`, `initiatedAt` | `pagofacil.identity.sesion-iniciada` |
| `CuentaBloqueada` | `userId`, `reason`, `blockedAt` | `pagofacil.identity.cuenta-bloqueada` |
| `PasswordResetSolicitado` | `userId`, `tokenExpiry` | `pagofacil.identity.password-reset-solicitado` |

### Puertos secundarios (interfaces del dominio)

```java
// UserRepository
Mono<User> findById(UUID userId);
Mono<User> findByEmail(Email email);
Mono<Boolean> existsByEmailOrDocument(Email email, String docType, String docNumber);
Mono<User> save(User user);

// KycRegistrationRepository
Mono<KycRegistration> save(KycRegistration reg);
Mono<KycRegistration> findByUserId(UUID userId);

// AuthCredentialRepository
Mono<AuthenticationCredentials> findByUserId(UUID userId);
Mono<AuthenticationCredentials> save(AuthenticationCredentials creds);

// MfaConfigRepository
Flux<MfaConfig> findActiveByUserId(UUID userId);
Mono<MfaConfig> save(MfaConfig mfa);

// SessionRepository
Mono<ActiveSession> save(ActiveSession session);
Mono<Void> invalidateByUserId(UUID userId);

// OutboxRepository
Mono<Void> save(OutboxEvent event);

// IdentityEventPublisher
Mono<Void> publish(DomainEvent event);
```

### Invariantes de dominio

- Un usuario no puede activarse si `kycRegistration.result != APROBADO`.
- Un usuario `BLOQUEADO` no puede iniciar sesión ni solicitar recuperación de contraseña.
- `failedAttempts >= maxAllowed` → bloqueo automático (transición `ACTIVA → BLOQUEADA`).
- La tabla `authentication_credentials` no almacena contraseñas en texto plano bajo ninguna circunstancia.
- El `secretEnc` de `mfa_configs` debe estar cifrado (AES-256) antes de persistir.

---

## 5. Capa de Aplicación (`application`) — _test-first_

### Casos de uso

| Use Case | Descripción | Puerto primario | Puertos secundarios |
|---|---|---|---|
| `RegisterUserUseCase` | Crea usuario en `PENDIENTE_KYC`; inicia proceso KYC vía `integration-service`; publica `UsuarioRegistrado` por Outbox | `RegisterUserInputPort` | `UserRepository`, `AuthCredentialRepository`, `OutboxRepository`, `KycGateway` |
| `VerifyLoginUseCase` | Primer factor: valida credenciales, incrementa `failedAttempts`, retorna `mfaSessionToken` temporal | `VerifyLoginInputPort` | `UserRepository`, `AuthCredentialRepository` |
| `VerifyMfaUseCase` | Segundo factor: valida código MFA; emite JWT vía Cognito; crea `ActiveSession`; publica `SesionIniciada` | `VerifyMfaInputPort` | `UserRepository`, `MfaConfigRepository`, `SessionRepository`, `CognitoPort`, `OutboxRepository` |
| `RequestPasswordRecoveryUseCase` | Genera token de recuperación de uso único; publica `PasswordResetSolicitado` | `PasswordRecoveryInputPort` | `UserRepository`, `OutboxRepository` |
| `ResetPasswordUseCase` | Valida token de recuperación; actualiza hash de contraseña; invalida sesiones activas | `ResetPasswordInputPort` | `AuthCredentialRepository`, `SessionRepository` |
| `GetKycStatusUseCase` | Retorna el estado actual del proceso KYC del usuario | `GetKycStatusInputPort` | `KycRegistrationRepository` |
| `CompensateAccountActivationUseCase` | Idempotente — revierte la activación de cuenta en saga KYC | `CompensateInputPort` | `UserRepository`, `SessionRepository` |

### DTOs principales

| Use Case | Input DTO | Output DTO |
|---|---|---|
| `RegisterUserUseCase` | `RegisterUserCommand(email, fullName, docType, docNumber, password, tenantId)` | `UserCreatedResponse(userId, email, accountStatus, createdAt)` |
| `VerifyLoginUseCase` | `LoginCommand(email, password)` | `MfaSessionResponse(mfaSessionToken, mfaType)` |
| `VerifyMfaUseCase` | `MfaVerifyCommand(mfaSessionToken, mfaCode)` | `SessionResponse(accessToken, expiresIn)` |

---

## 6. Capa de Infraestructura (`infrastructure`) — _test-first_

### Adaptadores R2DBC

| Adaptador | Tablas | Operaciones principales |
|---|---|---|
| `UserR2dbcAdapter` | `users` | `findById`, `findByEmail`, `existsByEmailOrDocument`, `save` |
| `KycRegistrationR2dbcAdapter` | `kyc_registrations` | `save`, `findByUserId` |
| `AuthCredentialR2dbcAdapter` | `authentication_credentials` | `findByUserId`, `save` |
| `MfaConfigR2dbcAdapter` | `mfa_configs` | `findActiveByUserId`, `save` |
| `SessionR2dbcAdapter` | `active_sessions` | `save`, `invalidateByUserId` |
| `OutboxR2dbcAdapter` | `outbox` | `save` (parte de la misma transacción R2DBC) |

### Productores Kafka (Outbox relay)

| Tópico | Evento | Cuándo se publica |
|---|---|---|
| `pagofacil.identity.usuario-registrado` | `UsuarioRegistrado` | Al crear usuario exitosamente |
| `pagofacil.identity.cuenta-activada` | `CuentaActivada` | Al aprobar KYC y activar cuenta |
| `pagofacil.identity.sesion-iniciada` | `SesionIniciada` | Al completar autenticación MFA |
| `pagofacil.identity.cuenta-bloqueada` | `CuentaBloqueada` | Al superar intentos fallidos |
| `pagofacil.identity.password-reset-solicitado` | `PasswordResetSolicitado` | Al iniciar recuperación de contraseña |

### Clientes REST (WebClient)

| Gateway | Endpoint | Propósito |
|---|---|---|
| `IntegrationServiceGateway` | `POST /v1/integration/sagas` (mTLS) | Iniciar saga KYC para validación del proveedor externo |

### Configuración de seguridad

- Endpoints `/v1/identity/auth/**` y `POST /v1/identity/users`: públicos (sin JWT).
- `GET /v1/identity/users/me/kyc-status`: requiere JWT Bearer (Cognito).
- `POST /v1/identity/users/{userId}/compensar`: requiere mTLS (solo `integration-service`).
- Hash de contraseña: `PasswordEncoder` con Argon2 (`spring-security-crypto`).

---

## 7. API REST (`rest-api`) — _test-first_

Especificación completa: `docs/design/api/SDD-PagoFacil-openapi.yaml` — tag `Identity`

| Método | Ruta | Request Body | Response | Códigos HTTP |
|---|---|---|---|---|
| POST | `/v1/identity/users` | `RegistroUsuarioRequest` | `UsuarioResponse` | 201, 409, 422 |
| POST | `/v1/identity/auth/login` | `LoginRequest` | `LoginParcialResponse` | 200, 401, 423 |
| POST | `/v1/identity/auth/mfa/verify` | `MfaVerifyRequest` | `SesionResponse` | 200, 401 |
| POST | `/v1/identity/auth/password/recover-request` | `PasswordRecoverRequest` | — | 202 |
| POST | `/v1/identity/auth/password/reset` | `PasswordResetRequest` | — | 204, 400 |
| GET | `/v1/identity/users/me/kyc-status` | — | `KycStatusResponse` | 200, 401 |
| POST | `/v1/identity/users/{userId}/compensar` | `CompensacionRequest` | — | 200, 404 |

Implementación: Router Functions WebFlux (no `@RestController`).

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> **Regla:** cada prueba se escribe y se ve **fallar (Red)** antes de escribir el código de producción que la hace **pasar (Green)**, seguido de **Refactor**. Tipos reactivos verificados con `StepVerifier`, nunca `block()`.

### Dominio

| Clase de test | Método | Invariante / regla | Elemento de Sección 4 que precede |
|---|---|---|---|
| `UserTest` | `shouldNotAllowActivationWithoutApprovedKyc` | Usuario no activa sin KYC aprobado | Entidad `User` |
| `UserTest` | `shouldLockAccountAfterMaxFailedAttempts` | Bloqueo tras N intentos | Entidad `User` + VO `failedAttempts` |
| `UserTest` | `shouldRejectInvalidEmail` | Formato email inválido → excepción | VO `Email` |
| `MfaCodeTest` | `shouldRejectCodeWithWrongLength` | MFA code ≠ 6 dígitos → excepción | VO `MfaCode` |
| `PasswordHashTest` | `shouldRejectPlainTextPassword` | Hash con prefijo de algoritmo obligatorio | VO `PasswordHash` |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case de Sección 5 |
|---|---|---|---|---|
| `RegisterUserUseCaseTest` | `shouldCreateUserAndPublishEvent` | Happy path: email y documento únicos | `UserRepository` (mock), `OutboxRepository` (mock), `KycGateway` (mock) | `RegisterUserUseCase` |
| `RegisterUserUseCaseTest` | `shouldFailOnDuplicateEmail` | Email duplicado → `DuplicateUserException` | `UserRepository` (devuelve `exists=true`) | `RegisterUserUseCase` |
| `VerifyLoginUseCaseTest` | `shouldReturnMfaTokenOnValidCredentials` | Happy path | `AuthCredentialRepository` (mock), `UserRepository` (mock) | `VerifyLoginUseCase` |
| `VerifyLoginUseCaseTest` | `shouldIncrementFailedAttemptsOnWrongPassword` | Contraseña incorrecta | `AuthCredentialRepository` (mock) | `VerifyLoginUseCase` |
| `VerifyLoginUseCaseTest` | `shouldThrowOnLockedAccount` | Cuenta bloqueada → `AccountLockedException` | `UserRepository` (devuelve BLOQUEADA) | `VerifyLoginUseCase` |
| `VerifyMfaUseCaseTest` | `shouldEmitJwtOnValidMfaCode` | Happy path: TOTP válido | `MfaConfigRepository` (mock), `CognitoPort` (mock), `SessionRepository` (mock) | `VerifyMfaUseCase` |
| `VerifyMfaUseCaseTest` | `shouldFailOnExpiredMfaSession` | Token temporal expirado | — | `VerifyMfaUseCase` |
| `CompensateAccountActivationUseCaseTest` | `shouldBeIdempotentOnRepeatedCall` | Segunda llamada no cambia estado | `UserRepository` (mock devuelve estado ya compensado) | `CompensateAccountActivationUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador de Sección 6 |
|---|---|---|---|
| `UserR2dbcAdapterTest` | `shouldSaveAndFindUser` | INSERT + SELECT con Testcontainers PostgreSQL | `UserR2dbcAdapter` |
| `UserR2dbcAdapterTest` | `shouldReturnMonoEmptyOnNotFound` | SELECT sin resultado → `Mono.empty()` | `UserR2dbcAdapter` |
| `AuthCredentialR2dbcAdapterTest` | `shouldIncrementFailedAttempts` | UPDATE en `failed_attempts` | `AuthCredentialR2dbcAdapter` |
| `OutboxR2dbcAdapterTest` | `shouldPersistEventAtomicallyWithUserSave` | INSERT usuario + INSERT outbox en misma transacción R2DBC | `OutboxR2dbcAdapter` |
| `OutboxR2dbcAdapterTest` | `shouldNotPublishTwiceOnRedelivery` | Relay idempotente | Outbox relay |

### REST

| Clase de test | Método | Endpoint | Status / body esperado | Elemento de Sección 7 |
|---|---|---|---|---|
| `IdentityControllerTest` | `shouldReturn201OnValidRegistration` | `POST /v1/identity/users` | 201 + `userId` en body | `POST /v1/identity/users` |
| `IdentityControllerTest` | `shouldReturn409OnDuplicateEmail` | `POST /v1/identity/users` | 409 | `POST /v1/identity/users` |
| `IdentityControllerTest` | `shouldReturn200OnValidLogin` | `POST /v1/identity/auth/login` | 200 + `mfaSessionToken` | `POST /v1/identity/auth/login` |
| `IdentityControllerTest` | `shouldReturn423OnLockedAccount` | `POST /v1/identity/auth/login` | 423 | `POST /v1/identity/auth/login` |
| `IdentityControllerTest` | `shouldReturn200OnValidMfaVerify` | `POST /v1/identity/auth/mfa/verify` | 200 + `accessToken` | `POST /v1/identity/auth/mfa/verify` |
| `IdentityControllerTest` | `shouldReturn200IdempotentOnCompensacion` | `POST /v1/identity/users/{userId}/compensar` | 200 (segunda llamada también) | Endpoint compensación |

### Umbrales de cobertura mínima

| Capa | Umbral |
|---|---|
| `domain` | ≥ 90% |
| `application` | ≥ 85% |
| `infrastructure` | ≥ 80% |
| `rest-api` | ≥ 80% |

---

## 9. Criterios de Aceptación

- [ ] Cada elemento de cada capa tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] `mvn test` finaliza en verde (0 fallos, 0 errores).
- [ ] La cobertura por capa cumple los umbrales declarados (SonarQube confirma).
- [ ] No existe lógica de negocio ni rama de error sin prueba asociada.
- [ ] `POST /v1/identity/users` retorna 201 con `userId` y `accountStatus: PENDIENTE_KYC`.
- [ ] `POST /v1/identity/auth/login` retorna 200 con `mfaSessionToken` para credenciales válidas; 401 para inválidas; 423 para cuenta bloqueada.
- [ ] `POST /v1/identity/auth/mfa/verify` retorna 200 con `accessToken` para código MFA correcto.
- [ ] Cuenta queda `BLOQUEADA` tras alcanzar el máximo de intentos fallidos configurado.
- [ ] Registro de usuario genera evento `UsuarioRegistrado` en el tópico `pagofacil.identity.usuario-registrado` vía Outbox.
- [ ] El endpoint de compensación `POST /v1/identity/users/{userId}/compensar` es idempotente.
- [ ] El pipeline CI despliega el servicio en K3d: `kubectl get pods -n dev | grep identity-service` muestra `Running`.
- [ ] ArgoCD muestra `identity-service` en estado `Synced`.
