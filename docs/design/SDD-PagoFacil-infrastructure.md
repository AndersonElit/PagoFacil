# Software Design Document — Infraestructura y Gobernanza

**Proyecto:** PagoFacil — Billetera Digital
**Conjunto SDD técnico:** Este documento forma parte del SDD Técnico junto con `SDD-PagoFacil-system.md` y `SDD-PagoFacil-design.md`.
**Versión:** 1.0
**Fecha:** 2026-06-08

---

## 1. Infraestructura y Deployment

### Modelo de Ambientes

| Ambiente | Kubernetes | Base de datos | Registry de imágenes | Kafka |
|---|---|---|---|---|
| `dev` | K3s nativo en VPS Ubuntu 26.04 LTS (sin Docker wrapper) | PostgreSQL 16 + MongoDB 7 como servicios systemd nativos en VPS (sin RDS) | Gitea Package Registry (`VPS_IP:3000/<org>`) | Kafka KRaft en K3s |
| `staging` | EKS (AWS) | RDS PostgreSQL 16 Multi-AZ | Amazon ECR | MSK |
| `prod` | EKS (AWS) | RDS PostgreSQL 16 Multi-AZ | Amazon ECR | MSK |

> En el ambiente `dev`, PostgreSQL 16 y MongoDB 7 corren como servicios **systemd nativos** en el VPS. EKS, RDS y ECR aplican **exclusivamente** a `staging` y `prod`.

### Infraestructura Base como Código (Terraform)

La infraestructura base se aprovisiona con el script:

```
.claude/scripts/base-infrastructure-builder.sh
```

Este script genera el árbol Terraform multi-ambiente (`dev`/`staging`/`prod`) a partir de las decisiones de este documento como insumos. Se ejecuta tras completar el diseño técnico.

| Componente de diseño | Recurso generado por el script | Ambiente |
|---|---|---|
| Kubernetes cluster | K3s nativo en VPS (systemd) | dev |
| Kubernetes cluster | EKS (AWS) | staging, prod |
| PostgreSQL 16 (write models, read model, reporting) | Servicio systemd `postgresql` en VPS | dev |
| PostgreSQL 16 (write models, read model, reporting) | RDS PostgreSQL 16 Multi-AZ | staging, prod |
| MongoDB 7 (audit-service) | Servicio systemd `mongod` en VPS | dev |
| MongoDB 7 (audit-service) | MongoDB Atlas o DocumentDB (AWS) | staging, prod |
| Kafka 3 KRaft | Kafka KRaft en K3s (VPS) | dev |
| Kafka 3 KRaft | MSK (AWS Managed Streaming) | staging, prod |
| Registry de imágenes Docker | Gitea Package Registry OCI (`VPS_IP:3000/<org>`) | dev |
| Registry de imágenes Docker | Amazon ECR | staging, prod |
| Autenticación / Identity Provider | AWS Cognito User Pool | todos |
| API Gateway | AWS API Gateway v2 | todos |
| Gestión de secretos | AWS Secrets Manager | todos |
| Almacenamiento Parquet | floci (S3-compatible en VPS) | dev |
| Almacenamiento Parquet | Amazon S3 | staging, prod |
| Serverless PDF/XLS/CSV | Lambda local (Localstack o equivalente) | dev |
| Serverless PDF/XLS/CSV | AWS Lambda + EventBridge | staging, prod |
| Coordinador LRA | `lra-coordinator` systemd en VPS (puerto 50000) | dev |
| Coordinador LRA | Deployment K8s (Narayana LRA) | staging, prod |
| Pruebas de integración Camel | WireMock systemd en VPS (puerto 9999) | dev |

> **Narayana LRA Coordinator** y **WireMock** son aprovisionados por `vps-setup.sh services`. El script `.claude/scripts/base-infrastructure-builder.sh` los referencia como servicios esperados en dev.

### Deployment Pipeline

| Etapa | Herramienta | Descripción |
|---|---|---|
| Build y test | Jenkins | Pipeline por microservicio; genera fat JAR / imagen Docker |
| Publicación de imagen | Jenkins → Gitea Package Registry (dev) / ECR (staging/prod) | `bumpImageTag` como paso final para microservicios batch (MS1/MS2) |
| Migración de esquema | Liquibase standalone (`run-liquibase-migrations.sh --gitea-clone`) | Paso previo al despliegue; changelogs en `pagofacil-migrations` en Gitea |
| Despliegue | ArgoCD | Sincroniza manifiestos K8s desde el repositorio Git; GitOps |
| Microservicios batch | K8s CronJob | MS1 y MS2 desplegados como CronJob; schedule configurable por ambiente; ArgoCD sincroniza el CronJob; Jenkins termina en `bumpImageTag` (sin smoke tests HTTP) |

