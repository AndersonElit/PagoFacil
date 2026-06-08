# Software Design Document — Arquitectura del Sistema

**Proyecto:** PagoFacil — Billetera Digital
**Conjunto SDD técnico:** Este documento forma parte del SDD Técnico junto con `SDD-PagoFacil-design.md` e `SDD-PagoFacil-infrastructure.md`.
**Versión:** 1.0
**Fecha:** 2026-06-08

---

## 1. Introducción

**Propósito:** Definir la arquitectura técnica del sistema PagoFacil, el stack tecnológico seleccionado, los componentes principales y el diseño de módulos internos. Este documento transforma las decisiones estratégicas del Strategic Design en una solución técnica concreta, lista para implementación.

**Objetivo técnico:** Establecer la estructura de microservicios, sus responsabilidades, dependencias y mecanismos de comunicación, respetando los bounded contexts definidos en el dominio y las restricciones arquitectónicas del SRS y el ADC.

**Alcance del diseño:** Cubre todos los bounded contexts del sistema (Identity, Wallet, Fraud & Compliance, Notification, Integration, Audit y Reporting), el pipeline ETL de reportería, la capa serverless de generación de formatos y la infraestructura de soporte (Kafka, PostgreSQL, MongoDB, AWS Cognito, Kubernetes).

**Contexto del sistema:** PagoFacil es una plataforma fintech de billetera digital multitenancy que gestiona onboarding KYC/AML, operaciones financieras distribuidas (depósito, transferencia, retiro), controles de compliance en tiempo real y reportería regulatoria. El diseño técnico respeta las decisiones estratégicas DS-001 a DS-008 y DS-CQRS-1 a DS-CQRS-3 como restricciones no revisables.

---

## 2. Arquitectura General

### Estilo Arquitectónico

El sistema implementa una **arquitectura de microservicios orientada a dominio**, donde cada bounded context se materializa como uno o más microservicios independientes. Los microservicios se comunican de forma asíncrona a través de Apache Kafka (eventos de dominio) y de forma síncrona mediante REST interno para operaciones que requieren respuesta inmediata (saga orchestration).

Las decisiones estratégicas imponen las siguientes capas arquitectónicas:

| Capa | Descripción |
|---|---|
| Presentación | Frontend Next.js 14 + AWS API Gateway v2 como punto de entrada único |
| Identidad | AWS Cognito para OAuth 2.0/OIDC; JWT con claims `role` y `tenant_id` |
| Dominio | Microservicios reactivos (Spring Boot 3 WebFlux) por bounded context |
| Integración | `integration-service` (Apache Camel 4) como ACL y orquestador de sagas |
| Mensajería | Apache Kafka 3 KRaft como bus de eventos de dominio |
| Persistencia | PostgreSQL 16 por servicio (write model); MongoDB 7 para auditoría |
| CQRS / Read Model | PostgreSQL 16 `pagofacil_readmodel` proyectado por `projection-service` |
| Reportería ETL | Spark batch (MS1, MS2) + Lambda serverless (PDF/XLS/CSV) |
| Observabilidad | OpenTelemetry + Prometheus + Jaeger + Fluent Bit |

### Organización General

Todos los microservicios de dominio son **reactivos** (Spring Boot WebFlux + R2DBC). El `integration-service` es el único componente con conectividad directa a sistemas externos; actúa como Anti-Corruption Layer (ACL) y orquestador de sagas mediante Apache Camel 4 + Narayana LRA. El `projection-service` es el único escritor del read model CQRS. MS1 y MS2 son jobs Spark batch ejecutados como Kubernetes CronJobs.

### Diagramas C4

Ver diagrama de contexto: [SDD-PagoFacil-c4-context.mmd](diagrams/SDD-PagoFacil-c4-context.mmd)

El diagrama de contexto muestra PagoFacil como sistema único en relación con cuatro tipos de usuarios internos (Usuario Final, Administrador, Analista de Fraude, Oficial de Cumplimiento) y cinco sistemas externos (Proveedor KYC, Proveedor AML, Entidades Financieras, Pasarelas de Pago, Proveedor SMS/Email). Todos los intercambios con sistemas externos ocurren exclusivamente a través del `integration-service`.

Ver diagrama de contenedores: [SDD-PagoFacil-c4-container.mmd](diagrams/SDD-PagoFacil-c4-container.mmd)

El diagrama de contenedores muestra los 9 microservicios de dominio, el frontend Next.js, el API Gateway, el coordinador Narayana LRA, el bus Kafka, las bases de datos por servicio, el read model CQRS, el pipeline Spark ETL y la capa serverless Lambda + EventBridge. El `integration-service` se posiciona explícitamente entre los microservicios de dominio y los sistemas externos, conforme a la decisión DS-004.

---

## 3. Stack Tecnológico

