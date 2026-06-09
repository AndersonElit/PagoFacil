# Etapa 1 — Bases de Datos y Migraciones

**Proyecto:** PagoFacil — Billetera Digital
**Etapa:** 1 — Bases de Datos y Migraciones
**Versión:** 1.0
**Fecha:** 2026-06-08

---

## 0. Automatización

Toda la creación de bases de datos de esta etapa se automatiza con un único script. Ejecutar en el directorio raíz del repositorio:

```bash
bash .claude/scripts/init-databases.sh \
  -P pagofacil \
  --vps-ip <VPS_IP> \
  -p pagofacil \
  -m pagofacil \
  -u pagofacil_app \
  -w p4g0f4c1l4pp
```

### Qué automatiza el script

El script realiza las siguientes acciones en orden:

1. Conecta a PostgreSQL 16 en `<VPS_IP>:5432` como superusuario y crea las siguientes bases de datos si no existen:
   - `pagofacil_identity_service`
   - `pagofacil_wallet_service`
   - `pagofacil_fraud_compliance_service`
   - `pagofacil_notification_service`
   - `pagofacil_integration_service`
   - `pagofacil_readmodel`
   - `pagofacil_reporting`
2. Crea el usuario de aplicación `pagofacil_app` (si no existe) con la contraseña `<CLAVE_APP>` y le otorga `CONNECT` y privilegios de DML (`SELECT`, `INSERT`, `UPDATE`, `DELETE`) en cada base de datos.
3. Conecta a MongoDB 7 en `<VPS_IP>:27017` y crea la base de datos `pagofacil_audit_service` con el usuario `pagofacil_app`.
4. Imprime un checklist al finalizar con el estado de cada base de datos creada.

> **No aplica migraciones de schema.** La aplicación del esquema DDL se realiza por separado con `bash .claude/scripts/run-liquibase-migrations.sh --gitea-clone`, que clona el repositorio `pagofacil-migrations` desde Gitea y ejecuta los changelogs Liquibase de cada microservicio antes del despliegue.

---

## 1. Objetivo

Provisionar todas las bases de datos del proyecto PagoFacil en el VPS de desarrollo y definir la estrategia de gestión de esquemas mediante Liquibase standalone. Al finalizar esta etapa cada microservicio debe tener su base de datos aislada, su usuario de aplicación configurado y su repositorio de changelogs Liquibase preparado para recibir migraciones incrementales.

---

## 2. Estrategia de Persistencia

### Patrón: Database-per-Service

Cada microservicio posee y gestiona su propia base de datos de forma exclusiva. Ningún otro servicio accede directamente a la base de datos de otro contexto. La comunicación entre servicios que necesita datos de otro dominio se resuelve mediante **eventos de dominio** (Kafka) o **llamadas REST** al servicio propietario, nunca con acceso directo a la BD ajena.

### Convención de Nomenclatura

| Elemento | Convención | Ejemplo |
|---|---|---|
| Prefijo de proyecto | `pagofacil` | — |
| Base de datos PostgreSQL | `pagofacil_<servicio_slug>` | `pagofacil_identity_service` |
| Base de datos MongoDB | `pagofacil_<servicio_slug>` | `pagofacil_audit_service` |
| Usuario de aplicación | `pagofacil_app` | — |

El `<servicio_slug>` es el nombre del microservicio en snake_case sin el sufijo `-service` convertido: `identity-service` → `identity_service`.

---

## 3. PostgreSQL — Esquema Relacional

Referencia completa: [`docs/design/database/SDD-PagoFacil-schema.sql`](../design/database/SDD-PagoFacil-schema.sql)

| Bounded Context | Base de Datos | Tablas |
|---|---|---|
| BC-01 identity-service | `pagofacil_identity_service` | `users`, `kyc_records`, `mfa_devices`, `sessions`, `outbox`, `processed_message` |
| BC-02 wallet-service | `pagofacil_wallet_service` | `wallets`, `wallet_transactions`, `transaction_limits`, `linked_bank_accounts`, `outbox`, `processed_message` |
| BC-03 fraud-compliance-service | `pagofacil_fraud_compliance_service` | `fraud_rules`, `risk_evaluations`, `compliance_alerts`, `outbox`, `processed_message` |
| BC-04 notification-service | `pagofacil_notification_service` | `notification_templates`, `notification_preferences`, `notifications`, `processed_message` |
| BC-05 integration-service | `pagofacil_integration_service` | `saga_instance`, `saga_step_log`, `external_integration_events`, `reconciliation_records`, `outbox`, `processed_message` |
| BC-07 projection-service (read model) | `pagofacil_readmodel` | `report_transactions`, `report_compliance_alerts`, `report_users` |
| BC-07 report-extraction-service (reporting) | `pagofacil_reporting` | `report_schema_catalog`, `report_executions` |

