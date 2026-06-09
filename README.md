# PagoFacil — Billetera Digital

Proyecto de desarrollo de una plataforma de billetera digital segura, escalable y de alta disponibilidad para la gestión de fondos electrónicos con cumplimiento regulatorio (KYC/AML).

---

## Framework SDLC

Este repositorio sigue un framework de ciclo de vida de desarrollo de software (SDLC) asistido por Claude Code. Cada etapa produce artefactos estructurados que alimentan la siguiente, garantizando trazabilidad desde el requerimiento inicial hasta la implementación.

```
Etapa 0 — Requerimiento del cliente              ✓ completada
Etapa 1 — Planeación (PID)                       ✓ completada
Etapa 2 — Análisis de Requerimientos (SRS)        ✓ completada
Etapa 2b — Contexto Arquitectónico (ADC)          ✓ completada
Etapa 3 — Pre-Diseño (Strategic SDD)              ✓ completada
Etapa 4 — Diseño Técnico (Technical SDD)          ✓ completada
Etapa 4b — Plan de Desarrollo                     ✓ completada
Etapa 5 — Implementación                          ← próximo paso
```

---

## Etapa 0 — Requerimiento del Cliente

### Proceso

1. Se diligencia el formato base ubicado en `.claude/formatos/input-template.md`.
2. El documento completado se guarda en `requerimiento/` con el nombre del proyecto.
3. Este documento sirve como entrada para la skill `/plan-pid` en la siguiente etapa.

### Artefacto generado

| Archivo | Descripción |
|---------|-------------|
| [`requerimiento/input-pagofacil.md`](requerimiento/input-pagofacil.md) | Requerimiento del cliente diligenciado — entrada para la etapa de Planeación |

### Resumen del requerimiento

| Campo | Valor |
|-------|-------|
| **Proyecto** | PagoFacil — Billetera Digital |
| **Tipo** | Nuevo desarrollo |
| **Dominio** | Finanzas / Fintech |
| **Objetivo** | Plataforma de billetera digital segura, escalable y de alta disponibilidad |
| **Alcance funcional** | Registro/autenticación MFA, depósito/retiro/transferencia, KYC/AML, APIs para integración financiera, monitoreo de fraude, observabilidad |
| **Fuera del alcance** | Apps móviles nativas, integración directa Visa/Mastercard, módulo de crédito, soporte multimoneda (fase inicial) |
| **Disponibilidad requerida** | 99.9% uptime |
| **Rendimiento** | Respuesta < 500ms bajo carga nominal |
| **RTO / RPO** | < 1 hora / < 15 minutos |

---

## Etapa 1 — Planeación (PID)

### Proceso

1. Se ejecuta la skill `/plan-pid` con el requerimiento del cliente como entrada.
2. El PID generado se guarda en `docs/planning/`.
3. Este documento sirve como entrada para la skill `/requirements-srs` en la siguiente etapa.

### Artefacto generado

| Archivo | Descripción |
|---------|-------------|
| [`docs/planning/PID-PagoFacil.md`](docs/planning/PID-PagoFacil.md) | Project Initiation Document — define alcance, stakeholders, riesgos, viabilidad y cronograma de alto nivel |

### Resumen del PID

| Campo | Valor |
|-------|-------|
| **Tipo de proyecto** | Nuevo desarrollo |
| **Duración estimada** | 9–12 meses |
| **Disponibilidad** | 99.9% uptime |
| **Recuperación** | RTO < 1h / RPO < 15min |
| **Etapas planificadas** | 8 fases (planeación → lanzamiento MVP) |
| **Riesgos identificados** | 7 (regulatorio, seguridad, integración, escalabilidad, consistencia, fraude, scope creep) |

---

## Etapa 2 — Análisis de Requerimientos (SRS)

### Proceso

1. Se ejecuta la skill `/requirements-srs` con el PID como entrada.
2. El SRS generado se guarda en `docs/requirements/`.
3. Este documento sirve como entrada para el ADC en la siguiente etapa.

### Artefacto generado

| Archivo | Descripción |
|---------|-------------|
| [`docs/requirements/SRS-PagoFacil.md`](docs/requirements/SRS-PagoFacil.md) | Software Requirements Specification — define actores, requerimientos funcionales y no funcionales, restricciones y criterios de aceptación |

### Resumen del SRS

