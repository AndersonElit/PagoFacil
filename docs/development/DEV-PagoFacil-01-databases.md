# Etapa 1 — Bases de Datos y Migraciones

**Proyecto:** PagoFacil | **Ambiente:** dev (floci + K3d)  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 0. Automatización

El script `init-databases.sh` automatiza la creación de todas las bases de datos de la plataforma siguiendo el patrón **Database-per-Service**.

```bash
bash .claude/scripts/init-databases.sh \
  -P pagofacil \
  -p pagofacil \
  -m pagofacil \
  -u pagofacil_app \
  -w P@gFacil_Dev2024
```

> **Nota sobre el parámetro `-m`:** PagoFacil no usa MongoDB (ADR-002: el Read Model es PostgreSQL). El parámetro `-m` es obligatorio para el script pero no creará bases de datos MongoDB ya que ningún servicio tiene adaptador `mongo`.

**Qué automatiza:**
- Escanea `backend/` y, por cada microservicio con adaptador `postgres` en `infrastructure/driven-adapters/`, crea la BD aislada `pagofacil_<svc_slug>` en el PostgreSQL dev.
- Habilita la extensión `pgcrypto` en cada BD PostgreSQL (requerida para `gen_random_uuid()` y funciones de cifrado).
- Crea el usuario de aplicación `pagofacil_app` con contraseña y otorga privilegios `CONNECT`, `USAGE` y DML sobre cada BD de su servicio.
- **No aplica `schema.sql` global:** el esquema de cada servicio lo aplica Liquibase standalone (`run-liquibase-migrations.sh`) como paso previo al despliegue, no durante el arranque del servicio.

Las secciones siguientes son referencia de diseño y guía para ejecución manual puntual.

---

## 1. Objetivo

Crear las bases de datos aisladas por servicio que el sistema PagoFacil requiere, siguiendo el patrón **Database-per-Service**: cada microservicio es propietario exclusivo de su base de datos. Ningún otro servicio accede directamente a ella.

---

## 2. Estrategia de Persistencia

**Database-per-Service** (ADR-001): cada microservicio posee su propia BD PostgreSQL 16.3. La comunicación de datos entre contextos ocurre únicamente mediante eventos Kafka o llamadas REST al servicio propietario.

**Persistencia monoglota:** toda la plataforma usa PostgreSQL 16.3 (ADR-002 reemplazó MongoDB por PostgreSQL para el Read Model CQRS).

**Convención de nombres:** `pagofacil_<svc_slug>` donde `svc_slug` es el nombre del servicio con guiones reemplazados por guiones bajos (ej: `identity-service` → `identity_service`).

**Archivo de diseño de referencia:** `docs/design/database/SDD-PagoFacil-schema.sql`

### Bases de datos creadas

| Servicio | BD | Slug | BC |
|---|---|---|---|
| `identity-service` | `pagofacil_identity_service` | `identity_service` | BC-01 |
| `wallet-service` | `pagofacil_wallet_service` | `wallet_service` | BC-02 |
| `fraud-service` | `pagofacil_fraud_service` | `fraud_service` | BC-03 |
| `notification-service` | `pagofacil_notification_service` | `notification_service` | BC-04 |
| `audit-service` | `pagofacil_reporting` | `reporting` | BC-07 (reporting context) |
| `integration-service` | `pagofacil_integration_service` | `integration_service` | BC-06 |
| `projection-service` | `pagofacil_readmodel` | `readmodel` | CQRS Read Model |

> **Excepción de nomenclatura — `audit-service`:** el bounded context BC-07 usa el nombre `pagofacil_reporting` (no `pagofacil_audit_service`) porque gestiona el contexto de reportería (tablas `report_schema_catalog` y `report_jobs`). El `audit-service` accede además a `pagofacil_readmodel` como fuente de consulta de solo lectura (propiedad del `projection-service`).

