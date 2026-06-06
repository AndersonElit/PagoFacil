# Software Design Document — Diseño Técnico

**Proyecto:** PagoFacil — Billetera Digital | Parte del conjunto SDD técnico v1.0 (system / design / infrastructure)  
**Fecha:** 2026-06-06 | **Etapa:** Technical Design — Diseño Técnico

---

## 1. Diseño de APIs

Especificación completa: [SDD-PagoFacil-openapi.yaml](api/SDD-PagoFacil-openapi.yaml)

La especificación OpenAPI 3.0 define todos los contratos REST agrupados por bounded context. Los esquemas de autenticación usan `BearerAuth` (JWT Cognito) para endpoints externos. Los endpoints de compensación y los de uso interno (fraud/evaluate, integration/sagas) solo son accesibles por servicios con mTLS.

### Resumen de Endpoints por Bounded Context

| Bounded Context | Método | Ruta | Descripción |
|---|---|---|---|
| Identity | POST | /v1/identity/users | Registro de usuario (crea cuenta en PENDIENTE_KYC) |
| Identity | POST | /v1/identity/auth/login | Inicio de sesión — primer factor |
| Identity | POST | /v1/identity/auth/mfa/verify | Verificación MFA — segundo factor |
| Identity | POST | /v1/identity/auth/password/recover-request | Solicitud de recuperación de contraseña |
| Identity | POST | /v1/identity/auth/password/reset | Restablecimiento de contraseña con token |
| Identity | GET | /v1/identity/users/me/kyc-status | Consultar estado del proceso KYC |
| Wallet | GET | /v1/wallet/me/balance | Saldo disponible y pendiente (write-side) |
| Wallet | POST | /v1/wallet/deposits | Iniciar depósito (inicia Saga-Deposito) |
| Wallet | POST | /v1/wallet/withdrawals | Iniciar retiro (inicia Saga-Retiro) |
| Wallet | POST | /v1/wallet/transfers | Iniciar transferencia (inicia Saga-Transferencia) |
| Wallet | GET | /v1/wallet/transactions | Historial de transacciones paginado (Read Model) |
| Wallet | GET | /v1/wallet/transactions/{id} | Detalle de una transacción |
| Fraud | GET | /v1/fraud/rules | Listar reglas de fraude activas |
| Fraud | POST | /v1/fraud/rules | Crear regla de fraude |
| Fraud | PUT | /v1/fraud/rules/{ruleId} | Actualizar configuración de regla |
| Fraud | POST | /v1/fraud/evaluate | Evaluar transacción (interno, mTLS) |
| Audit | GET | /v1/audit/transactions | Dashboard: buscar transacciones (Read Model) |
| Audit | GET | /v1/audit/alerts | Listar alertas de fraude y AML |
| Audit | PUT | /v1/audit/alerts/{alertId}/resolve | Resolver alerta (auditor autorizado) |
| Audit | POST | /v1/audit/reports/trigger | Disparar reporte on-demand |
| Audit | GET | /v1/audit/reports/{reportId}/download | Descargar reporte desde S3 |
| Integration — Saga | POST | /v1/integration/sagas | Iniciar saga (interno, mTLS) |
| Integration — Saga | GET | /v1/integration/sagas/{sagaId} | Consultar estado de saga (interno, mTLS) |
| Compensaciones | POST | /v1/wallet/deposits/{id}/compensar | Revertir saldo pendiente de depósito |
| Compensaciones | POST | /v1/wallet/withdrawals/{id}/compensar | Liberar fondos reservados de retiro |
| Compensaciones | POST | /v1/wallet/transfers/{id}/compensar | Revertir débito+crédito de transferencia |
| Compensaciones | POST | /v1/fraud/evaluate/{id}/compensar | Liberar retención de fraude |
| Compensaciones | POST | /v1/integration/sagas/{sagaId}/compensar | Forzar compensación de saga |

---

## 2. Diseño de Persistencia

Modelo de datos: [SDD-PagoFacil-schema.sql](database/SDD-PagoFacil-schema.sql)

### Estrategia General

**Database-per-Service** (DS-002): cada microservicio es propietario exclusivo de su base de datos. Ningún otro servicio accede directamente a ella. La comunicación de datos entre contextos ocurre únicamente mediante eventos Kafka o llamadas REST al servicio propietario.

