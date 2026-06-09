# Etapa 2 — Scaffolding de Proyectos

---

## 1. Objetivo

Generar la estructura base de todos los proyectos que componen la plataforma PagoFacil: microservicios Spring Boot, jobs batch Spark/Scala, frontend Next.js, changelogs Liquibase, Helm charts, Dockerfiles, Jenkinsfiles y configuración inicial de secrets. Al finalizar esta etapa, cada repositorio debe estar creado en Gitea, compilar sin errores y contar con sus secrets de ambiente dev disponibles en floci.

---

## 2. Scaffolding de Microservicios y Frontend

### 2.1 Comando principal

El script `scaffold-all-services.sh` genera todos los proyectos en un único paso. Ejecutar desde la raíz del repositorio de infraestructura:

```bash
bash .claude/scripts/scaffold-all-services.sh \
  -P pagofacil \
  --vps-ip <VPS_IP> \
  -p pagofacil \
  -m pagofacil \
  -u pagofacil_app \
  -w <CLAVE_APP> \
  --backend identity-service:postgres:kafka-producer:8081 \
  --backend wallet-service:postgres:kafka-producer+kafka-consumer:8082 \
  --backend fraud-compliance-service:postgres:kafka-producer+kafka-consumer:8083 \
  --backend notification-service:postgres:kafka-consumer:8084 \
  --backend audit-service:mongo:kafka-consumer:8086 \
  --backend reporting-projection-service:postgres:kafka-consumer:8087 \
  --frontend pagofacil-web \
  --bc-tags identity-service=BC-01 \
  --bc-tags wallet-service=BC-02 \
  --bc-tags fraud-compliance-service=BC-03 \
  --bc-tags notification-service=BC-04 \
  --bc-tags reporting-projection-service=BC-07 \
  --integration-service "kyc=BC-01,aml=BC-03,financial-entities=BC-02,payment-gateways=BC-02,sms-email=BC-04" \
  --saga-flows deposit,transfer,withdrawal \
  --saga-participant identity-service \
  --saga-participant wallet-service \
  --saga-participant fraud-compliance-service \
  --outbox identity-service \
  --outbox wallet-service \
  --outbox fraud-compliance-service \
  --report-extraction report-extraction-service:jdbc:report.extracted \
  --report-processing report-processing-service:report.extracted:report.processed \
  --report-types TRANSACTIONS,COMPLIANCE_ALERTS,USERS \
  --report-formats pdf,xls,csv \
  --report-schedule "0 2 * * *"
```

> **Nota:** `integration-service` (Apache Camel 4 + Narayana LRA) se genera internamente mediante el flag `--integration-service`. No lleva `--bc-tags` propio ya que actúa como orquestador de integraciones externas. `audit-service` tampoco lleva `--bc-tags` porque su persistencia es MongoDB, no PostgreSQL.

### 2.2 Tabla resumen de servicios

| Servicio | Puerto | BD | Mensajería | Módulos generados | Tipo |
|---|---|---|---|---|---|
| identity-service | 8081 | PostgreSQL | Kafka Producer | BC-01, Outbox, Saga Participant, R2DBC, Liquibase | Spring Boot WebFlux |
| wallet-service | 8082 | PostgreSQL | Kafka Producer + Consumer | BC-02, Outbox, Saga Participant, R2DBC, Liquibase | Spring Boot WebFlux |
| fraud-compliance-service | 8083 | PostgreSQL | Kafka Producer + Consumer | BC-03, Outbox, Saga Participant, R2DBC, Liquibase | Spring Boot WebFlux |
| notification-service | 8084 | PostgreSQL | Kafka Consumer | BC-04, R2DBC, Liquibase | Spring Boot WebFlux |
| integration-service | 8085 | PostgreSQL | Kafka Producer + Consumer | Camel Routes, LRA, Outbox, R2DBC, Liquibase | Spring Boot WebFlux + Camel |
| audit-service | 8086 | MongoDB | Kafka Consumer | Reactive Mongo, Event Store | Spring Boot WebFlux |
| reporting-projection-service | 8087 | PostgreSQL | Kafka Consumer | BC-07, Read Model, R2DBC, Liquibase | Spring Boot WebFlux |
| report-extraction-service | — | JDBC (PostgreSQL) | — | Spark Job, CronJob Helm, Assembly SBT | Spark 3.5 / Scala 3 |
| report-processing-service | — | — | report.extracted → report.processed | Spark Job, CronJob Helm, Assembly SBT | Spark 3.5 / Scala 3 |
| pagofacil-web | — | — | — | Next.js 14 App Router, TypeScript, ESLint | Next.js / React |

