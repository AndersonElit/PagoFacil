# Software Design Document — Infraestructura y Gobernanza

**Proyecto:** PagoFacil — Billetera Digital | Parte del conjunto SDD técnico v1.0 (system / design / infrastructure)  
**Fecha:** 2026-06-06 | **Etapa:** Technical Design — Diseño Técnico

---

## 1. Infraestructura y Deployment

### Infraestructura Base como Código (Terraform)

La infraestructura base del proyecto se aprovisiona con:

```
.claude/scripts/base-infrastructure-builder.sh
```

Este script genera el árbol Terraform multi-ambiente (`dev` / `staging` / `prod`) con los siguientes recursos. Se ejecuta tras completar la etapa de Diseño Técnico, usando las decisiones de este documento como insumos.

**Nota sobre el ambiente `dev`:** el cluster Kubernetes en dev es **K3d** (K3s en Docker, sobre `floci-net`) con su propio registry de imágenes local. EKS solo aplica a `staging` y `prod`. El flujo CI/CD+GitOps completo (Jenkins + ArgoCD) opera sobre K3d en dev.

### Tabla de Componentes de Infraestructura

| Componente | Tecnología | Ambiente | Descripción |
|---|---|---|---|
| Frontend | Vercel (provider `vercel`) | dev/staging/prod | Despliegue de `pagofacil-web` (Next.js). Jenkins es el único disparador de despliegues. |
| Cluster Kubernetes (dev) | K3d (K3s en Docker, floci-net) | dev | Cluster local para desarrollo. Registro de imágenes interno. |
| Cluster Kubernetes (prod) | AWS EKS | staging/prod | Cluster gestionado en `us-east-1`. Autoescaling horizontal por microservicio. |
| Base de datos operacional | AWS RDS PostgreSQL 16.3 | staging/prod | Instancias por servicio, Multi-AZ en prod. En dev: PostgreSQL Docker sobre floci-net. |
| Base de datos Read Model | AWS RDS PostgreSQL 16.3 | staging/prod | Instancia `pagofacil_readmodel`. En dev: PostgreSQL Docker. |
| Bus de mensajes | Apache Kafka 3.7.0 (KRaft) | dev: Docker / staging+prod: MSK o self-managed | Topics con mTLS y ACL por bounded context. |
| Identity Provider | AWS Cognito User Pool | staging/prod | OAuth 2.0 / OIDC. En dev: Cognito local mock o pool de dev. |
| API Gateway | AWS API Gateway v2 (HTTP) | staging/prod | Validación JWT, enrutamiento. En dev: K3d Ingress. |
| Gestión de secretos | AWS Secrets Manager | staging/prod | Acceso vía IAM Role + K8s ServiceAccount. En dev: Secrets Manager dev o secrets K3d. |
| Registry de imágenes | AWS ECR | staging/prod | Una entrada por microservicio. En dev: registry K3d local. |
| IAM | AWS IAM | staging/prod | Roles con least privilege por microservicio y por lambda. |
| Almacenamiento de objetos | AWS S3 | staging/prod | Buckets: `pagofacil-parquet-raw`, `pagofacil-parquet-processed`, `pagofacil-reports`. En dev: S3 sobre floci (MinIO o Localstack). |
| Serverless | AWS Lambda + EventBridge | staging/prod | Lambda Kafka Consumer, lambda-pdf, lambda-xls, lambda-csv. En dev: emulación Localstack/SAM. |
| Coordinador de Sagas | Narayana LRA Coordinator | dev: Docker floci-net / staging+prod: pod K8s | Expuesto vía ClusterIP. `base-infrastructure-builder.sh` incluye el contenedor. |
| Simulador de sistemas externos | WireMock | dev | Simulación de entidades financieras, proveedor KYC y listas AML para pruebas de integración de rutas Camel. `base-infrastructure-builder.sh` incluye el contenedor. |
| CI/CD | Jenkins (controller EC2 + agentes pod K8s) + ArgoCD | staging/prod | Jenkins ejecuta el pipeline; ArgoCD sincroniza el estado del cluster. Jenkins termina en `bumpImageTag`. |
| IaC | Terraform ≥ 1.6.0 | todos | Módulos en `terraform/backend` y `terraform/frontend`. Estado remoto en S3 + DynamoDB lock. |