| Campo | Valor |
|-------|-------|
| **Versión** | 1.0 |
| **Estado** | Borrador — pendiente revisión por stakeholders |
| **Actores identificados** | 7 (Usuario Final, Administrador, Oficial de Cumplimiento, Analista de Fraude, Entidad Financiera, Pasarela de Pago, Sistema de Auditoría) |
| **Procesos principales** | Onboarding/KYC, operaciones financieras (depósito/retiro/transferencia), consulta/reportes, compliance AML, integración APIs, auditoría |
| **Fuera del alcance** | Apps móviles nativas, integración directa Visa/Mastercard, crédito/préstamos, multimoneda (fase inicial) |
| **Arquitectura operacional** | Microservicios sobre Kubernetes en nube pública, comunicación basada en eventos |

---

## Etapa 2b — Contexto Arquitectónico (ADC)

### Proceso

1. Se diligencia el formato base ubicado en `.claude/formatos/input-adc-template.md` apoyándose en el SRS y en el stack soportado por `.claude/scripts/` y `.claude/templates/`.
2. El ADC completado se guarda en `docs/planning/`.
3. Este documento se pasa junto al SRS como entrada para la skill `/strategic-design-sdd` en la siguiente etapa.

### Artefacto generado

| Archivo | Descripción |
|---------|-------------|
| [`docs/planning/ADC-PagoFacil.md`](docs/planning/ADC-PagoFacil.md) | Architectural Decision Context — define stack mandatorio, infraestructura, estilo arquitectónico, SLAs, compliance, integraciones y decisiones previas tomadas |

### Resumen del ADC

| Campo | Valor |
|-------|-------|
| **Backend** | Java 21 + Spring Boot 3 WebFlux (hexagonal, reactivo) |
| **ETL / Reportería** | Scala 3 + Apache Spark + AWS Lambda + EventBridge |
| **Integración** | Apache Camel 4 (`integration-service`) + Narayana LRA (sagas) |
| **Frontend** | Next.js 14 (TypeScript, App Router) |
| **BD write model** | PostgreSQL 16 (ACID, Liquibase) |
| **BD read model** | PostgreSQL 16 — `pagofacil_readmodel` (ADR-002, override de MongoDB) |
| **Mensajería** | Apache Kafka 3 KRaft |
| **Auth** | AWS Cognito + OAuth 2.0 / OIDC |
| **K8s** | K3s en VPS (dev) / EKS (staging-prod) |
| **CI/CD** | Jenkins + ArgoCD + SonarQube + Gitea |
| **Observabilidad** | OpenTelemetry + Prometheus + Grafana + Jaeger + Fluent Bit |
| **Compliance** | KYC/AML obligatorio, GDPR por verificar, retención regulatoria de datos financieros |

---

## Etapa 3 — Pre-Diseño Estratégico (Strategic SDD)

### Proceso

1. Se ejecuta la skill `/strategic-design-sdd` con el SRS y el ADC como entradas.
2. Los tres documentos SDD generados se guardan en `docs/strategic-design/`.
3. Este conjunto de documentos sirve como entrada para la skill `/technical-design-sdd` en la siguiente etapa.

### Artefactos generados

| Archivo | Descripción |
|---------|-------------|
| [`docs/strategic-design/SDD-PagoFacil-domain.md`](docs/strategic-design/SDD-PagoFacil-domain.md) | Dominio y Comportamiento — ubiquitous language, bounded contexts, context map, modelos de dominio, eventos, workflows y escenarios BDD |
| [`docs/strategic-design/SDD-PagoFacil-security.md`](docs/strategic-design/SDD-PagoFacil-security.md) | Diseño de Seguridad — modelo de seguridad, threat modeling STRIDE y trust boundaries |
| [`docs/strategic-design/SDD-PagoFacil-architecture.md`](docs/strategic-design/SDD-PagoFacil-architecture.md) | Estrategia Arquitectónica — drivers arquitectónicos, decisiones estratégicas (DS-xxx), riesgos, tradeoffs y próximos pasos |

### Resumen del Strategic SDD

| Campo | Valor |
|-------|-------|
| **Bounded contexts** | 7 — Identity, Wallet, Fraud & Compliance, Notification, Integration, Audit, Reporting |
| **Eventos de dominio** | 12 (incluye eventos de compensación de sagas y eventos de fallo del pipeline ETL) |
| **Flujos de saga** | 3 — Depósito, Transferencia entre usuarios, Retiro de fondos |
| **Sistemas externos con ACL** | 5 — Proveedor KYC, Entidades Financieras, Pasarelas de Pago, Proveedor AML, SMS/Email |
| **Decisiones estratégicas** | 10 — DS-001 a DS-008 + DS-CQRS-1/2/3 (stack y decisiones previas del ADC incorporadas) |
| **Amenazas STRIDE identificadas** | 15 ordenadas por impacto descendente |
| **Riesgos arquitectónicos** | 8 con plan de mitigación |

