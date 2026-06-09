# Etapa 3a — Microservicio: identity-service

**Proyecto:** PagoFacil — Billetera Digital Multitenancy
**Bounded Context:** BC-01 Identity
**Servicio:** identity-service
**Puerto local:** 8081
**Versión:** 1.0
**Fecha:** 2026-06-08

---

## 1. Contexto y Responsabilidad

### 1.1 Bounded Context BC-01 Identity

El `identity-service` es el guardián de la identidad digital dentro de PagoFacil. Es el único servicio autorizado para crear usuarios, gestionar el ciclo de vida de cuentas, coordinar el proceso KYC y emitir/revocar sesiones mediante AWS Cognito. Ningún otro microservicio puede modificar el estado de un usuario directamente; deben comunicarse a través de eventos Kafka o llamadas REST autorizadas.

### 1.2 Responsabilidades

| Responsabilidad | Descripción |
|---|---|
| Registro de usuarios | Validación de unicidad email+tenant_id, formato de campos y creación del registro con estado PENDING |
| Coordinación KYC | Publicación de evento `UserRegistered` → integration-service inicia verificación con proveedor externo |
| Autenticación primer factor | Validación email+password con bcrypt/Argon2, conteo de intentos fallidos y bloqueo automático |
| Gestión MFA | Soporte TOTP (RFC 6238), SMS OTP y EMAIL OTP; secret cifrado AES-256 |
| Emisión de sesiones | Delegada a AWS Cognito User Pool via SDK; identity-service persiste metadatos de sesión |
| Ciclo de vida de cuenta | Gestión de transiciones: PENDING → ACTIVE \| SUSPENDED \| BLOCKED |
| Publicación de eventos | UserRegistered, KYCApproved, KYCRejected, AccountSuspendedByAML via outbox Kafka |
| Compensación de saga | Reversión idempotente del onboarding si una saga coordinada falla |

### 1.3 Dependencias de Infraestructura

| Dependencia | Tipo | Propósito |
|---|---|---|
| PostgreSQL 16 — `pagofacil_identity_service` | Base de datos OLTP | Persistencia de usuarios, KYC, MFA, sesiones y outbox |
| Apache Kafka 3 (KRaft) | Mensajería asíncrona | Publicación de eventos de dominio y consumo de resultados KYC |
| AWS Cognito (floci) | Servicio externo emulado | Emisión y revocación de tokens JWT (access + refresh) |
| floci `<VPS_IP>:4566` | Emulación AWS | Cognito User Pool en ambiente dev |
| LRA Coordinator `<VPS_IP>:50000` | Saga/LRA Narayana | Coordinación de sagas distribuidas (DEPOSIT, TRANSFER, ONBOARDING) |

### 1.4 Dependencias REST

| Dirección | Servicio | Protocolo | Descripción |
|---|---|---|---|
| Entrante | API Gateway | REST/HTTPS | Todas las peticiones de clientes pasan por el gateway |
| Saliente | Ninguna directa | — | La comunicación con integration-service es exclusivamente vía Kafka |

---

## 2. Prerrequisitos

### 2.1 Etapas Previas Completadas

- [ ] **Etapa 0** — Infraestructura VPS: K3s, namespaces `pagofacil-dev`, ArgoCD operativo
- [ ] **Etapa 0c** — Observabilidad: Prometheus, Grafana, Loki, OTel Collector desplegados
- [ ] **Etapa 1** — Base de datos `pagofacil_identity_service` creada; usuario `pagofacil_app` con privilegios DML; migraciones Liquibase ejecutadas (`users`, `kyc_records`, `mfa_devices`, `sessions`, `outbox`, `processed_message`)
- [ ] **Etapa 2** — Scaffolding `identity-service` generado: estructura Maven multimódulo, Dockerfile, Helm chart en Gitea, Jenkinsfile, `.env.dev`
- [ ] **Etapa 2b** — Pipeline Jenkins configurado; ArgoCD Application `identity-service` apuntando a `pagofacil-gitops/identity-service/dev`

### 2.2 Servicios Corriendo en VPS

| Servicio | Verificación |
|---|---|
| PostgreSQL 16 — `pagofacil_identity_service` | `psql -h <VPS_IP> -U pagofacil_app -d pagofacil_identity_service -c "SELECT 1"` |
| Apache Kafka 3 | `kafka-topics.sh --bootstrap-server <VPS_IP>:9092 --list` |
| floci Cognito | `curl http://<VPS_IP>:4566/_localstack/health \| jq '.services.cognito'` |
| LRA Coordinator | `curl http://<VPS_IP>:50000/lra-coordinator` → 200 |
| K3s + ArgoCD | `kubectl get pods -n argocd` → todos Running |

### 2.3 Secret en floci

El secret `pagofacil/dev/identity-service` debe existir en floci antes del primer despliegue:

```bash
floci secretsmanager create-secret \
  --name "pagofacil/dev/identity-service" \
  --secret-string '{
    "DB_URL": "r2dbc:postgresql://<VPS_IP>:5432/pagofacil_identity_service",
    "DB_USER": "pagofacil_app",
    "DB_PASSWORD": "<CLAVE_APP>",
    "COGNITO_USER_POOL_ID": "us-east-1_DEV00001",
    "COGNITO_CLIENT_ID": "<CLIENT_ID>",
    "COGNITO_CLIENT_SECRET": "<CLIENT_SECRET>",
    "MFA_AES_KEY": "<AES_256_KEY_BASE64>",
    "KAFKA_BOOTSTRAP_SERVERS": "<VPS_IP>:9092",
    "JWT_JWKS_URI": "http://<VPS_IP>:4566/us-east-1_DEV00001/.well-known/jwks.json",
    "MAX_FAILED_LOGIN_ATTEMPTS": "5",
    "ACCOUNT_LOCK_DURATION_MINUTES": "30"
  }'
```

---

## 3. Ciclo de Desarrollo Incremental en K3s VPS dev

### 3.1 Condición Mínima del Primer Despliegue

Antes de implementar cualquier caso de uso, el primer commit al repositorio debe satisfacer:

1. Spring Boot arranca sin errores (`ApplicationContext` cargado completamente).
2. `GET /actuator/health/readiness` responde `{"status":"UP"}`.
3. Conexión R2DBC a `pagofacil_identity_service` establecida (DataSource healthy).
4. Secret `pagofacil/dev/identity-service` existe en floci y es leído por la app.