> **`pagofacil_readmodel`:** es la BD del Read Model CQRS, propiedad exclusiva del `projection-service`. `audit-service` y `report-extraction-service` (MS1) acceden a ella en modo solo lectura. El usuario `pagofacil_app` tiene `SELECT` sobre `pagofacil_readmodel`, no `INSERT`/`UPDATE`/`DELETE`.

---

## 3. PostgreSQL — Esquema Relacional

Archivo de referencia: `docs/design/database/SDD-PagoFacil-schema.sql`

### Tablas por bounded context

| Bounded Context | Tabla | BD propietaria | Descripción |
|---|---|---|---|
| BC-01 Identity | `users` | `pagofacil_identity_service` | Ciclo de vida de la cuenta y estado KYC |
| BC-01 Identity | `kyc_registrations` | `pagofacil_identity_service` | Resultado inmutable del proceso KYC |
| BC-01 Identity | `authentication_credentials` | `pagofacil_identity_service` | Hash de contraseña + control de bloqueo |
| BC-01 Identity | `mfa_configs` | `pagofacil_identity_service` | Configuración y secreto MFA (cifrado) |
| BC-01 Identity | `active_sessions` | `pagofacil_identity_service` | Sesiones activas con expiración |
| BC-02 Wallet | `wallets` | `pagofacil_wallet_service` | Saldo disponible y pendiente por usuario/tenant |
| BC-02 Wallet | `transaction_limits` | `pagofacil_wallet_service` | Límites transaccionales por tenant |
| BC-02 Wallet | `transactions` | `pagofacil_wallet_service` | Registro inmutable de operaciones financieras |
| BC-02 Wallet | `fund_sources` | `pagofacil_wallet_service` | Fuentes de fondos registradas (número cifrado) |
| BC-02 Wallet | `outbox` | `pagofacil_wallet_service` | Outbox para publicación confiable de eventos |
| BC-02 Wallet | `processed_message` | `pagofacil_wallet_service` | Idempotencia de consumers Kafka |
| BC-03 Fraud | `fraud_rules` | `pagofacil_fraud_service` | Catálogo de reglas configurables |
| BC-03 Fraud | `aml_verifications` | `pagofacil_fraud_service` | Resultados de verificación AML (inmutables) |
| BC-03 Fraud | `fraud_alerts` | `pagofacil_fraud_service` | Alertas generadas con decisión de auditor |
| BC-03 Fraud | `outbox` | `pagofacil_fraud_service` | Outbox del fraud-service |
| BC-03 Fraud | `processed_message` | `pagofacil_fraud_service` | Idempotencia de consumers Kafka |
| BC-04 Notification | `notification_templates` | `pagofacil_notification_service` | Plantillas por tipo de evento y canal |
| BC-04 Notification | `notifications` | `pagofacil_notification_service` | Registro de entregas por canal |
| BC-04 Notification | `processed_message` | `pagofacil_notification_service` | Idempotencia de consumers Kafka |
| BC-06 Integration | `saga_instance` | `pagofacil_integration_service` | Estado del ciclo de vida de cada saga LRA |
| BC-06 Integration | `saga_step_log` | `pagofacil_integration_service` | Pasos completados y payloads de compensación |
| BC-06 Integration | `external_requests` | `pagofacil_integration_service` | Registro de llamadas a sistemas externos |
| BC-06 Integration | `outbox` | `pagofacil_integration_service` | Outbox del orquestador |
| BC-06 Integration | `processed_message` | `pagofacil_integration_service` | Idempotencia de consumers Kafka |
| BC-07 Reporting | `report_schema_catalog` | `pagofacil_reporting` | Esquemas declarados por tipo de reporte |
| BC-07 Reporting | `report_jobs` | `pagofacil_reporting` | Historial de jobs de extracción/procesamiento |
| CQRS Read Model | `report_transactions` | `pagofacil_readmodel` | Transacciones desnormalizadas para ETL |
| CQRS Read Model | `report_alerts` | `pagofacil_readmodel` | Alertas proyectadas para consulta |
| CQRS Read Model | `report_wallets` | `pagofacil_readmodel` | Estado actual de billeteras |
| CQRS Read Model | `report_reconciliations` | `pagofacil_readmodel` | Discrepancias de conciliación |

