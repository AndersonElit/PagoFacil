# Software Design Document — Diseño Técnico

**Proyecto:** PagoFacil — Billetera Digital
**Conjunto SDD técnico:** Este documento forma parte del SDD Técnico junto con `SDD-PagoFacil-system.md` e `SDD-PagoFacil-infrastructure.md`.
**Versión:** 1.0
**Fecha:** 2026-06-08

---

## 1. Diseño de APIs

Especificación completa: [SDD-PagoFacil-openapi.yaml](api/SDD-PagoFacil-openapi.yaml)

La API REST sigue el estilo OpenAPI 3.0.3. Todos los endpoints requieren JWT emitido por AWS Cognito salvo los webhooks de integración externa (OAuth 2.0 client credentials) y el flujo de registro. El header `Idempotency-Key` (UUID v4) es obligatorio en todas las operaciones financieras.

### Resumen de Endpoints por Bounded Context

| Bounded Context | Método | Ruta | Descripción |
|---|---|---|---|
| Auth (BC-01) | POST | `/auth/register` | Registro de usuario; inicia flujo KYC |
| Auth (BC-01) | POST | `/auth/login` | Autenticación primer factor |
| Auth (BC-01) | POST | `/auth/mfa/verify` | Verificación MFA; emite tokens |
| Auth (BC-01) | POST | `/auth/refresh` | Renovación de access token |
| Auth (BC-01) | POST | `/auth/logout` | Revocación de sesión |
| Users (BC-01) | GET | `/users/{userId}` | Perfil de usuario |
| Users (BC-01) | PUT | `/users/{userId}/profile` | Actualización de perfil |
| Users (BC-01) | GET | `/users/{userId}/kyc-status` | Estado KYC del usuario |
| Wallets (BC-02) | GET | `/wallets/{walletId}` | Saldo y estado de billetera |
| Wallets (BC-02) | GET | `/wallets/{walletId}/transactions` | Historial paginado de movimientos |
| Wallets (BC-02) | GET | `/wallets/{walletId}/linked-bank-accounts` | Cuentas bancarias vinculadas |
| Transactions (BC-02/05) | POST | `/transactions/deposits` | Iniciación de depósito |
| Transactions (BC-02/05) | POST | `/transactions/transfers` | Iniciación de transferencia |
| Transactions (BC-02/05) | POST | `/transactions/withdrawals` | Iniciación de retiro |
| Transactions (BC-02/05) | GET | `/transactions/{transactionId}` | Estado de transacción |
| Compliance (BC-03) | GET | `/compliance/alerts` | Listado de alertas |
| Compliance (BC-03) | GET | `/compliance/alerts/{alertId}` | Detalle de alerta |
| Compliance (BC-03) | PUT | `/compliance/alerts/{alertId}/resolve` | Resolución de alerta |
| Integration (BC-05) | POST | `/webhooks/kyc` | Resultado KYC del proveedor |
| Integration (BC-05) | POST | `/webhooks/payment` | Notificación de pago |
| Integration (BC-05) | POST | `/webhooks/withdrawal-confirmation` | Confirmación de retiro |
| Integration (BC-05) | GET | `/sagas/{sagaId}` | Estado de saga |
| Saga Compensation | POST | `/users/{userId}/compensar` | Compensación de onboarding |
| Saga Compensation | POST | `/wallets/{walletId}/compensar` | Compensación de operación en billetera |
| Saga Compensation | POST | `/transactions/{transactionId}/compensar` | Compensación de transacción |
| Saga Compensation | POST | `/compliance/alerts/{alertId}/compensar` | Compensación de evaluación de riesgo |
| Saga Compensation | POST | `/sagas/{sagaId}/compensar` | Inicio de compensación de saga (interno LRA) |
| Audit (BC-06) | GET | `/audit/traces` | Consulta filtrada de trazas |
| Audit (BC-06) | GET | `/audit/traces/{traceId}` | Detalle de traza |
| Reporting (BC-07) | GET | `/reports/schemas` | Catálogo de esquemas de reportes |
| Reporting (BC-07) | POST | `/reports/executions` | Solicitud on-demand de reporte |
| Reporting (BC-07) | GET | `/reports/executions/{executionId}` | Estado de ejecución |
| Reporting (BC-07) | GET | `/reports/executions/{executionId}/download` | Descarga del reporte generado |