| Categoría | Tecnología | Razón |
|---|---|---|
| Runtime backend | Java 21 (LTS) | Compatibilidad con Spring Boot 3 WebFlux y R2DBC; virtual threads disponibles; restricción ADC §2 |
| Framework backend | Spring Boot 3.3 WebFlux | Stack reactivo no bloqueante obligatorio por ADC §2; compatible con R2DBC y Kafka reactivo |
| ORM / DB reactivo | Spring Data R2DBC | Acceso reactivo a PostgreSQL; incompatibilidad de Flyway con R2DBC justifica Liquibase standalone como herramienta de migraciones |
| Integración | Apache Camel 4 + Spring Boot | Mandatorio por DS-004; bridge reactivo vía `camel-reactive-streams`; Resilience4j para circuit breaker |
| Saga / LRA | Narayana LRA Coordinator | Mandatorio por DS-005; gestión del ciclo de vida de sagas distribuidas con compensación |
| Reportería ETL | Apache Spark 3.5.1 + Scala 3 (fat JAR sbt-assembly) | Mandatorio por DS-006; SparkJdbcSourceAdapter para lectura del read model PostgreSQL sin adaptadores adicionales |
| Base de datos operacional | PostgreSQL 16 | Write model ACID por servicio; Database-per-Service (DS-002); compatible con R2DBC y Spark JDBC |
| Read model CQRS | PostgreSQL 16 `pagofacil_readmodel` | Decisión DS-003 / ADR-002 (override MongoDB→PostgreSQL); compatibilidad nativa con SparkJdbcSourceAdapter |
| Base de datos auditoría | MongoDB 7 | Almacenamiento append-only; flexibilidad de schema para metadatos variables de trazas |
| Bus de mensajes | Apache Kafka 3 KRaft | Mandatorio por ADC §2; sin ZooKeeper; MSK en staging/prod |
| Autenticación / Identidad | AWS Cognito (User Pool) | OAuth 2.0 / OIDC; MFA nativo; emisión de JWT con claims `role` y `tenant_id`; restricción ADC §3 |
| API Gateway | AWS API Gateway v2 | JWT authorizer Cognito; rate limiting; routing; punto de entrada único; restricción ADC §3 |
| Gestión de secretos | AWS Secrets Manager | Mandatorio por ADC §3 y RN-008; rotación automática; sin secretos en código fuente |
| Serverless formatos | AWS Lambda (Python 3.12) + EventBridge | Mandatorio por DS-007; generación esporádica de PDF/XLS/CSV; pay-per-use |
| Almacenamiento Parquet | Amazon S3 (floci en dev) | Contrato entre etapas ETL (MS1→MS2→Lambda); cifrado AES-256 en reposo |
| Frontend | Next.js 14 + TypeScript | SSR + SPA; integración nativa con Cognito; dashboard de auditoría y compliance |
| Migraciones de esquema | Liquibase standalone (`run-liquibase-migrations.sh`) | Mandatorio por ADC §2; changelogs en repo `pagofacil-migrations` en Gitea del VPS; incompatibilidad de Flyway con R2DBC |
| Contenedores | Docker + Kubernetes (K3s dev / EKS staging/prod) | Mandatorio por DS-001 y ADC §3 |
| CI/CD | Jenkins + ArgoCD + Gitea | Pipeline por servicio; ArgoCD sincroniza manifiestos K8s; imágenes publicadas en Gitea Package Registry |
| Observabilidad | OpenTelemetry + Prometheus + Jaeger + Fluent Bit + Grafana | Mandatorio por RNF-009; trazas distribuidas por `correlationId`; logs JSON estructurado |

---

## 4. Componentes del Sistema

## Componente: identity-service

### Responsabilidades
- Registro de usuarios con validación de unicidad y formato de datos.
- Coordinación del proceso KYC con el proveedor externo a través del `integration-service`.
- Autenticación de primer factor (email + password) con conteo de intentos fallidos y bloqueo automático de cuenta.
- Gestión del segundo factor MFA (TOTP, SMS OTP, email OTP).
- Emisión de sesiones (access token + refresh token) delegada a AWS Cognito.
- Gestión del ciclo de vida de cuenta: Pendiente, Activo, Suspendido, Bloqueado.
- Publicación de eventos de dominio: `UserRegistered`, `KYCApproved`, `KYCRejected`, `AccountSuspendedByAML`.

### Dependencias
- AWS Cognito (emisión y validación de tokens).
- `integration-service` (coordinación KYC y resultado AML del onboarding).
- Kafka (publicación de eventos de dominio).
- PostgreSQL `pagofacil_identity_service` (write model propio).

---

## Componente: wallet-service