### Networking

| Componente | Descripción |
|---|---|
| Ingress (dev) | Traefik (K3s nativo) con TLS |
| Ingress (staging/prod) | AWS ALB + Ingress Controller |
| TLS | Certificados Let's Encrypt (dev) / ACM (staging/prod); TLS 1.2+ obligatorio |
| Service Mesh | TLS mutuo entre microservicios via Kubernetes Service y Secrets Manager |
| Segmentación de red | Namespaces K8s por ambiente; Network Policies para aislar BDs de dominio |

---

## 2. Observabilidad y Monitoreo

### Stack de Observabilidad

| Categoría | Herramienta | Descripción |
|---|---|---|
| Trazas distribuidas | OpenTelemetry + Jaeger | Instrumentación automática; propagación de `correlationId` y `spanId` en todos los servicios |
| Métricas | Prometheus + Grafana | Métricas técnicas (latencia, throughput, error rate) y de negocio (operaciones por tipo, alertas generadas) |
| Logs | Fluent Bit → Elasticsearch / OpenSearch | Logs JSON estructurado; sin PII en texto plano; agregados por `correlationId` |
| Health checks | Spring Boot Actuator `/health` | Liveness y readiness probes en todos los microservicios; Kubernetes los usa para HPA y restart automático |
| Alertas | Alertmanager (Prometheus) | Alertas sobre SLOs, error rate > umbral, HPA scaling, fallo de jobs batch ETL |

### SLIs / SLOs

| SLI | SLO | Componente |
|---|---|---|
| Latencia p95 — consultas de lectura | < 500 ms | wallet-service, identity-service, fraud-compliance-service |
| Latencia p95 — operaciones financieras | < 2 s end-to-end (saga completa) | integration-service + participantes |
| Disponibilidad | 99.9% mensual (< 44 min downtime/mes) | Componentes críticos: identity, wallet, integration |
| Throughput nominal | 1,000 req/s | API Gateway + microservicios de dominio |
| Lag del read model | < 30 s en condiciones nominales | projection-service |
| Tiempo de ejecución de reporte (MS1+MS2) | < 10 min para volúmenes nominales | report-extraction-service, report-processing-service |

### Trazabilidad de Sagas

El `correlationId` (= `sagaId`) se propaga en todos los headers HTTP, eventos Kafka y trazas OpenTelemetry durante el ciclo de vida de una saga. Los dashboards de Jaeger y Grafana permiten reconstruir el flujo completo de una saga por `correlationId`.

---

## 3. Consideraciones No Funcionales

### Escalabilidad

- **HPA (Horizontal Pod Autoscaler):** Todos los microservicios críticos (`identity-service`, `wallet-service`, `integration-service`, `projection-service`) tienen HPA configurado en Kubernetes. El diseño soporta 10x el volumen transaccional base sin rediseño (RNF-006).
- **integration-service:** Diseñado sin estado de sesión en las rutas Camel para permitir escalabilidad horizontal libre. El estado de las sagas reside exclusivamente en `saga_instance` y es coordinado por Narayana LRA.
- **Kafka:** Particionamiento por `tenant_id` en topics de alta carga para distribución uniforme entre consumidores.

### Disponibilidad

- SLA de 99.9% mensual (RNF-002). Componentes críticos en modo activo-activo (múltiples réplicas en K8s).
- Circuit breaker Resilience4j en todas las rutas Camel del `integration-service` para aíslar fallos de sistemas externos.
- PostgreSQL en modo Multi-AZ en staging/prod (RDS); failover automático ante fallo del nodo primario.
- RTO < 1 hora; RPO < 15 minutos (RNF-008).

### Resiliencia

- **Transactional Outbox:** Garantía de publicación de eventos Kafka incluso ante fallo transitorio del bus. El relay por polling publica eventos pendientes tras recuperación.
- **Idempotencia:** `Idempotency-Key` en APIs + tabla `processed_message` en cada participante de saga. Reintentos seguros sin duplicación de efectos.
- **Narayana LRA:** Gestiona la recuperación del estado de sagas tras fallo del orquestador. Las compensaciones se completan automáticamente al recuperarse.
- **Retry + Backoff:** Todas las rutas Camel con sistemas externos tienen política de retry exponencial configurable.