---

## 2. Diseño de Persistencia

### Patrón: Database-per-Service

Cada microservicio posee y gestiona su propia base de datos de forma exclusiva. Ningún otro servicio accede directamente a la base de datos de otro contexto. Las bases de datos se provisionan automáticamente por `init-databases.sh` usando la convención `pagofacil_<servicio_slug>`. El esquema inicial de cada servicio lo aplica **Liquibase standalone** (`run-liquibase-migrations.sh --gitea-clone`) como paso previo al despliegue; los changelogs residen en el repositorio `pagofacil-migrations` en Gitea del VPS (`http://VPS_IP:3000/pagofacil/pagofacil-migrations`).

La comunicación entre servicios que necesita datos de otra base de datos se resuelve mediante **eventos de dominio** (Kafka) o **llamadas REST** al servicio propietario — nunca acceso directo.

### Modelo de Datos

Modelo de datos relacional: [SDD-PagoFacil-schema.sql](database/SDD-PagoFacil-schema.sql)

Modelo de datos MongoDB (auditoría): [SDD-PagoFacil-collections.js](database/SDD-PagoFacil-collections.js)

### Resumen de Entidades por Bounded Context

| Bounded Context | Entidad / Colección | Tipo de almacenamiento | BD propietaria | Descripción |
|---|---|---|---|---|
| BC-01 Identity | users | PostgreSQL (tabla) | `pagofacil_identity_service` | Datos de usuario, estado de cuenta, intentos fallidos |
| BC-01 Identity | kyc_records | PostgreSQL (tabla) | `pagofacil_identity_service` | Registros del proceso KYC, resultado y referencia externa |
| BC-01 Identity | mfa_devices | PostgreSQL (tabla) | `pagofacil_identity_service` | Dispositivos MFA registrados (TOTP, SMS, Email) |
| BC-01 Identity | sessions | PostgreSQL (tabla) | `pagofacil_identity_service` | Sesiones activas y refresh tokens |
| BC-02 Wallet | wallets | PostgreSQL (tabla) | `pagofacil_wallet_service` | Billeteras con saldo disponible y reservado |
| BC-02 Wallet | wallet_transactions | PostgreSQL (tabla) | `pagofacil_wallet_service` | Movimientos confirmados con idempotency_key |
| BC-02 Wallet | transaction_limits | PostgreSQL (tabla) | `pagofacil_wallet_service` | Límites transaccionales por tipo y período |
| BC-02 Wallet | linked_bank_accounts | PostgreSQL (tabla) | `pagofacil_wallet_service` | Cuentas bancarias vinculadas y verificadas |
| BC-03 Fraud | compliance_alerts | PostgreSQL (tabla) | `pagofacil_fraud_compliance_service` | Alertas AML y fraude con ciclo de vida |
| BC-03 Fraud | fraud_rules | PostgreSQL (tabla) | `pagofacil_fraud_compliance_service` | Reglas de detección configuradas |
| BC-03 Fraud | risk_evaluations | PostgreSQL (tabla) | `pagofacil_fraud_compliance_service` | Resultados de evaluaciones por operación |
| BC-04 Notification | notifications | PostgreSQL (tabla) | `pagofacil_notification_service` | Historial de notificaciones enviadas |
| BC-04 Notification | notification_templates | PostgreSQL (tabla) | `pagofacil_notification_service` | Plantillas por canal y tipo de evento |
| BC-05 Integration | saga_instance | PostgreSQL (tabla) | `pagofacil_integration_service` | Estado e historial de sagas activas y completadas |
| BC-05 Integration | saga_step_log | PostgreSQL (tabla) | `pagofacil_integration_service` | Log de cada paso de saga con payload de compensación |
| BC-05 Integration | outbox | PostgreSQL (tabla) | `pagofacil_integration_service` | Outbox transaccional para publicación confiable de eventos Kafka |
| BC-06 Audit | audit_traces | MongoDB (colección, append-only) | `pagofacil_audit_service` | Trazas inmutables con actor, acción, IP y correlationId |
| BC-07 Reporting | report_transactions | PostgreSQL (tabla) | `pagofacil_readmodel` | Proyección desnormalizada de transacciones para ETL |
| BC-07 Reporting | report_compliance_alerts | PostgreSQL (tabla) | `pagofacil_readmodel` | Proyección desnormalizada de alertas para ETL |
| BC-07 Reporting | report_users | PostgreSQL (tabla) | `pagofacil_readmodel` | Proyección desnormalizada de usuarios para ETL |
| BC-07 Reporting | report_schema_catalog | PostgreSQL (tabla) | `pagofacil_reporting` | Catálogo de esquemas de reportes (MS1 lo consulta) |
| BC-07 Reporting | report_executions | PostgreSQL (tabla) | `pagofacil_reporting` | Metadatos y estado de ejecuciones del pipeline ETL |