### Deployment Strategy

- **Blue/Green deployment** para servicios de dominio en staging/prod, gestionado por ArgoCD.
- **CronJob K8s** para MS1 y MS2: schedule configurable por ambiente vía `--schedule "<cron>"`. ArgoCD sincroniza el CronJob. Jenkins termina en `bumpImageTag`; no ejecuta smoke tests HTTP (los jobs no exponen endpoints).
- Los microservicios de dominio están configurados con `readinessProbe` y `livenessProbe`. Las migraciones Liquibase se ejecutan como paso previo al despliegue (`run-liquibase-migrations.sh`), no como `initContainer` — el servicio arranca con el esquema ya aplicado.

---

## 2. Observabilidad y Monitoreo

### Logging

- Logging estructurado **JSON** en todos los microservicios.
- Campo `correlationId` obligatorio en cada entrada de log — propaga la traza entre servicios.
- Sin datos PII en texto libre. Email, documento y saldo: enmascarados en logs.
- Retención mínima 5 años para logs de operaciones financieras (RN-012).
- Recolección: CloudWatch Logs Agent en los pods K8s (staging/prod). Fluentd/Loki en dev (K3d).

### Métricas

- **Prometheus** en todos los microservicios (Spring Boot Actuator + Micrometer). Exporta a Prometheus central en el cluster.
- Métricas clave por servicio: throughput de transacciones, latencia p50/p95/p99, tasa de errores, lag de Outbox relay, lag del `projection-service`.
- **CloudWatch Metrics** para RDS, Lambda, API Gateway y MSK en staging/prod.
- Dashboards Grafana por bounded context.

### Trazas Distribuidas

- **OpenTelemetry** en todos los microservicios. Exporta a Jaeger (dev) / AWS X-Ray (staging/prod).
- El `correlationId` se propaga como span attribute a través de todos los servicios, Kafka headers y logs Spark.

### Alertas y SLOs

| SLI | SLO | Alerta si |
|---|---|---|
| Latencia p95 consultas (saldo, historial) | < 500 ms | p95 > 500 ms durante 5 min |
| Latencia p95 operaciones financieras (encolado) | < 2000 ms | p95 > 2000 ms durante 5 min |
| Disponibilidad del sistema | ≥ 99.9% mensual | Uptime < 99.9% en ventana 30 días |
| Lag del projection-service | < 30 s en operación normal | Lag > 60 s durante 10 min |
| Sagas en estado STUCK (> umbral configurable) | 0 sagas STUCK en producción | Cualquier saga STUCK > 10 min |
| Tasa de errores 5xx | < 0.1% | Tasa > 0.5% durante 3 min |

### Health Checks

- Todos los microservicios exponen `/actuator/health` (Spring Boot Actuator).
- `readinessProbe`: verifica conectividad con BD y Kafka antes de recibir tráfico.
- `livenessProbe`: verifica que el proceso responde. Restart automático si falla.
- Narayana LRA expone `/lra-coordinator/` — monitoreado para sagas en estado STUCK.

---

## 3. Consideraciones No Funcionales

### Disponibilidad (SLA 99.9%)

- Multi-AZ en RDS y EKS para staging/prod. RTO < 1 hora, RPO < 15 min.
- Circuit breakers en todas las dependencias externas (Resilience4j). Degradación controlada si una entidad financiera no está disponible: los demás servicios continúan operando.
- El `integration-service` es el único punto de fallo para integraciones externas; se despliega con múltiples réplicas y autoescaling.

### Escalabilidad

- Escalamiento horizontal automático (HPA) por microservicio basado en CPU y throughput de Kafka consumer lag.
- Cada BD es independiente — el escalamiento de un servicio no impacta a otros.
- Diseño para ≥ 10x el volumen transaccional inicial sin rediseño estructural (RNF-006).
- MS1 y MS2 escalan horizontalmente en Spark (workers en K8s o EMR en prod).