### 2.3 Artefactos generados por el scaffold

#### Observabilidad (automática)

Cada servicio Spring Boot recibe los siguientes artefactos de observabilidad sin intervención manual:

- **`src/main/resources/logback-spring.xml`**: configuración de logs estructurados en formato JSON con correlación de trazas (traceId, spanId).
- **Dependencias Maven** (agregadas al `pom.xml`): `micrometer-registry-prometheus`, `micrometer-tracing-bridge-otel`, `opentelemetry-exporter-otlp`.
- **`application.yml` — bloque `management`**: expone endpoints `/actuator/health`, `/actuator/prometheus`, `/actuator/info`; configura `management.tracing.sampling.probability=1.0` en dev.
- **Anotaciones Prometheus** en `templates/deployment.yaml` del Helm chart: `prometheus.io/scrape: "true"`, `prometheus.io/port`, `prometheus.io/path: /actuator/prometheus`.
- **Init container `otel-agent`** en el Helm chart: descarga y monta el agente OTEL Java antes del arranque del servicio principal.

#### Repositorios Gitea

Cada scaffold crea automáticamente el repositorio correspondiente en Gitea y realiza el primer push:

- URL base: `http://<VPS_IP>:3000/pagofacil/`
- Credenciales de push inicial: `gitea-admin:gitea-admin`
- El repositorio se crea como privado dentro de la organización `pagofacil`.

### 2.4 Pipelines CI/CD (Jenkinsfiles)

#### Backend — Spring Boot / Maven

| # | Stage | Descripción |
|---|---|---|
| 1 | `computeImageTag` | Calcula el tag de imagen con hash de commit corto y timestamp |
| 2 | `buildBackendService` | `mvn clean package -DskipTests`; genera el JAR ejecutable |
| 3 | `runIntegrationTests` | `mvn verify` con perfil `integration`; levanta contenedores Testcontainers |
| 4 | `runQualityGates` | SonarQube analysis; falla el pipeline si Quality Gate no pasa |
| 5 | `runSecurityScans` | OWASP Dependency-Check; genera reporte de CVEs |
| 6 | `buildAndPushImage` | `docker build` + `docker push` hacia Gitea Package Registry `<VPS_IP>:3000/pagofacil` |
| 7 | `scanImage` | Trivy scan sobre la imagen recién publicada; bloquea en severidad CRITICAL |
| 8 | `bumpImageTag` | Actualiza el `values.yaml` del Helm chart con el nuevo tag y hace commit al repo |
| 9 | `runSmokeTests` | Valida endpoints `/actuator/health` del despliegue en K3s dev tras sync ArgoCD |
| 10 | `notify` | Envía notificación (Slack / email) con resultado del pipeline |

#### Batch — Spark / Scala (sbt)

| # | Stage | Descripción |
|---|---|---|
| 1 | `computeImageTag` | Calcula el tag de imagen con hash de commit corto y timestamp |
| 2 | `buildScalaBatchJob` | `sbt "entryPoints/assembly"`; genera el fat JAR con dependencias |
| 3 | `runQualityGates` | `sbt scoverage:report` + análisis SonarQube para cobertura Scala |
| 4 | `runSecurityScans` | `sbt dependencyCheck`; reporta CVEs en dependencias SBT |
| 5 | `buildAndPushImage` | `docker build` + `docker push` hacia Gitea Package Registry `<VPS_IP>:3000/pagofacil` |
| 6 | `scanImage` | Trivy scan sobre la imagen del job Spark |
| 7 | `bumpImageTag` | Actualiza el `values.yaml` del CronJob Helm chart con el nuevo tag |
| 8 | `notify` | Envía notificación con resultado; sin smoke tests HTTP (pipeline CI puro) |

> Los jobs Spark son CronJobs de K3s. No existe endpoint HTTP que verificar; el smoke test se sustituye por validación de logs de ejecución en el siguiente ciclo del cron.

#### Frontend — Next.js 14