### 3.2 Diagrama del Ciclo por Caso de Uso

```
Implementar caso de uso → mvn test (local) → git push → Jenkins pipeline → push Gitea registry → bumpImageTag → ArgoCD sync → K3s VPS → endpoint disponible
```

Desglose de cada paso:

| Paso | Herramienta | Acción |
|---|---|---|
| Implementar caso de uso | Local IDE | Escribir prueba (Red) → implementar (Green) → refactorizar |
| `mvn test` | Maven 3.9 / Java 21 | Suite completa: dominio + aplicación + infra (Testcontainers) + REST |
| `git push` | Gitea | Trigger automático del pipeline Jenkins vía webhook |
| Jenkins pipeline | Jenkins | Checkout → `mvn verify` → SonarQube → `docker build` → push imagen |
| Push Gitea registry | `<VPS_IP>:3000/pagofacil` | Imagen `identity-service:<sha>` disponible en registro |
| `bumpImageTag` | Jenkins | Actualiza `values-dev.yaml` en repo `pagofacil-gitops` con nuevo SHA |
| ArgoCD sync | ArgoCD | Detecta cambio en gitops repo → sincroniza → `kubectl rollout` |
| K3s VPS | K3s namespace `pagofacil-dev` | Pod reemplazado; readiness probe debe pasar |
| Endpoint disponible | API Gateway / NodePort | Endpoint probado con `curl` o Postman |

> **TDD obligatorio**: cada prueba de la Sección 8 se escribe y se ve **FALLAR (Red)** antes de implementar el código de producción (**Green**), seguido de **Refactor**. Ningún caso de uso ni rama de error puede existir sin una prueba que lo respalde.

---

## 4. Capa de Dominio (`domain`)

### 4.1 Estructura del Módulo

```
identity-service/
  domain/
    src/
      main/java/com/pagofacil/identity/domain/
        model/
          User.java
          KycRecord.java
          MfaDevice.java
          Session.java
        valueobject/
          UserId.java
          TenantId.java
          Email.java
          PasswordHash.java
          KycStatus.java
          UserStatus.java
        event/
          UserRegisteredEvent.java
          KycApprovedEvent.java
          KycRejectedEvent.java
          AccountSuspendedByAmlEvent.java
        port/
          UserRepository.java
          KycRecordRepository.java
          MfaDeviceRepository.java
          SessionRepository.java
          OutboxRepository.java
          CognitoPort.java
      test/java/com/pagofacil/identity/domain/
        model/
          UserTest.java
          KycRecordTest.java
          MfaDeviceTest.java
          SessionTest.java
```

### 4.2 Entidad `User`

**Campos clave:** `id` (UUID), `tenantId`, `email`, `phoneNumber`, `fullName`, `dateOfBirth`, `documentType`, `documentId`, `passwordHash`, `status` (PENDING|ACTIVE|SUSPENDED|BLOCKED), `failedLoginAttempts`, `lockedUntil`, `createdAt`, `updatedAt`.

**Reglas de negocio:**

| Regla | Descripción | Método |
|---|---|---|
| Unicidad email+tenant_id | Dos usuarios en el mismo tenant no pueden tener el mismo email | Invariante verificada en `UserRepository` antes del `save` |
| Estado inicial | Todo usuario nuevo nace en PENDING | Constructor `User.register(...)` fija `status = PENDING` |
| Bloqueo automático | Tras `MAX_FAILED_LOGIN_ATTEMPTS` (configurable, defecto 5) intentos fallidos consecutivos, el estado pasa a BLOCKED y se fija `lockedUntil = now + lockDuration` | `User.incrementFailedAttempts(int max, Duration lockDuration)` |
| Reseteo de intentos | Un login exitoso resetea `failedLoginAttempts = 0` y `lockedUntil = null` | `User.resetFailedAttempts()` |
| Transiciones de estado válidas | PENDING→ACTIVE (KYC aprobado), ACTIVE→SUSPENDED (AML), ACTIVE→BLOCKED (intentos), SUSPENDED→ACTIVE (revisión manual) | `User.transitionTo(UserStatus)` lanza `InvalidStatusTransitionException` si la transición no es permitida |
| Password hash | `passwordHash` debe ser resultado de bcrypt/Argon2; el dominio no cifra, recibe el hash ya calculado desde la capa de aplicación | Campo inmutable tras la creación; se reemplaza solo via `User.changePassword(PasswordHash)` |

### 4.3 Entidad `KycRecord`

**Campos clave:** `id` (UUID), `userId`, `status` (PENDING|APPROVED|REJECTED|SUSPENDED), `providerReference`, `verificationResult` (mapa JSON), `verifiedAt`, `rejectedReason`, `createdAt`, `updatedAt`.

**Transiciones de estado:**

```
PENDING → APPROVED  (resultado positivo del proveedor)
PENDING → REJECTED  (resultado negativo del proveedor)
APPROVED → SUSPENDED (AML posterior)
```

`KycRecord.approve(String providerReference, Map<String,Object> result)` fija `status = APPROVED`, `verifiedAt = now`.
`KycRecord.reject(String providerReference, String reason)` fija `status = REJECTED`.

### 4.4 Entidad `MfaDevice`

**Campos clave:** `id` (UUID), `userId`, `deviceType` (TOTP|SMS_OTP|EMAIL_OTP), `deviceIdentifier`, `secretEncrypted` (AES-256 GCM, Base64), `isActive`, `createdAt`.

**Reglas:**
- `secretEncrypted` nunca se expone en texto plano desde el dominio.
- Un usuario puede tener múltiples dispositivos MFA, pero solo uno activo por tipo.
- `MfaDevice.deactivate()` marca `isActive = false`.

### 4.5 Entidad `Session`

**Campos clave:** `id` (UUID), `userId`, `tenantId`, `refreshTokenHash` (SHA-256 del refresh token), `accessTokenJti`, `ipAddress`, `userAgent`, `expiresAt`, `revokedAt`, `createdAt`.

**Reglas:**
- `refreshTokenHash` es único en la tabla (UNIQUE constraint).
- `Session.revoke()` fija `revokedAt = now`; sesiones revocadas no pueden emitir nuevos access tokens.
- `Session.isExpired()` retorna `true` si `expiresAt.isBefore(Instant.now())`.
- `Session.isValid()` retorna `true` si no está revocada y no está expirada.