Las bases de datos se provisionan automáticamente por `init-databases.sh` con la convención `pagofacil_<svc_slug>`. El esquema inicial de cada servicio lo aplica **Liquibase standalone** (`run-liquibase-migrations.sh`) como paso previo al despliegue (`db/<servicio>/changelog/00001_initial_schema.yaml`), nunca un script global.

**CQRS** (DS-003 / DS-CQRS-1): el lado write usa PostgreSQL 16.3 con modelo normalizado y garantías ACID. El lado read (`pagofacil_readmodel`) es un Read Model PostgreSQL desnormalizado, propiedad exclusiva del `projection-service`.

**Migraciones:** **Liquibase standalone** gestiona el esquema de cada servicio de forma independiente mediante `run-liquibase-migrations.sh` (imagen Docker `liquibase/liquibase`, sin dependencias en el JAR). El archivo `SDD-PagoFacil-schema.sql` es el artefacto de diseño de referencia; en producción no existe un schema global compartido.

### Entidades Principales por Bounded Context

| Bounded Context | Entidad / Tabla | BD propietaria | Descripción |
|---|---|---|---|
| BC-01 Identity | `users` | `pagofacil_identity_service` | Ciclo de vida de la cuenta y estado KYC |
| BC-01 Identity | `kyc_registrations` | `pagofacil_identity_service` | Resultado inmutable del proceso KYC |
| BC-01 Identity | `authentication_credentials` | `pagofacil_identity_service` | Hash de contraseña + control de bloqueo |
| BC-01 Identity | `mfa_configs` | `pagofacil_identity_service` | Configuración y secreto MFA por usuario |
| BC-01 Identity | `active_sessions` | `pagofacil_identity_service` | Sesiones activas con expiración |
| BC-02 Wallet | `wallets` | `pagofacil_wallet_service` | Saldo disponible y pendiente por usuario/tenant |
| BC-02 Wallet | `transactions` | `pagofacil_wallet_service` | Registro inmutable de operaciones financieras |
| BC-02 Wallet | `fund_sources` | `pagofacil_wallet_service` | Fuentes de fondos registradas (cifradas) |
| BC-02 Wallet | `transaction_limits` | `pagofacil_wallet_service` | Límites por tenant |
| BC-02 Wallet | `outbox` | `pagofacil_wallet_service` | Outbox para publicación confiable de eventos |
| BC-03 Fraud | `fraud_rules` | `pagofacil_fraud_service` | Catálogo de reglas configurables |
| BC-03 Fraud | `fraud_alerts` | `pagofacil_fraud_service` | Alertas generadas con decisión de auditor |
| BC-03 Fraud | `aml_verifications` | `pagofacil_fraud_service` | Resultados de verificación AML (inmutables) |
| BC-04 Notification | `notifications` | `pagofacil_notification_service` | Registro de entregas por canal |
| BC-04 Notification | `notification_templates` | `pagofacil_notification_service` | Plantillas por tipo de evento |
| BC-06 Integration | `saga_instance` | `pagofacil_integration_service` | Estado del ciclo de vida de cada saga LRA |
| BC-06 Integration | `saga_step_log` | `pagofacil_integration_service` | Pasos completados y payloads de compensación |
| BC-06 Integration | `external_requests` | `pagofacil_integration_service` | Registro de llamadas a sistemas externos |
| BC-06 Integration | `outbox` | `pagofacil_integration_service` | Outbox del orquestador |
| BC-07 Reporting | `report_schema_catalog` | `pagofacil_reporting` | Esquemas declarados por tipo de reporte |
| BC-07 Reporting | `report_jobs` | `pagofacil_reporting` | Historial de jobs de extracción/procesamiento |
| CQRS Read Model | `report_transactions` | `pagofacil_readmodel` | Transacciones desnormalizadas para ETL y dashboard |
| CQRS Read Model | `report_alerts` | `pagofacil_readmodel` | Alertas proyectadas para consulta y ETL |
| CQRS Read Model | `report_wallets` | `pagofacil_readmodel` | Estado actual de billeteras (eventual consistency) |
| CQRS Read Model | `report_reconciliations` | `pagofacil_readmodel` | Discrepancias detectadas en conciliación |

### Consideraciones de Consistencia

- Las escrituras en las BDs operacionales son **ACID** dentro de cada servicio.
- La consistencia entre servicios es **eventual**: el Read Model refleja el estado con latencia proporcional al throughput de Kafka y el delay del `projection-service`.
- La consulta de **saldo disponible en tiempo real** se sirve directamente desde `pagofacil_wallet_service` (write-side), nunca desde el Read Model.
- Los registros de auditoría y transacciones confirmadas son **inmutables**: no se implementan UPDATE ni DELETE sobre ellos.