### Resiliencia

- Reintentos con backoff exponencial (Resilience4j) en todas las rutas Camel hacia sistemas externos.
- Transactional Outbox garantiza que ningún evento se pierde ante fallo de Kafka.
- Idempotencia en todos los consumers Kafka y endpoints de compensación.
- Narayana LRA mantiene el estado de sagas en BD; ante fallo del orquestador, se puede reiniciar desde el paso en curso.

### Performance

- Programación reactiva non-blocking (WebFlux) en todos los microservicios de dominio.
- El Read Model PostgreSQL desnormalizado permite queries directas sin JOINs entre BDs operacionales.
- Índices definidos en el schema DDL para los accesos frecuentes de auditoría y ETL.
- Parquet como formato de contrato entre MS1 y MS2: columnar, comprimido, eficiente para Spark.

### Mantenibilidad

- Arquitectura hexagonal por servicio: el dominio no depende de infraestructura; los adapters son intercambiables.
- Liquibase standalone gestiona migraciones independientes por servicio (`db/<servicio>/changelog/`, fuera del JAR).
- Cobertura de tests ≥ 80% en módulos financieros y de seguridad (SonarQube quality gate).
- ADRs documentados en este archivo para traceabilidad de decisiones.

### Aislamiento Multitenancy

- `tenantId` como predicado obligatorio en todas las queries de escritura y lectura.
- Validación del `tenantId` del JWT contra el recurso solicitado en cada microservicio.
- Tests de aislamiento entre tenants antes del despliegue a staging/prod.

---

## 4. Decisiones Técnicas (ADR)

### ADR-001 — Database-per-Service con PostgreSQL 16.3

**Decisión:**  
Cada microservicio es propietario exclusivo de su base de datos PostgreSQL (`pagofacil_<svc_slug>`). Ningún otro servicio accede directamente a ella. La comunicación de datos entre contextos usa eventos Kafka o REST al servicio propietario. Las BDs se provisionan por `init-databases.sh`; el esquema lo aplica Liquibase standalone (`run-liquibase-migrations.sh`) como paso previo al despliegue.

**Razón:**  
Garantiza autonomía completa de datos por bounded context: evolución de esquema independiente, despliegue independiente, aislamiento de fallos de infraestructura. Consecuencia natural de DS-002 y DS-001.

**Tradeoffs:**  
Se gana autonomía e independencia de despliegue. Se sacrifica la posibilidad de JOINs directos entre contextos y se acepta consistencia eventual entre servicios.

**Alternativas consideradas:**
- Schema-per-service en un cluster PostgreSQL compartido: descartado por acoplamiento en operaciones y riesgo de degradación cruzada.
- Shared database: descartado explícitamente por DS-002.

---

### ADR-002 — CQRS con Read Model PostgreSQL Relacional (override de DS-CQRS-1)

**Decisión:**  
El Read Model CQRS se implementa en PostgreSQL 16.3 (`pagofacil_readmodel`), propiedad exclusiva del `projection-service`, con tablas desnormalizadas (`report_transactions`, `report_alerts`, `report_wallets`, `report_reconciliations`). El `projection-service` usa R2DBC reactivo para escribir. MS1 Spark lee el Read Model vía JDBC (`SparkJdbcSourceAdapter`). Se elimina el conector Spark-MongoDB.

**Razón:**  
La elección de PostgreSQL para el Read Model unifica el motor de base de datos (PostgreSQL en toda la plataforma), simplifica la operación, permite queries SQL expresivos para el dashboard de auditoría y el ETL de reportería, y elimina la complejidad operacional de MongoDB en el cluster. El Strategic Design (DS-CQRS-1) originalmente propuso MongoDB; esta decisión técnica lo reemplaza con PostgreSQL.

**Tradeoffs:**  
Se gana homogeneidad tecnológica y facilidad para queries tabulares de ETL. Se pierde la flexibilidad de documentos de MongoDB para datos semi-estructurados (aceptable dado que los datos proyectados son tablas desnormalizadas bien definidas).