### 4.6 Value Objects

| Value Object | Invariantes |
|---|---|
| `UserId` | UUID no nulo; inmutable |
| `TenantId` | UUID o string alfanumérico no nulo; inmutable |
| `Email` | Formato RFC 5322 validado; lower-case normalizado en constructor |
| `PasswordHash` | String no nulo, longitud mínima 60 chars (bcrypt) o 95 chars (Argon2) |
| `KycStatus` | Enum: PENDING, APPROVED, REJECTED, SUSPENDED |
| `UserStatus` | Enum: PENDING, ACTIVE, SUSPENDED, BLOCKED |

### 4.7 Eventos de Dominio

| Evento | Campos clave | Publicado cuando |
|---|---|---|
| `UserRegisteredEvent` | `userId`, `tenantId`, `email`, `fullName`, `documentType`, `documentId`, `correlationId`, `occurredAt` | Usuario creado con status PENDING |
| `KycApprovedEvent` | `userId`, `tenantId`, `kycRecordId`, `providerReference`, `correlationId`, `occurredAt` | KycRecord transicionado a APPROVED |
| `KycRejectedEvent` | `userId`, `tenantId`, `kycRecordId`, `rejectedReason`, `correlationId`, `occurredAt` | KycRecord transicionado a REJECTED |
| `AccountSuspendedByAmlEvent` | `userId`, `tenantId`, `reason`, `correlationId`, `occurredAt` | User transicionado a SUSPENDED por AML |

### 4.8 Puertos Secundarios (Interfaces)

```java
// UserRepository
public interface UserRepository {
    Mono<User> findByEmailAndTenantId(Email email, TenantId tenantId);
    Mono<User> findById(UserId id);
    Mono<User> save(User user);
}

// KycRecordRepository
public interface KycRecordRepository {
    Mono<KycRecord> findByUserId(UserId userId);
    Mono<KycRecord> save(KycRecord record);
}

// MfaDeviceRepository
public interface MfaDeviceRepository {
    Flux<MfaDevice> findActiveByUserId(UserId userId);
    Mono<MfaDevice> save(MfaDevice device);
}

// SessionRepository
public interface SessionRepository {
    Mono<Session> findByRefreshTokenHash(String hash);
    Mono<Session> save(Session session);
    Mono<Void> revokeAllByUserId(UserId userId);
}

// OutboxRepository
public interface OutboxRepository {
    Mono<Void> save(OutboxMessage message);
}

// CognitoPort
public interface CognitoPort {
    Mono<TokenResponse> issueTokens(UserId userId, TenantId tenantId, String username);
    Mono<Void> revokeRefreshToken(String refreshToken);
}
```

---

## 5. Capa de Aplicación (`application`)

### 5.1 Casos de Uso

| Caso de Uso | Clase | Entrada | Salida |
|---|---|---|---|
| Registro de usuario | `RegisterUserUseCase` | `RegisterRequest` | `Mono<Void>` (202 implícito) |
| Autenticación primer factor | `LoginUseCase` | `LoginRequest` | `Mono<MfaChallengeResponse>` |
| Verificación MFA | `VerifyMfaUseCase` | `MfaVerifyRequest` | `Mono<TokenResponse>` |
| Renovación de token | `RefreshTokenUseCase` | `RefreshTokenRequest` | `Mono<TokenResponse>` |
| Cierre de sesión | `LogoutUseCase` | `LogoutRequest` | `Mono<Void>` |
| Consulta de perfil | `GetUserProfileUseCase` | `UserId` | `Mono<UserProfileResponse>` |
| Actualización de perfil | `UpdateUserProfileUseCase` | `UserId`, `UpdateProfileRequest` | `Mono<UserProfileResponse>` |
| Consulta estado KYC | `GetKycStatusUseCase` | `UserId` | `Mono<KycStatusResponse>` |
| Procesamiento resultado KYC | `ProcessKycResultUseCase` | `KycResultEvent` | `Mono<Void>` |
| Compensación onboarding | `CompensateOnboardingUseCase` | `UserId`, `correlationId` | `Mono<Void>` (idempotente) |

### 5.2 DTOs Clave

**`RegisterRequest`**
```java
public record RegisterRequest(
    String tenantId,
    String email,
    String password,           // texto plano; se hashea en use case
    String fullName,
    String phoneNumber,
    String dateOfBirth,        // ISO-8601
    String documentType,       // DNI, PASAPORTE, etc.
    String documentId,
    String correlationId
) {}
```

**`LoginRequest`**
```java
public record LoginRequest(
    String tenantId,
    String email,
    String password,
    String ipAddress,
    String userAgent
) {}
```

**`MfaVerifyRequest`**
```java
public record MfaVerifyRequest(
    String challengeToken,    // token opaco emitido en el login challenge
    String otpCode,
    String deviceType         // TOTP | SMS_OTP | EMAIL_OTP
) {}
```

**`TokenResponse`**
```java
public record TokenResponse(
    String accessToken,
    String refreshToken,
    long expiresIn,
    String tokenType          // "Bearer"
) {}
```

**`MfaChallengeResponse`**
```java
public record MfaChallengeResponse(
    String challengeToken,    // JWT de corta duración (5 min) para el segundo factor
    String availableMfaTypes, // "TOTP,SMS_OTP"
    String maskedPhoneNumber  // "+54 9 11 ****-7890"
) {}
```

**`UserProfileResponse`**
```java
public record UserProfileResponse(
    String userId,
    String tenantId,
    String email,
    String fullName,
    String phoneNumber,
    String status,
    String kycStatus,
    Instant createdAt
) {}
```

### 5.3 Flujo de Orquestación: `RegisterUserUseCase`