---

## Etapa 4 — Diseño Técnico (Technical SDD)

### Proceso

1. Se ejecuta la skill `/technical-design-sdd` con los documentos del Strategic SDD como entrada.
2. Los tres documentos SDD técnicos y los artefactos independientes se guardan en `docs/design/`.
3. Este conjunto de documentos sirve como entrada para la skill `/development-plan` en la siguiente etapa.

### Artefactos generados

**Documentos principales:**

| Archivo | Descripción |
|---------|-------------|
| [`docs/design/SDD-PagoFacil-system.md`](docs/design/SDD-PagoFacil-system.md) | Arquitectura del Sistema — estilo arquitectónico, stack tecnológico, componentes por bounded context y diseño de módulos |
| [`docs/design/SDD-PagoFacil-design.md`](docs/design/SDD-PagoFacil-design.md) | Diseño Técnico — APIs, persistencia (Database-per-Service), flujos de sagas, pipeline ETL y seguridad técnica |
| [`docs/design/SDD-PagoFacil-infrastructure.md`](docs/design/SDD-PagoFacil-infrastructure.md) | Infraestructura y Gobernanza — ambientes, deployment, observabilidad, ADRs y riesgos técnicos |

**Artefactos independientes:**

| Archivo | Descripción |
|---------|-------------|
| [`docs/design/diagrams/SDD-PagoFacil-c4-context.mmd`](docs/design/diagrams/SDD-PagoFacil-c4-context.mmd) | Diagrama C4 Nivel 1 — contexto del sistema con actores y sistemas externos |
| [`docs/design/diagrams/SDD-PagoFacil-c4-container.mmd`](docs/design/diagrams/SDD-PagoFacil-c4-container.mmd) | Diagrama C4 Nivel 2 — contenedores internos, bases de datos, mensajería y capa serverless |
| [`docs/design/api/SDD-PagoFacil-openapi.yaml`](docs/design/api/SDD-PagoFacil-openapi.yaml) | Especificación OpenAPI 3.0 — 30+ endpoints REST por bounded context, incluyendo endpoints de compensación de saga |
| [`docs/design/database/SDD-PagoFacil-schema.sql`](docs/design/database/SDD-PagoFacil-schema.sql) | DDL PostgreSQL — esquema de 7 bases de datos (write models, read model CQRS, reporting), tablas de saga, outbox e idempotencia |
| [`docs/design/database/SDD-PagoFacil-collections.js`](docs/design/database/SDD-PagoFacil-collections.js) | Colecciones MongoDB — BC-06 audit-service, modo append-only con validadores `$jsonSchema` |

### Resumen del Technical SDD

| Campo | Valor |
|-------|-------|
| **Microservicios** | 9 — identity, wallet, fraud-compliance, notification, integration, audit, projection, report-extraction (MS1), report-processing (MS2) |
| **Bases de datos** | 8 — 6 PostgreSQL operacionales + `pagofacil_readmodel` + `pagofacil_reporting` + MongoDB audit |
| **Patrón de persistencia** | Database-per-Service; migraciones con Liquibase standalone; changelogs en repo `pagofacil-migrations` en Gitea |
| **Sagas documentadas** | 3 — Depósito, Transferencia, Retiro; con tabla de pasos, compensaciones e idempotencia |
| **ADRs técnicos** | 9 — Database-per-Service, override MongoDB→PostgreSQL (ADR-002), Camel ACL, Narayana LRA, Transactional Outbox, CQRS Projection Service, Spark CronJob, Lambda serverless, CQRS read model |
| **Pipeline ETL** | MS1 (Spark JDBC → Parquet raw/) → MS2 (Factory por ReportType → Parquet processed/) → Lambda (PDF/XLS/CSV) |
| **Infraestructura** | K3s + systemd en VPS (dev) / EKS + RDS + MSK (staging/prod); Terraform vía `base-infrastructure-builder.sh` |

---

---

## Etapa 4b — Plan de Desarrollo

### Proceso