### Estrategia de Migraciones

- **Motor:** Liquibase standalone en modo `run-liquibase-migrations.sh --gitea-clone`.
- **Changelogs:** Residen en el repositorio `pagofacil-migrations` en Gitea del VPS (`http://VPS_IP:3000/pagofacil/pagofacil-migrations`). El scaffold genera `00001_initial_schema.yaml` por servicio a partir de los bloques `-- BC-XX:` del `schema.sql` de referencia.
- **Aplicación:** Se ejecuta como paso previo al despliegue de cada microservicio; no embebida en el JAR.
- **Razón:** Flyway es incompatible con Spring Boot WebFlux + R2DBC (usa JDBC bloqueante). Liquibase standalone es la herramienta mandatoria.

---

## 3. Flujos Técnicos Principales

## Flujo: Onboarding de Usuario

1. El Usuario Final envía `POST /auth/register` al **API Gateway**.
2. **API Gateway** enruta la solicitud al **identity-service**.
3. **identity-service** valida el formato de datos y la unicidad del email en `pagofacil_identity_service`.
4. **identity-service** persiste el usuario con estado `PENDING` y publica `UserRegistered` en el outbox → Kafka.
5. **fraud-compliance-service** consume `UserRegistered` y solicita al **integration-service** la evaluación AML.
6. **integration-service** invoca la ruta Camel `aml-route` → **Proveedor AML** vía HTTPS/API Key.
7. Si hay coincidencia AML positiva: **fraud-compliance-service** genera `ComplianceAlert` y publica `AccountSuspendedByAML`; el onboarding se detiene.
8. Si sin coincidencia AML: **identity-service** recibe el OK y el **integration-service** inicia la saga de onboarding vía Camel + Narayana LRA → `kyc-route` → **Proveedor KYC**.
9. El **Proveedor KYC** notifica resultado vía webhook → `POST /webhooks/kyc` → **integration-service**.
10. **integration-service** traduce el resultado (ACL) y publica el evento `KYCApproved` o `KYCRejected`.
11. **identity-service** consume el evento y transiciona el `UserStatus` a `ACTIVE` (si aprobado).
12. **wallet-service** consume `KYCApproved` y crea la billetera con saldo cero.
13. **notification-service** consume `KYCApproved` y envía notificación de cuenta activa al usuario.

---

## Flujo: Autenticación con MFA