### Outbox y Procesamiento de Mensajes

Cada servicio participante en sagas (wallet, fraud, integration) tiene:
- Tabla `outbox`: publica eventos de forma atómica con el cambio de BD. Un relay por polling lee la tabla y publica a Kafka.
- Tabla `processed_message`: garantiza idempotencia en los consumers (clave `message_id` única por consumer).

---

## 3. Flujos Técnicos Principales

### Flujo: Autenticación con MFA

1. **Zona Pública → API Gateway** — Cliente envía `POST /v1/identity/auth/login` con credenciales.
2. **identity-service** — Valida credenciales contra `authentication_credentials` (hash Argon2/bcrypt). Si falla N veces consecutivas, bloquea la cuenta.
3. **identity-service** — Retorna `mfaSessionToken` temporal. No emite JWT de sesión aún.
4. **Cliente → API Gateway** — Envía `POST /v1/identity/auth/mfa/verify` con el código MFA.
5. **identity-service** — Valida el código contra `mfa_configs` (TOTP/SMS/email). Si es válido, emite token JWT mediante AWS Cognito y crea registro en `active_sessions`.
6. **identity-service** — Publica `SesionIniciada` a Kafka vía Outbox. Registro de auditoría inmutable.

---

### Saga: Saga-Deposito

**Estilo:** Orquestación — orquestador en `integration-service`, Apache Camel Saga EIP + Narayana LRA.

| # | Paso (acción) | Servicio participante | Evento / Comando | Compensación | Idempotencia |
|---|---|---|---|---|---|
| 1 | Registrar depósito en PENDIENTE; incrementar saldo pendiente | wallet-service | `DepositoIniciado` (Outbox → Kafka) | `POST /wallet/deposits/{id}/compensar` | `idempotency_key` en `transactions` |
| 2 | Enviar solicitud de fondeo a entidad financiera (ruta Camel) | integration-service → Entidad Financiera | `SolicitudFondeoEnviada` | Cancelar solicitud si aplica | `external_request_id` en `external_requests` |
| 3 | Recibir confirmación (webhook entrante validado por HMAC) | integration-service | `ConfirmacionFondeoRecibida` | — | `idempotency_key` del webhook |
| 4 | Confirmar depósito; mover saldo pendiente → disponible | wallet-service | `DepositoConfirmado` (Outbox → Kafka) | `DepositoRevertido` via compensación paso 1 | `transaction_id` |
| 5 | Notificar al usuario | notification-service | consume `DepositoConfirmado` | — | `message_id` en `processed_message` |

**Fallo en paso 2 o 3 (rechazo de entidad financiera):** el orquestador dispara `POST /wallet/deposits/{id}/compensar` (paso 1 invertido). wallet-service revierte el saldo pendiente, marca la transacción FALLIDA y publica `DepositoRevertido`.

Cada participante usa **Transactional Outbox** para publicar eventos de forma atómica con su cambio de BD. Las compensaciones son **idempotentes** (tabla `processed_message`).

---

### Saga: Saga-Retiro

**Estilo:** Orquestación — orquestador en `integration-service`, Camel Saga EIP + Narayana LRA.

| # | Paso (acción) | Servicio participante | Evento / Comando | Compensación | Idempotencia |
|---|---|---|---|---|---|
| 1 | Reservar fondos del saldo disponible (estado EN_PROCESO) | wallet-service | `RetiroIniciado` (Outbox → Kafka) | `POST /wallet/withdrawals/{id}/compensar` (liberar fondos) | `idempotency_key` en `transactions` |
| 2 | Solicitar evaluación de fraude | integration-service → fraud-service | `EvaluacionSolicitada` | `POST /fraud/evaluate/{id}/compensar` | `transaction_id` + `consumer` |
| 3a | **Fraude aprueba:** enviar instrucción de pago a entidad financiera | integration-service → Entidad Financiera | `InstruccionPagoEnviada` | — | `external_request_id` |
| 3b | **Fraude retiene:** mantener fondos reservados hasta decisión del auditor | wallet-service | `TransaccionRetenida` | Continúa en flujo Manual de Alerta | — |
| 4 | Recibir confirmación de pago (webhook) | integration-service | `ConfirmacionPagoRecibida` | `FondosLiberados` via compensación paso 1 | `idempotency_key` del webhook |
| 5 | Confirmar retiro; eliminar fondos reservados | wallet-service | `RetiroConfirmado` (Outbox → Kafka) | — | `transaction_id` |
| 6 | Notificar al usuario | notification-service | consume `RetiroConfirmado` | — | `message_id` |