**Alternativas consideradas:**
- MongoDB 7 (decisión original DS-CQRS-1): descartado para este diseño técnico por la razón expuesta.
- ElasticSearch para búsqueda en el dashboard: descartado por complejidad operacional extra innecesaria.

---

### ADR-003 — Apache Camel como ACL y Capa de Integración en `integration-service`

**Decisión:**  
Toda conectividad con sistemas externos se centraliza en `integration-service` (DS-005). Las rutas Camel actúan como ACL: reciben la solicitud del servicio de dominio en el modelo interno, traducen al protocolo/formato del sistema externo, ejecutan la llamada con reintentos (backoff exponencial) y circuit breaker (Resilience4j), y traducen la respuesta al lenguaje ubicuo. El bridge reactivo Camel↔WebFlux usa `camel-reactive-streams`; está **prohibido** el uso de `.block()`.

**Razón:**  
Centralización del gobierno de credenciales, SLAs y observabilidad de integraciones externas. Los servicios de dominio no conocen protocolos externos (DS-005).

**Tradeoffs:**  
Se gana gobierno unificado y protección del modelo de dominio. Se introduce un hop de red adicional para toda operación que requiera integración externa; `integration-service` se convierte en componente crítico que requiere alta disponibilidad.

**Alternativas consideradas:**
- Integración directa desde wallet-service o identity-service: descartado por violación de DS-005 y dispersión de credenciales.

---

### ADR-004 — Saga por Orquestación con Narayana LRA

**Decisión:**  
Las transacciones distribuidas se implementan con el patrón Saga de **orquestación**. El orquestador reside en `integration-service`, usando Apache Camel Saga EIP y Narayana LRA como coordinador (DS-006). Cada paso tiene un endpoint de compensación idempotente. Los participantes usan Transactional Outbox para publicar eventos atómicamente.

**Razón:**  
La orquestación centraliza la lógica del flujo, facilita visibilidad y diagnóstico operacional. Narayana LRA provee infraestructura probada para la gestión del ciclo de vida.

**Tradeoffs:**  
Se gana visibilidad centralizada del estado de cada saga y facilidad de auditoría. Se sacrifica descentralización: `integration-service` concentra lógica de coordinación y se acopla con todos los participantes.

**Alternativas consideradas:**
- Saga por coreografía: descartado por dificultad de rastrear el estado global y diagnóstico operacional.
- Temporal.io como coordinador: descartado por no estar en el ADC.

---

### ADR-005 — Transactional Outbox para Publicación Confiable de Eventos

**Decisión:**  
Cada microservicio que publica eventos de dominio persiste el evento en su tabla `outbox` dentro de la misma transacción PostgreSQL antes de confirmar el cambio de estado. Un proceso de relay por polling lee la tabla y publica a Kafka con garantía at-least-once. Los consumers implementan idempotencia (tabla `processed_message`).

**Razón:**  
Elimina el problema del doble commit entre BD y Kafka. Garantiza que ningún evento se pierda ante fallo del proceso Kafka (DS-004).

**Tradeoffs:**  
Latencia adicional mínima del relay. Complejidad manejable con el template Maven existente.

**Alternativas consideradas:**
- Transacciones XA (two-phase commit): descartado por complejidad operacional y menor soporte en JDBC reactivo.
- CDC (Debezium): válido a futuro; el Outbox por polling es suficiente para la fase inicial.

---

### ADR-006 — ETL Spark Batch en Dos Servicios (MS1 + MS2) como CronJob K8s

**Decisión:**  
El subsistema de reportería implementa un pipeline ETL de dos etapas con jobs Spark batch ejecutados como **CronJob Kubernetes** (DS-007). MS1 extrae del Read Model vía JDBC y genera Parquet `raw/`. MS2 consume el Parquet y aplica transformaciones por ReportType usando el patrón Factory (Open/Closed). Jenkins termina en `bumpImageTag`; no hay smoke tests HTTP.