---

## 4. PostgreSQL — Changelogs Liquibase por Microservicio

Los changelogs Liquibase viven en `db/<servicio>/changelog/` en la raíz del repositorio, **fuera del JAR**. Liquibase corre standalone vía el script `run-liquibase-migrations.sh` como paso previo a cada despliegue.

**Nomenclatura obligatoria:** `00001_initial_schema.yaml`, `00002_*.yaml`, ... El changelog maestro `root.yaml` los incluye en orden.

**Aplicar migraciones (manual o en pipeline):**

```bash
bash .claude/scripts/run-liquibase-migrations.sh \
  -P pagofacil \
  -p pagofacil \
  -u pagofacil_app \
  -w P@gFacil_Dev2024
```

Para un solo servicio:

```bash
bash .claude/scripts/run-liquibase-migrations.sh \
  -P pagofacil \
  -p pagofacil \
  -u pagofacil_app \
  -w P@gFacil_Dev2024 \
  --service identity-service
```

### Tabla de changelogs por servicio

| Servicio | BD | Archivo changelog | Tablas incluidas |
|---|---|---|---|
| `identity-service` | `pagofacil_identity_service` | `db/identity-service/changelog/00001_initial_schema.yaml` | `users`, `kyc_registrations`, `authentication_credentials`, `mfa_configs`, `active_sessions` |
| `wallet-service` | `pagofacil_wallet_service` | `db/wallet-service/changelog/00001_initial_schema.yaml` | `wallets`, `transaction_limits`, `transactions`, `fund_sources`, `outbox`, `processed_message` |
| `wallet-service` (outbox saga) | `pagofacil_wallet_service` | `db/wallet-service/changelog/00003_outbox.yaml` | Actualización outbox pattern para participante de saga |
| `fraud-service` | `pagofacil_fraud_service` | `db/fraud-service/changelog/00001_initial_schema.yaml` | `fraud_rules`, `aml_verifications`, `fraud_alerts`, `outbox`, `processed_message` |
| `fraud-service` (outbox saga) | `pagofacil_fraud_service` | `db/fraud-service/changelog/00003_outbox.yaml` | Actualización outbox pattern para participante de saga |
| `notification-service` | `pagofacil_notification_service` | `db/notification-service/changelog/00001_initial_schema.yaml` | `notification_templates`, `notifications`, `processed_message` |
| `integration-service` | `pagofacil_integration_service` | `db/integration-service/changelog/00001_initial_schema.yaml` | `saga_instance`, `saga_step_log`, `external_requests`, `outbox`, `processed_message` |
| `audit-service` | `pagofacil_reporting` | `db/audit-service/changelog/00001_initial_schema.yaml` | `report_schema_catalog`, `report_jobs` |
| `audit-service` (seed) | `pagofacil_reporting` | `db/audit-service/changelog/00002_seed_report_catalog.yaml` | Datos iniciales de `report_schema_catalog` (5 tipos de reporte) |
| `projection-service` | `pagofacil_readmodel` | `db/projection-service/changelog/00001_initial_schema.yaml` | `report_transactions`, `report_alerts`, `report_wallets`, `report_reconciliations` |

> **Regla de propiedad:** cada tabla es propiedad de exactamente un microservicio. Ningún otro servicio hace DDL sobre ella. Los changelogs de cada servicio aplican sobre **su propia BD**, nunca sobre una BD compartida.

### Seed del catálogo de reportes (00002_seed_report_catalog.yaml)

El changelog `db/audit-service/changelog/00002_seed_report_catalog.yaml` pre-carga los 5 tipos de reporte definidos en el OpenAPI:

| `report_type` | `columns` (muestra) | `source_tables` | `formats` |
|---|---|---|---|
| `transacciones-diario` | transaction_id, user_id, amount, status, created_at | report_transactions | PDF, XLS, CSV |
| `reporte-aml` | alert_id, user_id, severity, alert_type, created_at | report_alerts | PDF, CSV |
| `alertas-fraude` | alert_id, transaction_id, severity, status | report_alerts | PDF, XLS, CSV |
| `saldo-usuarios` | wallet_id, user_id, available_balance, currency | report_wallets | PDF, CSV |
| `conciliacion` | reconciliation_id, transaction_id, discrepancy_type | report_reconciliations | PDF, XLS, CSV |

### Estructura de directorios esperada

```
db/
├── identity-service/
│   ├── liquibase.properties   # url, username, password, changeLogFile
│   └── changelog/
│       ├── root.yaml
│       └── 00001_initial_schema.yaml
├── wallet-service/
│   ├── liquibase.properties
│   └── changelog/
│       ├── root.yaml
│       ├── 00001_initial_schema.yaml
│       └── 00003_outbox.yaml
├── fraud-service/
│   ├── liquibase.properties
│   └── changelog/
│       ├── root.yaml
│       ├── 00001_initial_schema.yaml
│       └── 00003_outbox.yaml
├── notification-service/
│   ├── liquibase.properties
│   └── changelog/
│       ├── root.yaml
│       └── 00001_initial_schema.yaml
├── integration-service/
│   ├── liquibase.properties
│   └── changelog/
│       ├── root.yaml
│       └── 00001_initial_schema.yaml
├── audit-service/
│   ├── liquibase.properties
│   └── changelog/
│       ├── root.yaml
│       ├── 00001_initial_schema.yaml
│       └── 00002_seed_report_catalog.yaml
└── projection-service/
    ├── liquibase.properties
    └── changelog/
        ├── root.yaml
        └── 00001_initial_schema.yaml
```

---

## 5. Criterios de Aceptación

- [ ] `bash .claude/scripts/init-databases.sh -P pagofacil -p pagofacil -m pagofacil -u pagofacil_app -w P@gFacil_Dev2024` finalizó con checklist ✓ y cada servicio tiene su propia BD aislada.
- [ ] Cada BD existe en PostgreSQL dev: `psql -h localhost -U postgres -c "\l" | grep pagofacil` muestra 7 bases de datos.
- [ ] El usuario `pagofacil_app` puede conectarse a cada BD de su servicio: `psql -h localhost -U pagofacil_app -d pagofacil_identity_service -c "\dt"` ejecuta sin error.
- [ ] `pgcrypto` está habilitado en cada BD: `psql -h localhost -U postgres -d pagofacil_wallet_service -c "SELECT gen_random_uuid();"` retorna un UUID.
- [ ] `pagofacil_readmodel` existe y `pagofacil_app` tiene solo `SELECT` (no puede insertar): `psql -h localhost -U pagofacil_app -d pagofacil_readmodel -c "INSERT INTO report_transactions VALUES (...);"` retorna error de permisos.
- [ ] Los changelogs Liquibase se aplican sin errores: `bash .claude/scripts/run-liquibase-migrations.sh -P pagofacil -p pagofacil -u pagofacil_app -w P@gFacil_Dev2024` finaliza con todos los servicios en verde.
- [ ] Las tablas existen según el schema: `psql -h localhost -U pagofacil_app -d pagofacil_wallet_service -c "\dt"` muestra `wallets`, `transactions`, `fund_sources`, `transaction_limits`, `outbox`, `processed_message`.
- [ ] El seed del catálogo existe: `psql -h localhost -U pagofacil_app -d pagofacil_reporting -c "SELECT report_type FROM report_schema_catalog;"` retorna 5 filas.