1. Se ejecuta la skill `/development-plan` con los documentos del Technical SDD como entrada (`docs/design/`).
2. El plan de desarrollo generado se guarda en `docs/development/` — un documento por componente.
3. Estos documentos sirven como guía ejecutable para la etapa de Implementación.

### Artefactos generados

**Documento maestro:**

| Archivo | Descripción |
|---------|-------------|
| [`docs/development/DEV-PagoFacil-roadmap.md`](docs/development/DEV-PagoFacil-roadmap.md) | Índice maestro — secuencia de 22 etapas, mapa de microservicios, features frontend, ambiente VPS y Definition of Done |

**Infraestructura y plataforma:**

| Archivo | Descripción |
|---------|-------------|
| [`docs/development/DEV-PagoFacil-00-infrastructure.md`](docs/development/DEV-PagoFacil-00-infrastructure.md) | Etapa 0 — Provisionar VPS Ubuntu 26.04 LTS, K3s nativo, floci, scripts `qemu-vps.sh` y `init-dev-environment.sh` |
| [`docs/development/DEV-PagoFacil-0c-observability.md`](docs/development/DEV-PagoFacil-0c-observability.md) | Etapa 0c — Stack OTEL + Prometheus + Grafana + Jaeger + Loki; `setup-observability.sh`; módulo Terraform staging/prod |
| [`docs/development/DEV-PagoFacil-01-databases.md`](docs/development/DEV-PagoFacil-01-databases.md) | Etapa 1 — `init-databases.sh`; Database-per-Service PostgreSQL + MongoDB; changelogs Liquibase en repo `pagofacil-migrations` |
| [`docs/development/DEV-PagoFacil-02-scaffold.md`](docs/development/DEV-PagoFacil-02-scaffold.md) | Etapa 2 — Comando `scaffold-all-services.sh` completo; Jenkinsfiles (Spring/Spark/Frontend); Helm charts; observabilidad automática |
| [`docs/development/DEV-PagoFacil-02b-cicd.md`](docs/development/DEV-PagoFacil-02b-cicd.md) | Etapa 2b — `setup-cicd-pipeline.sh`; Jenkins systemd en VPS; 10 jobs multibranch; webhooks Gitea; bootstrap ArgoCD K3s |

**Microservicios (uno por bounded context):**

| Archivo | Descripción |
|---------|-------------|
| [`docs/development/DEV-PagoFacil-03-ms-identity-service.md`](docs/development/DEV-PagoFacil-03-ms-identity-service.md) | Etapa 3a — BC-01 Identity; KYC, MFA, autenticación; saga onboarding; outbox; TDD por capa |
| [`docs/development/DEV-PagoFacil-03-ms-wallet-service.md`](docs/development/DEV-PagoFacil-03-ms-wallet-service.md) | Etapa 3b — BC-02 Wallet; operaciones atómicas débito/crédito/reserva; límites transaccionales; TDD |
| [`docs/development/DEV-PagoFacil-03-ms-notification-service.md`](docs/development/DEV-PagoFacil-03-ms-notification-service.md) | Etapa 3c — BC-04 Notification; Kafka consumer puro; delegación de envío al integration-service |
| [`docs/development/DEV-PagoFacil-03-ms-fraud-compliance-service.md`](docs/development/DEV-PagoFacil-03-ms-fraud-compliance-service.md) | Etapa 3d — BC-03 Fraud & Compliance; evaluación AML/antifraude; ciclo de vida de alertas; TDD |
| [`docs/development/DEV-PagoFacil-03-ms-integration-service.md`](docs/development/DEV-PagoFacil-03-ms-integration-service.md) | Etapa 3e — BC-05 Integration; Apache Camel ACL; orquestador Narayana LRA; 3 sagas; WireMock en pruebas |
| [`docs/development/DEV-PagoFacil-03-ms-audit-service.md`](docs/development/DEV-PagoFacil-03-ms-audit-service.md) | Etapa 3f — BC-06 Audit; MongoDB append-only; trazas inmutables; masking PII; TDD |
| [`docs/development/DEV-PagoFacil-03-ms-projection-service.md`](docs/development/DEV-PagoFacil-03-ms-projection-service.md) | Etapa 3g — BC-07 CQRS; único escritor de `pagofacil_readmodel`; 9 projectors; idempotencia |
| [`docs/development/DEV-PagoFacil-03-ms-report-extraction-service.md`](docs/development/DEV-PagoFacil-03-ms-report-extraction-service.md) | Etapa 3h — MS1 Spark/Scala; `SparkJdbcSourceAdapter`; validación de esquema; Parquet `raw/`; CronJob K8s |
| [`docs/development/DEV-PagoFacil-03-ms-report-processing-service.md`](docs/development/DEV-PagoFacil-03-ms-report-processing-service.md) | Etapa 3i — MS2 Spark/Scala; patrón Factory (Abierto/Cerrado) por `ReportType`; Parquet `processed/`; CronJob K8s |