| # | Stage | Descripción |
|---|---|---|
| 1 | `Install` | `npm ci` con caché de `node_modules` |
| 2 | `Type Check` | `npm run type-check` (`tsc --noEmit`) |
| 3 | `Lint` | `npm run lint` (ESLint + reglas Next.js) |
| 4 | `Unit Tests` | `npm test -- --ci --coverage` (Jest / React Testing Library) |
| 5 | `Build` | `npm run build`; genera el bundle de producción |
| 6 | `docker build` | Construye la imagen Docker multi-stage del frontend |
| 7 | `push Gitea registry` | Push de la imagen hacia Gitea Package Registry `<VPS_IP>:3000/pagofacil` |
| 8 | `bumpImageTag` | Actualiza el `values.yaml` del Helm chart del frontend |
| 9 | `ArgoCD sync → K3s` | Sincronización ArgoCD; despliega como pod en K3s con Ingress Traefik |
| 10 | `E2E Tests` | Playwright contra la URL del Ingress Traefik en K3s dev |
| 11 | `Notify` | Notificación con resultado del pipeline |

> **El frontend se despliega como pod en K3s con Ingress Traefik. No se utiliza Vercel.**

### 2.5 Dockerfiles

#### Backend — Spring Boot (Maven)

Dockerfile multi-stage optimizado para producción:

```dockerfile
# Stage 1 — Build
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn clean package -DskipTests -q

# Stage 2 — Runtime
FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/target/*.jar app.jar
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-javaagent:/otel-agent/opentelemetry-javaagent.jar", "-jar", "app.jar"]
```

#### Batch — Spark / Scala (sbt)

Dockerfile multi-stage con caché de dependencias SBT:

```dockerfile
# Stage 1 — Descarga de dependencias (caché)
FROM sbtscala/scala-sbt:eclipse-temurin-17.0.5_8_1.9.3_3.3.1 AS deps
WORKDIR /app
COPY build.sbt .
COPY project/ ./project/
RUN sbt update

# Stage 2 — Assembly del fat JAR
FROM deps AS builder
COPY src ./src
RUN sbt "entryPoints/assembly"

# Stage 3 — Runtime mínimo
FROM eclipse-temurin:17-jre-jammy AS runtime
WORKDIR /app
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser
COPY --from=builder /app/target/scala-3*/entryPoints-assembly-*.jar app.jar
USER appuser
ENTRYPOINT ["java", "-cp", "app.jar", "com.pagofacil.batch.EntryPoint"]
```

### 2.6 Helm Charts

#### Spring Boot — `templates/deployment.yaml`

El Helm chart de cada servicio Spring Boot incluye:

- **`Deployment`**: con `readinessProbe` y `livenessProbe` sobre `/actuator/health`, variables de entorno inyectadas desde secrets de floci, init container `otel-agent`.
- **`Service`**: tipo `ClusterIP` exponiendo el puerto configurado del servicio.
- **Probes configuradas**:
  - `readinessProbe`: `httpGet /actuator/health/readiness`, `initialDelaySeconds: 20`, `periodSeconds: 10`.
  - `livenessProbe`: `httpGet /actuator/health/liveness`, `initialDelaySeconds: 40`, `periodSeconds: 15`.

#### Spark — `templates/cronjob.yaml`

El Helm chart de cada job Spark genera un `CronJob` con las siguientes propiedades clave:

```yaml
spec:
  schedule: "0 2 * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: spark-job
              image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

- `concurrencyPolicy: Forbid`: evita ejecuciones solapadas del job.
- `restartPolicy: Never`: el pod no se reinicia ante fallos; el `CronJob` gestiona el reintento en el siguiente ciclo.

---

## 3. Generación de Changelogs Liquibase

> Esta sección es **informativa**. Los changelogs son generados automáticamente por `scaffold-all-services.sh` durante los pasos 5, 6 y 6b. No requieren intervención manual.

### 3.1 Paso 5 — Changelogs iniciales de esquema (`00001_initial_schema.yaml`)

El script genera el changelog inicial para cada servicio con persistencia relacional:

| Servicio | Bounded Context | Changelog generado |
|---|---|---|
| identity-service | BC-01 | `db/identity-service/changelog/00001_initial_schema.yaml` |
| wallet-service | BC-02 | `db/wallet-service/changelog/00001_initial_schema.yaml` |
| fraud-compliance-service | BC-03 | `db/fraud-compliance-service/changelog/00001_initial_schema.yaml` |
| notification-service | BC-04 | `db/notification-service/changelog/00001_initial_schema.yaml` |
| integration-service | BC-05 | `db/integration-service/changelog/00001_initial_schema.yaml` |
| reporting-projection-service | BC-07 | `db/reporting-projection-service/changelog/00001_initial_schema.yaml` |
| report-extraction-service | — (Reporting BD) | `db/report-extraction-service/changelog/00001_initial_schema.yaml` |

> `audit-service` no genera changelog Liquibase dado que su persistencia es MongoDB (esquema flexible).

### 3.2 Paso 6 — Changelog de seed para integration-service

```
db/integration-service/changelog/00002_seed_integration.yaml
```

Contiene los datos semilla de:
- Sistemas externos registrados: `kyc` (BC-01), `aml` (BC-03), `financial-entities` (BC-02), `payment-gateways` (BC-02), `sms-email` (BC-04).
- Rutas Camel persistidas si el integration-service utiliza enrutamiento dinámico desde BD.

### 3.3 Paso 6b — Repositorio `pagofacil-migrations`

El script crea el repositorio centralizado de migraciones en Gitea:

```
http://<VPS_IP>:3000/pagofacil/pagofacil-migrations
```

#### Estructura de directorios esperada

```
pagofacil-migrations/
├── db/
│   ├── identity-service/
│   │   └── changelog/
│   │       ├── db.changelog-master.yaml
│   │       └── 00001_initial_schema.yaml
│   ├── wallet-service/
│   │   └── changelog/
│   │       ├── db.changelog-master.yaml
│   │       └── 00001_initial_schema.yaml
│   ├── fraud-compliance-service/
│   │   └── changelog/
│   │       ├── db.changelog-master.yaml
│   │       └── 00001_initial_schema.yaml
│   ├── notification-service/
│   │   └── changelog/
│   │       ├── db.changelog-master.yaml
│   │       └── 00001_initial_schema.yaml
│   ├── integration-service/
│   │   └── changelog/
│   │       ├── db.changelog-master.yaml
│   │       ├── 00001_initial_schema.yaml
│   │       └── 00002_seed_integration.yaml
│   ├── reporting-projection-service/
│   │   └── changelog/
│   │       ├── db.changelog-master.yaml
│   │       └── 00001_initial_schema.yaml
│   └── report-extraction-service/
│       └── changelog/
│           ├── db.changelog-master.yaml
│           └── 00001_initial_schema.yaml
└── README.md
```

---

## 4. Verificación Post-Scaffolding

> Esta sección es **informativa**. La verificación se ejecuta automáticamente durante los pasos 9 y 10 de `scaffold-all-services.sh`.

### 4.1 Paso 9 — Compilación de servicios backend (`compile-services.sh`)

El script itera sobre todos los directorios `*-service` dentro de `backend/` y ejecuta:

```bash
mvn -q -DskipTests package
```

Un fallo de compilación en cualquier servicio detiene el script con código de salida distinto de 0 y reporta el servicio afectado.

### 4.2 Paso 10 — Verificación del frontend (`verify-frontend.sh`)

El script ejecuta en `frontend/pagofacil-web/` la siguiente secuencia:

```bash
npm install
npm run type-check
npm run lint
```

Cualquier error de tipos o lint detiene la verificación e impide avanzar a los pasos siguientes.

---

## 5. Configuración Inicial Post-Scaffold

> Los secrets se crean automáticamente durante el **paso 11** de `scaffold-all-services.sh`. El siguiente comando permite re-ejecutar este paso de forma aislada si es necesario:

```bash
bash .claude/scripts/create-all-secrets-dev.sh \
  -P pagofacil \
  -p pagofacil \
  -m pagofacil \
  -u pagofacil_app \
  -w <CLAVE_APP> \
  --vps-ip <VPS_IP>