**Fallo en paso 4 (rechazo entidad):** compensaciones en orden inverso: paso 3 cancelado, paso 2 compensado, paso 1 compensado (fondos liberados).

---

### Saga: Saga-Transferencia

**Estilo:** Orquestación — orquestador en `integration-service`, Camel Saga EIP + Narayana LRA.

| # | Paso (acción) | Servicio participante | Evento / Comando | Compensación | Idempotencia |
|---|---|---|---|---|---|
| 1 | Verificar saldo; ejecutar débito remitente + crédito destinatario en una transacción ACID | wallet-service | `TransferenciaIniciada` (Outbox → Kafka) | `POST /wallet/transfers/{id}/compensar` (ACID inversa) | `idempotency_key` |
| 2 | Solicitar evaluación de fraude (post-débito) | integration-service → fraud-service | `EvaluacionSolicitada` | `POST /fraud/evaluate/{id}/compensar` | `transaction_id` |
| 3a | **Fraude aprueba:** confirmar transferencia | wallet-service | `TransferenciaConfirmada` (Outbox → Kafka) | — | `transaction_id` |
| 3b | **Fraude retiene post-débito (retención tardía):** disparar compensación ACID | wallet-service | `TransferenciaCompensada` (crédito remitente + débito destinatario) | — | `transaction_id` + flag compensado |
| 4 | Notificar a ambas partes | notification-service | consume `TransferenciaConfirmada` / `TransferenciaCompensada` | — | `message_id` |

La operación de débito+crédito en el paso 1 es **ACID** dentro de `pagofacil_wallet_service`. La compensación (paso 3b) es también una transacción ACID inversa dentro del mismo servicio.

---

### Flujo: Evaluación de Fraude en Tiempo Real

1. **wallet-service** publica `TransaccionIniciada` a Kafka vía Outbox.
2. **fraud-service** consume el evento (consumer group `fraud-evaluator`).
3. Evalúa contra el conjunto de reglas activas de `fraud_rules` para el tenant.
4. Ejecuta verificación AML: consulta cache local de listas de sanciones (sincronizado por integration-service).
5. Si **todas las reglas pasan:** publica `EvaluacionAprobada` a Kafka; la saga continúa.
6. Si **regla de bloqueo activa:** publica `TransaccionRechazadaPorAML`; transacción marcada FALLIDA.
7. Si **regla de revisión activa:** crea `fraud_alerts` (estado PENDIENTE), publica `TransaccionRetenidaPorFraude`; transacción en RETENIDA.

---

### Flujo ETL — Pipeline de Reportería (BC-07 + CQRS)

1. **Servicios operacionales (BC-01, BC-02, BC-03, BC-06)** publican eventos de dominio a Kafka vía Outbox.
2. **projection-service** consume todos los eventos y proyecta tablas desnormalizadas en `pagofacil_readmodel` (PostgreSQL) usando R2DBC reactivo.
3. **CronJob K8s** dispara **MS1** (`report-extraction-service`) según schedule configurado, o el auditor dispara on-demand desde el dashboard.
4. **MS1 (Spark batch):** lee `pagofacil_readmodel` vía JDBC (`SparkJdbcSourceAdapter`), valida el esquema del DataFrame contra `report_schema_catalog`, genera Parquet `raw/` en S3, publica `report.extracted` al topic Kafka.
5. **MS2 (Spark batch):** consume `report.extracted`, carga Parquet `raw/` desde S3, aplica transformaciones por ReportType usando el patrón Factory (abierto/cerrado para agregar tipos), genera Parquet `processed/` en S3, publica `report.processed` al topic Kafka.
6. **Lambda Kafka Consumer:** recibe `report.processed`, publica el evento a **EventBridge** (`pagofacil-report-bus`).
7. **EventBridge** enruta mediante rules independientes a `lambda-pdf`, `lambda-xls` o `lambda-csv` según los formatos solicitados.
8. **Lambdas de formato:** leen Parquet `processed/` desde S3, generan el archivo final y lo depositan en S3 `pagofacil-reports/`.
9. El auditor descarga el reporte desde el dashboard vía `GET /v1/audit/reports/{id}/download` (URL pre-firmada S3, TTL 15 min).