### Performance

- Stack reactivo (WebFlux + R2DBC) en todos los microservicios de dominio: sin bloqueo de threads bajo carga concurrente.
- Read model PostgreSQL desnormalizado optimizado para queries de extracción sin JOINs cross-BD.
- Índices en todas las columnas de filtro frecuente (tenant_id, user_id, correlationId, status, created_at).
- MS1 y MS2 son jobs batch; la latencia de reportería es inherente al modelo batch y está fuera del SLO de latencia interactiva.

### Mantenibilidad

- Cada microservicio es independientemente desplegable, actualizable y escalable (RNF-012).
- Contratos de API versionados (`/v1`); cambios breaking requieren nueva versión de path.
- Changelogs Liquibase en repositorio dedicado (`pagofacil-migrations`); evolución de esquema independiente por servicio.
- Pipeline ETL extensible: añadir un nuevo `ReportType` solo requiere una nueva implementación del Factory en MS2 (patrón Abierto/Cerrado).

### Seguridad

- Zero Trust: ningún componente interno es confiable por defecto. TLS 1.2+ en toda comunicación interna y externa.
- Secretos gestionados exclusivamente en AWS Secrets Manager.
- Multitenancy: `tenant_id` propagado desde claims JWT y validado en cada operación y query.
- Auditoría inmutable: trazas append-only en MongoDB; sin interfaz de modificación.

---

## 4. Decisiones Técnicas (ADR)

## ADR-001 — Database-per-Service con Liquibase Standalone

**Decisión:**
Cada microservicio posee y gestiona su propia base de datos aislada, provisionada por `init-databases.sh` con la convención `pagofacil_<servicio_slug>`. El esquema inicial se aplica con **Liquibase standalone** (`run-liquibase-migrations.sh --gitea-clone`) como paso previo al despliegue; los changelogs residen en el repositorio `pagofacil-migrations` en Gitea del VPS. Ningún otro servicio accede directamente a la BD de otro contexto; la comunicación cross-servicio usa eventos Kafka o REST al servicio propietario.

**Razón:**
Autonomía de datos: cada servicio evoluciona su esquema de forma independiente. Flyway fue descartado por incompatibilidad con Spring Boot WebFlux + R2DBC (requiere JDBC bloqueante).

**Tradeoffs:**
- Ganancia: autonomía de despliegue; fallos de BD aislados; independencia de esquema.
- Costo aceptado: ausencia de JOINs entre BDs de diferentes servicios; consistencia eventual cross-service; mayor complejidad en queries analíticos (resuelto por el read model CQRS).

**Alternativas consideradas:**
- BD compartida: descartada por acoplamiento fuerte entre servicios.
- Flyway: descartado por incompatibilidad con R2DBC reactivo.

---

## ADR-002 — Read Model PostgreSQL en lugar de MongoDB (Override)

**Decisión:**
El read model CQRS `pagofacil_readmodel` se implementa en **PostgreSQL 16** con tablas desnormalizadas, reemplazando la decisión inicial de MongoDB del Strategic Design v0.

**Razón:**
PostgreSQL permite el uso directo de `SparkJdbcSourceAdapter` en MS1 sin adaptadores adicionales (`mongo-spark-connector`). Queries SQL expresivos sobre tablas desnormalizadas son verificables y performantes. Simplificación operacional al mantener un único motor relacional para write y read model.

**Tradeoffs:**
- Ganancia: compatibilidad nativa con Spark JDBC; queries SQL expresivos; un solo motor relacional.
- Costo aceptado: menor flexibilidad de esquema para estructuras semiestructuradas; migraciones explícitas del read model con Liquibase.

**Alternativas consideradas:**
- MongoDB como read model: descartado por necesidad de `mongo-spark-connector` y menor expresividad de queries para extracción tabular.

---

## ADR-003 — Apache Camel como Capa de Integración en `integration-service`

**Decisión:**
Toda la conectividad con sistemas externos se centraliza en `integration-service`, implementado con Apache Camel 4 + Spring Boot. El bridge reactivo usa `camel-reactive-streams`; el uso de `.block()` está **prohibido**. Resilience4j gestiona circuit breaker y retry por ruta de integración. Las credenciales de cada sistema externo se gestionan en AWS Secrets Manager con ACL por sistema (ninguna ruta accede a credenciales ajenas).