1. El usuario envía `POST /auth/login` con email y contraseña.
2. **identity-service** valida las credenciales hasheadas; incrementa `failed_login_attempts` si son incorrectas.
3. Si se supera el umbral: `status = BLOCKED`; se rechaza el acceso con `423 Locked`.
4. Si las credenciales son válidas: **identity-service** inicia el challenge MFA y retorna `MFAChallengeResponse`.
5. El usuario envía `POST /auth/mfa/verify` con el código MFA.
6. **identity-service** valida el código (TOTP, OTP de SMS o email vía `notification-service`).
7. Si es válido: **identity-service** registra la sesión y delega la emisión de tokens a **AWS Cognito**; retorna `TokenResponse`.

---

## Saga: Depósito de Fondos

**Estilo:** Orquestación — orquestador en `integration-service` (Camel Saga EIP + Narayana LRA).

| # | Paso (acción) | Servicio participante | Evento / Comando | Compensación | Idempotencia |
|---|---|---|---|---|---|
| 1 | Recibe notificación de pago y valida firma | `integration-service` | `PaymentNotification` recibida | Registrar fallo sin acción | `idempotency_key` en `external_integration_events` |
| 2 | Solicita evaluación AML/fraude | `fraud-compliance-service` | Comando REST/Kafka `EvaluateRisk` | `POST /compliance/alerts/{alertId}/compensar` | `correlationId` en `risk_evaluations` |
| 3 | Acredita fondos en billetera | `wallet-service` | Comando `CreditWallet` | `POST /wallets/{walletId}/compensar` (REVERSE_CREDIT) | `idempotency_key` en `wallet_transactions` |
| 4 | Confirma depósito con entidad financiera | `integration-service` (ACL) | Confirmación hacia entidad externa | Solicitar reversión a entidad financiera | `idempotency_key` en confirmación externa |
| 5 | Publica `DepositCompleted` | `integration-service` | Evento Kafka `DepositCompleted` | Publica `DepositReverted` | `correlationId` |

**Fallo en paso N:** El orquestador Narayana LRA dispara las compensaciones de los pasos N-1…1 en orden inverso. Cada compensación es idempotente gracias a la tabla `processed_message` en cada participante.

**Transactional Outbox:** Cada servicio participante publica los eventos de forma atómica con su cambio de BD mediante el patrón Outbox (tabla `outbox` + relay por polling en dev; CDC/Debezium en staging/prod).

---

## Saga: Transferencia entre Usuarios

**Estilo:** Orquestación (Camel Saga EIP + Narayana LRA) en `integration-service`.

| # | Paso (acción) | Servicio participante | Evento / Comando | Compensación | Idempotencia |
|---|---|---|---|---|---|
| 1 | Valida KYC activo de emisor y receptor | `identity-service` | Consulta REST | — | — |
| 2 | Solicita evaluación de riesgo de la operación | `fraud-compliance-service` | `EvaluateRisk` | `POST /compliance/alerts/{alertId}/compensar` | `correlationId` |
| 3 | Valida límites y ejecuta débito del emisor | `wallet-service` | `DebitWallet` | `POST /wallets/{walletId}/compensar` (REVERSE_DEBIT) | `idempotency_key` |
| 4 | Ejecuta crédito al receptor | `wallet-service` | `CreditWallet` | `POST /wallets/{walletId}/compensar` (REVERSE_CREDIT) | `idempotency_key` |
| 5 | Publica `TransferCompleted` | `integration-service` | Evento `TransferCompleted` | Publica `TransferReverted` | `correlationId` |

**Fallo en paso 4 (crédito al receptor):** El orquestador revierte el débito del paso 3 mediante `REVERSE_DEBIT`. El emisor recupera su saldo. Se notifica al emisor el fallo.

---

## Saga: Retiro de Fondos

**Estilo:** Orquestación (Camel Saga EIP + Narayana LRA) en `integration-service`.

