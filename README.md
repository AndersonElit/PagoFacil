# PagoFacil — Billetera Digital

Plataforma de billetera digital segura, escalable y de alta disponibilidad para la gestión de fondos electrónicos con garantías de integridad, trazabilidad y cumplimiento regulatorio.

---

## Proceso SDLC

El proyecto sigue un ciclo de vida de desarrollo de software (SDLC) guiado por skills de Claude Code. Cada etapa produce un artefacto documentado que sirve de entrada a la siguiente.

---

### Paso 1 — Requerimiento del Cliente

**Objetivo:** Capturar la visión del proyecto, el problema de negocio, objetivos, alcance y restricciones en un formato estructurado que alimenta la etapa de Planeación.

| Campo | Detalle |
|---|---|
| Formato base | [`.claude/formatos/input-template.md`](.claude/formatos/input-template.md) |
| Documento generado | [`requerimiento/input-pagofacil.md`](requerimiento/input-pagofacil.md) |
| Acción | Diligenciar el template con la información del cliente y del proyecto |

**Cómo replicarlo:**

1. Copiar `.claude/formatos/input-template.md` a `requerimiento/input-<proyecto>.md`.
2. Completar todos los campos obligatorios (`*`): identificación, problema de negocio, objetivos, alcance, stakeholders, requerimientos de alto nivel, supuestos, restricciones y riesgos.
3. El documento resultante se usa como entrada directa en el Paso 2.

---

### Paso 2 — Planeación (PID)

**Objetivo:** Formalizar el inicio del proyecto generando un Project Initiation Document (PID) profesional con cronograma de alto nivel, criterios de éxito y análisis de riesgos.

| Campo | Detalle |
|---|---|
| Skill | `/plan-pid` |
| Input | [`requerimiento/input-pagofacil.md`](requerimiento/input-pagofacil.md) |
| Documento generado | [`docs/planning/PID-PagoFacil.md`](docs/planning/PID-PagoFacil.md) |
| Commit de referencia | `e95cdee` — Ejecutar etapa SDLC - planeacion |

**Cómo replicarlo:**

```
/plan-pid [contenido de requerimiento/input-pagofacil.md]
```

---

### Paso 3 — Análisis de Requerimientos (SRS)

**Objetivo:** Generar la especificación completa de requerimientos funcionales, no funcionales, reglas de negocio y casos de uso a partir del PID.

| Campo | Detalle |
|---|---|
| Skill | `/requirements-srs` |
| Input | [`docs/planning/PID-PagoFacil.md`](docs/planning/PID-PagoFacil.md) |
| Documento generado | [`docs/requirements/SRS-PagoFacil.md`](docs/requirements/SRS-PagoFacil.md) |
| Commit de referencia | `bd793e5` — ejecutar etapa SDLC - Analisis de requerimiento |

**Cómo replicarlo:**

```
/requirements-srs docs/planning/PID-PagoFacil.md
```

O sin argumentos (busca el PID en `docs/planning/` automáticamente):

```
/requirements-srs
```

---

### Paso 4 — Contexto Arquitectónico (ADC)

**Objetivo:** Capturar el stack tecnológico, drivers arquitectónicos, restricciones organizacionales, SLAs e integraciones en un documento que enriquece las decisiones del diseño estratégico. El ADC se deriva de los scripts e templates del proyecto y del SRS.

| Campo | Detalle |
|---|---|
| Formato base | [`.claude/formatos/input-adc-template.md`](.claude/formatos/input-adc-template.md) |
| Fuentes consultadas | [`docs/requirements/SRS-PagoFacil.md`](docs/requirements/SRS-PagoFacil.md) · [`.claude/scripts/`](.claude/scripts/) · [`.claude/templates/`](.claude/templates/) |
| Documento generado | [`docs/planning/ADC-PagoFacil.md`](docs/planning/ADC-PagoFacil.md) |

**Cómo replicarlo:**

1. Copiar `.claude/formatos/input-adc-template.md` a `docs/planning/ADC-<proyecto>.md`.
2. Diligenciar cada sección apoyándose en el SRS y en los scripts/templates del proyecto (el stack se infiere de `.claude/scripts/` y `.claude/templates/`).
3. El documento resultante se usa como entrada junto al SRS en el Paso 5.

**Stack tecnológico inferido** (resumen):

| Capa | Tecnología |
|---|---|
| Backend (dominio) | Java 21 + Spring Boot 3.4.1 WebFlux — Arquitectura Hexagonal |
| Backend (ETL/reportería) | Scala 2.13 + Apache Spark 3.5.1 |
| Integración / Saga | Apache Camel 4.10.2 + Narayana LRA |
| Frontend | Next.js 15.3 + TypeScript 5 + React 19 |
| BD operacional (command) | PostgreSQL 16.3 (CQRS write side) |
| BD read model / auditoría | ~~MongoDB 7~~ → **PostgreSQL 16.3** (`pagofacil_readmodel`) ¹ |
| Mensajería | Apache Kafka 3.7.0 (KRaft) |
| Identidad / Auth | AWS Cognito — OAuth 2.0 / OpenID Connect |
| Secrets | AWS Secrets Manager |
| Contenedores | Docker + Kubernetes (K3d dev / EKS prod) |
| IaC | Terraform ≥ 1.6.0 |
| CI/CD | Jenkins (EC2) + ArgoCD (GitOps) + Gitea |
| Frontend hosting | Vercel |
| Reportería serverless | AWS Lambda + EventBridge + S3 |
| Observabilidad | OpenTelemetry + Prometheus + CloudWatch |
| Calidad de código | SonarQube LTS Community |

