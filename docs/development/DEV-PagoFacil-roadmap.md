# Plan de Desarrollo — PagoFacil

**Proyecto:** PagoFacil — Billetera Digital  
**Versión:** 1.0 | **Fecha:** 2026-06-06  
**Etapa SDLC:** Implementación

---

## 1. Introducción

Este documento es el índice maestro del plan de desarrollo de la plataforma PagoFacil. Define la secuencia de etapas, los documentos de referencia, el mapa de microservicios, el mapa de features frontend y los criterios de done aplicables a toda la implementación.

**Ambiente objetivo (dev):** floci (emulador local de servicios AWS) + K3d (cluster Kubernetes real en Docker sobre `floci-net`). EKS solo aplica a `staging` y `prod`.

**Stack tecnológico principal:**

| Categoría | Tecnología |
|---|---|
| Backend — servicios de dominio | Java 21 + Spring Boot 3.4.1 (WebFlux, reactivo) |
| Backend — integración / saga | Java 21 + Apache Camel 4.10.2 + Narayana LRA |
| Backend — reportería ETL | Scala 2.13 + Apache Spark 3.5.1 (fat JAR con sbt-assembly) |
| Frontend | TypeScript 5 + Next.js 15.3 + React 19 (Vercel) |
| Base de datos | PostgreSQL 16.3 (Database-per-Service) |
| Mensajería | Apache Kafka 3.7.0 (KRaft) |
| Autenticación | AWS Cognito (emulado por floci en dev) |
| Contenedores | Docker, K3d (dev) / AWS EKS (staging+prod) |
| CI/CD | Jenkins + ArgoCD (GitOps) |
| IaC | Terraform ≥ 1.6.0 |
| Migraciones BD | Liquibase standalone (Docker `liquibase/liquibase`) |
| Quality Gate | SonarQube LTS Community |
| Resiliencia | Resilience4j |

---

## 2. Prerrequisitos Globales

Herramientas a instalar antes de comenzar cualquier etapa:

| Herramienta | Versión mínima | Propósito |
|---|---|---|
| Docker Desktop / Docker Engine | 24.x | Contenedores, floci, K3d |
| k3d | 5.6.x | Cluster Kubernetes local en Docker |
| kubectl | 1.29.x | Administración del cluster K3d |
| Terraform | 1.6.0 | IaC — aprovisionar infraestructura dev |
| Java (Temurin) | 21 | Build y ejecución de microservicios |
| Maven | 3.9.x | Build de microservicios Spring Boot |
| sbt | 1.9.x | Build de jobs Spark (Scala) |
| Scala | 2.13.x | Jobs Spark (MS1, MS2) |
| Node.js | 20 LTS | Frontend Next.js |
| Python | 3.11+ | Scripts de scaffolding |
| floci CLI | Latest | Emulación de servicios AWS (LocalStack) |
| git | 2.40+ | Control de versiones |
| jq | 1.6+ | Procesamiento de JSON en scripts |
| curl / httpie | Cualquiera | Verificación de endpoints |
| aws CLI | 2.x | Interacción con floci (LocalStack) |

---

## 3. Secuencia de Etapas