```

### 5.1 Secrets en floci (AWS Secrets Manager local)

Los secrets se crean bajo el path `pagofacil/dev/<servicio>` en la instancia de floci en `<VPS_IP>:4566`:

| Secret Path (floci) | Servicio | Contenido principal |
|---|---|---|
| `pagofacil/dev/identity-service` | identity-service | DB URL, DB user/password, Kafka brokers, JWT secret |
| `pagofacil/dev/wallet-service` | wallet-service | DB URL, DB user/password, Kafka brokers |
| `pagofacil/dev/fraud-compliance-service` | fraud-compliance-service | DB URL, DB user/password, Kafka brokers, AML config |
| `pagofacil/dev/notification-service` | notification-service | DB URL, DB user/password, Kafka brokers, SMTP/SMS config |
| `pagofacil/dev/integration-service` | integration-service | DB URL, DB user/password, Kafka brokers, sistemas externos config |
| `pagofacil/dev/audit-service` | audit-service | MongoDB URI, Kafka brokers |
| `pagofacil/dev/reporting-projection-service` | reporting-projection-service | DB URL, DB user/password, Kafka brokers |
| `pagofacil/dev/report-extraction-service` | report-extraction-service | JDBC URL, DB user/password |
| `pagofacil/dev/report-processing-service` | report-processing-service | Kafka brokers, storage config |
| `pagofacil/dev/pagofacil-web` | pagofacil-web | Cognito config, NextAuth secret, API base URL |

### 5.2 Variables de entorno del frontend

El script crea `frontend/pagofacil-web/.env.local` con el siguiente contenido:

```env
COGNITO_ISSUER_URI=https://cognito-idp.<REGION>.amazonaws.com/<USER_POOL_ID>
COGNITO_CLIENT_ID=<COGNITO_CLIENT_ID>
NEXTAUTH_URL=http://<VPS_IP>:3000
NEXTAUTH_SECRET=<NEXTAUTH_SECRET>
NEXT_PUBLIC_API_BASE_URL=http://<VPS_IP>:8080
```

> Este archivo está incluido en `.gitignore` y no se versiona en el repositorio.

---

## 6. Re-aplicar Infraestructura Terraform (dev)

> Los pasos 12 y 13 se ejecutan automáticamente al finalizar el scaffold para sincronizar el estado de Terraform con los nuevos recursos creados.

### 6.1 Paso 12 — Terraform apply

```bash
cd terraform/backend/environments/dev/
terraform apply -auto-approve
```

Provisiona o actualiza los recursos de infraestructura dev: namespaces K3s, ConfigMaps base, ExternalSecrets apuntando a floci, y cualquier recurso Terraform que referencie los nuevos servicios scaffoldeados.

### 6.2 Paso 13 — Verificación de registros y secrets

El script verifica los siguientes recursos tras el apply:

- **Gitea Package Registry**: accesible en `http://<VPS_IP>:3000/pagofacil` con al menos una imagen publicada por servicio.
- **floci Secrets**: lista todos los secrets bajo `pagofacil/dev/` y confirma que están presentes los 10 paths esperados.

Comando de verificación manual (opcional):

```bash
# Listar imágenes en Gitea Package Registry
curl -s -u gitea-admin:gitea-admin \
  http://<VPS_IP>:3000/api/v1/packages/pagofacil | jq '.[].name'

# Listar secrets en floci
aws --endpoint-url=http://<VPS_IP>:4566 secretsmanager list-secrets \
  --query 'SecretList[?starts_with(Name, `pagofacil/dev/`)].Name' \
  --output table
```

---

## 7. Criterios de Aceptación

### Criterio principal

- [ ] `scaffold-all-services.sh` finaliza los 13 pasos con código de salida `0` sin errores.

### Repositorios y código fuente

- [ ] Todos los repositorios de microservicios están creados en Gitea bajo `http://<VPS_IP>:3000/pagofacil/`.
- [ ] Cada repositorio contiene Dockerfile, Helm chart, Jenkinsfile y estructura Maven/SBT/Next.js generada.
- [ ] El repositorio `pagofacil-migrations` es accesible en `http://<VPS_IP>:3000/pagofacil/pagofacil-migrations`.

### Changelogs Liquibase

- [ ] Existe el archivo `00001_initial_schema.yaml` para cada uno de los 7 servicios con persistencia relacional.
- [ ] Existe el archivo `00002_seed_integration.yaml` para `integration-service`.
- [ ] El archivo `db.changelog-master.yaml` referencia correctamente todos los changelogs en cada servicio.

### Compilación y calidad de código

- [ ] `compile-services.sh` (paso 9) completa sin errores para los 7 servicios Spring Boot + Maven.
- [ ] `verify-frontend.sh` (paso 10) pasa `npm install`, `type-check` y `lint` sin errores.

### Secrets e infraestructura

- [ ] Los 10 secrets `pagofacil/dev/<servicio>` están disponibles en floci (`<VPS_IP>:4566`).
- [ ] El archivo `frontend/pagofacil-web/.env.local` existe y contiene las 5 variables requeridas.
- [ ] Gitea Package Registry en `<VPS_IP>:3000/pagofacil` es accesible y contiene las imágenes base publicadas.
- [ ] `terraform apply` (paso 12) finaliza sin errores en `terraform/backend/environments/dev/`.

### Observabilidad

- [ ] Cada servicio Spring Boot contiene `logback-spring.xml` en `src/main/resources/`.
- [ ] El `pom.xml` de cada servicio Spring Boot incluye las dependencias de Micrometer y OpenTelemetry.
- [ ] El `values.yaml` de cada Helm chart Spring Boot incluye las anotaciones Prometheus y el init container `otel-agent`.