```
RegisterRequest recibido
        │
        ▼
Validar formato email, password, documentId
        │ falla → lanzar ValidationException (→ 422)
        ▼
UserRepository.findByEmailAndTenantId(email, tenantId)
        │ existe → lanzar DuplicateEmailException (→ 409)
        ▼
Hashear password (Argon2id)
        │
        ▼
Crear entidad User (status=PENDING, failedLoginAttempts=0)
        │
        ▼
UserRepository.save(user)
        │
        ▼
Crear KycRecord (status=PENDING, userId=user.id)
        │
        ▼
KycRecordRepository.save(kycRecord)
        │
        ▼
Crear UserRegisteredEvent con correlationId
        │
        ▼
OutboxRepository.save(OutboxMessage {
  aggregateType: "User",
  aggregateId: userId,
  eventType: "UserRegistered",
  topic: "pagofacil.identity.user-registered",
  payload: UserRegisteredEvent,
  status: PENDING
})
        │
        ▼
Retornar Mono<Void>  (HTTP 202 al caller)
```

> **Nota de transaccionalidad**: los pasos `UserRepository.save`, `KycRecordRepository.save` y `OutboxRepository.save` deben ejecutarse dentro de una única transacción R2DBC. El outbox garantiza que el evento se publique a Kafka exactamente cuando la transacción de negocio commitea.

---

## 6. Capa de Infraestructura (`infrastructure`)

### 6.1 Adaptador R2DBC — `UserR2dbcRepository`

**Tablas gestionadas:** `users`

| Operación | SQL / Spring Data |
|---|---|
| `findByEmailAndTenantId` | `SELECT * FROM users WHERE email = :email AND tenant_id = :tenantId` |
| `findById` | `SELECT * FROM users WHERE id = :id` |
| `save` | `INSERT INTO users ... ON CONFLICT (id) DO UPDATE SET ...` |

Implementa el puerto `UserRepository`. Utiliza `DatabaseClient` de R2DBC para las operaciones que requieren SQL nativo; `R2dbcEntityTemplate` para el mapeo de entidades.

### 6.2 Adaptador R2DBC — `KycRecordR2dbcRepository`

**Tablas gestionadas:** `kyc_records`

| Operación | Descripción |
|---|---|
| `findByUserId` | Busca el registro KYC activo de un usuario |
| `save` | INSERT con ON CONFLICT DO UPDATE |

### 6.3 Adaptador R2DBC — `SessionR2dbcRepository`

**Tablas gestionadas:** `sessions`

| Operación | Descripción |
|---|---|
| `findByRefreshTokenHash` | Busca sesión activa por hash del refresh token |
| `save` | Persiste nueva sesión |
| `revokeAllByUserId` | `UPDATE sessions SET revoked_at = now() WHERE user_id = :userId AND revoked_at IS NULL` |

### 6.4 Adaptador R2DBC — `MfaDeviceR2dbcRepository`

**Tablas gestionadas:** `mfa_devices`

Implementa `MfaDeviceRepository`. El campo `secret_encrypted` se almacena y recupera como texto Base64 (AES-256 GCM aplicado por `MfaEncryptionService` en la capa de aplicación).

### 6.5 Productor Kafka — Outbox Relay

El relay publica mensajes de la tabla `outbox` con `status = PENDING` a los tópicos Kafka correspondientes.

**Tópicos publicados:**

| Tópico | Evento | Particionado por |
|---|---|---|
| `pagofacil.identity.user-registered` | `UserRegisteredEvent` | `tenantId` |
| `pagofacil.identity.kyc-approved` | `KycApprovedEvent` | `tenantId` |
| `pagofacil.identity.kyc-rejected` | `KycRejectedEvent` | `tenantId` |
| `pagofacil.identity.account-suspended-by-aml` | `AccountSuspendedByAmlEvent` | `tenantId` |

**Estructura del evento Kafka (envelope):**

```json
{
  "eventId": "uuid-v4",
  "eventType": "UserRegistered",
  "aggregateType": "User",
  "aggregateId": "uuid-del-usuario",
  "correlationId": "uuid-de-la-operacion",
  "tenantId": "uuid-del-tenant",
  "occurredAt": "2026-06-08T14:30:00Z",
  "payload": { ... }
}
```

**Relay por polling:**

```
@Scheduled(fixedDelay = 500ms)
OutboxRelay.publishPending():
  SELECT * FROM outbox WHERE status = 'PENDING' ORDER BY created_at LIMIT 100
  Para cada mensaje:
    KafkaProducer.send(topic, key=tenantId, value=mensaje)
    UPDATE outbox SET status='PUBLISHED', published_at=now() WHERE id=:id
    En caso de error: UPDATE outbox SET status='FAILED' WHERE id=:id
```

### 6.6 Consumidor Kafka — Resultado KYC del integration-service

**Tópico consumido:** `pagofacil.integration.kyc-result`

**Grupo de consumidores:** `identity-service-kyc-result`

**Flujo de procesamiento:**

```
Mensaje recibido → verificar processed_message (idempotencia)
        │ ya procesado → ACK y descarte
        ▼
Deserializar KycResultEvent
        │
        ▼
ProcessKycResultUseCase.execute(event)
        │ APPROVED → KycRecord.approve() + User.transitionTo(ACTIVE) + publicar KycApprovedEvent en outbox
        │ REJECTED → KycRecord.reject() + publicar KycRejectedEvent en outbox
        ▼
INSERT INTO processed_message (message_id, consumer, processed_at)
        │
        ▼
ACK a Kafka
```

### 6.7 Adaptador `CognitoAdapter`

Implementa `CognitoPort` usando `software.amazon.awssdk:cognito-idp` v2 con endpoint custom apuntando a `http://<VPS_IP>:4566`.

| Método | Operación Cognito |
|---|---|
| `issueTokens(userId, tenantId, username)` | `AdminInitiateAuth` con `ADMIN_USER_PASSWORD_AUTH`; retorna `AccessToken` + `RefreshToken` |
| `revokeRefreshToken(refreshToken)` | `RevokeToken` |

Configuración en `application.yml`:
```yaml
aws:
  cognito:
    endpoint-override: http://<VPS_IP>:4566
    region: us-east-1
    user-pool-id: ${COGNITO_USER_POOL_ID}
    client-id: ${COGNITO_CLIENT_ID}
    client-secret: ${COGNITO_CLIENT_SECRET}
```