**Razón:**  
Los jobs batch no son servicios persistentes; no exponen endpoints HTTP, por lo que no hay superficie de ataque adicional. La separación en dos etapas con Parquet como contrato permite reintento independiente ante fallos y evolución del esquema sin afectar la extracción.

**Tradeoffs:**  
Latencia batch en la disponibilidad de reportes (no tiempo real). Se simplifica la operación: sin gestión de estado de servicio persistente.

**Alternativas consideradas:**
- Streaming con Spark Structured Streaming: descartado por mayor complejidad operacional para reportes que no requieren tiempo real.
- Un único job monolítico: descartado por acoplamiento entre extracción y transformación.

---

### ADR-007 — Capa Serverless Lambda + EventBridge para Generación de Formatos

**Decisión:**  
Tras el procesamiento Spark, un Lambda Kafka Consumer publica a EventBridge (`pagofacil-report-bus`). EventBridge enruta mediante rules independientes a `lambda-pdf`, `lambda-xls` y `lambda-csv`. Cada lambda genera el archivo final en S3. WireMock simula los sistemas externos para pruebas de integración en dev (DS-008).

**Razón:**  
La generación de formatos es puntual e impredecible en frecuencia; el modelo serverless es óptimo. EventBridge permite agregar nuevos formatos sin modificar el pipeline ETL.

**Tradeoffs:**  
Límites de memoria/tiempo de Lambda a validar contra tamaño máximo de reportes. Cold start posible en reportes on-demand con baja frecuencia.

**Alternativas consideradas:**
- Microservicio dedicado de formateo siempre activo: descartado por costo operacional innecesario para carga puntual.

---

### ADR-008 — Arquitectura Hexagonal por Microservicio con Template Maven

**Decisión:**  
Cada microservicio de dominio sigue el template `maven_hexagonal_scaffold.py`. La capa de dominio no importa clases de infraestructura. Los adapters primarios (controllers, consumers) llaman a los casos de uso de aplicación. Los adapters secundarios (repositorios, clientes REST, Kafka producers) implementan interfaces definidas en el dominio.

**Razón:**  
Permite evolucionar la implementación de infraestructura sin modificar el dominio. Facilita tests unitarios del dominio sin dependencias externas.

**Tradeoffs:**  
Mayor número de clases e interfaces que un enfoque en capas planas. Inversión inicial en setup por servicio amortizada con el template de scaffolding.

**Alternativas consideradas:**
- Arquitectura en capas planas: descartado por restricción ADC y menor mantenibilidad a largo plazo.

---

## 5. Riesgos Técnicos

| ID | Riesgo | Impacto | Probabilidad | Mitigación |
|---|---|---|---|---|
| RT-001 | Contratos y protocolos con entidades financieras no firmados. Las rutas Camel podrían requerir retrabajo significativo al conocer el protocolo real. | Alto | Alta | Priorizar la firma de contratos antes del sprint de `integration-service`. Usar WireMock para desarrollo paralelo sin bloquear al proveedor. |
| RT-002 | Complejidad operacional de Narayana LRA. Fallos del coordinador pueden dejar sagas en estado STUCK, requiriendo intervención manual. | Alto | Media | Monitorear sagas STUCK con alerta automática (> 10 min). Documentar runbooks. Pruebas de caos antes del lanzamiento a producción. |
| RT-003 | Lag del projection-service en ventanas de alta carga. El Read Model puede mostrar estado desfasado afectando reportes regulatorios. | Medio | Media | Lag del projection-service como métrica de negocio con alerta. SLA interno de lag máximo ≤ 30 s. Capacidad de reprocessar desde offset Kafka ante fallo. |
| RT-004 | Volúmenes de datos de auditoría a 5+ años en `pagofacil_readmodel`. PostgreSQL puede requerir estrategia de archivado no planificada. | Medio | Baja | Definir estrategia de archivado (particionamiento por fecha + cold storage S3) antes de comprometer el esquema del Read Model. |
| RT-005 | Límites de memoria/tiempo de Lambda insuficientes para reportes de gran volumen. | Medio | Media | Validar tamaño máximo de Parquet `processed/` contra límites de Lambda (10 GB /tmp, 15 min). Usar S3 Byte-Range reads si el archivo excede la memoria Lambda. |
| RT-006 | PCI-DSS no confirmado por compliance antes del diseño técnico. Puede requerir controles adicionales (tokenización, logging específico). | Alto | Media | Oficial de compliance debe emitir dictamen antes del inicio del desarrollo de módulos de pago. |
| RT-007 | Proveedor KYC no seleccionado. El flujo de onboarding en `integration-service` queda bloqueado hasta definir el protocolo. | Alto | Alta | WireMock simula el proveedor KYC en dev. Priorizar la selección antes del sprint de onboarding. |
| RT-008 | Cold start de Lambda afecta latencia de reportes on-demand con baja frecuencia. | Bajo | Media | Provisioned Concurrency para las lambdas de formato si la latencia on-demand es un requisito. |