> ¹ **Override en Diseño Técnico (ADR-002):** DS-CQRS-1 del Diseño Estratégico definía MongoDB para el Read Model. El Diseño Técnico reemplazó MongoDB por PostgreSQL 16.3 (`pagofacil_readmodel`) para homogeneizar el motor de base de datos en toda la plataforma y simplificar el acceso JDBC desde los jobs Spark. No existe ninguna base de datos MongoDB en la arquitectura final.

---

### Paso 5 — Diseño Estratégico (SDD)

**Objetivo:** Modelar el dominio del negocio, establecer el lenguaje ubicuo, definir bounded contexts y su mapa de relaciones, diseñar el modelo de seguridad con threat modeling, e identificar los drivers y decisiones estratégicas que guiarán el diseño técnico.

| Campo | Detalle |
|---|---|
| Skill | `/strategic-design-sdd` |
| Inputs | [`docs/requirements/SRS-PagoFacil.md`](docs/requirements/SRS-PagoFacil.md) · [`docs/planning/ADC-PagoFacil.md`](docs/planning/ADC-PagoFacil.md) |
| Documentos generados | [`docs/strategic-design/SDD-PagoFacil-domain.md`](docs/strategic-design/SDD-PagoFacil-domain.md) · [`docs/strategic-design/SDD-PagoFacil-security.md`](docs/strategic-design/SDD-PagoFacil-security.md) · [`docs/strategic-design/SDD-PagoFacil-architecture.md`](docs/strategic-design/SDD-PagoFacil-architecture.md) |

**Cómo replicarlo:**

```
/strategic-design-sdd docs/requirements/SRS-PagoFacil.md docs/planning/ADC-PagoFacil.md
```

**Artefactos generados:**

| Documento | Contenido |
|---|---|
| `SDD-PagoFacil-domain.md` | Visión del dominio · Ubiquitous Language (26 términos) · 7 Bounded Contexts con Database-per-Service · Context Map con ACL para sistemas externos · 3 flujos de saga (Deposito, Retiro, Transferencia) · 5 Aggregates con reglas de dominio · 23 eventos de dominio con eventos de compensación · 7 workflows de negocio · 6 features BDD con escenarios Gherkin |
| `SDD-PagoFacil-security.md` | 7 principios de seguridad (Zero Trust, Defense in Depth, Least Privilege…) · Modelo de identidad dual (Cognito externo + mTLS interno) · RBAC por bounded context · Clasificación de 10 categorías de datos sensibles · 15 amenazas STRIDE ordenadas por impacto · 7 zonas de confianza con controles por cruce de trust boundary |
| `SDD-PagoFacil-architecture.md` | 9 atributos de calidad con SLAs del ADC · 14 restricciones fijas · 13 decisiones estratégicas (DS-001…DS-009 + DS-CQRS-1/2/3) · 7 riesgos clasificados · 7 tradeoffs aceptados · Próximos pasos y bloqueadores críticos |

---

### Paso 6 — Diseño Técnico (SDD Técnico)

**Objetivo:** Traducir las decisiones estratégicas en una arquitectura técnica concreta: microservicios, módulos, persistencia, contratos de API, diagramas C4, esquema de base de datos e infraestructura como código.

| Campo | Detalle |
|---|---|
| Skill | `/technical-design-sdd` |
| Inputs | [`docs/strategic-design/`](docs/strategic-design/) |
| Documentos generados | [`docs/design/SDD-PagoFacil-system.md`](docs/design/SDD-PagoFacil-system.md) · [`docs/design/SDD-PagoFacil-design.md`](docs/design/SDD-PagoFacil-design.md) · [`docs/design/SDD-PagoFacil-infrastructure.md`](docs/design/SDD-PagoFacil-infrastructure.md) |
| Artefactos de soporte | [`docs/design/api/SDD-PagoFacil-openapi.yaml`](docs/design/api/SDD-PagoFacil-openapi.yaml) · [`docs/design/database/SDD-PagoFacil-schema.sql`](docs/design/database/SDD-PagoFacil-schema.sql) · Diagramas C4 ([contexto](docs/design/diagrams/SDD-PagoFacil-c4-context.mmd) / [contenedores](docs/design/diagrams/SDD-PagoFacil-c4-container.mmd)) |

**Cómo replicarlo:**

```
/technical-design-sdd docs/strategic-design/
```

O sin argumentos (busca en `docs/strategic-design/` automáticamente):

```
/technical-design-sdd
```

**Artefactos generados:**