### 6.8 Spring Security — Validación JWT

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          jwk-set-uri: ${JWT_JWKS_URI}
```

El filtro de seguridad extrae del JWT:
- `sub` → `userId`
- `custom:tenant_id` → `tenantId`
- `cognito:groups` → roles

Los endpoints `/auth/register` y `/auth/login` son públicos (`.permitAll()`). Los demás requieren token válido.

### 6.9 Módulo Outbox — Idempotencia

**Tabla `outbox`:** gestiona mensajes pendientes de publicación a Kafka.

**Tabla `processed_message`:** registra mensajes Kafka consumidos (idempotencia de consumo).

```sql
-- processed_message
CREATE TABLE processed_message (
    message_id   VARCHAR(255) NOT NULL,
    consumer     VARCHAR(100) NOT NULL,
    processed_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (message_id, consumer)
);
```

Verificación de idempotencia antes de procesar:
```sql
INSERT INTO processed_message (message_id, consumer, processed_at)
VALUES (:messageId, :consumer, now())
ON CONFLICT (message_id, consumer) DO NOTHING
RETURNING message_id
```
Si no retorna filas, el mensaje ya fue procesado: se ignora.

---

## 7. API REST (`rest-api`)

### 7.1 Tabla de Endpoints

| Método | Ruta | Auth | Request Body | Response Body | Códigos HTTP |
|---|---|---|---|---|---|
| POST | `/auth/register` | Público | `RegisterRequest` | `{ "message": "KYC iniciado" }` | 202, 409, 422 |
| POST | `/auth/login` | Público | `LoginRequest` | `MfaChallengeResponse` | 200, 401, 423 |
| POST | `/auth/mfa/verify` | Público | `MfaVerifyRequest` | `TokenResponse` | 200, 401 |
| POST | `/auth/refresh` | Público | `{ "refreshToken": "..." }` | `TokenResponse` | 200, 401 |
| POST | `/auth/logout` | Bearer JWT | `{ "refreshToken": "..." }` | — | 204, 401 |
| GET | `/users/{userId}` | Bearer JWT | — | `UserProfileResponse` | 200, 404 |
| PUT | `/users/{userId}/profile` | Bearer JWT | `UpdateProfileRequest` | `UserProfileResponse` | 200, 404, 422 |
| GET | `/users/{userId}/kyc-status` | Bearer JWT | — | `KycStatusResponse` | 200, 404 |
| POST | `/users/{userId}/compensar` | Interno (LRA) | `{ "correlationId": "..." }` | `{ "compensated": true }` | 200 |

**Descripción de códigos de error:**
- `409` — Email ya registrado en el mismo tenant
- `422` — Error de validación de campos (body con lista de errores)
- `423` — Cuenta bloqueada (body incluye `lockedUntil`)
- `401` — Credenciales inválidas o token expirado

### 7.2 Configuración — Router Functions WebFlux

```java
@Configuration
public class IdentityRouterConfig {

    @Bean
    public RouterFunction<ServerResponse> authRoutes(AuthHandler handler) {
        return RouterFunctions.route()
            .POST("/auth/register",    handler::register)
            .POST("/auth/login",       handler::login)
            .POST("/auth/mfa/verify",  handler::verifyMfa)
            .POST("/auth/refresh",     handler::refresh)
            .POST("/auth/logout",      handler::logout)
            .build();
    }