### Responsabilidades
- Creación de billetera digital al recibir el evento `KYCApproved` desde Kafka.
- Consulta de saldo disponible en tiempo real con garantías de lectura consistente.
- Historial paginado de movimientos con filtros por tipo, fecha y estado.
- Validación y aplicación de límites transaccionales acumulativos por período.
- Gestión de cuentas bancarias vinculadas como destino exclusivo de retiros.
- Ejecución de operaciones atómicas (débito, crédito, reserva, liberación) bajo instrucción del `integration-service`.
- Publicación de eventos: `WalletCreated`, `DepositCompleted`, `TransferCompleted`, `WithdrawalCompleted` y sus compensaciones.

### Dependencias
- Kafka (consumo de `KYCApproved`; publicación de eventos de billetera).
- `integration-service` (recibe instrucciones de operación durante sagas).
- PostgreSQL `pagofacil_wallet_service`.

---

## Componente: fraud-compliance-service

### Responsabilidades
- Evaluación AML de usuarios durante el onboarding (consumo de `UserRegistered`).
- Evaluación AML y antifraude en tiempo real por solicitud del `integration-service` en cada operación financiera.
- Gestión del ciclo de vida de alertas: creación, asignación, revisión, aprobación, rechazo y escalamiento.
- Bloqueo automático de operaciones con RiskLevel Crítico.
- Soporte a la generación de ROS/SAR: datos estructurados para MS2.
- Publicación de eventos: `FraudAlertCreated`, `ComplianceAlertResolved`, `AccountSuspendedByAML`.

### Dependencias
- Kafka (consumo y publicación de eventos de alerta y compliance).
- `integration-service` (consulta al proveedor AML externo vía ACL).
- PostgreSQL `pagofacil_fraud_compliance_service`.

---

## Componente: notification-service

### Responsabilidades
- Envío de confirmaciones de operaciones financieras (depósito, transferencia, retiro).
- Envío de códigos MFA (OTP, TOTP) bajo solicitud del `identity-service`.
- Notificaciones de resultado KYC, alertas de seguridad y cambios de estado de cuenta.
- Gestión de preferencias de canal por usuario y tenant.
- Delegación del envío físico (SMS/email) al proveedor externo a través del `integration-service`.

### Dependencias
- Kafka (consumo de eventos de otros contextos; no publica eventos de dominio).
- `integration-service` (envío físico de SMS y email vía ACL al proveedor).
- PostgreSQL `pagofacil_notification_service`.

---

## Componente: integration-service

### Responsabilidades
- Anti-Corruption Layer (ACL) exclusivo para todos los sistemas externos: KYC, AML, entidades financieras, pasarelas, SMS/Email.
- Orquestación de sagas distribuidas (depósito, transferencia, retiro) con Narayana LRA.
- Traducción de modelos externos al lenguaje ubicuo de PagoFacil.
- Gobierno centralizado de credenciales de terceros (AWS Secrets Manager).
- Conciliación automática periódica con entidades financieras.
- Recepción y validación de webhooks entrantes (firma digital, OAuth 2.0).

### Dependencias
- Narayana LRA Coordinator (gestión del ciclo de vida de sagas; puerto 50000).
- AWS Secrets Manager (credenciales de sistemas externos).
- Kafka (publicación de eventos de saga y orquestación).
- PostgreSQL `pagofacil_integration_service` (sagas, outbox, reconciliación).
- Todos los microservicios de dominio como participantes de saga (REST interno + Kafka).
- Sistemas externos directos: Proveedor KYC, Proveedor AML, Entidades Financieras, Pasarelas, Proveedor SMS/Email.

---

## Componente: audit-service

### Responsabilidades
- Ingesta y almacenamiento inmutable de trazas de todos los eventos de negocio.
- Registro con actor, acción, timestamp, IP de origen y correlationId.
- Dashboard de consulta filtrada para Administradores y Oficiales de Cumplimiento.
- Consulta por usuario, tipo de evento, rango de fechas, correlationId y sagaId.

### Dependencias
- Kafka (consumidor pasivo de todos los topics de dominio; nunca productor).
- MongoDB 7 `pagofacil_audit_service` (almacenamiento append-only; sin UPDATE ni DELETE).

---

## Componente: projection-service

### Responsabilidades
- Consumo reactivo de eventos de dominio de todos los bounded contexts desde Kafka.
- Proyección del estado del sistema en tablas PostgreSQL desnormalizadas del read model.
- Garantía de idempotencia en el procesamiento de eventos (tabla `processed_message`).
- Es el único escritor de `pagofacil_readmodel`; ningún otro microservicio tiene permiso de escritura.

### Dependencias
- Kafka (consumidor multi-topic de todos los bounded contexts).
- PostgreSQL `pagofacil_readmodel` (escritura exclusiva; R2DBC).

---

## Componente: report-extraction-service (MS1)