| Documento | Contenido |
|---|---|
| `SDD-PagoFacil-system.md` | Estilo arquitectónico (microservicios event-driven + hexagonal) · Stack tecnológico por capa · 8 microservicios de dominio (BC-01 a BC-06) + projection-service · Estructura de módulos hexagonales (domain / application / infrastructure) · 2 servicios de reportería batch (MS1 Spark ETL, MS2 Lambda Consumer) · Comunicación: Kafka async + REST/mTLS sync · Diagramas C4 de contexto y contenedores |
| `SDD-PagoFacil-design.md` | Contratos REST por bounded context (26 endpoints agrupados en 6 tags OpenAPI) · Endpoints de compensación idempotentes (Saga) · Estrategia de persistencia CQRS con Database-per-Service · Esquema SQL PostgreSQL por servicio con Liquibase standalone · Read Model PostgreSQL desnormalizado (projection-service) · Diseño de topics Kafka con ACL por bounded context · Política de retención y particionamiento |
| `SDD-PagoFacil-infrastructure.md` | IaC Terraform multi-ambiente (dev K3d / staging+prod EKS) · Tabla completa de componentes de infraestructura AWS · Blue/Green deployment con ArgoCD · Pipeline CI/CD Jenkins → bumpImageTag → ArgoCD sync · Observabilidad: logging JSON + correlationId · Métricas Prometheus + CloudWatch · Trazas OpenTelemetry · Governance: gestión de secretos, RBAC K8s, política de imágenes, gestión de ramas y revisión de código |
| `SDD-PagoFacil-openapi.yaml` | Especificación OpenAPI 3.0 completa con esquemas JSON para todos los bounded contexts · Seguridad BearerAuth (JWT Cognito) + mTLS para endpoints internos |
| `SDD-PagoFacil-schema.sql` | DDL completo: tablas por bounded context con constraints, índices y extensiones PostgreSQL (uuid-ossp, pgcrypto) |
| Diagramas C4 (`.mmd` + `.png`) | Diagrama de contexto del sistema y diagrama de contenedores en Mermaid + renders PNG |

---

### Paso 7 — Plan de Desarrollo (Implementación)

**Objetivo:** Transformar los documentos de Diseño Técnico en planes de trabajo concretos, secuenciales y accionables para la etapa de Implementación del SDLC. Cada plan es un documento independiente que un desarrollador puede seguir de forma autónoma bajo TDD (Red-Green-Refactor).

| Campo | Detalle |
|---|---|
| Skill | `/development-plan` |
| Input | [`docs/design/`](docs/design/) |
| Directorio de salida | [`docs/development/`](docs/development/) |
| Commit de referencia | `82cec55` — incorporar liquibase diseño pagafacil |
| Ambiente objetivo | `dev`: floci (LocalStack) + K3d (Kubernetes local en Docker) |

**Cómo replicarlo:**

```
/development-plan docs/design/
```

O sin argumentos (busca en `docs/design/` automáticamente):

```
/development-plan
```

**19 documentos generados:**

