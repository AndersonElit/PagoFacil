# Plan de Desarrollo — PagoFacil

## 1. Introducción

Este documento describe el plan maestro de implementación de la plataforma **PagoFacil**, una billetera digital multitenancy de tipo fintech. La etapa de implementación abarca la provisión de infraestructura, creación de esquemas de bases de datos, scaffolding de microservicios, pipeline CI/CD, desarrollo de microservicios backend, capa de procesamiento batch/serverless, frontend y suite de pruebas de aceptación.

### Ambiente objetivo

El ambiente de desarrollo se ejecuta sobre un **VPS Ubuntu 26.04 LTS** con las siguientes capas:

- **K3s nativo** — orquestador Kubernetes ligero para todos los workloads contenedorizados (microservicios, Kafka, ArgoCD).
- **floci** — emulador de servicios AWS (S3, Lambda, EventBridge, SQS) expuesto en `<VPS_IP>:4566`.
- **Servicios systemd** — PostgreSQL 16, MongoDB 7, Kafka KRaft, SonarQube, Jenkins, LRA Coordinator y WireMock corren como unidades systemd directamente en el VPS.
- **Gitea Package Registry** — registro de imágenes OCI y artefactos Maven/npm en `<VPS_IP>:3000/pagofacil`.

### Tecnologías del stack

| Capa | Tecnología |
|---|---|
| Runtime backend | Java 21 (virtual threads) |
| Framework backend | Spring Boot 3.3 WebFlux + R2DBC |
| Integración / Saga | Apache Camel 4 + Narayana LRA |
| Procesamiento batch | Apache Spark 3.5.1 + Scala 3 |
| Frontend | Next.js 14 TypeScript (App Router) |
| Mensajería | Apache Kafka 3 KRaft |
| Base de datos OLTP | PostgreSQL 16 |
| Base de datos documental | MongoDB 7 |
| Contenedores / Orquestación | Docker + K3s |
| GitOps | ArgoCD |
| CI/CD | Jenkins |
| Calidad de código | SonarQube |
| Emulación AWS | floci (LocalStack-compatible) |

---

## 2. Prerrequisitos Globales

Las siguientes herramientas deben estar instaladas y disponibles en el PATH de la máquina de desarrollo (o en el VPS según corresponda) antes de iniciar cualquier etapa.

| Herramienta | Versión mínima | Propósito |
|---|---|---|
| Terraform | 1.8+ | Provisión de infraestructura as-code (K3s namespaces, ConfigMaps, Secrets) |
| kubectl | 1.29+ | Gestión de recursos K3s |
| Java (JDK) | 21 (LTS) | Compilación y ejecución de microservicios Spring Boot / Spark |
| Node.js | 20 LTS | Compilación y ejecución del frontend Next.js 14 |
| Python | 3.11+ | Scripts de automatización y utilidades de CI |
| floci CLI | latest | Interacción con servicios AWS emulados (S3, Lambda, EventBridge) |
| sbt | 1.9+ | Build tool de los proyectos Scala/Spark |
| Scala | 3.x | Lenguaje de los jobs Spark |
| Apache Spark | 3.5.1 | Ejecución local/distribuida de jobs de reportes |
| Docker | 24+ | Construcción de imágenes de contenedor |
| Helm | 3.14+ | Gestión de charts K3s |
| Git | 2.40+ | Control de versiones |

---

## 3. Secuencia de Etapas

Las etapas deben ejecutarse en el orden indicado. Las dependencias señalan qué etapas deben estar completadas antes de comenzar cada una.

