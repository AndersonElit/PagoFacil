# Etapa 2 — Scaffolding de Proyectos

**Proyecto:** PagoFacil | **Ambiente:** dev (floci + K3d)  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Objetivo

Generar la estructura base de todos los proyectos — microservicios Spring Boot, jobs Spark, frontend Next.js y el `integration-service` — con sus Jenkinsfiles, Dockerfiles, Helm charts, changelogs Liquibase, secrets floci y configuración de Terraform.

---

## 2. Scaffolding de Microservicios y Frontend

El script `.claude/scripts/scaffold-all-services.sh` unifica la generación de todos los proyectos. Acepta parámetros `--backend nombre:db:messaging:puerto` (repetible), `--frontend nombre`, `--bc-tags servicio=BC-XX`, `--integration-service`, `--saga-flows`, `--saga-participant`, `--outbox`, `--report-*` y los cuatro parámetros de BD obligatorios.

### Comando completo para PagoFacil

```bash
bash .claude/scripts/scaffold-all-services.sh \
  -P pagofacil \
  -p pagofacil \
  -m pagofacil \
  -u pagofacil_app \
  -w P@gFacil_Dev2024 \
  --backend identity-service:postgres:kafka-producer:8081 \
  --backend wallet-service:postgres:kafka-producer:8082 \
  --backend fraud-service:postgres:kafka-consumer:8083 \
  --backend notification-service:postgres:kafka-consumer:8084 \
  --backend audit-service:postgres:kafka-consumer:8085 \
  --backend projection-service:postgres:kafka-consumer:8087 \
  --backend reporting-projection-service:postgres:kafka-consumer:8088 \
  --bc-tags identity-service=BC-01 \
  --bc-tags wallet-service=BC-02 \
  --bc-tags fraud-service=BC-03 \
  --bc-tags notification-service=BC-04 \
  --bc-tags audit-service=BC-07 \
  --bc-tags integration-service=BC-06 \
  --integration-service "entidad-financiera=BC-06,proveedor-kyc=BC-06,listas-aml=BC-06" \
  --saga-flows DEPOSITO,RETIRO,TRANSFERENCIA,CONCILIACION \
  --saga-participant wallet-service \
  --saga-participant fraud-service \
  --saga-participant identity-service \
  --outbox wallet-service \
  --outbox fraud-service \
  --outbox identity-service \
  --report-extraction report-extraction-service:jdbc:report.extracted \
  --report-schedule "0 2 * * *" \
  --report-processing report-processing-service:report.extracted:report.processed \
  --report-types transacciones-diario,reporte-aml,alertas-fraude,saldo-usuarios,conciliacion \
  --report-formats pdf,xls,csv \
  --frontend pagofacil-web
```

> **Nota sobre `reporting-projection-service`:** el scaffold incluye este servicio como un Spring Boot reactivo con Kafka consumer + R2DBC PostgreSQL. `create-all-secrets-dev.sh` lo detecta por el patrón `*projection*` y le asigna `pagofacil_readmodel` como BD. Es el único escritor del Read Model.

### Resumen de servicios generados

| Servicio | Puerto | BD | Mensajería | Módulos generados |
|---|---|---|---|---|
| `identity-service` | 8081 | `pagofacil_identity_service` | kafka-producer | Maven hexagonal, Outbox, Dockerfile, Helm, Jenkinsfile, saga-participant, compensación |
| `wallet-service` | 8082 | `pagofacil_wallet_service` | kafka-producer | Maven hexagonal, Outbox, Dockerfile, Helm, Jenkinsfile, saga-participant, compensación |
| `fraud-service` | 8083 | `pagofacil_fraud_service` | kafka-consumer + producer | Maven hexagonal, Outbox, Dockerfile, Helm, Jenkinsfile, saga-participant, compensación |
| `notification-service` | 8084 | `pagofacil_notification_service` | kafka-consumer | Maven hexagonal, Dockerfile, Helm, Jenkinsfile |
| `audit-service` | 8085 | `pagofacil_reporting` | kafka-consumer | Maven hexagonal, Dockerfile, Helm, Jenkinsfile |
| `projection-service` | 8087 | `pagofacil_readmodel` | kafka-consumer | Maven hexagonal, Dockerfile, Helm, Jenkinsfile |
| `integration-service` | 8086 | `pagofacil_integration_service` | kafka-producer + consumer | integration_service_scaffold, Camel routes (3 sistemas externos), saga orchestrator (4 flows), Dockerfile, Helm, Jenkinsfile |
| `report-extraction-service` (MS1) | CronJob | JDBC `pagofacil_readmodel` + `pagofacil_reporting` | kafka-producer | scala_hexagonal_scaffold, CronJob Helm, Jenkinsfile batch |
| `report-processing-service` (MS2) | CronJob | S3 Parquet | kafka-consumer + producer | scala_hexagonal_scaffold, CronJob Helm, Jenkinsfile batch |
| `pagofacil-web` | 3000 (dev Vercel) | — | — | Next.js 15 app router, Jenkinsfile frontend |
| Serverless reporting | — | S3 | kafka-consumer + EventBridge | Python lambdas (PDF, XLS, CSV), Terraform EventBridge |