| Documento | Contenido |
|---|---|
| [`DEV-PagoFacil-roadmap.md`](docs/development/DEV-PagoFacil-roadmap.md) | Índice maestro · mapa de microservicios · mapa de features frontend · ambiente local floci+K3d · Definition of Done con criterios TDD |
| [`DEV-PagoFacil-00-infrastructure.md`](docs/development/DEV-PagoFacil-00-infrastructure.md) | Scripts de infraestructura base (`base-infrastructure-builder.sh` · `init-dev-environment.sh`) · floci + K3d + SonarQube + Narayana LRA + WireMock · checklist de criterios de aceptación |
| [`DEV-PagoFacil-01-databases.md`](docs/development/DEV-PagoFacil-01-databases.md) | 7 bases de datos PostgreSQL (Database-per-Service) · changelogs Liquibase standalone por servicio · seed del catálogo de reportes (BC-07) · `init-databases.sh` + `run-liquibase-migrations.sh` |
| [`DEV-PagoFacil-02-scaffold.md`](docs/development/DEV-PagoFacil-02-scaffold.md) | Comando completo de `scaffold-all-services.sh` con todos los parámetros · Jenkinsfiles Maven/sbt/Vercel · Dockerfiles multi-stage · Helm charts (Deployment / CronJob) · secrets floci · pasos 1-14 del scaffold |
| [`DEV-PagoFacil-02b-cicd.md`](docs/development/DEV-PagoFacil-02b-cicd.md) | Shared Library Jenkins (11 steps) · controller K3d (`docker run` idempotente) · jobs Multibranch Pipeline · webhooks Gitea · ArgoCD ApplicationSet · `setup-cicd-pipeline.sh` autónomo en dev |
| [`DEV-PagoFacil-03-ms-identity-service.md`](docs/development/DEV-PagoFacil-03-ms-identity-service.md) | BC-01 · ciclo de vida de cuenta · KYC · MFA · JWT Cognito · participante de saga · TDD por capa (dominio → aplicación → infraestructura R2DBC → REST WebFlux) |
| [`DEV-PagoFacil-03-ms-wallet-service.md`](docs/development/DEV-PagoFacil-03-ms-wallet-service.md) | BC-02 · saldo · depósito/retiro/transferencia ACID · Outbox Pattern · idempotencia · 3 endpoints de compensación · TDD completo con StepVerifier |
| [`DEV-PagoFacil-03-ms-fraud-service.md`](docs/development/DEV-PagoFacil-03-ms-fraud-service.md) | BC-03 · reglas de fraude configurables · verificación AML · alertas con severidad · Kafka consumer idempotente · compensación de saga |
| [`DEV-PagoFacil-03-ms-notification-service.md`](docs/development/DEV-PagoFacil-03-ms-notification-service.md) | BC-04 · consumer multi-topic · plantillas de notificación · gateways de canal (SMTP / SMS / FCM) · flujo degradado sin plantilla |
| [`DEV-PagoFacil-03-ms-audit-service.md`](docs/development/DEV-PagoFacil-03-ms-audit-service.md) | BC-05+07 · dashboard Read Model · resolución de alertas inmutable · gestión de `report_jobs` · URL pre-firmada S3 · dos data sources R2DBC |
| [`DEV-PagoFacil-03-ms-projection-service.md`](docs/development/DEV-PagoFacil-03-ms-projection-service.md) | CQRS Read Model · único escritor de `pagofacil_readmodel` · proyectores por evento (8 topics) · UPSERT idempotente · métrica `projection.lag.seconds` |
| [`DEV-PagoFacil-03-ms-integration-service.md`](docs/development/DEV-PagoFacil-03-ms-integration-service.md) | BC-06 · ACL + orquestador de sagas · rutas Camel (3 sistemas externos) · Narayana LRA · Resilience4j (retry + circuit breaker) · TDD con WireMock + camel-test-spring-junit5 |
| [`DEV-PagoFacil-03-ms-report-extraction-service.md`](docs/development/DEV-PagoFacil-03-ms-report-extraction-service.md) | MS1 Spark batch · `SparkJdbcSourceAdapter` (Read Model JDBC) · validación de schema contra catálogo · Parquet `raw/` en S3 · CronJob K8s · TDD ScalaTest + Testcontainers |
| [`DEV-PagoFacil-03-ms-report-processing-service.md`](docs/development/DEV-PagoFacil-03-ms-report-processing-service.md) | MS2 Spark batch · patrón Factory (5 transformadores) · Principio Abierto/Cerrado · Parquet `processed/` en S3 · trigger por `report.extracted` Kafka |
| [`DEV-PagoFacil-04-fe-auth.md`](docs/development/DEV-PagoFacil-04-fe-auth.md) | Feature auth · registro + MFA + recuperación de contraseña · schemas Zod · hooks TanStack Query · MSW · Playwright ATDD · NextAuth.js |
| [`DEV-PagoFacil-04-fe-wallet.md`](docs/development/DEV-PagoFacil-04-fe-wallet.md) | Feature wallet · dashboard · depósito/retiro/transferencia · saldo en tiempo real · historial paginado · idempotencyKey automático · polling de estado de saga |
| [`DEV-PagoFacil-04-fe-audit.md`](docs/development/DEV-PagoFacil-04-fe-audit.md) | Feature audit · búsqueda de transacciones · resolución de alertas · disparo/descarga de reportes · RBAC por rol en middleware NextAuth |
| [`DEV-PagoFacil-05-tests.md`](docs/development/DEV-PagoFacil-05-tests.md) | Pruebas de integración (saga happy path + compensada + idempotencia) · contract tests WireMock · E2E Playwright (5 flujos) · estrés k6 (500 VU) · carga sostenida k6 (15 min) |
| [`DEV-PagoFacil-06-reporting-serverless.md`](docs/development/DEV-PagoFacil-06-reporting-serverless.md) | Lambdas Python (PDF/XLS/CSV) · Lambda Kafka Consumer · EventBridge bus + 3 rules · Terraform floci · pytest con S3 y EventBridge de LocalStack |

**Esfuerzo total estimado:** ~57 días-persona. Orden de implementación: infra → BDs → scaffold → CI/CD → identity → wallet → fraud → notification → projection → audit → integration → MS1 → MS2 → frontend → serverless.

---

## Descripción del proyecto

| Campo | Detalle |
|---|---|
| Tipo de proyecto | Nuevo desarrollo |
| Dominio de negocio | Finanzas / Fintech |
| Sponsor | Por definir |
| Project Manager | Por definir |
| Duración estimada | ~36-46 semanas (sujeto a aprobación tras estimación detallada) |
| Modalidad de despliegue | Nube pública — contenedores (Kubernetes) |
| Metodología | Ágil con hitos por fases |

PagoFacil provee una plataforma centralizada y propia para gestionar fondos electrónicos, ejecutar transferencias y consultar movimientos, eliminando la dependencia de soluciones de terceros con limitada integración y control.

---

## Problema que resuelve

- Ausencia de trazabilidad y auditoría transaccional completa, dificultando conciliación y reporte regulatorio.
- Falta de controles antifraude integrados, exponiendo la operación a pérdidas financieras y sanciones.
- Incapacidad para cumplir normativas KYC/AML de forma sistemática y auditable.
- Ausencia de APIs propias para integración con entidades financieras y pasarelas de pago.
- Arquitectura no escalable horizontalmente ante incrementos de volumen transaccional.

---

## Objetivos

**General:** Desarrollar una plataforma de billetera digital segura, escalable y de alta disponibilidad que permita a los usuarios gestionar fondos electrónicos con garantías de integridad, trazabilidad y cumplimiento regulatorio.

**Específicos:**