**Features frontend (uno por área funcional):**

| Archivo | Descripción |
|---------|-------------|
| [`docs/development/DEV-PagoFacil-04-fe-auth.md`](docs/development/DEV-PagoFacil-04-fe-auth.md) | Etapa 4a — Registro, login MFA, callback Cognito; TDD Vitest + RTL + MSW; Playwright ATDD |
| [`docs/development/DEV-PagoFacil-04-fe-wallets.md`](docs/development/DEV-PagoFacil-04-fe-wallets.md) | Etapa 4b — Saldo, historial paginado con filtros, cuentas bancarias vinculadas |
| [`docs/development/DEV-PagoFacil-04-fe-transactions.md`](docs/development/DEV-PagoFacil-04-fe-transactions.md) | Etapa 4c — Depósito, transferencia, retiro; `Idempotency-Key`; polling de estado de saga |
| [`docs/development/DEV-PagoFacil-04-fe-compliance.md`](docs/development/DEV-PagoFacil-04-fe-compliance.md) | Etapa 4d — Dashboard alertas AML/fraude; resolución por rol (FRAUD_ANALYST, COMPLIANCE_OFFICER) |
| [`docs/development/DEV-PagoFacil-04-fe-audit.md`](docs/development/DEV-PagoFacil-04-fe-audit.md) | Etapa 4e — Dashboard trazabilidad; filtros avanzados por correlationId, sagaId, eventType |
| [`docs/development/DEV-PagoFacil-04-fe-reporting.md`](docs/development/DEV-PagoFacil-04-fe-reporting.md) | Etapa 4f — Catálogo de reportes, solicitud on-demand, polling de estado, descarga PDF/XLS/CSV |

**Pruebas y capa serverless:**

| Archivo | Descripción |
|---------|-------------|
| [`docs/development/DEV-PagoFacil-05-tests.md`](docs/development/DEV-PagoFacil-05-tests.md) | Etapa 5 — Pruebas de integración (sagas completas + compensaciones), E2E Playwright, estrés y carga con k6, verificación E2E de observabilidad |
| [`docs/development/DEV-PagoFacil-06-reporting-serverless.md`](docs/development/DEV-PagoFacil-06-reporting-serverless.md) | Etapa 6 — Lambda Kafka Consumer + EventBridge rules + lambdas PDF/XLS/CSV; pytest TDD; Terraform floci/AWS |

### Resumen del Plan de Desarrollo

| Campo | Valor |
|-------|-------|
| **Documentos generados** | 23 (1 roadmap + 5 plataforma + 9 microservicios + 6 features frontend + 2 pruebas/serverless) |
| **Microservicios cubiertos** | 9 Spring Boot WebFlux + 2 Spark/Scala (MS1, MS2) + 1 capa serverless Lambda |
| **Features frontend** | 6 (auth, wallets, transactions, compliance, audit, reporting) |
| **Esfuerzo estimado total** | ~47 días de desarrollo |
| **Orden de implementación** | identity → wallet → notification → fraud → integration → audit → projection → MS1 → MS2 → frontend → serverless |
| **Estrategia de pruebas** | TDD obligatorio (Red-Green-Refactor) en todas las capas; JUnit 5 + Mockito + Testcontainers + WebTestClient (backend); Vitest + RTL + MSW + Playwright (frontend) |
| **Ambiente objetivo** | VPS Ubuntu 26.04 LTS — K3s nativo + floci (`VPS_IP:4566`); sin Docker local, sin EKS en dev |

---

## Próximo paso

Con el plan de desarrollo generado, iniciar la etapa de Implementación:

```bash
# Etapa 0 — Aprovisionar VPS e infraestructura base
bash .claude/scripts/base-infrastructure-builder.sh -P pagofacil --vps-ip <VPS_IP>
bash .claude/scripts/init-dev-environment.sh -P pagofacil --vps-ip <VPS_IP>
```

Ver [`docs/development/DEV-PagoFacil-roadmap.md`](docs/development/DEV-PagoFacil-roadmap.md) para la secuencia completa de etapas.