---

## 3. Generación de Changelogs Liquibase

> Esta sección describe los pasos 5 y 6 ejecutados automáticamente por `scaffold-all-services.sh`. No son pasos manuales.

**Paso 5 — Changelog inicial por microservicio:**  
Para cada servicio con `--bc-tags`, el script extrae el bloque `-- BC-XX:` del `docs/design/database/SDD-PagoFacil-schema.sql` y genera `db/<servicio>/changelog/00001_initial_schema.yaml`. Idempotente: si el archivo ya existe, lo omite.

**Paso 6 — Changelogs especiales:**
- `db/wallet-service/changelog/00003_outbox.yaml`: tablas `outbox` y `processed_message` para el patrón Outbox como participante de saga.
- `db/fraud-service/changelog/00003_outbox.yaml`: ídem para `fraud-service`.
- `db/identity-service/changelog/00003_outbox.yaml`: ídem para `identity-service`.
- `db/audit-service/changelog/00002_seed_report_catalog.yaml`: 5 tipos de reporte con esquemas y formatos.

**Changelogs que requieren creación manual:**
- `db/projection-service/changelog/00001_initial_schema.yaml`: la sección `-- CQRS Read Model:` del schema.sql no tiene un tag `-- BC-XX:`, por lo que el scaffold no puede extraerla automáticamente. Copiar manualmente las tablas `report_transactions`, `report_alerts`, `report_wallets`, `report_reconciliations` desde el schema de referencia.

---

## 4. Verificación Post-Scaffolding

> Esta sección describe los pasos 9 y 10 ejecutados automáticamente. No son pasos manuales.

**Paso 9 — Compilación backend (`compile-services.sh`):**  
Detecta todos los directorios `*-service` en `backend/` con `find`, ejecuta `mvn -q -DskipTests package` en cada uno, reporta OK/FALLA por servicio y sale con código 1 si algún servicio falla.

**Paso 10 — Verificación frontend (`verify-frontend.sh`):**  
Detecta `frontend/pagofacil-web`, ejecuta `npm install`, `npm run type-check` y `npm run lint`. Se omite si no se pasó `--frontend` al script.

---

## 5. Configuración Inicial Post-Scaffold

> Esta sección describe el paso 11 ejecutado automáticamente. Sin edición manual posterior.

**Paso 11 — Secrets floci (`create-all-secrets-dev.sh`, automático):**  
Lee los parámetros de BD (`-p pagofacil -m pagofacil -u pagofacil_app -w P@gFacil_Dev2024`) y los outputs de Terraform (`rds_port`, `user_pool_endpoint`). Para cada servicio:
- Detecta el tipo de BD inspeccionando `infrastructure/driven-adapters/`.
- Deriva la BD propia: `pagofacil_<svc_slug>` (ej: `identity-service` → `pagofacil_identity_service`).
- Detecta si usa Kafka buscando `driven-adapters/kafka-producer/` o `entry-points/kafka-consumer/`.
- Aplica upsert idempotente en floci Secrets Manager con el secret `pagofacil/dev/<servicio>`.

**Secreto generado por servicio (ejemplo: `identity-service`):**

```json
{
  "R2DBC_URL": "r2dbc:postgresql://pagofacil-postgres-dev:5432/pagofacil_identity_service",
  "DB_USERNAME": "pagofacil_app",
  "DB_PASSWORD": "P@gFacil_Dev2024",
  "KAFKA_BOOTSTRAP_SERVERS": "pagofacil-kafka-dev:9092",
  "COGNITO_USER_POOL_ENDPOINT": "<output Terraform>",
  "NARAYANA_LRA_COORDINATOR_URL": "http://narayana-lra:8180/lra-coordinator"
}
```

**Override puntual de puerto RDS:**