**Integración Camel → Sistema Externo (integration-service):**  
Flujo de ruta Camel para cada sistema externo: servicio de dominio invoca `integration-service` (REST/mTLS) → `integration-service` ejecuta ruta Camel con ACL traductora, reintentos con backoff exponencial (Resilience4j) y circuit breaker → traduce la respuesta al modelo del dominio → responde al servicio invocante. Los sistemas externos solo son alcanzables desde `integration-service`.

---

## 4. Diseño de Seguridad Técnica

### Autenticación

| Plano | Mecanismo | Detalles |
|---|---|---|
| **Externo (usuarios)** | AWS Cognito + OAuth 2.0 / OIDC | JWT Bearer validado por API Gateway v2. MFA obligatorio (TOTP / SMS / email). Tokens con TTL configurable. |
| **Externo (entidades financieras)** | OAuth 2.0 Client Credentials | Credenciales en Secrets Manager. |
| **Webhooks entrantes** | Firma HMAC + lista blanca de IPs | validation en integration-service antes de procesar cualquier confirmación. |
| **Inter-servicio** | mTLS (certificados de servicio) | Ninguna llamada entre microservicios sin certificado válido. Incluye producers/consumers Kafka. |
| **Secretos y credenciales** | AWS Secrets Manager | Lectura en arranque. Variables de entorno no cifradas: prohibidas. |

### Autorización — RBAC

| Rol | Alcance de acceso |
|---|---|
| Usuario Final | Lectura/escritura sobre su propia billetera y transacciones. `userId` del JWT validado contra el recurso. |
| Administrador de Plataforma | Lectura de transacciones, escritura de límites y reglas de fraude. Sin acceso a datos de otro tenant. |
| Auditor / Compliance | Lectura completa de transacciones y alertas; resolución de alertas; disparo de reportes. |
| Servicio Interno (mTLS) | Acceso acotado al contrato del servicio destino según rol de servicio en el certificado. |

Los claims de rol provienen exclusivamente de AWS Cognito. API Gateway los valida antes de enrutar. Cada microservicio revalida el claim para su recurso específico; no se confía en claims del cliente.

### Cifrado

| Contexto | Mecanismo |
|---|---|
| Datos en tránsito (externo) | TLS 1.2+ en todas las comunicaciones con usuarios y sistemas externos |
| Datos en tránsito (inter-servicio) | mTLS dentro del cluster Kubernetes |
| Datos en reposo (BDs) | AES-256 en los volúmenes EBS de PostgreSQL (staging/prod) |
| Datos sensibles en BD | `account_number_enc` (fuentes de fondos) y `secret_enc` (MFA) cifrados en capa de aplicación antes de persistir |
| Contraseñas | Hash Argon2/bcrypt con salt único por usuario; nunca texto plano |

### Protección de APIs

- **Rate limiting por usuario/tenant:** configurado en API Gateway. Previene TH-010 (DoS).
- **Rate limiting saliente por entidad financiera:** configurado en rutas Camel (Camel throttle). Previene TH-011.
- **Validación de ownership:** en cada operación de Wallet, el `userId` del JWT se verifica contra el `wallet.user_id`. Previene TH-005 (IDOR).
- **Multitenancy:** `tenantId` como predicado obligatorio en todas las queries. Validado en cada microservicio. Previene TH-015.
- **Circuit breakers:** Resilience4j en todas las rutas Camel hacia sistemas externos. Degradación controlada ante fallos.

### Manejo de Secretos

- AWS Secrets Manager es la única fuente de credenciales, claves de cifrado y tokens de integración.
- Cada microservicio accede exclusivamente a los secretos de su propio servicio, mediante IAM Role con least privilege y ServiceAccount de Kubernetes.
- Los secretos se rotan periódicamente; los microservicios los leen en el arranque.

### Auditoría e Inmutabilidad

- Todo evento financiero y decisión de auditoría genera un registro persistido atómicamente vía Outbox antes de confirmar la operación local.
- Las tablas `transactions` (confirmadas), `kyc_registrations` y `aml_verifications` no implementan UPDATE ni DELETE.
- Los logs estructurados JSON incluyen `correlationId`, `userId` enmascarado, `timestamp` y resultado. Sin PII en texto libre.
- OpenTelemetry propaga el `CorrelationId` entre todos los servicios para trazabilidad completa.