### Tablas Transversales

Las tablas `outbox` y `processed_message` aparecen en los servicios que participan en el patrón Transactional Outbox + idempotent consumer:

- `outbox` — registra eventos de dominio pendientes de publicar a Kafka (escrita en la misma transacción que la operación de negocio).
- `processed_message` — registra IDs de mensajes Kafka ya procesados (garantía de exactly-once en el consumidor).

`notification-service` e `projection-service` implementan solo `processed_message` ya que son consumidores puros (no producen eventos de dominio propios).

---

## 4. PostgreSQL — Changelogs Liquibase por Microservicio

### Repositorio de Migraciones

Los changelogs Liquibase de todos los microservicios residen en un repositorio dedicado:

```
http://<VPS_IP>:3000/pagofacil/pagofacil-migrations
```

El script `run-liquibase-migrations.sh --gitea-clone` clona este repositorio y ejecuta los changelogs de cada microservicio antes del despliegue. Liquibase corre en modo standalone (sin depender del microservicio).

### Estructura del Repositorio

```
pagofacil-migrations/
├── identity-service/
│   ├── changelog-master.yaml
│   ├── 00001_initial_schema.yaml
│   ├── 00002_seed_roles.yaml
│   └── 00003_outbox.yaml
├── wallet-service/
│   ├── changelog-master.yaml
│   ├── 00001_initial_schema.yaml
│   └── 00003_outbox.yaml
├── fraud-compliance-service/
│   ├── changelog-master.yaml
│   ├── 00001_initial_schema.yaml
│   └── 00003_outbox.yaml
├── notification-service/
│   ├── changelog-master.yaml
│   └── 00001_initial_schema.yaml
├── integration-service/
│   ├── changelog-master.yaml
│   ├── 00001_initial_schema.yaml
│   └── 00003_outbox.yaml
├── projection-service/
│   ├── changelog-master.yaml
│   └── 00001_initial_schema.yaml
└── reporting/
    ├── changelog-master.yaml
    └── 00001_initial_schema.yaml
```

### Nomenclatura de ChangeSets

| Nombre de archivo | Contenido |
|---|---|
| `00001_initial_schema.yaml` | Tablas principales del bounded context (CREATE TABLE con índices y constraints) |
| `00002_seed_roles.yaml` | Datos semilla de roles, configuraciones iniciales o catálogos (aplica solo donde corresponda) |
| `00003_outbox.yaml` | Tablas `outbox` y `processed_message` (aplica solo a servicios con Transactional Outbox) |

### Asignación de Tablas por Microservicio

| Microservicio | BD propietaria | ChangeSets |
|---|---|---|
| `identity-service` | `pagofacil_identity_service` | `00001` (users, kyc_records, mfa_devices, sessions) · `00002` (seed roles) · `00003` (outbox, processed_message) |
| `wallet-service` | `pagofacil_wallet_service` | `00001` (wallets, wallet_transactions, transaction_limits, linked_bank_accounts) · `00003` (outbox, processed_message) |
| `fraud-compliance-service` | `pagofacil_fraud_compliance_service` | `00001` (fraud_rules, risk_evaluations, compliance_alerts) · `00003` (outbox, processed_message) |
| `notification-service` | `pagofacil_notification_service` | `00001` (notification_templates, notification_preferences, notifications, processed_message) |
| `integration-service` | `pagofacil_integration_service` | `00001` (saga_instance, saga_step_log, external_integration_events, reconciliation_records) · `00003` (outbox, processed_message) |
| `projection-service` | `pagofacil_readmodel` | `00001` (report_transactions, report_compliance_alerts, report_users, processed_message) |
| `report-extraction-service` | `pagofacil_reporting` | `00001` (report_schema_catalog, report_executions) |

### Reglas de Propiedad de Tablas

- **Una tabla pertenece a exactamente un microservicio.** Ninguna tabla es compartida entre servicios.
- **Solo el servicio propietario define y mantiene los changelogs de sus tablas.** Otro servicio que necesite datos de esas tablas los obtiene vía API REST o evento Kafka del servicio propietario.
- **Los changelogs son inmutables una vez aplicados.** Para modificar un esquema se agrega un nuevo changeSet incremental; nunca se edita un changeSet ya ejecutado en algún ambiente.
- **El `id` de cada changeSet sigue el formato `<NNNNNN>-<descripcion-kebab>`.** Ejemplo: `00001-create-users-table`.