```bash
export RDS_PORT=5432 && bash .claude/scripts/create-all-secrets-dev.sh \
  -P pagofacil -p pagofacil -m pagofacil -u pagofacil_app -w P@gFacil_Dev2024
```

**Frontend `.env.local`:**  
El script crea `frontend/pagofacil-web/.env.local` con:

```bash
COGNITO_ISSUER_URI=<output Terraform user_pool_endpoint>
COGNITO_CLIENT_ID=<output Terraform cognito_client_id>
NEXTAUTH_URL=http://localhost:3001
NEXTAUTH_SECRET=<openssl rand -base64 32>
NEXT_PUBLIC_API_BASE_URL=http://localhost:8080
```

---

## 6. Re-aplicar Infraestructura Terraform (dev)

> Esta sección describe los pasos 12, 13 y 14 ejecutados automáticamente.

`maven_hexagonal_scaffold.py` edita `terraform/backend/environments/{dev,staging,prod}/main.tf` agregando cada servicio a la lista `services = [...]` de `module.ecr` y `module.secrets_manager`. Solo `dev` se aplica en esta etapa.

**Paso 12 — Terraform apply (automático):**

```bash
cd terraform/backend/environments/dev && terraform apply -auto-approve
```

**Paso 13 — Verificación ECR (automático):**

```bash
aws --endpoint-url=http://localhost:4566 ecr describe-repositories \
  --region us-east-1 \
  --query 'repositories[].repositoryName' \
  --output table
```

Criterio: un repositorio por cada microservicio generado (7 repositorios de dominio + MS1 + MS2 = 9 mínimo).

**Paso 14 — Verificación secrets (automático):**

```bash
aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets \
  --region us-east-1 \
  --query 'SecretList[?starts_with(Name, `pagofacil/dev/`)].Name' \
  --output table
```

Criterio: `pagofacil/dev/identity-service`, `pagofacil/dev/wallet-service`, `pagofacil/dev/fraud-service`, `pagofacil/dev/notification-service`, `pagofacil/dev/audit-service`, `pagofacil/dev/integration-service`, `pagofacil/dev/projection-service`.

---

## 7. Descripción de Artefactos por Tipo de Servicio

### Backend `Jenkinsfile` (Spring Boot / Maven)

Stages del pipeline CI para servicios Maven:

| Stage | Step shared library | Descripción |
|---|---|---|
| Compute Image Tag | `computeImageTag` | Genera el tag de imagen basado en git SHA |
| Build | `buildBackendService` | `mvn clean package -DskipTests` |
| Integration Tests | `runIntegrationTests` | `mvn verify` con Testcontainers |
| Quality Gate | `runQualityGates` | SonarQube analysis + gate |
| Security Scan | `runSecurityScans` | OWASP Dependency-Check |
| Build & Push Image | `buildAndPushImage` | Kaniko: construye imagen y hace push al registry K3d |
| Scan Image | `scanImage` | Trivy: escaneo de vulnerabilidades |
| Bump Image Tag | `bumpImageTag` | Actualiza `helm/<service>/values-dev.yaml` y hace push a Gitea |
| Smoke Tests | `runSmokeTests` | Prueba mínima del endpoint `/actuator/health` en K3d |
| Notify | `notify` | Slack (opcional en dev) o echo en log |

El pod se carga desde `org/pagofacil/podBackend.yaml` (contenedor `maven`). Corre en K3d (dev) o EKS (staging/prod).

### Batch `Jenkinsfile` (Spark / Scala)

Stages del pipeline CI para servicios Spark (sin smoke tests — no exponen HTTP):

| Stage | Step shared library | Descripción |
|---|---|---|
| Compute Image Tag | `computeImageTag` | Tag basado en git SHA |
| Build Scala Batch | `buildScalaBatchJob` | `sbt clean test` + `sbt "entryPoints/assembly"` |
| Quality Gate | `runQualityGates(projectType:'sbt')` | `sbt sonarScan` |
| Security Scan | `runSecurityScans(projectType:'sbt')` | `sbt dependencyCheckAggregate` |
| Build & Push Image | `buildAndPushImage` | Kaniko |
| Scan Image | `scanImage` | Trivy |
| Bump Image Tag | `bumpImageTag` | Actualiza `helm/<service>/values-dev.yaml` → ArgoCD sincroniza el **CronJob** |
| Notify | `notify` | Slack / echo |

El pod se carga desde `org/pagofacil/podScalaBatch.yaml` (contenedor `sbt`, sin sidecar dind).