| Etapa | Documento | Dependencias | Esfuerzo estimado |
|---|---|---|---|
| Etapa 0 — Infraestructura VPS | [DEV-PagoFacil-00-infrastructure.md](DEV-PagoFacil-00-infrastructure.md) | Ninguna | 2 días |
| Etapa 0c — Observabilidad | [DEV-PagoFacil-00c-observability.md](DEV-PagoFacil-00c-observability.md) | Etapa 0 | 0.5 días |
| Etapa 1 — Bases de datos | [DEV-PagoFacil-01-databases.md](DEV-PagoFacil-01-databases.md) | Etapa 0 | 0.5 días |
| Etapa 2 — Scaffolding | [DEV-PagoFacil-02-scaffolding.md](DEV-PagoFacil-02-scaffolding.md) | Etapa 1 | 1 día |
| Etapa 2b — CI/CD | [DEV-PagoFacil-02b-cicd.md](DEV-PagoFacil-02b-cicd.md) | Etapa 2 | 1 día |
| Etapa 3a — identity-service | [DEV-PagoFacil-03a-identity-service.md](DEV-PagoFacil-03a-identity-service.md) | Etapa 2b | 3 días |
| Etapa 3b — wallet-service | [DEV-PagoFacil-03b-wallet-service.md](DEV-PagoFacil-03b-wallet-service.md) | Etapa 3a | 3 días |
| Etapa 3c — notification-service | [DEV-PagoFacil-03c-notification-service.md](DEV-PagoFacil-03c-notification-service.md) | Etapa 2b | 2 días |
| Etapa 3d — fraud-compliance-service | [DEV-PagoFacil-03d-fraud-compliance-service.md](DEV-PagoFacil-03d-fraud-compliance-service.md) | Etapa 3b | 3 días |
| Etapa 3e — integration-service | [DEV-PagoFacil-03e-integration-service.md](DEV-PagoFacil-03e-integration-service.md) | Etapa 3b, 3d | 5 días |
| Etapa 3f — audit-service | [DEV-PagoFacil-03f-audit-service.md](DEV-PagoFacil-03f-audit-service.md) | Etapa 2b | 2 días |
| Etapa 3g — projection-service | [DEV-PagoFacil-03g-projection-service.md](DEV-PagoFacil-03g-projection-service.md) | Etapa 3b, 3e | 2 días |
| Etapa 3h — report-extraction-service | [DEV-PagoFacil-03h-report-extraction-service.md](DEV-PagoFacil-03h-report-extraction-service.md) | Etapa 3g | 3 días |
| Etapa 3i — report-processing-service | [DEV-PagoFacil-03i-report-processing-service.md](DEV-PagoFacil-03i-report-processing-service.md) | Etapa 3h | 2 días |
| Etapa 4a — Frontend auth | [DEV-PagoFacil-04a-frontend-auth.md](DEV-PagoFacil-04a-frontend-auth.md) | Etapa 3a | 2 días |
| Etapa 4b — Frontend wallets | [DEV-PagoFacil-04b-frontend-wallets.md](DEV-PagoFacil-04b-frontend-wallets.md) | Etapa 3b, 4a | 2 días |
| Etapa 4c — Frontend transactions | [DEV-PagoFacil-04c-frontend-transactions.md](DEV-PagoFacil-04c-frontend-transactions.md) | Etapa 3e, 4b | 2 días |
| Etapa 4d — Frontend compliance | [DEV-PagoFacil-04d-frontend-compliance.md](DEV-PagoFacil-04d-frontend-compliance.md) | Etapa 3d, 4a | 2 días |
| Etapa 4e — Frontend audit | [DEV-PagoFacil-04e-frontend-audit.md](DEV-PagoFacil-04e-frontend-audit.md) | Etapa 3f, 4a | 1 día |
| Etapa 4f — Frontend reporting | [DEV-PagoFacil-04f-frontend-reporting.md](DEV-PagoFacil-04f-frontend-reporting.md) | Etapa 3h, 3i, 4a | 2 días |
| Etapa 5 — Tests de aceptación | [DEV-PagoFacil-05-tests.md](DEV-PagoFacil-05-tests.md) | Etapas 4a–4f | 3 días |
| Etapa 6 — Reporting serverless | [DEV-PagoFacil-06-reporting-serverless.md](DEV-PagoFacil-06-reporting-serverless.md) | Etapa 3i | 2 días |

**Esfuerzo total estimado:** ~47 días de desarrollo

---

## 4. Mapa de Microservicios