---

## 6. Recomendación y Próximos Pasos

### Estado del Diseño Técnico

El diseño técnico está **completo** para iniciar la implementación. Los tres documentos SDD, la especificación OpenAPI, el schema DDL y los diagramas C4 proveen la base técnica suficiente para desarrollar todos los bounded contexts y el subsistema de reportería.

### Preparación para Implementación

El sistema está listo para implementación bajo las siguientes condiciones:

| Condición | Estado |
|---|---|
| Stack tecnológico definido (ADC + ADRs) | Listo |
| Contratos de API (OpenAPI 3.0) | Listo |
| Schema de base de datos (DDL por servicio) | Listo |
| Flujos de saga con compensaciones documentados | Listo |
| Arquitectura hexagonal con template Maven | Listo |
| Infraestructura Terraform (script disponible) | Pendiente de ejecución |
| Contratos con entidades financieras | **Bloqueador crítico** |
| Selección del proveedor KYC | **Bloqueador crítico** |
| Dictamen PCI-DSS y marco KYC/AML de compliance | **Bloqueador crítico** |

### Aprovisionamiento de Infraestructura Base

El primer paso operativo antes de iniciar el desarrollo es provisionar la infraestructura base ejecutando:

```bash
.claude/scripts/base-infrastructure-builder.sh
```

Usando las decisiones de infraestructura definidas en este documento como insumos:
- Prefijo de BDs PostgreSQL: `pagofacil`
- Región AWS: `us-east-1`
- Ambiente inicial: `dev` (K3d + floci-net)
- Incluir: Narayana LRA Coordinator, WireMock (simulador sistemas externos), Kafka, PostgreSQL (por servicio), S3 (floci/MinIO), ECR local.

### Áreas que Requieren Validación Adicional

1. **Protocolo de integración con entidades financieras:** firma de mensaje (HMAC vs certificado), formato de webhook, estructura de la solicitud de fondeo. Definir antes del sprint de `integration-service`.
2. **Marco KYC/AML y PCI-DSS:** el oficial de compliance debe confirmar los controles adicionales requeridos antes de implementar los módulos de Identity y Fraud.
3. **Dimensionamiento de infraestructura:** pruebas de carga con volúmenes estimados antes del lanzamiento a staging.
4. **Estrategia de archivado del Read Model:** definir particionamiento y cold storage antes de comprometer el schema de `pagofacil_readmodel` para grandes volúmenes históricos.
5. **Proveedor KYC:** selección y definición del protocolo de integración antes del sprint de onboarding.

### Siguiente Etapa del SDLC

**Desarrollo / Implementación**

Orden recomendado de sprints:
1. Infraestructura base (Terraform + K3d + Kafka + PostgreSQL dev).
2. identity-service + wallet-service (núcleo financiero).
3. fraud-service + integration-service (con WireMock para sistemas externos).
4. projection-service + audit-service (CQRS Read Model).
5. notification-service.
6. report-extraction-service (MS1) + report-processing-service (MS2).
7. Capa serverless Lambda + EventBridge.
8. Frontend (pagofacil-web).