| # | Etapa | Documento | Dependencias previas | Esfuerzo estimado |
|---|---|---|---|---|
| 0 | Infraestructura local (floci + K3d + SonarQube) | [DEV-PagoFacil-00-infrastructure.md](DEV-PagoFacil-00-infrastructure.md) | Prerrequisitos globales | 0.5 días |
| 0c | Stack de observabilidad (OTEL + Prometheus + Grafana + CloudWatch) | [DEV-PagoFacil-0c-observability.md](DEV-PagoFacil-0c-observability.md) | Etapa 0 completa | 0.5 días |
| 1 | Bases de datos y migraciones | [DEV-PagoFacil-01-databases.md](DEV-PagoFacil-01-databases.md) | Etapa 0c | 0.5 días |
| 2 | Scaffolding de proyectos | [DEV-PagoFacil-02-scaffold.md](DEV-PagoFacil-02-scaffold.md) | Etapa 1 | 1 día |
| 2b | Configuración del pipeline CI/CD (Jenkins + ArgoCD) | [DEV-PagoFacil-02b-cicd.md](DEV-PagoFacil-02b-cicd.md) | Etapa 2 + infra Jenkins/ArgoCD (Etapa 0) | 1 día |
| 3a | Microservicio: identity-service | [DEV-PagoFacil-03-ms-identity-service.md](DEV-PagoFacil-03-ms-identity-service.md) | Etapa 2b | 4 días |
| 3b | Microservicio: wallet-service | [DEV-PagoFacil-03-ms-wallet-service.md](DEV-PagoFacil-03-ms-wallet-service.md) | Etapa 2b | 5 días |
| 3c | Microservicio: fraud-service | [DEV-PagoFacil-03-ms-fraud-service.md](DEV-PagoFacil-03-ms-fraud-service.md) | Etapa 2b | 4 días |
| 3d | Microservicio: notification-service | [DEV-PagoFacil-03-ms-notification-service.md](DEV-PagoFacil-03-ms-notification-service.md) | Etapa 2b | 2 días |
| 3e | Microservicio: audit-service | [DEV-PagoFacil-03-ms-audit-service.md](DEV-PagoFacil-03-ms-audit-service.md) | Etapa 3f (projection) | 3 días |
| 3f | Microservicio: projection-service | [DEV-PagoFacil-03-ms-projection-service.md](DEV-PagoFacil-03-ms-projection-service.md) | Etapas 3a, 3b, 3c | 3 días |
| 3g | Microservicio: integration-service (ACL + Saga Orchestrator) | [DEV-PagoFacil-03-ms-integration-service.md](DEV-PagoFacil-03-ms-integration-service.md) | Etapas 3a, 3b, 3c | 7 días |
| 3h | MS1: report-extraction-service (Spark) | [DEV-PagoFacil-03-ms-report-extraction-service.md](DEV-PagoFacil-03-ms-report-extraction-service.md) | Etapa 3f (Read Model) | 4 días |
| 3i | MS2: report-processing-service (Spark) | [DEV-PagoFacil-03-ms-report-processing-service.md](DEV-PagoFacil-03-ms-report-processing-service.md) | Etapa 3h | 3 días |
| 4a | Frontend: auth | [DEV-PagoFacil-04-fe-auth.md](DEV-PagoFacil-04-fe-auth.md) | Etapa 3a (identity-service) | 3 días |
| 4b | Frontend: wallet | [DEV-PagoFacil-04-fe-wallet.md](DEV-PagoFacil-04-fe-wallet.md) | Etapas 4a, 3b | 4 días |
| 4c | Frontend: audit | [DEV-PagoFacil-04-fe-audit.md](DEV-PagoFacil-04-fe-audit.md) | Etapas 4a, 3e, 3g | 4 días |
| 5 | Pruebas de integración, E2E, estrés y carga | [DEV-PagoFacil-05-tests.md](DEV-PagoFacil-05-tests.md) | Todos los servicios y features | 5 días |
| 6 | Reportería serverless (Lambda + EventBridge) | [DEV-PagoFacil-06-reporting-serverless.md](DEV-PagoFacil-06-reporting-serverless.md) | Etapa 3i | 3 días |

**Esfuerzo total estimado:** ~57.5 días-persona (sin contar paralelismo de equipos)

---

## 4. Mapa de Microservicios