| Servicio | Bounded Context | Base de datos | Mensajería | Dependencias REST salientes | Sistemas externos consumidos | Rol en saga |
|---|---|---|---|---|---|---|
| identity-service | BC-01 Identity & Auth | PostgreSQL `pagofacil_identity_service` | Kafka producer (`identity.events`) | — | Proveedor KYC (vía integration-service) | Participante LRA |
| wallet-service | BC-02 Wallet | PostgreSQL `pagofacil_wallet_service` | Kafka producer+consumer (`wallet.events`, `saga.wallet.*`) | identity-service (validación token) | — | Participante LRA |
| fraud-compliance-service | BC-03 Fraud & Compliance | PostgreSQL `pagofacil_fraud_compliance_service` | Kafka producer+consumer (`compliance.events`, `saga.compliance.*`) | — | Proveedor AML (vía integration-service) | Participante LRA |
| notification-service | BC-04 Notifications | PostgreSQL `pagofacil_notification_service` | Kafka consumer (`notification.commands`) | — | Proveedor SMS/Email (vía integration-service) | Ninguno |
| integration-service | BC-05 Integration | PostgreSQL `pagofacil_integration_service` | Kafka producer+consumer (`integration.events`, `saga.*`) | wallet-service, fraud-compliance-service, identity-service | Entidades Financieras, Pasarelas de Pago, Proveedor KYC, Proveedor AML, Proveedor SMS/Email | Orquestador LRA (Camel + Narayana) |
| audit-service | BC-06 Audit | MongoDB `pagofacil_audit_service` | Kafka consumer (`audit.events`) | — | — | Ninguno |
| projection-service | BC-07 Read Model | PostgreSQL `pagofacil_readmodel` | Kafka consumer (`*.events`) | — | — | Ninguno |
| report-extraction-service (MS1) | BC-07 Reporting | PostgreSQL `pagofacil_readmodel` + `pagofacil_reporting` (JDBC) | Kafka producer (`reporting.extraction.*`) | — | — | Ninguno (CronJob K3s) |
| report-processing-service (MS2) | BC-07 Reporting | S3 (floci) | Kafka consumer+producer (`reporting.extraction.*`, `reporting.processed.*`) | — | S3 floci | Ninguno (CronJob K3s) |
| capa-serverless-lambda | BC-07 Reporting | S3 + EventBridge (floci) | Kafka consumer (`reporting.processed.*`) | — | S3 floci, EventBridge floci | Ninguno (Lambda floci) |

---

## 5. Mapa de Features Frontend

| Feature | Rutas (App Router) | Contextos de dominio | Dependencias backend |
|---|---|---|---|
| auth | `/login`, `/register`, `/mfa`, `/auth/refresh` | BC-01 Identity | identity-service `:8081` |
| wallets | `/wallets`, `/wallets/[id]/balance`, `/wallets/[id]/history`, `/wallets/[id]/bank-accounts` | BC-02 Wallet | wallet-service `:8082`, identity-service `:8081` |
| transactions | `/transactions/deposit`, `/transactions/transfer`, `/transactions/withdraw`, `/transactions/[id]/status` | BC-02 Wallet, BC-05 Integration | integration-service `:8085`, wallet-service `:8082` |
| compliance | `/compliance/alerts`, `/compliance/alerts/[id]/resolve`, `/compliance/aml` | BC-03 Fraud & Compliance | fraud-compliance-service `:8083` |
| audit | `/audit`, `/audit/traces` | BC-06 Audit | audit-service `:8086`, projection-service `:8087` |
| reporting | `/reporting/schemas`, `/reporting/executions`, `/reporting/executions/[id]/download` | BC-07 Reporting | projection-service `:8087`, report-extraction-service, report-processing-service |

---

## 6. Ambiente VPS (floci + K3s nativo)

### Descripción general

El VPS es la única máquina del ambiente de desarrollo. No se usa ningún servicio cloud externo; todos los servicios AWS son emulados por **floci** en `<VPS_IP>:4566`. K3s corre de forma nativa con un único nodo (control-plane + worker). Los microservicios de la plataforma se despliegan como `Deployment` en K3s y se exponen vía `NodePort` o `ClusterIP` según corresponda.

### Tabla de endpoints VPS

| Servicio | Tipo | Host | Puerto | Protocolo |
|---|---|---|---|---|
| PostgreSQL 16 | systemd | `<VPS_IP>` | 5432 | TCP |
| MongoDB 7 | systemd | `<VPS_IP>` | 27017 | TCP |
| Kafka KRaft (externo) | K3s NodePort | `<VPS_IP>` | 29092 | TCP |
| Kafka KRaft (interno) | K3s ClusterIP | `<VPS_IP>` | 9092 | TCP |
| floci (AWS emulado) | systemd | `<VPS_IP>` | 4566 | HTTP |
| SonarQube | systemd | `<VPS_IP>` | 9000 | HTTP |
| Jenkins | systemd | `<VPS_IP>` | 8080 | HTTP |
| ArgoCD | K3s NodePort | `<VPS_IP>` | 30080 | HTTP |
| K3s API Server | K3s | `<VPS_IP>` | 6443 | HTTPS |
| Gitea Package Registry | systemd | `<VPS_IP>` | 3000 | HTTP |
| LRA Coordinator | systemd | `<VPS_IP>` | 50000 | HTTP |
| WireMock | systemd | `<VPS_IP>` | 9999 | HTTP |
| identity-service | K3s NodePort | `<VPS_IP>` | 8081 | HTTP |
| wallet-service | K3s NodePort | `<VPS_IP>` | 8082 | HTTP |
| fraud-compliance-service | K3s NodePort | `<VPS_IP>` | 8083 | HTTP |
| notification-service | K3s NodePort | `<VPS_IP>` | 8084 | HTTP |
| integration-service | K3s NodePort | `<VPS_IP>` | 8085 | HTTP |
| audit-service | K3s NodePort | `<VPS_IP>` | 8086 | HTTP |
| projection-service | K3s NodePort | `<VPS_IP>` | 8087 | HTTP |