### Frontend `Jenkinsfile` (Next.js / Vercel)

| Stage | Descripción |
|---|---|
| Install | `npm ci` |
| Type Check | `npm run type-check` |
| Lint | `npm run lint` |
| Unit Tests | `npm run test` (Vitest) |
| Pull config Vercel | `vercel env pull` |
| Build | `npm run build` |
| Deploy prebuilt | `vercel deploy --prebuilt` |
| E2E Tests | Playwright contra la preview URL |
| Promote / Alias prod | `vercel alias` (solo en rama `main`) |
| Notify | Slack / echo |

La Git integration de Vercel se **desactiva**. Jenkins es el único disparador de despliegues.

### `Dockerfile` backend (Maven)

Multi-stage con caché de dependencias:

```dockerfile
# Stage 1: Build
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn -q -DskipTests package

# Stage 2: Runtime
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### `Dockerfile` batch (Scala / sbt)

Multi-stage con caché de dependencias sbt:

```dockerfile
# Stage 1: Deps cache
FROM sbt:1.9-eclipse-temurin-17 AS deps
WORKDIR /app
COPY build.sbt .
COPY project/ ./project/
RUN sbt update

# Stage 2: Assembly
FROM deps AS builder
COPY src ./src
RUN sbt "entryPoints/assembly"

# Stage 3: Runtime
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
COPY --from=builder /app/target/scala-2.13/*-assembly.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Helm charts `helm/<service>/`

- Servicios Maven → `templates/deployment.yaml` (Deployment + Service + readiness/liveness probes en `/actuator/health/readiness` y `/actuator/health/liveness`).
- Servicios Scala → `templates/cronjob.yaml` (CronJob con `concurrencyPolicy: Forbid`, `restartPolicy: Never`).
- `values-dev.yaml` / `values-staging.yaml` / `values-prod.yaml` contienen `image.repository` y `image.tag` que escribe `bumpImageTag` y lee ArgoCD.

### Gitea: push automático en dev

El scaffold (`maven_hexagonal_scaffold.py` / `nextjs_feature_scaffold.py`) crea el repositorio en Gitea (`http://gitea:3000/pagofacil/<servicio>.git`) y hace push de la rama `main` con credenciales `gitea-admin:gitea-admin`. No requiere `git push` manual en dev.

---

## 8. Criterios de Aceptación

- [ ] `bash .claude/scripts/scaffold-all-services.sh` (con todos los parámetros del Paso 2) finalizó los 14 pasos con código de salida 0.
- [ ] Cada directorio de microservicio existe en `backend/`: `backend/identity-service/`, `backend/wallet-service/`, `backend/fraud-service/`, `backend/notification-service/`, `backend/audit-service/`, `backend/integration-service/`, `backend/projection-service/`.
- [ ] Los jobs Spark existen en `backend/report-extraction-service/` y `backend/report-processing-service/`.
- [ ] El frontend existe en `frontend/pagofacil-web/`.
- [ ] Los changelogs iniciales existen: `db/<svc>/changelog/00001_initial_schema.yaml` para cada servicio PostgreSQL (paso 5).
- [ ] El seed de catálogo de reportes existe: `db/audit-service/changelog/00002_seed_report_catalog.yaml` (paso 6).
- [ ] `db/projection-service/changelog/00001_initial_schema.yaml` creado manualmente con las tablas del Read Model.
- [ ] Cada servicio `backend/*-service/` compila sin errores con Maven: `mvn -q -DskipTests package` (paso 9).
- [ ] El frontend pasa type-check y lint: `npm run type-check && npm run lint` (paso 10).
- [ ] Los repositorios ECR existen en floci para todos los microservicios (paso 13).
- [ ] Los secrets `pagofacil/dev/<servicio>` existen en floci con valores correctos (paso 14).
- [ ] `frontend/pagofacil-web/.env.local` existe con las variables de Cognito y NextAuth.
- [ ] Cada repositorio de servicio existe en Gitea: `curl -u gitea-admin:gitea-admin http://localhost:3000/api/v1/repos/pagofacil/identity-service` retorna HTTP 200.
- [ ] Los Jenkinsfiles existen en la raíz de cada proyecto generado: `backend/identity-service/Jenkinsfile`.
- [ ] Los Helm charts existen: `helm/identity-service/templates/deployment.yaml`.
- [ ] Los Helm charts de servicios Spark usan CronJob: `helm/report-extraction-service/templates/cronjob.yaml`.