**Razón:**
Gobierno centralizado de credenciales y SLAs; dominio limpio sin acoplamientos externos en los servicios de negocio; un único punto de cambio ante reemplazo de proveedor externo (DS-004).

**Tradeoffs:**
- Ganancia: dominio limpio; gobierno central; ACL bien definido; testabilidad con WireMock.
- Costo aceptado: `integration-service` como componente crítico de alta disponibilidad; hop de red adicional para todas las operaciones que involucran sistemas externos.

**Alternativas consideradas:**
- Integración directa en cada servicio de dominio: descartada por duplicación de lógica de retry/circuit-breaker y dispersión de credenciales.

---

## ADR-004 — Orquestación de Saga con Narayana LRA y Camel Saga EIP

**Decisión:**
Las tres sagas financieras (depósito, transferencia, retiro) se implementan mediante **Camel Saga EIP + coordinador Narayana LRA**. El orquestador reside exclusivamente en `integration-service`. Las compensaciones se invocan mediante endpoints REST idempotentes (`POST /{recurso}/{id}/compensar`) en cada servicio participante. La recuperación de sagas interrupted es responsabilidad de Narayana LRA.

**Razón:**
Visibilidad centralizada del estado de cada saga; lógica de compensación concentrada; debugging simplificado. Narayana LRA es compatible con el stack Spring Boot reactivo y disponible como servicio systemd en dev (DS-005).

**Tradeoffs:**
- Ganancia: visibilidad completa; compensación centralizada; debugging simplificado.
- Costo aceptado: acoplamiento del orquestador con los participantes; dependencia de disponibilidad del coordinador LRA.

**Alternativas consideradas:**
- Coreografía pura: descartada por dificultad de rastrear el estado global de una saga y gestionar compensaciones encadenadas.
- Orquestador dedicado (Temporal, Conductor): descartados por no estar en el stack mandatorio del ADC.

---

## ADR-005 — Transactional Outbox para Publicación Confiable de Eventos Kafka

**Decisión:**
Cada microservicio participante de saga publica eventos de dominio de forma atómica con su cambio de BD mediante el patrón **Transactional Outbox**. Una tabla `outbox` por servicio almacena el evento en la misma transacción local. Un relay por polling (en dev) o CDC/Debezium (en staging/prod) publica los eventos pendientes a Kafka. Los consumidores de eventos usan la tabla `processed_message` para garantía de idempotencia.

**Razón:**
Elimina el problema de la dualidad write/publish: el evento se publica si y solo si la transacción local se confirma, garantizando consistencia entre el estado de la BD y los eventos publicados.

**Tradeoffs:**
- Ganancia: consistencia garantizada entre BD y Kafka; reintentos seguros sin duplicación.
- Costo aceptado: latencia adicional mínima por el relay de polling; complejidad de la tabla outbox por servicio.

**Alternativas consideradas:**
- Publicación directa a Kafka en la misma transacción de negocio: descartada por riesgo de inconsistencia si Kafka falla después de la confirmación en BD.
- Dual write sin outbox: descartado por riesgo de mensajes perdidos o duplicados.

---

## ADR-006 — CQRS con Projection Service como Único Escritor del Read Model

**Decisión:**
El `projection-service` es el único microservicio con permiso de escritura sobre `pagofacil_readmodel`. Consume eventos de dominio de todos los bounded contexts desde Kafka y construye tablas PostgreSQL desnormalizadas. MS1 tiene permiso de **solo lectura** sobre `pagofacil_readmodel`. Ningún otro servicio de dominio tiene acceso a esta BD.

**Razón:**
Separación de responsabilidades entre producción de eventos y proyección de estado. El read model puede reconstruirse completamente reprocesando el historial de eventos de Kafka (DS-CQRS-2).

**Tradeoffs:**
- Ganancia: read model optimizado para queries SQL sin JOINs cross-service; alto rendimiento en consultas.
- Costo aceptado: consistencia eventual (lag proporcional al throughput de Kafka y velocidad del projection-service).

**Alternativas consideradas:**
- Lectura directa de BDs operacionales desde MS1: descartada por violación de Database-per-Service y acoplamiento al modelo interno de cada servicio.

---

## ADR-007 — ETL Batch en Dos Servicios Kubernetes CronJob (MS1 y MS2)