### Responsabilidades
- Extracción de datos del read model `pagofacil_readmodel` vía Spark JDBC (SparkJdbcSourceAdapter).
- Validación del esquema extraído según `report_schema_catalog` en `pagofacil_reporting`.
- Generación de archivos Parquet en S3 `raw/` como contrato de salida para MS2.
- Publicación de eventos `report.extracted` (éxito) o `report.extraction_failed` (fallo).
- Ejecución como Kubernetes CronJob (schedule configurable por ambiente) o bajo comando on-demand.

### Dependencias
- PostgreSQL `pagofacil_readmodel` (solo lectura vía Spark JDBC).
- PostgreSQL `pagofacil_reporting` (consulta del catálogo de esquemas vía Spark JDBC).
- S3 / floci (escritura de Parquet `raw/`).
- Kafka (publicación de eventos del pipeline ETL).

---

## Componente: report-processing-service (MS2)

### Responsabilidades
- Consumo del evento `report.extracted` y lectura del Parquet `raw/` desde S3.
- Transformación de datos por ReportType mediante el patrón Factory (Abierto/Cerrado).
- Generación de archivos Parquet en S3 `processed/`.
- Publicación del evento `report.processed`.
- Ejecución como Kubernetes CronJob (encadenado a MS1 o disparado por evento Kafka).

### Dependencias
- S3 / floci (lectura de Parquet `raw/`; escritura de Parquet `processed/`).
- Kafka (consumo de `report.extracted`; publicación de `report.processed`).

---

## Componente: capa serverless Lambda + EventBridge

### Responsabilidades
- Lambda Kafka Consumer: consume `report.processed` y publica el evento a EventBridge con el formato solicitado.
- EventBridge: enruta el evento a la lambda correspondiente según el formato (PDF, XLS o CSV).
- Lambdas de formato: generan el archivo final desde el Parquet `processed/` y lo almacenan en S3 `output/`.

### Dependencias
- Kafka (consumo del topic `report.processed` por Lambda Consumer).
- S3 / floci (lectura de Parquet `processed/`; escritura de PDF/XLS/CSV en `output/`).
- EventBridge (enrutamiento interno entre Lambda Consumer y Lambdas de formato).

---

## 5. Diseño de Módulos

### identity-service — Módulos Internos

| Módulo | Responsabilidad | Dependencias internas |
|---|---|---|
| `registration` | Validación de datos, hash de contraseña, persistencia en `users` | `outbox` |
| `kyc` | Gestión del estado KYC, persistencia en `kyc_records` | `outbox`, `integration` (vía evento) |
| `authentication` | Validación de credenciales, MFA, integración con Cognito | `sessions`, `mfa` |
| `mfa` | Generación y validación de códigos TOTP/OTP | — |
| `sessions` | Emisión, renovación y revocación de tokens de sesión | Cognito |
| `outbox` | Relay de eventos de dominio hacia Kafka | Kafka |

### wallet-service — Módulos Internos

| Módulo | Responsabilidad | Dependencias internas |
|---|---|---|
| `wallet` | CRUD de billeteras, estado y saldo | `transaction`, `limits` |
| `transaction` | Operaciones financieras atómicas con idempotencia | `outbox` |
| `limits` | Validación y acumulación de límites transaccionales | — |
| `linked-bank` | Alta, verificación y consulta de cuentas bancarias | — |
| `outbox` | Relay de eventos de dominio hacia Kafka | Kafka |

### integration-service — Módulos Internos (Apache Camel Routes)

| Módulo / Ruta Camel | Responsabilidad | Sistemas externos |
|---|---|---|
| `kyc-route` | ACL con proveedor KYC; traducción de modelos; gestión de webhook KYC | Proveedor KYC |
| `aml-route` | Consulta de listas AML; traducción de respuesta al dominio | Proveedor AML |
| `deposit-saga-route` | Orquestación de la saga de depósito (Camel Saga EIP + Narayana LRA) | Entidades Financieras |
| `transfer-saga-route` | Orquestación de la saga de transferencia | — |
| `withdrawal-saga-route` | Orquestación de la saga de retiro | Entidades Financieras |
| `notification-route` | Envío delegado de SMS y email | Proveedor SMS/Email |
| `reconciliation-route` | Conciliación periódica con entidades financieras | Entidades Financieras |
| `outbox` | Relay de eventos de saga hacia Kafka | Kafka |

### Separación y límites inter-módulo

- Cada microservicio es la única unidad con acceso a su propia base de datos; no existen accesos cruzados entre BDs de distintos servicios.
- La comunicación entre módulos dentro de un mismo servicio es síncrona e interna (llamadas de método).
- La comunicación entre bounded contexts distintos se realiza exclusivamente mediante eventos Kafka o REST interno (saga participants).
- El `integration-service` es el único módulo con acceso a sistemas externos; ningún otro servicio tiene este privilegio.