| # | Paso (acción) | Servicio participante | Evento / Comando | Compensación | Idempotencia |
|---|---|---|---|---|---|
| 1 | Valida saldo y límites | `wallet-service` | Consulta REST | — | — |
| 2 | Reserva fondos en billetera | `wallet-service` | `ReserveFunds` | `POST /wallets/{walletId}/compensar` (RELEASE_RESERVATION) | `idempotency_key` |
| 3 | Solicita evaluación AML/fraude | `fraud-compliance-service` | `EvaluateRisk` | `POST /compliance/alerts/{alertId}/compensar` | `correlationId` |
| 4 | Instruye retiro a entidad financiera | `integration-service` (ACL) | Solicitud HTTPS a entidad | No aplica (entidad reporta fallo en paso 5) | `idempotency_key` externo |
| 5 | Recibe confirmación de entidad financiera | `integration-service` | `WithdrawalConfirmation` webhook | Si falla: libera reserva (paso 2) | `idempotency_key` en webhook |
| 6 | Confirma débito permanente o libera reserva | `wallet-service` | `ConfirmWithdrawal` / `ReleaseReservation` | — | `idempotency_key` |
| 7 | Publica `WithdrawalCompleted` o `WithdrawalReverted` | `integration-service` | Evento Kafka | — | `correlationId` |

---

## Flujo: Integración con Sistema Externo (Camel ACL)

### Consulta AML (integration-service → Proveedor AML)

1. `fraud-compliance-service` solicita evaluación AML al **integration-service** vía comando Kafka o REST interno.
2. **integration-service** invoca la ruta Camel `aml-route` con las credenciales almacenadas en **AWS Secrets Manager**.
3. La ruta Camel aplica ACL (mapeo del modelo interno al contrato del proveedor AML), Resilience4j (circuit breaker + reintentos), y timeout configurable por SLA.
4. El **Proveedor AML** responde con el resultado de la consulta.
5. La ruta Camel traduce la respuesta al modelo de dominio de PagoFacil (AMLResult) y responde al `fraud-compliance-service`.
6. Ningún otro microservicio conoce la existencia del Proveedor AML; el ACL es el único punto de traducción.

---

## Flujo: Pipeline ETL de Reportería

1. Un schedule programado (CronJob K8s) o un comando on-demand (`POST /reports/executions`) inicia la ejecución del reporte.
2. **MS1 (report-extraction-service)** ejecuta `SparkJdbcSourceAdapter` para leer `pagofacil_readmodel` según el `ReportSchema` declarado en `pagofacil_reporting.report_schema_catalog`.
3. MS1 valida el esquema del DataFrame extraído contra las `integrity_rules` del catálogo.
4. MS1 escribe el archivo Parquet en S3 `raw/{report_type}/{execution_id}/`.
5. MS1 publica el evento `report.extracted` en Kafka con la ruta S3 como payload.
6. **MS2 (report-processing-service)** consume `report.extracted`, lee el Parquet `raw/` y aplica la transformación correspondiente al `ReportType` mediante el patrón Factory.
7. MS2 escribe el Parquet transformado en S3 `processed/{report_type}/{execution_id}/`.
8. MS2 publica el evento `report.processed`.
9. **Lambda Kafka Consumer** consume `report.processed` y publica el evento a **EventBridge** con el formato de salida solicitado.
10. **EventBridge** enruta el evento a la Lambda correspondiente (PDF, XLS o CSV).
11. La Lambda genera el archivo final y lo almacena en S3 `output/{report_type}/{execution_id}/{format}/`.
12. El estado de la ejecución en `pagofacil_reporting.report_executions` avanza de `QUEUED` → `EXTRACTING` → `PROCESSING` → `GENERATING_FORMAT` → `COMPLETED`.

---

## Flujo: Auditoría Transversal

1. Cada microservicio publica un evento de dominio en Kafka (vía Transactional Outbox) al completar una operación de negocio.
2. **audit-service** consume pasivamente **todos** los topics de dominio de Kafka.
3. Por cada evento consumido, **audit-service** construye una `AuditTrace` con `actor`, `action`, `eventType`, `correlationId`, `tenantId`, `ipAddress` y `timestamp`.
4. La traza se inserta en MongoDB `pagofacil_audit_service` en modo append-only (sin UPDATE ni DELETE).
5. Los operadores internos consultan las trazas desde el **Frontend** vía `GET /audit/traces` con filtros.