**Decisión:**
MS1 (report-extraction-service) y MS2 (report-processing-service) se despliegan como **Kubernetes CronJob**, no como Deployments. Su schedule es configurable por ambiente (`--schedule "<cron>"`). ArgoCD sincroniza el CronJob desde el repositorio Git. Jenkins termina en `bumpImageTag` (sin smoke tests HTTP, ya que los jobs no exponen endpoints). El contrato entre etapas es el archivo Parquet almacenado en S3.

**Razón:**
Jobs batch sin estado HTTP; Parquet como contrato tipado e inmutable entre etapas; separación de responsabilidades entre extracción/validación (MS1) y transformación/enriquecimiento (MS2); compatibilidad nativa con SparkJdbcSourceAdapter (DS-006).

**Tradeoffs:**
- Ganancia: simplicidad operacional; Parquet como contrato tipado reutilizable; independencia de cada etapa.
- Costo aceptado: latencia inherente al modelo batch; reportes no en tiempo real.

**Alternativas consideradas:**
- Spark Streaming / Flink: descartados por complejidad operacional innecesaria para reportes regulatorios periódicos.
- MS1 y MS2 en un único job: descartado para preservar independencia y el patrón de extensión Factory.

---

## ADR-008 — Capa Serverless (Lambda + EventBridge) para Generación de Formatos

**Decisión:**
La generación de formatos de salida (PDF, XLS, CSV) se implementa con **AWS Lambda (Python 3.12) + EventBridge**. Un Kafka Consumer Lambda recibe `report.processed`; EventBridge enruta a la lambda del formato solicitado. En dev se usa Localstack o equivalente floci.

**Razón:**
Costo optimizado para carga esporádica (pay-per-use); desacople por EventBridge para añadir nuevos formatos sin modificar el pipeline ETL; cada lambda es independiente (DS-007).

**Tradeoffs:**
- Ganancia: costo optimizado; extensibilidad sin impacto en pipeline; lambdas independientes.
- Costo aceptado: cold start en primera invocación; dependencia de AWS Lambda y EventBridge como servicios gestionados.

**Alternativas consideradas:**
- Servicio persistente (Spring Boot) para generación de formatos: descartado por costo de infraestructura para carga esporádica.

---

## ADR-009 — CQRS con Read Model PostgreSQL Relacional (BC-07 Reporting)

**Decisión:**
El `projection-service` proyecta eventos de dominio (Kafka) sobre tablas SQL desnormalizadas en `pagofacil_readmodel` (PostgreSQL). MS1 Spark lee con JDBC (`SparkJdbcSourceAdapter`, `--source jdbc`). El read model es **read-only para todos los servicios excepto el projection-service**.

**Razón:**
Consistencia eventual aceptable para reportes regulatorios periódicos; queries SQL expresivos sin JOINs entre BDs operacionales; compatibilidad nativa con Spark JDBC (DS-CQRS-3, ADR-002).

**Tradeoffs:**
- Ganancia: queries SQL expresivos; consistencia eventual adecuada para reportería batch; no requiere adaptadores adicionales.
- Costo aceptado: el read model puede reflejar estado con lag proporcional al procesamiento del projection-service.

**Alternativas consideradas:**
- Acceso directo a BDs operacionales desde MS1: descartado por violación de Database-per-Service.

---

## 5. Riesgos Técnicos

| ID | Riesgo | Impacto | Probabilidad | Mitigación |
|---|---|---|---|---|
| RT-001 | `integration-service` se convierte en cuello de botella al centralizar toda la conectividad externa y la orquestación de sagas | Alto | Media | HPA en K8s; rutas Camel sin estado de sesión; circuit breaker Resilience4j por ruta; load testing en staging |
| RT-002 | Lag del read model impacta la exactitud de reportes solicitados inmediatamente tras un pico de transacciones | Medio | Media | Lag inherente al CQRS; documentar SLA de consistencia; aceptable para reportes regulatorios periódicos |
| RT-003 | Fallo del coordinador Narayana LRA durante una saga deja el sistema en estado inconsistente | Alto | Baja | Narayana LRA gestiona recuperación de sagas interrupted; drill periódico de escenarios de fallo en staging; pruebas de caos |
| RT-004 | Propagación incorrecta del `tenant_id` en algún microservicio genera cross-tenant data leak | Alto | Media | Lint / test automático en CI que verifica la propagación del `tenant_id` en cada endpoint y evento; validación en API Gateway |
| RT-005 | Volúmenes transaccionales reales superan el dimensionamiento inicial de HPA y particiones Kafka | Medio | Media | Los volúmenes baseline están pendientes de definición (R-005 del Strategic Design); bloqueante para configuración final de HPA |
| RT-006 | Incompatibilidad de versiones entre Narayana LRA, Camel 4 y Spring Boot 3 en el stack reactivo | Alto | Baja | Validar la combinación de versiones en el entorno dev antes de iniciar la implementación de sagas; spike técnico recomendado |
| RT-007 | SLAs y contratos con proveedor KYC/AML no definidos antes del módulo de compliance | Alto | Alta | Dependencia bloqueante heredada del Strategic Design (R-004, R-006); escalar al Oficial de Cumplimiento y al Project Manager |
| RT-008 | Jobs Spark MS1/MS2 exceden el tiempo de ejecución esperado ante volúmenes reales sin tuning de Spark | Medio | Media | Benchmark de MS1/MS2 con datos representativos en staging antes de go-live; configurar `spark.executor.memory` y paralelismo por ambiente |