1. Implementar registro y autenticación con MFA y gestión de identidad bajo estándares KYC/AML.
2. Habilitar operaciones financieras core: depósito, retiro, transferencia y consulta de saldos con registro auditable.
3. Garantizar integridad y no repudio de transacciones mediante UUID/correlationId, registros inmutables y conciliación automática.
4. Implementar controles de seguridad: cifrado TLS 1.2+ en tránsito, AES-256 en reposo y gestión de secretos mediante vault.
5. Exponer APIs seguras (OAuth 2.0 / OpenID Connect) para integración con entidades financieras y pasarelas de pago.
6. Garantizar consistencia financiera con garantías ACID, procesamiento asíncrono e idempotencia.
7. Implementar monitoreo de fraude en tiempo real con alertas y controles AML.
8. Proveer observabilidad completa: logging estructurado, métricas y trazas distribuidas (OpenTelemetry).
9. Alcanzar disponibilidad de 99.9% con escalamiento horizontal y plan DR (RTO < 1h, RPO < 15min).
10. Cumplir con legislación de protección de datos personales y normativas regulatorias financieras vigentes.

---

## Alcance

### Incluido

| Área | Detalle |
|---|---|
| Identidad | Registro y autenticación con MFA; módulo KYC y controles AML |
| Operaciones | Depósito, retiro y transferencia entre usuarios |
| Consultas | Saldo actual e historial auditable con paginación y filtros |
| Seguridad | Cifrado TLS 1.2+ en tránsito, AES-256 en reposo, vault para secretos |
| APIs | REST/async autenticadas (OAuth 2.0 / OpenID Connect) para integraciones externas |
| Transacciones | Procesamiento asíncrono con idempotencia y conciliación automática |
| Fraude | Monitoreo y detección en tiempo real; alertas ante patrones sospechosos |
| Límites | Configurables por usuario, tipo de operación y período |
| Auditoría | Dashboard para revisión de transacciones y reportes regulatorios |
| Observabilidad | Logging estructurado, métricas, trazas distribuidas (OpenTelemetry) y alertas |
| Disponibilidad | Alta disponibilidad, escalamiento horizontal y plan DR |
| Compliance | Protección de datos personales, normativas KYC/AML |
| Multitenancy | Segmentación por canal de distribución para alianzas futuras |

### Fuera del alcance (fase inicial)

- Aplicaciones móviles nativas (iOS/Android) — se proveen APIs para integración posterior.
- Integración directa con redes de tarjetas (Visa/Mastercard).
- Módulo de crédito o préstamos.
- Soporte multimoneda.

---

## Actores del Sistema

| Actor | Descripción | Responsabilidades Principales |
|---|---|---|
| Usuario Final | Titular de la billetera digital | Registro, autenticación, fondeo, retiro, transferencia y consulta de movimientos |
| Administrador de Plataforma | Personal interno con acceso privilegiado | Gestión de configuración, límites transaccionales, revisión de alertas y soporte operacional |
| Auditor / Compliance | Oficial de cumplimiento o auditor interno | Revisión del dashboard de auditoría, generación de reportes regulatorios, gestión de casos AML |
| Entidad Financiera | Proveedor bancario o pasarela de pago externa | Fondeo y liquidación de operaciones mediante APIs autenticadas |
| Sistema de Fraude (interno) | Motor automatizado de detección de fraude | Evaluación en tiempo real de patrones transaccionales sospechosos |
| Sistema de Notificaciones (interno) | Servicio de alertas y comunicaciones | Emisión de notificaciones a usuarios y administradores ante eventos relevantes |

---

## Requerimientos Funcionales

| ID | Nombre |
|---|---|
| RF-001 | Registro de Usuario |
| RF-002 | Validación de Identidad (KYC) |
| RF-003 | Autenticación con MFA |
| RF-004 | Recuperación de Contraseña |
| RF-005 | Consulta de Saldo |
| RF-006 | Depósito de Fondos |
| RF-007 | Retiro de Fondos |
| RF-008 | Transferencia entre Usuarios |
| RF-009 | Historial de Movimientos |
| RF-010 | Identificadores Únicos de Operación |
| RF-011 | Idempotencia de Operaciones Financieras |
| RF-012 | Conciliación Automática |
| RF-013 | Gestión de Límites Transaccionales |
| RF-014 | Monitoreo de Fraude en Tiempo Real |
| RF-015 | Controles AML |
| RF-016 | Gestión de Alertas |
| RF-017 | Dashboard de Auditoría |
| RF-018 | APIs de Integración Externa |
| RF-019 | Procesamiento Asíncrono de Transacciones |
| RF-020 | Soporte Multitenancy |

Especificación completa: [`docs/requirements/SRS-PagoFacil.md`](docs/requirements/SRS-PagoFacil.md)

---

## Requerimientos No Funcionales

| ID | Atributo | Meta |
|---|---|---|
| RNF-001 | Disponibilidad | 99.9% uptime mínimo (máx. 43.8 min de inactividad no planificada/mes) |
| RNF-002 | Rendimiento | < 500 ms para el 95% de consultas; < 2 s para encolamiento de operaciones bajo carga nominal |
| RNF-003 | Seguridad en tránsito y reposo | TLS 1.2+ en tránsito · AES-256 en reposo · vault para secretos |
| RNF-004 | Autenticación y autorización | OAuth 2.0 / OpenID Connect para APIs externas · mTLS para servicios internos · mínimo privilegio |
| RNF-005 | Consistencia financiera | Garantías ACID · patrón Saga con compensación · outbox pattern |
| RNF-006 | Escalabilidad | Escalamiento horizontal automático · soporte ≥ 10x volumen inicial sin rediseño |
| RNF-007 | Observabilidad | Logging estructurado (JSON) + métricas (Prometheus) + trazas distribuidas (OpenTelemetry) |
| RNF-008 | Idempotencia de API | Idempotency key obligatorio en operaciones financieras; reintentos sin efectos duplicados |
| RNF-009 | Mantenibilidad | Microservicios modulares · cobertura de pruebas automatizadas ≥ 80% en módulos críticos |
| RNF-010 | Cumplimiento regulatorio | GDPR / Ley de protección de datos · KYC · AML · registros inmutables por período legal |
| RNF-011 | Resistencia a fallos | Circuit breakers · reintentos con backoff exponencial · degradación controlada ante fallos parciales |
| — | Recuperación | RTO < 1 hora · RPO < 15 minutos |