| Servicio | Bounded Context | BD propia | Mensajería | Dependencias REST salientes | Sistemas externos | Rol en saga |
|---|---|---|---|---|---|---|
| `identity-service` | BC-01 Identity | `pagofacil_identity_service` | Kafka producer (Outbox) | integration-service (coordina KYC) | AWS Cognito | Participante (saga KYC) |
| `wallet-service` | BC-02 Wallet | `pagofacil_wallet_service` | Kafka producer (Outbox) | integration-service (inicia sagas) | — | Participante (saga Deposito, Retiro, Transferencia) |
| `fraud-service` | BC-03 Fraud | `pagofacil_fraud_service` | Kafka producer (Outbox) + consumer (`fraud-evaluator`) | — | integration-service (invocado via REST mTLS) | Participante (saga Retiro, Transferencia) |
| `notification-service` | BC-04 Notification | `pagofacil_notification_service` | Kafka consumer | — | SMTP / SMS / FCM (via Secrets Manager) | Ninguno |
| `audit-service` | BC-05 + BC-07 | `pagofacil_readmodel` (read-only) + `pagofacil_reporting` (owner) | Kafka consumer (opcional) | — | AWS S3 (presigned URLs) | Ninguno |
| `integration-service` | BC-06 Integration | `pagofacil_integration_service` | Kafka producer (Outbox) + consumer | wallet-service, fraud-service, identity-service (mTLS) | Entidades financieras, proveedor KYC, listas AML, Narayana LRA | **Orquestador** (saga Deposito, Retiro, Transferencia, Conciliacion) |
| `projection-service` | CQRS Read Model | `pagofacil_readmodel` (owner/writer) | Kafka consumer multi-topic | — | — | Ninguno |
| `report-extraction-service` (MS1) | BC-07 Reporting | — (JDBC `pagofacil_readmodel` + `pagofacil_reporting`) | Kafka producer (`report.extracted`) | — | AWS S3 (escritura Parquet `raw/`) | Ninguno |
| `report-processing-service` (MS2) | BC-07 Reporting | — (S3 Parquet) | Kafka consumer (`report.extracted`) + producer (`report.processed`) | — | AWS S3 (lectura `raw/`, escritura `processed/`) | Ninguno |

**Nota sobre `audit-service`:** conecta a dos fuentes de datos — `pagofacil_readmodel` (solo lectura, propiedad del `projection-service`) y `pagofacil_reporting` (lectura/escritura, propietario exclusivo, contiene `report_schema_catalog` y `report_jobs`). MS1 accede a `pagofacil_reporting` vía JDBC Spark (excepción acordada al patrón Database-per-Service para el subsistema ETL).

---

## 5. Mapa de Features Frontend

| Feature | Rutas asociadas | Bounded contexts consumidos | Servicios backend | Tipo de acceso |
|---|---|---|---|---|
| `auth` | `/login`, `/register`, `/mfa-verify`, `/password/recover`, `/password/reset` | BC-01 Identity | identity-service | Público |
| `wallet` | `/dashboard`, `/deposit`, `/withdraw`, `/transfer`, `/transactions`, `/transactions/[id]` | BC-02 Wallet | wallet-service, integration-service | Protegido (usuario final) |
| `fraud-admin` | `/admin/fraud-rules`, `/admin/fraud-rules/[id]` | BC-03 Fraud | fraud-service | Protegido (administrador de plataforma) |
| `audit` | `/audit/transactions`, `/audit/alerts`, `/audit/alerts/[id]`, `/audit/reports`, `/audit/reports/[id]` | BC-05 Audit, BC-07 Reporting | audit-service | Protegido (auditor / compliance) |

---

## 6. Ambiente Local (floci + K3d)

### Contenedores de soporte en `floci-net`

| Contenedor | Propósito | Endpoint local | Endpoint interno (floci-net) |
|---|---|---|---|
| `floci` (LocalStack) | Emulación AWS (S3, Cognito, Lambda, EventBridge, Secrets Manager) | `http://localhost:4566` | `http://floci:4566` |
| `pagofacil-kafka-dev` | Apache Kafka 3.7.0 (KRaft) | `localhost:9092` | `pagofacil-kafka-dev:9092` |
| `pagofacil-postgres-dev` | PostgreSQL 16.3 (todas las BDs dev) | `localhost:5432` | `pagofacil-postgres-dev:5432` |
| `gitea` | Git remoto local | `http://localhost:3000` | `http://gitea:3000` |
| `pagofacil-sonarqube` | Quality Gate CI | `http://localhost:9000` | `http://pagofacil-sonarqube:9000` |
| `narayana-lra` | Coordinador LRA para sagas | `http://localhost:8180` | `http://narayana-lra:8180` |
| `wiremock` | Simulador de sistemas externos (entidades financieras, KYC, AML) | `http://localhost:8888` | `http://wiremock:8888` |

### Cluster Kubernetes K3d (dev)