---

## 4. Diseño de Seguridad Técnica

### Autenticación

| Flujo | Mecanismo | Detalles |
|---|---|---|
| Usuarios finales y operadores internos | OAuth 2.0 / OIDC — AWS Cognito User Pool | MFA obligatorio (TOTP, SMS OTP, email OTP); acceso bloqueado tras umbral de intentos fallidos |
| Access Token | JWT firmado por Cognito | Expiración máxima 15 min; claims: `sub`, `role`, `tenant_id`, `exp`, `jti` |
| Refresh Token | Cognito Refresh Token | Revocación explícita ante logout o anomalía de sesión |
| Sistemas externos (machine-to-machine) | OAuth 2.0 client credentials | Credenciales en AWS Secrets Manager; rotación automática |
| Webhooks de pasarelas / entidades financieras | Firma HMAC-SHA256 del payload | Validación obligatoria antes de cualquier procesamiento; rechazo sin procesamiento si inválida |
| Comunicación inter-servicio | JWT de servicio (scope `service:internal`) emitido por Cognito | Usado en endpoints de compensación de saga; `ServiceToken` en el OpenAPI |

### Autorización

- Cada microservicio valida los claims JWT (`role`, `tenant_id`) en **cada** solicitud sin excepción.
- El `tenant_id` se extrae **exclusivamente del claim JWT**; nunca del body de la solicitud (mitigación TH-003 y TH-008).
- El `userId` se extrae del claim `sub` del JWT; nunca de parámetros de URL modificables por el cliente.
- Control de acceso por rol alineado al modelo de autorización del Strategic Design (Tabla §2 del `security.md`).

### Cifrado

| Dato | En tránsito | En reposo |
|---|---|---|
| Toda comunicación interna y externa | TLS 1.2+ obligatorio | — |
| Datos sensibles en BD (contraseñas, TOTP secrets) | — | bcrypt / Argon2 para contraseñas; AES-256 para TOTP secrets |
| Archivos Parquet en S3 | TLS 1.2+ | AES-256 (S3 SSE-KMS) |
| Claves y credenciales | — | AWS Secrets Manager (KMS + rotación automática) |

### Manejo de Secretos

- **Prohibido:** secretos en código fuente, repositorios, variables de entorno en texto plano o logs.
- **Mandatorio:** todos los secretos residen en AWS Secrets Manager, accedidos por identidad de servicio (IAM Role / Service Account K8s).
- Las credenciales de sistemas externos (KYC, AML, SMS/Email) son leídas por el `integration-service` en tiempo de ejecución desde Secrets Manager, nunca en variables de entorno.

### Protección de APIs

| Control | Implementación |
|---|---|
| Rate limiting | API Gateway v2: por usuario (`sub`) y por tenant (`tenant_id`); límites configurables por ambiente |
| Idempotencia | Header `Idempotency-Key` (UUID v4) obligatorio en operaciones financieras; tabla `processed_message` en cada participante de saga |
| Inyección de eventos Kafka | Autenticación de productores con credenciales de servicio; validación de schema (JSON Schema / Avro) en todos los consumidores |
| Multitenancy | `tenant_id` validado en todas las queries de base de datos; aislamiento a nivel de aplicación y a nivel de consulta |

### Auditoría de Seguridad

Los siguientes eventos generan traza de auditoría inmutable en MongoDB:
- Registro, activación, suspensión y bloqueo de cuentas.
- Intentos de autenticación (exitosos y fallidos); bloqueo por umbral.
- Inicio y resultado del proceso KYC.
- Creación y cambio de estado de toda operación financiera.
- Eventos de compensación de saga.
- Creación, asignación y resolución de alertas de fraude y AML.
- Acceso al dashboard de auditoría.
- Generación y descarga de reportes regulatorios.
- Cambios de configuración (límites transaccionales, reglas de fraude).

### Logs y Observabilidad