---

## Reglas de Negocio

| ID | Regla |
|---|---|
| RN-001 | Una cuenta solo puede activarse tras la aprobación exitosa del proceso KYC. |
| RN-002 | Un usuario con cuenta suspendida, bloqueada o pendiente de KYC no puede ejecutar operaciones financieras. |
| RN-003 | El saldo de una billetera no puede ser negativo. Toda operación que resulte en saldo negativo es rechazada. |
| RN-004 | Los fondos depositados no están disponibles hasta confirmación de la entidad financiera externa. |
| RN-005 | Toda operación financiera genera un registro inmutable con identificador único, timestamp, actor, monto, estado y resultado. |
| RN-006 | Una operación confirmada no puede revertirse de forma unilateral; requiere proceso de disputa formal con aprobación de auditor. |
| RN-007 | El sistema rechaza operaciones de usuarios o contrapartes en listas de sanciones AML activas, generando evento auditable. |
| RN-008 | Los límites transaccionales configurados por el administrador tienen precedencia; el usuario no puede elevar sus propios límites. |
| RN-009 | Las transacciones marcadas como sospechosas quedan retenidas hasta resolución manual por un auditor autorizado. |
| RN-010 | Las contraseñas se almacenan con hash (bcrypt o Argon2) con salt único por usuario. Prohibido texto plano o hash reversible. |
| RN-011 | La expiración de sesión no cancela ni revierte operaciones ya encoladas. |
| RN-012 | La retención mínima de registros de transacciones y auditoría es la exigida por normativa; en ausencia de ésta, no inferior a 5 años. |

---

## Arquitectura y principios de diseño

- **Security by Design** y **Privacy by Design** desde las etapas iniciales de arquitectura.
- **Arquitectura hexagonal / puertos y adaptadores** para separar lógica de negocio de infraestructura y facilitar pruebas automatizadas.
- **Event-driven architecture** con bus de eventos para procesamiento asíncrono, trazabilidad y desacoplamiento con sistemas externos.
- **CQRS** — escrituras en PostgreSQL (ACID), lecturas en PostgreSQL Read Model desnormalizado (`pagofacil_readmodel`, propiedad del `projection-service`) para historial, dashboard y reportería batch (ADR-002 reemplazó MongoDB por PostgreSQL para homogeneizar el motor de BD).
- **Transactional Outbox Pattern + Saga (orquestación LRA)** para consistencia en transacciones distribuidas entre microservicios.
- **Idempotencia** en todas las operaciones financieras: cada operación puede reintentarse de forma segura sin generar duplicados.
- **Multitenancy / segmentación por canal** para alianzas futuras con entidades financieras.
- Despliegue en nube pública con contenedores (**Kubernetes**), GitOps con **ArgoCD** y CI/CD con **Jenkins**.

---

## Stakeholders

| Stakeholder | Rol | Responsabilidad |
|---|---|---|
| Sponsor ejecutivo | Patrocinador | Aprobación de presupuesto y priorización estratégica |
| Project Manager | Gestión de proyecto | Planificación, seguimiento y control |
| Arquitecto de software | Diseño técnico | Arquitectura, estándares y revisión de diseño |
| Equipo de desarrollo | Implementación | Construcción, pruebas unitarias e integración |
| Equipo de seguridad | Seguridad de la información | Revisión de controles, pentesting y cumplimiento |
| Oficial de cumplimiento | Compliance / Regulatorio | Validación KYC, AML y protección de datos |
| Equipo de operaciones | DevOps / SRE | Infraestructura, despliegue y observabilidad |
| Usuarios finales | Usuarios de la plataforma | Gestión de fondos y transacciones |
| Entidades financieras | Integración externa | Proveedores de fondeo, liquidación y servicios financieros |

---

## Cronograma de alto nivel

| Fase | Descripción | Duración Estimada |
|---|---|---|
| 0 — Iniciación | Designación de sponsor y PM; marco regulatorio; conformación del equipo | 2 semanas |
| 1 — Análisis de Requerimientos | Levantamiento de requerimientos; casos de uso core | 3-4 semanas |
| 2 — Diseño Estratégico | Arquitectura de alto nivel; contratos de APIs; estrategia de seguridad | 3-4 semanas |
| 3 — Diseño Técnico | Diseño detallado de microservicios; especificaciones de integración | 3-4 semanas |
| 4 — Implementación Fase 1 | Núcleo financiero: identidad, operaciones core, seguridad base | 10-12 semanas |
| 5 — Implementación Fase 2 | Fraude, AML, dashboard de auditoría, integraciones externas | 8-10 semanas |
| 6 — QA y Seguridad | Pruebas funcionales, de carga, penetración y cumplimiento | 4-6 semanas |
| 7 — Despliegue y Estabilización | Producción, monitoreo intensivo y ajustes post-lanzamiento | 3-4 semanas |
| **Total estimado** | | **~36-46 semanas** |