| Recurso | Valor |
|---|---|
| Nombre del cluster | `pagofacil-dev` |
| Registry local | `k3d-pagofacil-registry:5100` (interno) / `localhost:5100` (externo) |
| Kubeconfig K3d | `terraform/backend/environments/dev/.kube/config-k3d` |
| Kubeconfig K3d (interno para Jenkins) | `terraform/backend/environments/dev/.kube/config-k3d-internal` |
| Namespace de aplicación | `dev` |
| Namespace ArgoCD | `argocd` |
| Namespace Jenkins | `jenkins` |
| ArgoCD UI | `kubectl port-forward -n argocd svc/argocd-server 8443:443` → `https://localhost:8443` |

### Variables de entorno base

| Variable | Valor en dev |
|---|---|
| `AWS_DEFAULT_REGION` | `us-east-1` |
| `AWS_ACCESS_KEY_ID` | `test` |
| `AWS_SECRET_ACCESS_KEY` | `test` |
| `AWS_ENDPOINT_URL` | `http://localhost:4566` |
| `POSTGRES_HOST` | `localhost` |
| `POSTGRES_PORT` | `5432` |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` |
| `COGNITO_USER_POOL_ENDPOINT` | Derivado del Terraform output `user_pool_endpoint` |
| `SONAR_URL` | `http://localhost:9000` |
| `NARAYANA_LRA_URL` | `http://localhost:8180/lra-coordinator` |

---

## 7. Criterios de Done (Definition of Done)

Un componente se considera **Done** cuando cumple **todos** los criterios siguientes:

### Criterios de TDD (obligatorios y transversales)

- [ ] Cada unidad de funcionalidad fue precedida por una prueba que falló (Red) y luego pasó (Green), seguida de Refactor.
- [ ] La suite de pruebas completa (`mvn test` / `sbt test` / `npm run test`) finaliza en verde.
- [ ] Los umbrales de cobertura por capa declarados en cada documento se cumplen (backend dominio ≥ 90%, aplicación ≥ 85%, infraestructura ≥ 80%; frontend ≥ 80%).
- [ ] No existe lógica de negocio ni rama de error sin prueba asociada.
- [ ] Los tipos reactivos (`Mono`/`Flux`) se verifican con `StepVerifier`, nunca con `block()`.

### Criterios de calidad

- [ ] El quality gate de SonarQube pasa (cobertura ≥ 80% en módulos financieros y de seguridad; 0 bloqueantes; 0 críticos sin justificación).
- [ ] El análisis de seguridad de dependencias (OWASP Dependency-Check) no reporta vulnerabilidades críticas sin mitigación documentada.
- [ ] La imagen Docker no tiene vulnerabilidades críticas según el escaneo de Trivy.

### Criterios de despliegue (dev)

- [ ] El servicio arranca en K3d (`Started ...Application in X seconds`) con `/actuator/health/readiness` respondiendo `UP`.
- [ ] ArgoCD muestra el estado `Synced` para el Application del servicio.
- [ ] Los secretos `pagofacil/dev/<servicio>` existen en floci con valores correctos.
- [ ] Las migraciones Liquibase (`run-liquibase-migrations.sh`) se aplican sin errores.

### Criterios de observabilidad (dev)

- [ ] `/actuator/prometheus` del servicio responde HTTP 200 (verificado en `runSmokeTests` del pipeline).
- [ ] Prometheus (`http://localhost:9090 → Status > Targets`) muestra el servicio como `UP`.
- [ ] Una request HTTP al servicio genera una traza visible en Jaeger (`http://localhost:16686`).
- [ ] Los logs del servicio en Grafana/Loki muestran JSON con `traceId` y `spanId` correlacionados con la traza de Jaeger.

### Criterios funcionales

- [ ] Cada endpoint documentado en `SDD-PagoFacil-openapi.yaml` retorna los códigos HTTP y schemas especificados.
- [ ] Los contratos de mensajes Kafka (eventos publicados) coinciden con los schemas definidos en el diseño.
- [ ] Los endpoints de compensación de saga son idempotentes (reentrega no produce doble efecto).
- [ ] Los flujos de saga completos (happy path y compensación) están cubiertos por pruebas de integración.