---

## 5. MongoDB — Colecciones y Validadores

Referencia completa: [`docs/design/database/SDD-PagoFacil-collections.js`](../design/database/SDD-PagoFacil-collections.js)

| Bounded Context | Base de Datos | Colección | Características |
|---|---|---|---|
| BC-06 audit-service | `pagofacil_audit_service` | `audit_traces` | Append-only. Sin operaciones UPDATE ni DELETE. Validador JSON Schema estricto aplicado a nivel de colección en MongoDB. |

### Colección `audit_traces`

La colección `audit_traces` registra trazas de auditoría inmutables de todas las operaciones de negocio del sistema. Sus características de diseño son:

- **Append-only:** el usuario `pagofacil_app` tiene permisos `find` e `insert` únicamente. Las operaciones `update` y `delete` están denegadas a nivel de rol MongoDB.
- **Validador JSON Schema estricto:** MongoDB aplica la validación del esquema en cada inserción (`validationAction: "error"`). Los documentos que no cumplan el schema son rechazados.
- **Sin migraciones Liquibase:** la creación de la colección y la aplicación del validador se realiza mediante el script MongoDB incluido en `SDD-PagoFacil-collections.js`, ejecutado por `init-databases.sh` en el paso de provisioning de MongoDB.
- **Índices:** índice compuesto `{ tenantId: 1, occurredAt: -1 }` para las consultas de auditoría paginadas por tenant. Índice `{ correlationId: 1 }` para trazabilidad de transacciones distribuidas.

---

## 6. Criterios de Aceptación

- [ ] `bash .claude/scripts/init-databases.sh -P pagofacil --vps-ip <VPS_IP> -p pagofacil -m pagofacil -u pagofacil_app -w <CLAVE_APP>` finaliza con checklist impreso con todos los ítems marcados como exitosos y cada servicio tiene su BD aislada.
- [ ] `psql -h <VPS_IP> -U pagofacil_app -d pagofacil_identity_service -c "\dt"` retorna las tablas de identity-service sin error de conexión.
- [ ] `psql -h <VPS_IP> -U pagofacil_app -d pagofacil_wallet_service -c "\dt"` retorna las tablas de wallet-service sin error de conexión.
- [ ] `psql -h <VPS_IP> -U pagofacil_app -d pagofacil_fraud_compliance_service -c "\dt"` retorna las tablas de fraud-compliance-service sin error de conexión.
- [ ] `psql -h <VPS_IP> -U pagofacil_app -d pagofacil_notification_service -c "\dt"` retorna las tablas de notification-service sin error de conexión.
- [ ] `psql -h <VPS_IP> -U pagofacil_app -d pagofacil_integration_service -c "\dt"` retorna las tablas de integration-service sin error de conexión.
- [ ] `psql -h <VPS_IP> -U pagofacil_app -d pagofacil_readmodel -c "\dt"` retorna las tablas del read model sin error de conexión.
- [ ] `psql -h <VPS_IP> -U pagofacil_app -d pagofacil_reporting -c "\dt"` retorna las tablas de reporting sin error de conexión.
- [ ] Un usuario de PostgreSQL que no sea `pagofacil_app` ni superusuario no puede conectarse a ninguna de las bases de datos anteriores.
- [ ] `mongosh "mongodb://<VPS_IP>:27017/pagofacil_audit_service" --eval "db.getCollectionNames()"` lista la colección `audit_traces`.
- [ ] El validador JSON Schema de `audit_traces` rechaza un documento de inserción que omita campos obligatorios (prueba manual con `db.audit_traces.insertOne({})` → error de validación).
- [ ] `mongosh` con el usuario `pagofacil_app` no puede ejecutar `db.audit_traces.deleteOne({})` ni `db.audit_traces.updateOne({}, { $set: {} })` (operaciones denegadas por rol).
- [ ] El repositorio `pagofacil-migrations` existe en `http://<VPS_IP>:3000/pagofacil/pagofacil-migrations` con la estructura de directorios por microservicio definida en la sección 4.
- [ ] `bash .claude/scripts/run-liquibase-migrations.sh --gitea-clone` aplica los changelogs de todos los microservicios sin errores y Liquibase reporta `0 changesets failed` para cada servicio.
- [ ] Ninguna tabla de un microservicio es accesible con `pagofacil_app` desde la base de datos de otro microservicio (aislamiento Database-per-Service verificado).