---

## Riesgos conocidos

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| Cambios regulatorios KYC/AML durante el desarrollo | Media | Alto | Oficial de cumplimiento desde análisis; diseño modular |
| Vulnerabilidades en componentes de terceros | Media | Crítico | SBOM, pentesting por fase, revisión criptográfica |
| APIs de entidades financieras no disponibles | Alta | Alto | Contratos previos al inicio; adaptadores desacoplados; mocks |
| Subestimación del volumen transaccional | Media | Alto | Pruebas de carga desde QA; escalamiento horizontal desde el origen |
| Debilidad en controles antifraude | Media | Crítico | Motor de reglas configurable; revisión periódica con oficial de cumplimiento |
| Inconsistencias en transacciones distribuidas | Baja | Crítico | Saga / outbox pattern; idempotencia; conciliación automática; pruebas de caos |
| Retrasos por falta de sponsor y PM | Alta | Alto | Designación como condición previa al arranque |

---

## Criterios de éxito

| Criterio | Indicador Medible |
|---|---|
| Disponibilidad | Uptime ≥ 99.9% en 90 días post-lanzamiento |
| Rendimiento | < 500 ms para el 95% de consultas bajo carga nominal |
| Cumplimiento regulatorio | Cero observaciones críticas en auditoría KYC/AML en primer ciclo |
| Seguridad | Cero vulnerabilidades críticas no resueltas al momento del despliegue |
| Integridad financiera | Tasa de discrepancias en conciliación < 0.01% del total diario |
| Cobertura de pruebas | ≥ 80% en módulos críticos (núcleo financiero, seguridad) |
| Recuperación ante desastres | RTO < 1h y RPO < 15min verificados en ejercicio previo al lanzamiento |
| Incidentes de fraude | Tasa de transacciones fraudulentas no detectadas < umbral regulatorio |

---

## Supuestos y restricciones

**Supuestos:**

- Conectividad con entidades bancarias o proveedores de fondeo mediante APIs disponibles y contratadas.
- El equipo cuenta con experiencia en microservicios y seguridad en aplicaciones financieras.
- Las normativas regulatorias aplicables se definen con el oficial de cumplimiento antes del inicio de la implementación.
- Infraestructura en nube pública con soporte completo a contenedores (Kubernetes).
- Los usuarios acceden a la plataforma a través de canales digitales (web o apps móviles que consumen las APIs expuestas).

**Restricciones:**

- Cumplimiento con legislación de protección de datos personales vigente en la jurisdicción de operación.
- Credenciales y datos sensibles no pueden almacenarse en texto plano bajo ninguna circunstancia.
- APIs externas deben implementar autenticación OAuth 2.0 / OpenID Connect sin excepción.
- Datos de transacciones financieras deben conservarse por el período mínimo exigido por normativa.
- Presupuesto y plazos sujetos a aprobación formal del sponsor ejecutivo.

---

## Documentación

