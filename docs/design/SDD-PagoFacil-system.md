# Software Design Document — Arquitectura del Sistema

**Proyecto:** PagoFacil — Billetera Digital | Parte del conjunto SDD técnico v1.0 (system / design / infrastructure)  
**Fecha:** 2026-06-06 | **Etapa:** Technical Design — Diseño Técnico

---

## 1. Introducción

### Propósito

Este documento define la arquitectura técnica del sistema PagoFacil, el stack tecnológico seleccionado y la estructura de componentes y módulos que soportarán la implementación. Es el punto de transición entre el Strategic Design y el desarrollo efectivo del sistema.

### Objetivo Técnico

Traducir las decisiones estratégicas (DS-001 a DS-009, DS-CQRS-1/2/3) en una arquitectura técnica concreta: servicios, módulos, capas, comunicación y persistencia.

### Alcance

Cubre todos los bounded contexts (BC-01 a BC-07), el subsistema de reportería batch, la capa de integración centralizada, y el modelo CQRS con Read Model PostgreSQL.

### Contexto del Sistema

PagoFacil es una plataforma fintech multitenancy que gestiona fondos electrónicos sobre Kubernetes (K3d en dev, EKS en staging/prod) con pipeline GitOps (Jenkins + ArgoCD), desplegada en AWS `us-east-1`.

---

## 2. Arquitectura General

### Estilo Arquitectónico

**Microservicios Event-Driven con Arquitectura Hexagonal por servicio** (DS-001).

Cada bounded context se implementa como un microservicio independiente con arquitectura hexagonal (ports & adapters). La comunicación asíncrona predomina sobre Apache Kafka 3.7.0 (KRaft); la comunicación síncrona REST/HTTP se usa exclusivamente para operaciones que requieren respuesta inmediata o coordinación de saga.

### Organización General

```
┌──────────────────────────────────────────────────┐
│  Zona Pública                                    │
│  Usuario / Auditor / Admin / Entidades           │
└─────────────────────┬────────────────────────────┘
                      │ HTTPS
┌─────────────────────▼────────────────────────────┐
│  Zona DMZ                                        │
│  AWS API Gateway v2 (valida JWT Cognito)         │
└─────────────────────┬────────────────────────────┘
                      │ HTTP/mTLS
┌─────────────────────▼────────────────────────────┐
│  Zona de Aplicación — Kubernetes Cluster         │
│  identity │ wallet │ fraud │ audit │ notification │
│  projection-service                              │
│  integration-service (ACL + Saga Orchestrator)   │
│  Narayana LRA Coordinator                        │
│  Reporting: MS1 (CronJob) │ MS2 (CronJob)        │
│  Lambda Consumer + EventBridge + Lambdas         │
├─────────────────────────────────────────────────┤
│  Apache Kafka 3.7.0 (KRaft)                     │
├─────────────────────────────────────────────────┤
│  Zona de Datos                                  │
│  PostgreSQL 16.3 (por servicio) + AWS S3        │
└─────────────────────────────────────────────────┘
```

### Capas por Microservicio (Hexagonal)

| Capa | Descripción |
|---|---|
| **Dominio** | Entidades, aggregates, value objects, puertos de entrada/salida |
| **Aplicación** | Casos de uso (command handlers, query handlers) |
| **Infraestructura — Adapters primarios** | Controllers REST (WebFlux), Kafka consumers |
| **Infraestructura — Adapters secundarios** | Repositorios R2DBC, Outbox relay, Kafka producers, clientes REST |

### Interacción Principal

1. El cliente llama a **API Gateway v2** que valida el JWT de Cognito y enruta al servicio destino.
2. Los servicios de dominio persisten cambios en su **PostgreSQL** propio y publican eventos vía **Outbox** a Kafka.
3. **projection-service** consume todos los eventos y construye el **Read Model** en `pagofacil_readmodel` (PostgreSQL).
4. **integration-service** (Apache Camel + Narayana LRA) orquesta las sagas y concentra toda la comunicación saliente con sistemas externos.
5. Los jobs Spark (**MS1**, **MS2**) leen el Read Model vía JDBC, procesan en batch y depositan reportes en S3.

### Diagramas C4

Ver diagrama de contexto: [SDD-PagoFacil-c4-context.mmd](diagrams/SDD-PagoFacil-c4-context.mmd)