- Logs en formato **JSON estructurado**; sin PII en texto plano, sin datos financieros en texto plano.
- Masking de campos sensibles en logs y trazas OpenTelemetry (email, nombre, monto se registran solo en auditoría, no en logs operacionales).
- Respuestas de error hacia el exterior son genéricas (sin stack trace ni detalles internos); detalle completo registrado internamente con `correlationId`.
- `correlationId` propagado en todos los headers HTTP y eventos Kafka para trazabilidad end-to-end.

---

## 5. Especificación de Pruebas (ATDD)

Trazabilidad de los criterios de aceptación del Strategic Design (AC-xxx) hacia los tipos de prueba técnica y los contratos verificables en implementación.

### Matriz de trazabilidad AC → Prueba técnica

| Criterio ATDD | Tipo de prueba | Componente bajo prueba | Escenarios técnicos clave | Gate de aceptación |
|---|---|---|---|---|
| AC-001-S1, AC-001-E1, AC-001-E2 | Integration + Contract | `identity-service` ↔ `integration-service` (proveedor KYC) | KYC aprobado activa cuenta; KYC rechazado deja cuenta en `REJECTED`; coincidencia AML suspende y publica alerta | Estado de cuenta correcto en BD; evento `UserActivated` / `KycRejected` / `UserSuspended` en Kafka |
| AC-001-E3 | Integration | `identity-service` | Registro con correo duplicado retorna error | HTTP 409 + sin registro parcial en BD |
| AC-002-S1 | Integration | `identity-service` ↔ AWS Cognito | Credenciales válidas + MFA correcto emiten tokens | JWT con claims `sub`, `role`, `tenant_id` válidos; sesión registrada |
| AC-002-E1 | Integration | `identity-service` | Intentos fallidos ≥ umbral bloquea cuenta | Estado `BLOCKED` en BD; ningún intento posterior autorizado |
| AC-002-E2, AC-002-E3 | Integration | `identity-service` | MFA incorrecto/expirado rechaza; cuenta bloqueada rechaza | HTTP 401 sin tokens; sin sesión creada |
| AC-003-S1 | Integration + Contract | `integration-service` → `wallet-service` | Notificación válida → evaluación fraude → acreditación | Saldo incrementado; `DepositCompleted` en Kafka; idempotencia con mismo `Idempotency-Key` |
| AC-003-E1 | Unit + Integration | `wallet-service` | Monto > límite transaccional rechaza antes de crear orden | HTTP 422 + saldo sin modificar |
| AC-003-E2 | Integration | `integration-service` | Firma HMAC inválida en webhook → rechaza sin procesar | HTTP 401 desde `integration-service`; sin evento de dominio publicado |
| AC-003-E3 | Integration | `integration-service` → `fraud-compliance-service` | Alerta bloqueante → depósito queda pendiente | Estado `PENDING_REVIEW` en `wallet-service`; alerta en `fraud-compliance-service` |
| AC-004-S1 | Integration | `wallet-service` | Débito y crédito atómicos; `TransferCompleted` publicado | Saldos correctos en ambas BDs; evento en Kafka; no doble procesamiento |
| AC-004-E1 | Unit + Integration | `wallet-service` | Saldo insuficiente rechaza antes de cualquier débito | HTTP 422 + saldo emisor intacto + saldo receptor intacto |
| AC-004-E2 | Integration | `wallet-service` | Receptor con KYC ≠ `APPROVED` rechaza | HTTP 422 + sin modificación de saldos |
| AC-004-E3 | Integration | `fraud-compliance-service` | Alerta bloqueante detiene transferencia | Estado `BLOCKED` + saldos intactos |
| AC-005-S1 | Integration (Saga E2E) | `integration-service` (orquestador LRA) | Flujo saga completo exitoso: reserva → confirmación → débito permanente | Saldo definitivo correcto; estado saga `COMPLETED`; `WithdrawalCompleted` en Kafka |
| AC-005-E1 | Integration (Saga E2E) | `integration-service` (orquestador LRA) | Fallo en entidad financiera dispara compensación `DE-009` | Reserva liberada; saldo restaurado; `FundsReservationReleased` en Kafka; estado saga `COMPENSATED` |
| AC-005-E2 | Unit + Integration | `wallet-service` | Saldo disponible < monto + reservas activas rechaza | HTTP 422 + sin reserva creada |
| AC-005-E3 | Integration | `wallet-service` | Cuenta bancaria no vinculada rechaza | HTTP 422 + sin reserva creada |
| AC-006-S1 | Integration | `wallet-service` / `integration-service` | Reintento con mismo `Idempotency-Key` completado → respuesta idéntica sin nuevo efecto | Tabla `processed_message` registra la entrada; HTTP 200 con resultado original |
| AC-006-E1 | Integration | `wallet-service` / `integration-service` | Reintento con `Idempotency-Key` en curso → rechazo por concurrencia | HTTP 409 Conflict; sin segunda instancia de operación |
| AC-007-S1 | Integration | `fraud-compliance-service` + `audit-service` | Analista aprueba alerta → operación liberada → auditoría inmutable | Estado alerta `RESOLVED`; operación liberada; registro inmutable en MongoDB |
| AC-007-E1 | Integration | `fraud-compliance-service` | Motor clasifica como `CRITICAL` → bloqueo automático | Operación en estado `BLOCKED`; alerta de alta prioridad creada; sin modificación de saldos |
| AC-007-E2 | Integration | `fraud-compliance-service` → `identity-service` | Oficial confirma AML positivo → suspensión de cuenta + cancelación de operaciones | Estado cuenta `SUSPENDED`; operaciones pendientes `CANCELLED`; ROS/SAR candidato registrado |
| AC-008-S1 | Integration (CronJob E2E) | MS1 → MS2 → Lambda | Pipeline ETL completo: extracción JDBC → Parquet raw → transformación → Parquet processed → PDF/XLS/CSV | Archivo de reporte generado; ejecución en catálogo `COMPLETED`; notificación enviada |
| AC-008-E1 | Integration | MS1 (`report-extraction-service`) | Error JDBC al leer `pagofacil_readmodel` → `ReportExtractionFailed` | Evento publicado en Kafka; ejecución en catálogo `FAILED`; alerta a operaciones; datos operacionales intactos |
| AC-008-E2 | Integration | MS1 (`report-extraction-service`) | Datos no cumplen `ReportSchema` → rechazo sin Parquet | `ReportExtractionFailed` con motivo `SCHEMA_VALIDATION`; sin archivo generado; ejecución `FAILED` |