| Documento | Ruta | Etapa SDLC |
|---|---|---|
| Requerimiento del cliente (input) | [`requerimiento/input-pagofacil.md`](requerimiento/input-pagofacil.md) | Paso 1 — Requerimiento |
| Project Initiation Document (PID) | [`docs/planning/PID-PagoFacil.md`](docs/planning/PID-PagoFacil.md) | Paso 2 — Planeación |
| Software Requirements Specification (SRS) | [`docs/requirements/SRS-PagoFacil.md`](docs/requirements/SRS-PagoFacil.md) | Paso 3 — Análisis de Requerimientos |
| Architectural Decision Context (ADC) | [`docs/planning/ADC-PagoFacil.md`](docs/planning/ADC-PagoFacil.md) | Paso 4 — Contexto Arquitectónico |
| SDD — Dominio y Comportamiento | [`docs/strategic-design/SDD-PagoFacil-domain.md`](docs/strategic-design/SDD-PagoFacil-domain.md) | Paso 5 — Diseño Estratégico |
| SDD — Seguridad | [`docs/strategic-design/SDD-PagoFacil-security.md`](docs/strategic-design/SDD-PagoFacil-security.md) | Paso 5 — Diseño Estratégico |
| SDD — Estrategia Arquitectónica | [`docs/strategic-design/SDD-PagoFacil-architecture.md`](docs/strategic-design/SDD-PagoFacil-architecture.md) | Paso 5 — Diseño Estratégico |
| SDD — Arquitectura del Sistema | [`docs/design/SDD-PagoFacil-system.md`](docs/design/SDD-PagoFacil-system.md) | Paso 6 — Diseño Técnico |
| SDD — Diseño de APIs y Persistencia | [`docs/design/SDD-PagoFacil-design.md`](docs/design/SDD-PagoFacil-design.md) | Paso 6 — Diseño Técnico |
| SDD — Infraestructura y Gobernanza | [`docs/design/SDD-PagoFacil-infrastructure.md`](docs/design/SDD-PagoFacil-infrastructure.md) | Paso 6 — Diseño Técnico |
| OpenAPI 3.0 — Contratos REST | [`docs/design/api/SDD-PagoFacil-openapi.yaml`](docs/design/api/SDD-PagoFacil-openapi.yaml) | Paso 6 — Diseño Técnico |
| Esquema SQL — DDL por Bounded Context | [`docs/design/database/SDD-PagoFacil-schema.sql`](docs/design/database/SDD-PagoFacil-schema.sql) | Paso 6 — Diseño Técnico |
| Diagrama C4 — Contexto del Sistema | [`docs/design/diagrams/SDD-PagoFacil-c4-context.mmd`](docs/design/diagrams/SDD-PagoFacil-c4-context.mmd) | Paso 6 — Diseño Técnico |
| Diagrama C4 — Contenedores | [`docs/design/diagrams/SDD-PagoFacil-c4-container.mmd`](docs/design/diagrams/SDD-PagoFacil-c4-container.mmd) | Paso 6 — Diseño Técnico |
| **Roadmap maestro de desarrollo** | [`docs/development/DEV-PagoFacil-roadmap.md`](docs/development/DEV-PagoFacil-roadmap.md) | Paso 7 — Plan de Desarrollo |
| Plan — Infraestructura local (floci + K3d) | [`docs/development/DEV-PagoFacil-00-infrastructure.md`](docs/development/DEV-PagoFacil-00-infrastructure.md) | Paso 7 — Plan de Desarrollo |
| Plan — Bases de datos y migraciones | [`docs/development/DEV-PagoFacil-01-databases.md`](docs/development/DEV-PagoFacil-01-databases.md) | Paso 7 — Plan de Desarrollo |
| Plan — Scaffolding de proyectos | [`docs/development/DEV-PagoFacil-02-scaffold.md`](docs/development/DEV-PagoFacil-02-scaffold.md) | Paso 7 — Plan de Desarrollo |
| Plan — Pipeline CI/CD (Jenkins + ArgoCD) | [`docs/development/DEV-PagoFacil-02b-cicd.md`](docs/development/DEV-PagoFacil-02b-cicd.md) | Paso 7 — Plan de Desarrollo |
| Plan MS — identity-service (BC-01) | [`docs/development/DEV-PagoFacil-03-ms-identity-service.md`](docs/development/DEV-PagoFacil-03-ms-identity-service.md) | Paso 7 — Plan de Desarrollo |
| Plan MS — wallet-service (BC-02) | [`docs/development/DEV-PagoFacil-03-ms-wallet-service.md`](docs/development/DEV-PagoFacil-03-ms-wallet-service.md) | Paso 7 — Plan de Desarrollo |
| Plan MS — fraud-service (BC-03) | [`docs/development/DEV-PagoFacil-03-ms-fraud-service.md`](docs/development/DEV-PagoFacil-03-ms-fraud-service.md) | Paso 7 — Plan de Desarrollo |
| Plan MS — notification-service (BC-04) | [`docs/development/DEV-PagoFacil-03-ms-notification-service.md`](docs/development/DEV-PagoFacil-03-ms-notification-service.md) | Paso 7 — Plan de Desarrollo |
| Plan MS — audit-service (BC-05+07) | [`docs/development/DEV-PagoFacil-03-ms-audit-service.md`](docs/development/DEV-PagoFacil-03-ms-audit-service.md) | Paso 7 — Plan de Desarrollo |
| Plan MS — projection-service (CQRS) | [`docs/development/DEV-PagoFacil-03-ms-projection-service.md`](docs/development/DEV-PagoFacil-03-ms-projection-service.md) | Paso 7 — Plan de Desarrollo |
| Plan MS — integration-service (BC-06) | [`docs/development/DEV-PagoFacil-03-ms-integration-service.md`](docs/development/DEV-PagoFacil-03-ms-integration-service.md) | Paso 7 — Plan de Desarrollo |
| Plan MS — report-extraction-service (MS1 Spark) | [`docs/development/DEV-PagoFacil-03-ms-report-extraction-service.md`](docs/development/DEV-PagoFacil-03-ms-report-extraction-service.md) | Paso 7 — Plan de Desarrollo |
| Plan MS — report-processing-service (MS2 Spark) | [`docs/development/DEV-PagoFacil-03-ms-report-processing-service.md`](docs/development/DEV-PagoFacil-03-ms-report-processing-service.md) | Paso 7 — Plan de Desarrollo |
| Plan FE — feature auth | [`docs/development/DEV-PagoFacil-04-fe-auth.md`](docs/development/DEV-PagoFacil-04-fe-auth.md) | Paso 7 — Plan de Desarrollo |
| Plan FE — feature wallet | [`docs/development/DEV-PagoFacil-04-fe-wallet.md`](docs/development/DEV-PagoFacil-04-fe-wallet.md) | Paso 7 — Plan de Desarrollo |
| Plan FE — feature audit | [`docs/development/DEV-PagoFacil-04-fe-audit.md`](docs/development/DEV-PagoFacil-04-fe-audit.md) | Paso 7 — Plan de Desarrollo |
| Plan — Pruebas de integración, E2E, estrés y carga | [`docs/development/DEV-PagoFacil-05-tests.md`](docs/development/DEV-PagoFacil-05-tests.md) | Paso 7 — Plan de Desarrollo |
| Plan — Reportería serverless (Lambda + EventBridge) | [`docs/development/DEV-PagoFacil-06-reporting-serverless.md`](docs/development/DEV-PagoFacil-06-reporting-serverless.md) | Paso 7 — Plan de Desarrollo |