Muestra PagoFacil como sistema único en relación con sus cuatro actores (usuario, auditor, administrador, entidades financieras) y los cuatro sistemas externos (AWS Cognito, entidades financieras/pasarelas, proveedor KYC y listas de sanciones AML).

Ver diagrama de contenedores: [SDD-PagoFacil-c4-container.mmd](diagrams/SDD-PagoFacil-c4-container.mmd)

Muestra los 15+ contenedores internos: servicios de dominio, integration-service (ACL + orquestador), projection-service, MS1/MS2 (CronJob Spark), capa serverless Lambda+EventBridge, bus Kafka, bases de datos PostgreSQL por servicio, Read Model y S3. Evidencia que solo `integration-service` se comunica con sistemas externos.

---

## 3. Stack Tecnológico

| Categoría | Tecnología | Razón |
|---|---|---|
| Backend — Servicios de dominio | Java 21 + Spring Boot 3.4.1 (WebFlux) | Restricción ADC. Programación reactiva non-blocking para alta concurrencia en operaciones financieras. |
| Backend — ETL / Reportería | Scala 2.13 + Apache Spark 3.5.1 | Restricción ADC. Procesamiento batch distribuido para volúmenes regulatorios. Fat JAR con sbt-assembly. |
| Backend — Integración / Saga | Java 21 + Apache Camel 4.10.2 + Narayana LRA | Restricción ADC. Camel como motor de integración y ACL; Narayana como coordinador LRA para sagas. |
| Frontend | TypeScript 5 + Next.js 15.3 + React 19 | Restricción ADC. SSR + SSG para dashboard de auditoría. Desplegado en Vercel. |
| Base de datos — Write side | PostgreSQL 16.3 | Restricción ADC. Garantías ACID para operaciones financieras. Database-per-Service. |
| Base de datos — Read Model CQRS | PostgreSQL 16.3 (`pagofacil_readmodel`) | Read Model relacional desnormalizado. MS1 accede vía JDBC sin JOINs entre BDs operacionales. |
| Mensajería | Apache Kafka 3.7.0 (KRaft) | Restricción ADC. Bus de eventos con garantías at-least-once, mTLS y ACL por topic. |
| Autenticación | AWS Cognito + OAuth 2.0 / OIDC | Restricción ADC. Identity Provider gestionado; emite JWT validados por API Gateway. |
| API Gateway | AWS API Gateway v2 (HTTP) | Restricción ADC. Validación JWT centralizada, enrutamiento y TLS terminación. |
| Gestión de secretos | AWS Secrets Manager | Restricción ADC. Ningún secreto en variables de entorno ni repositorio. |
| Orquestación K8s | K3d (dev) / AWS EKS (staging+prod) | Restricción ADC. GitOps con ArgoCD. Jenkins como disparador de despliegues. |
| CI/CD | Jenkins + ArgoCD | Restricción ADC. Jenkins ejecuta pipeline; ArgoCD sincroniza el estado en Kubernetes. |
| IaC | Terraform ≥ 1.6.0 | Restricción ADC. Módulos separados por ambiente (dev/staging/prod). |
| Serverless | AWS Lambda + AWS EventBridge | Restricción ADC. DS-008: capa de formatos de reporte sin servicio persistente. |
| Almacenamiento de objetos | AWS S3 | Parquet intermedio (contrato ETL entre MS1 y MS2) y reportes finales. |
| Migraciones de BD | Liquibase standalone (`liquibase/liquibase` Docker) | Aplicadas por `run-liquibase-migrations.sh` como paso previo al despliegue; changelogs en `db/<servicio>/changelog/` fuera del JAR. |
| Observabilidad | Prometheus + OpenTelemetry + CloudWatch | Métricas, trazas distribuidas con CorrelationId y logs estructurados JSON. |
| Quality Gate | SonarQube LTS Community | Cobertura ≥ 80% en módulos financieros y de seguridad. |
| Resiliencia | Resilience4j | Circuit breakers, retry con backoff exponencial y rate limiting saliente en Camel. |

---

## 4. Componentes del Sistema

### Componente: identity-service