### Estrategia de prueba por capa

| Capa | Herramienta | Alcance |
|---|---|---|
| Unit | JUnit 5 + Mockito (Java) / ScalaTest (Scala) | Lógica de dominio, reglas de negocio, validaciones de entidad |
| Integration | Spring Boot Test + Testcontainers (PostgreSQL + Kafka) + WireMock (sistemas externos) | Flujos de saga, persistencia, publicación de eventos, contratos REST internos |
| Contract (Consumer-Driven) | Pact JVM | Contratos entre `integration-service` y sistemas externos KYC/AML/pasarelas; entre productores y consumidores Kafka |
| E2E | API calls sobre entorno `dev` (K3s) | Flujos críticos: onboarding completo, transferencia, retiro con compensación, pipeline ETL |
| Carga / Estrés | k6 o Gatling | Respuesta < 500 ms bajo carga nominal; comportamiento bajo carga sostenida y picos |

### Convención de nombrado de tests de integración

Los tests de integración que validan criterios ATDD deben incluir el ID del criterio en el nombre del método o en la anotación `@DisplayName`:

```java
@Test
@DisplayName("AC-004-E1: transferencia rechazada cuando saldo emisor es insuficiente")
void shouldRejectTransferWhenInsufficientBalance() { ... }
```

Esto garantiza trazabilidad directa entre criterio de aceptación y test ejecutable en el reporte de CI.