    @Bean
    public RouterFunction<ServerResponse> userRoutes(UserHandler handler) {
        return RouterFunctions.route()
            .GET("/users/{userId}",               handler::getProfile)
            .PUT("/users/{userId}/profile",       handler::updateProfile)
            .GET("/users/{userId}/kyc-status",    handler::getKycStatus)
            .POST("/users/{userId}/compensar",    handler::compensate)
            .build();
    }
}
```

### 7.3 Especificación OpenAPI

Ubicación: `docs/design/api/SDD-PagoFacil-openapi.yaml`

Tags aplicables a identity-service: `Auth`, `Users`

Los endpoints de este servicio están agrupados bajo los tags `Auth` (rutas `/auth/**`) y `Users` (rutas `/users/**`). El documento OpenAPI es la fuente de verdad del contrato de la API; cualquier cambio en los endpoints debe reflejarse primero en el YAML y luego implementarse.

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> **Regla fundamental**: cada prueba listada en esta sección se escribe **primero** y se verifica que **FALLA (Red)** antes de escribir una sola línea del código de producción. Solo entonces se implementa el mínimo código necesario para que **PASE (Green)**. Finalmente se **Refactoriza** sin romper la prueba.
>
> Los tipos reactivos (`Mono`, `Flux`) se verifican **siempre** con `StepVerifier`. El uso de `.block()` en pruebas está **prohibido**.

### 8.1 Pruebas de Dominio

| Clase de Test | Método | Invariante / Regla de Negocio | Elemento de §4 que Precede |
|---|---|---|---|
| `UserTest` | `shouldCreateUserWithPendingStatus` | Usuario nuevo siempre inicia en PENDING | `User.register(...)` |
| `UserTest` | `shouldBlockUserAfterMaxFailedAttempts` | Tras N intentos fallidos → status BLOCKED + lockedUntil fijado | `User.incrementFailedAttempts(int, Duration)` |
| `UserTest` | `shouldNotBlockUserBeforeMaxFailedAttempts` | N-1 intentos no bloquean la cuenta | `User.incrementFailedAttempts(int, Duration)` |
| `UserTest` | `shouldResetFailedAttemptsOnSuccessfulLogin` | Login exitoso → failedLoginAttempts = 0, lockedUntil = null | `User.resetFailedAttempts()` |
| `UserTest` | `shouldTransitionFromPendingToActiveWhenKycApproved` | PENDING → ACTIVE es transición válida | `User.transitionTo(UserStatus)` |
| `UserTest` | `shouldThrowExceptionOnInvalidStatusTransition` | BLOCKED → ACTIVE directo no está permitido | `User.transitionTo(UserStatus)` lanza `InvalidStatusTransitionException` |
| `UserTest` | `shouldNormalizEmailToLowercase` | Email almacenado siempre en minúsculas | `Email` value object |
| `KycRecordTest` | `shouldCreateKycRecordWithPendingStatus` | KycRecord nuevo inicia en PENDING | `KycRecord` constructor |
| `KycRecordTest` | `shouldTransitionToApprovedWithVerifiedAt` | `approve()` fija status APPROVED y verifiedAt | `KycRecord.approve(...)` |
| `KycRecordTest` | `shouldTransitionToRejectedWithReason` | `reject()` fija status REJECTED y rejectedReason | `KycRecord.reject(...)` |
| `KycRecordTest` | `shouldThrowOnInvalidKycTransition` | APPROVED → PENDING no está permitido | `KycRecord` transiciones |
| `MfaDeviceTest` | `shouldNotExposeSecretInPlainText` | `secretEncrypted` nunca iguala al secret original (string plano) | `MfaDevice` campo `secretEncrypted` |
| `MfaDeviceTest` | `shouldDeactivateDevice` | `deactivate()` fija `isActive = false` | `MfaDevice.deactivate()` |
| `SessionTest` | `shouldBeValidWhenNotExpiredAndNotRevoked` | Sesión válida si expiresAt > now y revokedAt == null | `Session.isValid()` |
| `SessionTest` | `shouldBeInvalidWhenRevoked` | `revoke()` invalida la sesión | `Session.revoke()` |
| `SessionTest` | `shouldBeInvalidWhenExpired` | Sesión con expiresAt en el pasado es inválida | `Session.isExpired()` |

**Ejemplo de prueba de dominio (Red primero):**

```java
@DisplayName("AC-DOM-01: Bloqueo automático tras máximo de intentos fallidos")
@Test
void shouldBlockUserAfterMaxFailedAttempts() {
    User user = User.register(
        TenantId.of("tenant-1"), Email.of("test@pagofacil.com"),
        PasswordHash.of("$argon2id$..."), "Juan Pérez", "+5491112345678",
        LocalDate.of(1990, 1, 1), "DNI", "12345678"
    );

    int maxAttempts = 5;
    Duration lockDuration = Duration.ofMinutes(30);

    for (int i = 0; i < maxAttempts; i++) {
        user.incrementFailedAttempts(maxAttempts, lockDuration);
    }

    assertThat(user.getStatus()).isEqualTo(UserStatus.BLOCKED);
    assertThat(user.getLockedUntil()).isAfter(Instant.now());
}
```

### 8.2 Pruebas de Aplicación

| Clase de Test | Método | Escenario | Puertos Mockeados | Caso de Uso que Precede |
|---|---|---|---|---|
| `RegisterUserUseCaseTest` | `shouldRegisterUserAndPublishEvent_whenEmailIsUnique` | Happy path: email único → usuario creado + outbox guardado | `UserRepository`, `KycRecordRepository`, `OutboxRepository` | `RegisterUserUseCase` |
| `RegisterUserUseCaseTest` | `shouldThrowDuplicateEmailException_whenEmailAlreadyExists` | Email duplicado en mismo tenant → excepción 409 | `UserRepository` retorna usuario existente | `RegisterUserUseCase` |
| `RegisterUserUseCaseTest` | `shouldThrowValidationException_whenEmailFormatIsInvalid` | Email con formato inválido → excepción 422 | Ninguno (falla antes de consultar repo) | `RegisterUserUseCase` |
| `LoginUseCaseTest` | `shouldReturnMfaChallenge_whenCredentialsAreValid` | Credenciales correctas, cuenta ACTIVE → MfaChallengeResponse | `UserRepository` | `LoginUseCase` |
| `LoginUseCaseTest` | `shouldThrowInvalidCredentialsException_whenPasswordIsWrong` | Password incorrecto → excepción 401 + incremento de intentos | `UserRepository` | `LoginUseCase` |
| `LoginUseCaseTest` | `shouldBlockUser_whenMaxAttemptsExceeded` | N-ésimo intento fallido → cuenta BLOCKED, excepción 423 | `UserRepository` | `LoginUseCase` |
| `LoginUseCaseTest` | `shouldThrowAccountBlockedException_whenAccountIsAlreadyBlocked` | Cuenta ya BLOCKED → excepción 423 inmediata sin verificar password | `UserRepository` retorna usuario BLOCKED | `LoginUseCase` |
| `VerifyMfaUseCaseTest` | `shouldReturnTokens_whenTotpCodeIsValid` | TOTP válido → `CognitoPort.issueTokens()` invocado → TokenResponse | `MfaDeviceRepository`, `CognitoPort`, `SessionRepository` | `VerifyMfaUseCase` |
| `VerifyMfaUseCaseTest` | `shouldThrowException_whenTotpCodeIsExpired` | TOTP con ventana de tiempo expirada → excepción 401 | `MfaDeviceRepository` | `VerifyMfaUseCase` |
| `RefreshTokenUseCaseTest` | `shouldReturnNewAccessToken_whenRefreshTokenIsValid` | Refresh token válido → nuevo access token via Cognito | `SessionRepository`, `CognitoPort` | `RefreshTokenUseCase` |
| `RefreshTokenUseCaseTest` | `shouldThrowException_whenRefreshTokenIsRevoked` | Sesión revocada → excepción 401 | `SessionRepository` retorna sesión revocada | `RefreshTokenUseCase` |
| `ProcessKycResultUseCaseTest` | `shouldApproveKycAndActivateUser_whenProviderApproves` | Evento KYC APPROVED → KycRecord.approve() + User.transitionTo(ACTIVE) + outbox | `KycRecordRepository`, `UserRepository`, `OutboxRepository` | `ProcessKycResultUseCase` |
| `ProcessKycResultUseCaseTest` | `shouldRejectKycAndKeepUserPending_whenProviderRejects` | Evento KYC REJECTED → KycRecord.reject() + outbox | `KycRecordRepository`, `OutboxRepository` | `ProcessKycResultUseCase` |
| `CompensateOnboardingUseCaseTest` | `shouldBeIdempotent_whenCalledMultipleTimes` | Compensación invocada 2 veces con mismo correlationId → mismo resultado, sin duplicados | `UserRepository`, `processed_message (mock)` | `CompensateOnboardingUseCase` |

**Ejemplo de prueba de aplicación (StepVerifier, Red primero):**

```java
@DisplayName("AC-APP-01: Registro exitoso publica evento en outbox cuando el email es único")
@Test
void shouldRegisterUserAndPublishEvent_whenEmailIsUnique() {
    when(userRepository.findByEmailAndTenantId(any(), any()))
        .thenReturn(Mono.empty());
    when(userRepository.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));
    when(kycRecordRepository.save(any())).thenAnswer(inv -> Mono.just(inv.getArgument(0)));
    when(outboxRepository.save(any())).thenReturn(Mono.empty());

    RegisterRequest request = new RegisterRequest(
        "tenant-1", "nuevo@pagofacil.com", "P@ssw0rd!",
        "Juan Pérez", "+5491112345678", "1990-01-01",
        "DNI", "12345678", "corr-001"
    );

    StepVerifier.create(registerUserUseCase.execute(request))
        .verifyComplete();

    verify(outboxRepository, times(1)).save(argThat(msg ->
        "UserRegistered".equals(msg.getEventType()) &&
        "pagofacil.identity.user-registered".equals(msg.getTopic())
    ));
}
```

### 8.3 Pruebas de Infraestructura

> Usar **Testcontainers** para PostgreSQL (`testcontainers:postgresql`) y Kafka (`testcontainers:kafka`). Las pruebas de infraestructura se ejecutan con el perfil `@Tag("integration")`.

| Clase de Test | Método | Operación | Adaptador que Precede |
|---|---|---|---|
| `UserR2dbcRepositoryTest` | `shouldSaveAndFindUserByEmailAndTenantId` | `save` + `findByEmailAndTenantId` en PostgreSQL real (Testcontainers) | `UserR2dbcRepository` |
| `UserR2dbcRepositoryTest` | `shouldReturnEmptyWhenUserNotFound` | `findById` con UUID inexistente → `Mono.empty()` | `UserR2dbcRepository` |
| `UserR2dbcRepositoryTest` | `shouldEnforceUniqueEmailPerTenant` | INSERT duplicado → error de constraint | `UserR2dbcRepository` |
| `KycRecordR2dbcRepositoryTest` | `shouldSaveAndFindKycRecordByUserId` | `save` + `findByUserId` | `KycRecordR2dbcRepository` |
| `SessionR2dbcRepositoryTest` | `shouldRevokeAllSessionsByUserId` | `revokeAllByUserId` → todas las sesiones tienen revokedAt != null | `SessionR2dbcRepository` |
| `OutboxRelayTest` | `shouldPublishPendingMessagesToKafka` | Relay polling: INSERT en outbox → relay publica en Kafka → status = PUBLISHED (Testcontainers Kafka) | `OutboxRelay` |
| `OutboxRelayTest` | `shouldMarkMessageAsFailedWhenKafkaIsDown` | Kafka no disponible → mensaje marcado como FAILED | `OutboxRelay` |
| `KafkaKycResultConsumerTest` | `shouldProcessKycResultEventIdempotently` | Mismo mensaje consumido 2 veces → `processed_message` previene doble procesamiento | `KycResultConsumer` |
| `CognitoAdapterTest` | `shouldIssueTokensForValidUser` | `issueTokens()` contra floci → retorna `TokenResponse` con accessToken y refreshToken | `CognitoAdapter` |

**Ejemplo de prueba de infraestructura (Testcontainers, Red primero):**

```java
@Tag("integration")
@DisplayName("AC-INFRA-01: Relay publica mensajes pendientes del outbox a Kafka")
@Test
void shouldPublishPendingMessagesToKafka() {
    // Arrange: insertar mensaje PENDING en outbox
    outboxRepository.save(OutboxMessage.builder()
        .aggregateType("User").aggregateId(userId.toString())
        .eventType("UserRegistered")
        .topic("pagofacil.identity.user-registered")
        .payload(samplePayload())
        .status(OutboxStatus.PENDING)
        .build()
    ).block(); // solo en setup de prueba de infra, no en pruebas de dominio/app

    // Act: ejecutar un ciclo del relay
    StepVerifier.create(outboxRelay.publishPending())
        .verifyComplete();

    // Assert: mensaje publicado en Kafka y marcado como PUBLISHED
    ConsumerRecord<String, String> record = KafkaTestUtils.getSingleRecord(
        kafkaConsumer, "pagofacil.identity.user-registered"
    );
    assertThat(record.value()).contains("UserRegistered");

    StepVerifier.create(outboxRepository.findById(messageId))
        .assertNext(msg -> assertThat(msg.getStatus()).isEqualTo(OutboxStatus.PUBLISHED))
        .verifyComplete();
}
```

### 8.4 Pruebas REST

> Usar **`WebTestClient`** con `@WebFluxTest` + mocks de los casos de uso. No levantar contexto completo ni base de datos.

| Clase de Test | Método | Endpoint + Status / Body | Elemento de §7 que Precede |
|---|---|---|---|
| `AuthControllerTest` | `shouldReturn202WhenRegistrationAccepted` | POST `/auth/register` → 202 + body `{"message":"KYC iniciado"}` | Endpoint `POST /auth/register` |
| `AuthControllerTest` | `shouldReturn409WhenEmailDuplicated` | POST `/auth/register` → 409 cuando `RegisterUserUseCase` lanza `DuplicateEmailException` | Endpoint `POST /auth/register` |
| `AuthControllerTest` | `shouldReturn422WhenRequestBodyIsInvalid` | POST `/auth/register` sin campos requeridos → 422 con lista de errores | Endpoint `POST /auth/register` |
| `AuthControllerTest` | `shouldReturn200WithMfaChallenge_whenLoginSucceeds` | POST `/auth/login` → 200 + `MfaChallengeResponse` | Endpoint `POST /auth/login` |
| `AuthControllerTest` | `shouldReturn401WhenCredentialsAreInvalid` | POST `/auth/login` → 401 | Endpoint `POST /auth/login` |
| `AuthControllerTest` | `shouldReturn423WhenAccountBlocked` | POST `/auth/login` → 423 + `{"lockedUntil":"..."}` cuando `LoginUseCase` lanza `AccountBlockedException` | Endpoint `POST /auth/login` |
| `AuthControllerTest` | `shouldReturn200WithTokens_whenMfaVerified` | POST `/auth/mfa/verify` → 200 + `TokenResponse` | Endpoint `POST /auth/mfa/verify` |
| `AuthControllerTest` | `shouldReturn204OnLogout` | POST `/auth/logout` → 204 | Endpoint `POST /auth/logout` |
| `UserControllerTest` | `shouldReturn200WithUserProfile` | GET `/users/{userId}` → 200 + `UserProfileResponse` | Endpoint `GET /users/{userId}` |
| `UserControllerTest` | `shouldReturn404WhenUserNotFound` | GET `/users/{userId}` → 404 cuando `GetUserProfileUseCase` retorna `Mono.empty()` | Endpoint `GET /users/{userId}` |
| `UserControllerTest` | `shouldReturn200WithKycStatus` | GET `/users/{userId}/kyc-status` → 200 + `{"status":"PENDING"}` | Endpoint `GET /users/{userId}/kyc-status` |
| `UserControllerTest` | `shouldReturn200WhenCompensationIsIdempotent` | POST `/users/{userId}/compensar` → 200 + `{"compensated":true}`, segunda llamada igual resultado | Endpoint `POST /users/{userId}/compensar` |

**Ejemplo de prueba REST (WebTestClient, Red primero):**

```java
@WebFluxTest(AuthHandler.class)
@DisplayName("AC-REST-01: POST /auth/register retorna 202 cuando el registro es aceptado")
@Test
void shouldReturn202WhenRegistrationAccepted() {
    when(registerUserUseCase.execute(any())).thenReturn(Mono.empty());

    webTestClient.post().uri("/auth/register")
        .contentType(MediaType.APPLICATION_JSON)
        .bodyValue("""
            {
              "tenantId": "tenant-1",
              "email": "nuevo@pagofacil.com",
              "password": "P@ssw0rd!",
              "fullName": "Juan Pérez",
              "phoneNumber": "+5491112345678",
              "dateOfBirth": "1990-01-01",
              "documentType": "DNI",
              "documentId": "12345678",
              "correlationId": "corr-001"
            }
            """)
        .exchange()
        .expectStatus().isAccepted()
        .expectBody()
        .jsonPath("$.message").isEqualTo("KYC iniciado");
}
```

### 8.5 Cobertura Mínima por Capa

| Capa | Umbral Mínimo | Herramienta | Nota |
|---|---|---|---|
| Dominio | ≥ 90% | JaCoCo | Incluir todas las reglas de negocio y transiciones de estado |
| Aplicación | ≥ 85% | JaCoCo | Incluir happy path y al menos un escenario de error por caso de uso |
| Infraestructura | ≥ 75% | JaCoCo | Testcontainers obligatorio; no mockear la base de datos en estas pruebas |
| REST API | ≥ 80% | JaCoCo | WebTestClient; cubrir todos los códigos de respuesta documentados en §7 |

Verificación de umbrales en `pom.xml` (módulo `rest-api`):
```xml
<plugin>
    <groupId>org.jacoco</groupId>
    <artifactId>jacoco-maven-plugin</artifactId>
    <configuration>
        <rules>
            <rule>
                <limits>
                    <limit>
                        <counter>LINE</counter>
                        <value>COVEREDRATIO</value>
                        <minimum>0.80</minimum>
                    </limit>
                </limits>
            </rule>
        </rules>
    </configuration>
</plugin>
```

---

## 9. Criterios de Aceptación

### 9.1 Criterios TDD (Proceso)

- [ ] Cada entidad de dominio (§4) tiene su clase de test correspondiente y **todas las pruebas de dominio fueron escritas antes del código de producción** (evidencia: commits con test en Red antes del Green)
- [ ] Cada caso de uso de aplicación (§5) tiene pruebas de happy path **y** al menos una rama de error
- [ ] Ningún adaptador de infraestructura (§6) accede a PostgreSQL en memoria falso — todas las pruebas de infra usan Testcontainers
- [ ] `mvn test` ejecuta en verde sin `@Disabled` ni `@Ignore` activos
- [ ] Cobertura por capa verificada por JaCoCo: dominio ≥ 90%, aplicación ≥ 85%, infraestructura ≥ 75%, REST ≥ 80%
- [ ] Los tipos reactivos en todas las pruebas de dominio y aplicación se verifican con `StepVerifier`; ningún `.block()` presente en pruebas unitarias
- [ ] Todos los métodos de prueba tienen `@DisplayName("AC-XXX: descripción legible")` siguiendo la convención ATDD

### 9.2 Criterios Funcionales (Comportamiento)

- [ ] `POST /auth/register` con email nuevo retorna **202** con body `{"message":"KYC iniciado"}` y el usuario queda en estado PENDING
- [ ] `POST /auth/register` con email duplicado en el mismo tenant retorna **409** con descripción del conflicto
- [ ] `POST /auth/register` con campos inválidos retorna **422** con lista de errores de validación
- [ ] `POST /auth/login` con credenciales válidas y cuenta ACTIVE retorna **200** con `MfaChallengeResponse`
- [ ] `POST /auth/login` con N intentos fallidos consecutivos retorna **423** en el N-ésimo intento y el campo `lockedUntil` está presente en la respuesta
- [ ] `POST /auth/mfa/verify` con TOTP válido retorna **200** con `TokenResponse` (accessToken + refreshToken)
- [ ] Evento `KycApproved` consumido desde Kafka transiciona al usuario de PENDING a **ACTIVE** y publica `KycApprovedEvent` en el outbox
- [ ] El outbox publica eventos a Kafka **sin dual-write**: el evento solo existe en Kafka cuando la transacción de negocio hizo commit en PostgreSQL
- [ ] `POST /users/{userId}/compensar` es **idempotente**: invocada dos veces con el mismo `correlationId` retorna 200 en ambas llamadas sin duplicar efectos
- [ ] `GET /actuator/health/readiness` retorna `{"status":"UP"}` con la conexión R2DBC activa
- [ ] Todas las llamadas autenticadas con JWT expirado retornan **401** con mensaje descriptivo
- [ ] El relay del outbox marca los mensajes como PUBLISHED tras publicarlos exitosamente a Kafka; mensajes no entregados se marcan como FAILED y son reintentables

### 9.3 Criterios de Despliegue

- [ ] Pod `identity-service` en namespace `pagofacil-dev` está en estado **Running** tras el sync de ArgoCD
- [ ] Readiness probe `GET /actuator/health/readiness` pasa tras el arranque (timeout máximo 60s)
- [ ] Liveness probe `GET /actuator/health/liveness` pasa en operación normal
- [ ] Métricas expuestas en `/actuator/prometheus` y visibles en Grafana (dashboard `identity-service`)
- [ ] Logs estructurados (JSON) visibles en Loki con campo `service=identity-service` y `tenant_id` en cada línea relevante
- [ ] Secret `pagofacil/dev/identity-service` leído correctamente desde floci (sin valores hardcodeados en el Helm chart)