#### Responsabilidades
- Registro de usuarios con validación de unicidad de email y documento.
- Coordinación del proceso KYC con el proveedor externo (a través de integration-service).
- Autenticación multifactor (TOTP, SMS, correo) y gestión de tokens de sesión.
- Gestión del ciclo de vida de la cuenta (PENDIENTE_KYC → ACTIVA → SUSPENDIDA/BLOQUEADA).
- Recuperación segura de contraseñas con token de uso único.

#### Dependencias
- `pagofacil_identity_service` (PostgreSQL — write side, propiedad exclusiva).
- integration-service (REST/mTLS — coordinación de validación KYC).
- Kafka (producer — eventos BC-01: UsuarioRegistrado, CuentaActivada, SesionIniciada, etc.).
- AWS Cognito (autenticación externa delegada).

---

### Componente: wallet-service

#### Responsabilidades
- Mantenimiento de saldo disponible y pendiente por billetera.
- Procesamiento de depósitos, retiros y transferencias con garantías ACID.
- Aplicación de límites transaccionales configurados por tenant/administrador.
- Garantía de idempotencia mediante IdempotencyKey.
- Publicación confiable de eventos de dominio vía Outbox Pattern.

#### Dependencias
- `pagofacil_wallet_service` (PostgreSQL — write side, propiedad exclusiva).
- integration-service (REST/mTLS — inicio de sagas Deposito/Retiro/Transferencia).
- Kafka (producer vía Outbox relay — eventos BC-02).

---

### Componente: fraud-service

#### Responsabilidades
- Evaluación en tiempo real de transacciones contra reglas de fraude configurables.
- Verificación AML contra listas de sanciones activas (cache local sincronizado).
- Clasificación, bloqueo y retención de transacciones sospechosas.
- Generación de alertas con severidad clasificada y preparación de datos para ROS.

#### Dependencias
- `pagofacil_fraud_service` (PostgreSQL — write side, propiedad exclusiva).
- integration-service (REST/mTLS — invocado para evaluación en saga Retiro).
- Kafka (producer vía Outbox relay — eventos BC-03; consumer de TransaccionIniciada).

---

### Componente: notification-service

#### Responsabilidades
- Envío de notificaciones transaccionales por canal configurado (email, SMS, push).
- Notificaciones de eventos de seguridad (bloqueo, cambio de contraseña).
- Alertas operacionales a administradores.

#### Dependencias
- `pagofacil_notification_service` (PostgreSQL — write side, propiedad exclusiva).
- Kafka (consumer — eventos de múltiples bounded contexts).
- Proveedores de canal (SMTP/SMS/FCM — configuración en Secrets Manager).

---

### Componente: audit-service

#### Responsabilidades
- Dashboard de búsqueda y revisión de transacciones por filtros múltiples.
- Gestión de alertas de fraude y AML: aprobación/rechazo con justificación inmutable.
- Exportación de reportes regulatorios y disparo de jobs on-demand.

#### Dependencias
- `pagofacil_readmodel` (PostgreSQL — Read Model, solo lectura).
- Kafka (consumer — consumo de eventos para operaciones en tiempo real si aplica).

---

### Componente: integration-service

#### Responsabilidades
- Centralizar toda la comunicación saliente con sistemas externos (ACL — DS-005).
- Orquestar las sagas Saga-Deposito, Saga-Retiro, Saga-Transferencia y Conciliacion mediante Apache Camel Saga EIP + Narayana LRA (DS-006).
- Recepción y validación de webhooks de confirmación de entidades financieras.
- Sincronización periódica de listas de sanciones AML.
- Traducción de modelos externos al lenguaje ubicuo interno.

#### Dependencias
- `pagofacil_integration_service` (PostgreSQL — estado de saga, outbox, propiedad exclusiva).
- Narayana LRA Coordinator (HTTP — registro y coordinación de sagas).
- Kafka (producer/consumer — eventos de saga y compensación).
- Entidades financieras externas (HTTPS + validación HMAC).
- Proveedor KYC (HTTPS).
- Listas AML (HTTPS).
- wallet-service, fraud-service, identity-service (REST/mTLS — pasos de saga y compensación).

---

### Componente: projection-service

#### Responsabilidades
- Consumir todos los eventos de dominio publicados en Kafka por los servicios operacionales.
- Proyectar y mantener el Read Model desnormalizado en `pagofacil_readmodel` (PostgreSQL).
- Es el **único escritor** del Read Model; audit-service y MS1 solo leen.
- Garantizar idempotencia en la proyección (event key + upsert).