---

## 6. Recomendación y Próximos Pasos

### Estado del Diseño Técnico

El diseño técnico de PagoFacil está **completo y listo para iniciar la etapa de Implementación**. Los tres documentos del SDD técnico cubren:

- Arquitectura de microservicios por bounded context con stack tecnológico justificado.
- Contratos de API (OpenAPI 3.0) y modelo de datos (DDL PostgreSQL + MongoDB).
- Flujos técnicos de sagas, integración Camel y pipeline ETL.
- Decisiones técnicas documentadas (ADR-001 a ADR-009) con tradeoffs explícitos.
- Infraestructura multi-ambiente con base como código (Terraform vía `base-infrastructure-builder.sh`).

### Aprovisionamiento de Infraestructura Base

Como primer paso operativo de la etapa de Implementación, ejecutar el script de Terraform:

```bash
.claude/scripts/base-infrastructure-builder.sh
```

Este script recibe como insumos las decisiones de infraestructura documentadas en este archivo (`infrastructure.md`) y genera el árbol Terraform para los ambientes `dev`, `staging` y `prod`.

### Áreas que Requieren Validación Adicional

| Área | Estado | Responsable |
|---|---|---|
| Normativa KYC/AML de la jurisdicción de operación | Pendiente — bloqueante para módulo de compliance | Oficial de Cumplimiento |
| SLAs y contratos con proveedor KYC | Pendiente — bloqueante para módulo de onboarding | Project Manager + Legal |
| Volúmenes transaccionales baseline | Pendiente — bloqueante para configuración de HPA y load testing | Sponsor + Oficial de Cumplimiento |
| Aplicabilidad GDPR / SOC 2 / ISO 27001 | Pendiente — necesario antes del diseño de privacidad y datos | Oficial de Cumplimiento + Legal |
| Spike técnico Narayana LRA + Camel 4 + Spring Boot 3 WebFlux | Recomendado antes de implementar sagas | Tech Lead |
| Benchmark MS1/MS2 Spark con datos representativos | Recomendado en staging antes de go-live | Equipo de datos |

### Dependencias y Bloqueadores

- La implementación del módulo de compliance (fraud-compliance-service, flujos AML, ROS/SAR) **no debe iniciarse** hasta que la normativa KYC/AML y los contratos con el proveedor KYC estén documentados.
- La configuración final de HPA y particiones Kafka **no puede completarse** hasta tener los volúmenes transaccionales baseline definidos.
- Los contratos técnicos con las entidades financieras (API de depósito/retiro) son necesarios para completar el diseño detallado de las rutas Camel en `integration-service`.

### Próxima Etapa

**Desarrollo / Implementación** — La siguiente etapa del SDLC inicia con:

1. Aprovisionamiento de infraestructura base via `.claude/scripts/base-infrastructure-builder.sh`.
2. Generación de scaffolding por microservicio (`maven_hexagonal_scaffold.py`, `scala_hexagonal_scaffold.py`, `integration_service_scaffold.py`, `nextjs_feature_scaffold.py`).
3. Aplicación de migraciones de esquema inicial via `run-liquibase-migrations.sh --gitea-clone`.
4. Implementación por bounded context en el orden: Identity → Wallet → Integration (saga) → Fraud & Compliance → Notification → Audit → Reporting (projection-service + MS1 + MS2 + Lambda).
