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

## Próximo paso

Con el Technical SDD generado, aprovisionar la infraestructura base y generar el plan de desarrollo:

```bash
# 1. Aprovisionar infraestructura base
bash .claude/scripts/base-infrastructure-builder.sh

# 2. Generar plan de desarrollo
/development-plan docs/design/
```