#### Dependencias
- `pagofacil_readmodel` (PostgreSQL — Read Model, escritura exclusiva).
- Kafka (consumer multi-topic — eventos de BC-01, BC-02, BC-03, BC-06).

---

### Componente: report-extraction-service (MS1)

#### Responsabilidades
- Job batch Spark ejecutado por CronJob K8s o comando on-demand.
- Leer tablas desnormalizadas del Read Model vía JDBC (SparkJdbcSourceAdapter).
- Validar el esquema del DataFrame extraído contra `report_schema_catalog`.
- Generar archivo Parquet en S3 (`raw/`) como contrato hacia MS2.
- Publicar evento `report.extracted` a Kafka.

#### Dependencias
- `pagofacil_readmodel` (PostgreSQL — solo lectura vía JDBC).
- `pagofacil_reporting` (PostgreSQL — consulta de `report_schema_catalog`).
- S3 (escritura de Parquet en `raw/`).
- Kafka (producer — `report.extracted`).

---

### Componente: report-processing-service (MS2)

#### Responsabilidades
- Job batch Spark ejecutado por CronJob K8s al consumir `report.extracted`.
- Aplicar transformaciones por ReportType usando el patrón Factory (abierto/cerrado).
- Generar Parquet transformado en S3 (`processed/`).
- Publicar evento `report.processed` a Kafka para consumo de la capa serverless.

#### Dependencias
- S3 (lectura de Parquet `raw/`; escritura en `processed/`).
- Kafka (consumer — `report.extracted`; producer — `report.processed`).

---

### Componente: Capa Serverless Lambda + EventBridge

#### Responsabilidades
- Lambda Kafka Consumer: recibe `report.processed` y publica a EventBridge (`pagofacil-report-bus`).
- EventBridge enruta según el formato requerido a lambda-pdf, lambda-xls o lambda-csv.
- Cada lambda genera el archivo final y lo deposita en S3 `pagofacil-reports/`.

#### Dependencias
- Kafka (consumer).
- AWS EventBridge.
- S3 (escritura de reportes finales).

---

## 5. Diseño de Módulos

Cada microservicio de dominio sigue el template Maven de arquitectura hexagonal. Los módulos son equivalentes entre servicios.

### Módulos por Microservicio de Dominio

| Módulo | Responsabilidad | Límite |
|---|---|---|
| `domain` | Entidades, aggregates, value objects, interfaces de puertos | Sin dependencias de infraestructura |
| `application` | Command/Query handlers, casos de uso, lógica de orquestación local | Depende solo de `domain` |
| `infrastructure.web` | Controllers WebFlux, request/response DTOs, validadores | Adaptador primario — expone el servicio |
| `infrastructure.persistence` | Repositorios R2DBC, entidades de BD, Outbox relay | Adaptador secundario — persiste estado |
| `infrastructure.messaging` | Kafka producers, consumers, serializadores | Adaptador secundario — bus de eventos |
| `infrastructure.client` | Clientes REST a otros microservicios (via mTLS) | Adaptador secundario — comunicación inter-servicio |
| `infrastructure.config` | Configuración de Spring, Secrets Manager | Configuración transversal |

### Módulos de integration-service

| Módulo | Responsabilidad |
|---|---|
| `domain` | Entidades SagaInstance, SolicitudExterna, RegistroConciliacion |
| `application` | Casos de uso de orquestación y coordinación de ACL |
| `infrastructure.camel` | Rutas Camel por sistema externo, ACL traductores, Resilience4j |
| `infrastructure.lra` | Participantes LRA, callbacks de compensación, registro con Narayana |
| `infrastructure.persistence` | Repositorios R2DBC, Outbox relay |
| `infrastructure.messaging` | Kafka producers/consumers para saga |

### Comunicación entre Módulos

- Los módulos `domain` y `application` no importan ninguna clase de `infrastructure.*`.
- Los adapters secundarios implementan interfaces definidas en `domain` (puertos de salida).
- Los adapters primarios llaman a los casos de uso de `application` a través de interfaces de entrada.
- El acoplamiento entre servicios distintos ocurre exclusivamente a través de Kafka (asíncrono) o REST con contratos OpenAPI (síncrono).