### Variables de entorno base

Todas las variables de entorno base se definen en `.env` en la raíz del repositorio y se exportan al shell del desarrollador. El frontend lee un archivo `.env.local` en la raíz del módulo `frontend/`.

```dotenv
# Infraestructura VPS
VPS_IP=<VPS_IP>
GITEA_REGISTRY=<VPS_IP>:3000/pagofacil
KAFKA_BOOTSTRAP=<VPS_IP>:29092
POSTGRES_HOST=<VPS_IP>
POSTGRES_PORT=5432
POSTGRES_APP_USER=pagofacil_app
MONGODB_URI=mongodb://pagofacil_app:<CLAVE>@<VPS_IP>:27017/
AWS_ENDPOINT_URL=http://<VPS_IP>:4566
AWS_DEFAULT_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
LRA_COORDINATOR_URL=http://<VPS_IP>:50000/lra-coordinator
WIREMOCK_URL=http://<VPS_IP>:9999
SONARQUBE_URL=http://<VPS_IP>:9000
K3S_API=https://<VPS_IP>:6443
```

**Frontend** (`.env.local` en `frontend/`):

```dotenv
NEXT_PUBLIC_API_BASE_URL=http://<VPS_IP>
NEXT_PUBLIC_IDENTITY_SERVICE_URL=http://<VPS_IP>:8081
NEXT_PUBLIC_WALLET_SERVICE_URL=http://<VPS_IP>:8082
NEXT_PUBLIC_INTEGRATION_SERVICE_URL=http://<VPS_IP>:8085
NEXT_PUBLIC_FRAUD_SERVICE_URL=http://<VPS_IP>:8083
NEXT_PUBLIC_AUDIT_SERVICE_URL=http://<VPS_IP>:8086
NEXT_PUBLIC_PROJECTION_SERVICE_URL=http://<VPS_IP>:8087
```

---

## 7. Criterios de Done (Definition of Done)

Los siguientes criterios aplican a **todas** las etapas del plan. Una etapa no se considera completada hasta que todos los criterios relevantes estén verificados.

### TDD obligatorio

- [ ] Cada clase de dominio / servicio de aplicación tiene al menos un test unitario escrito **antes** de la implementación (ciclo Red-Green-Refactor documentado).
- [ ] La cobertura de líneas en el módulo es ≥ 80 % según el reporte de SonarQube.
- [ ] Los tests de integración se ejecutan con contenedor o conexión real al ambiente VPS (no mocks para persistencia).
- [ ] Los tests de aceptación (ATDD) se expresan en lenguaje Gherkin y automatizan con Cucumber/Playwright antes de codificar la feature.

### Calidad de código

- [ ] El análisis de SonarQube no reporta issues de tipo `BLOCKER` ni `CRITICAL`.
- [ ] El pipeline CI/CD en Jenkins ejecuta `sonar:sonar` y el Quality Gate es `PASSED`.
- [ ] No hay secrets hardcodeados detectados por el scanner.

### CI/CD y GitOps

- [ ] Cada microservicio tiene un `Dockerfile` multi-stage y la imagen se publica en Gitea Registry `<VPS_IP>:3000/pagofacil`.
- [ ] El pipeline Jenkins construye, testea, analiza y publica la imagen de forma automatizada.
- [ ] El chart Helm o manifiesto K3s está actualizado y ArgoCD sincroniza sin errores (`Synced`, `Healthy`).

### Funcional

- [ ] Todos los criterios de aceptación del documento de etapa específico están verificados.
- [ ] Los contratos de API (OpenAPI 3.1 o AsyncAPI) están publicados y sin cambios breaking no versionados.
- [ ] Las sagas LRA finalizan en estado `CLOSED` o ejecutan correctamente la compensación ante fallo.

### Operacional

- [ ] Los health checks (`/actuator/health`) responden `UP` en el ambiente K3s.
- [ ] Los logs estructurados (JSON) se emiten correctamente y son visibles en el dashboard de observabilidad.
- [ ] Las migraciones de base de datos (Flyway/Liquibase) se aplican de forma idempotente.
