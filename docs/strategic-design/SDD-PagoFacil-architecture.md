# Strategic Design Document — Estrategia Arquitectónica

**Proyecto:** PagoFacil — Billetera Digital
**Conjunto SDD:** Este documento forma parte del Strategic Design Document junto con `SDD-PagoFacil-domain.md` y `SDD-PagoFacil-security.md`.
**Versión:** 1.0
**Fecha:** 2026-06-08

---

## 1. Drivers Arquitectónicos

### Atributos de Calidad Prioritarios

| Atributo | Prioridad | Justificación |
|----------|-----------|---------------|
| Disponibilidad | Alta | SLA de 99.9% mensual (< 44 min downtime/mes); componentes críticos con redundancia activa-activa (RNF-002) |
| Seguridad | Alta | Sistema financiero con datos PII, credenciales y transacciones; normativas KYC/AML obligatorias; MFA, OAuth 2.0, cifrado AES-256, TLS 1.2+ (RNF-003, RNF-004, RNF-005) |
| Consistencia Financiera | Alta | Operaciones de saldo con garantías ACID en el write model; consistencia eventual con compensación (Saga) en operaciones distribuidas; saldo nunca negativo (RNF-007, RN-002) |
| Rendimiento | Alta | p95 < 500 ms para consultas; p95 < 2 s para operaciones financieras; throughput nominal de 1,000 req/s (RNF-001, ADC §5) |
| Escalabilidad | Alta | HPA Kubernetes para escalar microservicios críticos; el diseño soporta 10x el volumen transaccional base sin rediseño (RNF-006) |
| Recuperabilidad | Alta | RTO < 1 hora; RPO < 15 minutos ante fallo de componente crítico (RNF-008) |
| Cumplimiento Normativo | Alta | KYC/AML; protección de datos personales (GDPR o equivalente local); períodos de retención de datos financieros; trazabilidad regulatoria (RNF-010, RN-007) |
| Mantenibilidad | Media | Microservicios con contratos de API versionados; cada servicio desplegable, escalable y actualizable de forma independiente (RNF-012) |
| Observabilidad | Media | Logging estructurado JSON; trazas distribuidas OpenTelemetry; métricas técnicas y de negocio; rastreo end-to-end por correlationId (RNF-009) |
| Multitenancy | Media | Aislamiento de datos y configuración por tenant desde el diseño inicial; `tenant_id` propagado desde claims JWT (RNF-011) |
| Idempotencia | Media | Todas las APIs de operaciones financieras soportan Idempotency-Key; el sistema garantiza procesamiento único ante reintentos (RNF-013, RF-016) |

---

### Restricciones

- **Arquitectura:** Microservicios en Kubernetes es mandatorio. Arquitectura monolítica prohibida (SRS §8, ADC §11).
- **Autenticación:** Todas las APIs externas e internas requieren OAuth 2.0 / OIDC. Esquemas propietarios prohibidos (SRS §8, RNF-005).
- **Cifrado en tránsito:** TLS 1.2 o superior obligatorio en toda comunicación, interna y externa (SRS §8, RNF-003).
- **Cifrado en reposo:** AES-256 para datos sensibles; claves gestionadas en AWS Secrets Manager con rotación automática (RNF-004).
- **Gestión de secretos:** Ningún secreto, clave o credencial puede residir en código fuente, repositorios no cifrados ni variables de entorno en texto plano (SRS §8, RN-008).
- **Migraciones de esquema:** Liquibase standalone (`run-liquibase-migrations.sh`); Flyway excluido por incompatibilidad con R2DBC reactivo (ADC §2, §11).
- **Read Model CQRS:** PostgreSQL 16 desnormalizado (`pagofacil_readmodel`); MongoDB excluido del read model (ADR-002 — override definitivo, ADC §11).
- **Capa de integración externa:** Reside exclusivamente en `integration-service` (Apache Camel 4). Los servicios de dominio no tienen acoplamiento directo con terceros (ADC §8, §11).
- **Stack backend:** Java 21 + Spring Boot 3 WebFlux (reactivo, R2DBC) para microservicios de dominio; Scala 3 + Apache Spark para jobs ETL de reportería (ADC §2).
- **Bus de mensajes:** Apache Kafka 3 KRaft (sin ZooKeeper) mandatorio para eventos de dominio y pipeline ETL (ADC §2).
- **Infraestructura:** Nube pública AWS (EKS, RDS, MSK, Cognito, API Gateway, Secrets Manager). Sin infraestructura on-premise en esta fase (SRS §8, ADC §3).
- **Observabilidad:** OpenTelemetry obligatorio para trazas distribuidas; logs en formato JSON estructurado (SRS §8, RNF-009).
- **Fuera de alcance (versión actual):** Aplicaciones móviles nativas, integración directa con redes de tarjetas (Visa/Mastercard), productos de crédito, soporte multimoneda (SRS §1).

---

### Cross-Cutting Concerns

- **Seguridad:** Autenticación OAuth 2.0 / OIDC, autorización por rol y `tenant_id`, cifrado TLS + AES-256, gestión de secretos en vault — presentes en todos los servicios.
- **Observabilidad:** Logging estructurado JSON, métricas (Prometheus), trazas distribuidas (OpenTelemetry + Jaeger), agregación de logs (Fluent Bit) — instrumentados en todos los servicios.
- **Multitenancy:** `tenant_id` propagado en claims JWT y en todas las entidades del modelo de datos; validado en cada operación sin excepción.
- **Idempotencia:** Header `Idempotency-Key` respetado en todas las APIs de operaciones financieras; registro de idempotencia por operación.
- **Auditoría:** Toda operación de negocio publica un evento hacia el Audit Context con actor, acción, timestamp, IP y correlationId.
- **Manejo de errores:** Respuestas de error genéricas hacia el exterior (sin stack traces ni datos internos); errores detallados registrados internamente con correlationId.
- **Consistencia distribuida:** Transactional Outbox para publicación confiable de eventos Kafka; Saga con compensación para transacciones cross-service.

---

## 2. Decisiones Estratégicas

## DS-001 — Microservicios en Kubernetes

*[Decisión previa — no revisable]*

**Contexto:** El SRS establece explícitamente que el sistema debe implementarse como microservicios en Kubernetes. La arquitectura monolítica está prohibida.

**Decisión:** El sistema se implementa como un conjunto de microservicios independientes desplegados en Kubernetes (K3s en desarrollo, EKS en staging y producción). Cada bounded context se materializa como uno o más microservicios con su propio ciclo de despliegue.

**Justificación:** Escalabilidad horizontal independiente por servicio (RNF-006); despliegue independiente sin afectar la disponibilidad del sistema (RNF-012); aislamiento de dominio por bounded context; soporte nativo a multitenancy (RNF-011).

**Consecuencias:** Complejidad operacional inherente a sistemas distribuidos (gestión de red, consistencia eventual, observabilidad distribuida). Esta complejidad se mitiga con las decisiones DS-004 (integración centralizada), DS-005 (saga orquestada) y la plataforma de observabilidad obligatoria.

---

## DS-002 — Database-per-Service

**Contexto:** La arquitectura de microservicios requiere una estrategia explícita para el acceso a datos que garantice autonomía e independencia de despliegue entre servicios.

**Decisión:** Cada bounded context (microservicio) posee y gestiona su propia base de datos de forma exclusiva. Ningún otro servicio puede acceder directamente a la base de datos de otro contexto. La comunicación de datos entre contextos se realiza únicamente mediante eventos de dominio (mensajería asíncrona vía Kafka) o mediante llamadas REST al servicio propietario.

**Justificación:** Autonomía de datos: cada servicio evoluciona su modelo de datos de forma independiente sin coordinar migraciones con otros servicios. Aislamiento de fallos: la caída de una base de datos no afecta directamente a otros servicios. Independencia de despliegue: el servicio puede redeployarse, escalarse y actualizarse sin dependencias de esquema compartido.

**Consecuencias:**
- **Ganancia:** Autonomía total de cada bounded context; independencia de despliegue; fallos aislados.
- **Costo aceptado:** Ausencia de JOINs entre bases de datos de diferentes servicios; consistencia eventual entre contextos (no consistencia fuerte transversal); mayor complejidad en queries que requieren datos de múltiples contextos (resuelto por el read model CQRS en el Reporting Context).

---

## DS-003 — CQRS con Transactional Outbox y Read Model PostgreSQL

*[Decisión previa — no revisable]*

**Contexto:** El sistema requiere tanto consistencia financiera en escrituras (ACID) como rendimiento en consultas de saldo e historial (p95 < 500 ms). Un modelo único no satisface ambas necesidades de forma óptima.

**Decisión:** Se adopta el patrón CQRS. El write model utiliza PostgreSQL 16 normalizado con garantías ACID para todas las operaciones de modificación de saldo. El read model utiliza PostgreSQL 16 desnormalizado en la base de datos dedicada `pagofacil_readmodel`, proyectado por el Projection Service que consume eventos Kafka de todos los contextos de dominio. El Transactional Outbox garantiza la publicación confiable de eventos de dominio a Kafka sin riesgo de pérdida por fallo del bus.

**Nota ADR-002:** El read model fue definido inicialmente como MongoDB en el Strategic Design. Esta decisión fue revertida (override definitivo) por el Technical Design SDD, motivado por la compatibilidad nativa con SparkJdbcSourceAdapter para el pipeline ETL de reportería y la simplificación operacional de mantener un único motor relacional para ambos modelos.

**Justificación:** Separación clara entre lógica de escritura (consistencia ACID, validaciones de dominio) y lógica de lectura (rendimiento, queries desnormalizados). El Transactional Outbox elimina el problema de dualidad write/publish (garantiza que el evento se publica si y solo si la transacción local se confirma).

**Consecuencias:**
- **Ganancia:** Consistencia ACID en write model; alto rendimiento en read model; pipeline ETL simplificado via JDBC.
- **Costo aceptado:** Consistencia eventual entre write model y read model (el read model refleja el estado con un lag proporcional al throughput de Kafka y la velocidad del Projection Service).

---

## DS-004 — Capa de Integración Centralizada en `integration-service` con Apache Camel

*[Decisión previa — no revisable]*

**Contexto:** El sistema se integra con múltiples sistemas externos de alta criticidad (KYC, AML, entidades financieras, pasarelas de pago, SMS/Email). Distribuir estas integraciones en cada servicio de dominio genera acoplamiento, duplicación de lógica de retry/circuit-breaker y dificultad para gobernar credenciales y SLAs.

**Decisión:** Toda la conectividad con sistemas externos se centraliza en un microservicio dedicado `integration-service` implementado con Apache Camel 4 y Spring Boot. Este servicio actúa como Anti-Corruption Layer (ACL) y Mediador EAI. Ningún servicio de dominio tiene acoplamiento directo con sistemas externos. El `integration-service` también actúa como orquestador de sagas (ver DS-005).

**Justificación:** Gobierno central de credenciales y SLAs de terceros; dominio limpio sin acoplamientos externos en los servicios de negocio; punto único de control para circuit breakers, retries y fallbacks; facilita el reemplazo de proveedores externos sin modificar servicios de dominio.

**Consecuencias:**
- **Ganancia:** Dominio limpio; gobierno centralizado de integraciones; Anti-Corruption Layer bien definido.
- **Costo aceptado:** El `integration-service` es un componente crítico de alta carga — requiere escalabilidad horizontal y alta disponibilidad propia; puede convertirse en cuello de botella si no se escala adecuadamente.

---

## DS-005 — Saga por Orquestación con Narayana LRA en `integration-service`

*[Decisión previa — no revisable]*

**Contexto:** Las operaciones financieras principales (depósito, transferencia, retiro) involucran múltiples bounded contexts y sistemas externos. Se requiere garantizar consistencia distribuida con capacidad de compensación ante fallos.

**Decisión:** Se adopta el patrón Saga en estilo de orquestación. El orquestador reside en el `integration-service` mediante Apache Camel + Narayana LRA Coordinator. Narayana LRA gestiona el ciclo de vida de cada saga, incluyendo la coordinación de pasos de compensación. Las tres sagas principales son: depósito de fondos, transferencia entre usuarios y retiro de fondos (ver Context Map en SDD-domain).

**Justificación:** La orquestación centraliza la lógica de coordinación en un único componente, lo que facilita la visibilidad del estado de cada saga, la gestión de compensaciones y el debugging. Narayana LRA es compatible con el stack Spring Boot reactivo y está disponible en el entorno dev como servicio systemd.

**Consecuencias:**
- **Ganancia:** Visibilidad completa del estado de cada saga; lógica de compensación centralizada; debugging simplificado.
- **Costo aceptado:** Acoplamiento del orquestador con los participantes de la saga; si el `integration-service` falla durante una saga, se requiere mecanismo de recuperación del estado (Narayana LRA gestiona esto); mayor complejidad operacional respecto a coreografía pura.

---

## DS-006 — ETL de Reportería en Dos Etapas con Apache Spark

**Contexto:** El sistema requiere generación de reportes regulatorios (ROS/SAR, volumen transaccional, alertas AML) a partir del read model CQRS. Los volúmenes pueden superar 1M de filas. La lógica de extracción y transformación debe estar separada para facilitar su evolución independiente.

**Decisión:** El pipeline ETL de reportería se implementa en dos etapas batch:
- **MS1 (report-extraction-service):** Job Spark que extrae datos del read model `pagofacil_readmodel` exclusivamente vía JDBC (SparkJdbcSourceAdapter) según el ReportSchema declarado en el catálogo, valida el esquema y genera un archivo Parquet como contrato de salida.
- **MS2 (report-processing-service):** Job Spark que consume el Parquet de MS1 y transforma los datos según el ReportType con el patrón Factory.

MS1 y MS2 son jobs batch ejecutados por schedule (reportes periódicos) o bajo demanda por evento de comando (ROS/SAR). No exponen endpoints HTTP. El contrato entre etapas es el archivo Parquet, que garantiza independencia de la lógica de cada etapa.

**Justificación:** Separación de responsabilidades entre extracción/validación (MS1) y transformación/enriquecimiento (MS2); Parquet como contrato tipado entre etapas; compatibilidad nativa con SparkJdbcSourceAdapter para leer el read model PostgreSQL sin adaptadores adicionales.

**Consecuencias:**
- **Ganancia:** Simplicidad operacional de jobs batch; separación clara de responsabilidades; Parquet como contrato tipado reutilizable.
- **Costo aceptado:** Latencia inherente al modelo batch (el reporte no es en tiempo real); el schedule introduce un lag entre el estado del sistema y el contenido del reporte; no aplica para consultas ad-hoc de baja latencia.

---

## DS-007 — Capa Serverless de Formatos con AWS Lambda y EventBridge

**Contexto:** Los reportes generados por MS2 deben ser exportados en múltiples formatos (PDF, XLS, CSV). La demanda de generación es esporádica y variable; un servicio persistente para este propósito sería costoso e ineficiente.

**Decisión:** La generación de formatos de salida se implementa con AWS Lambda (Python) + EventBridge. Un Kafka Consumer Lambda recibe el evento `report.processed`; EventBridge enruta el evento a la lambda correspondiente según el formato de salida solicitado (una rule por formato: PDF, XLS, CSV). Las lambdas generan el archivo final en el formato solicitado.

**Justificación:** Costo optimizado para carga esporádica (serverless pay-per-use); desacople por EventBridge permite añadir nuevos formatos sin modificar el pipeline ETL; cada lambda es independiente y reemplazable.

**Consecuencias:**
- **Ganancia:** Costo optimizado; desacople por EventBridge; independencia por formato.
- **Costo aceptado:** Cold start de Lambda puede introducir latencia en la primera invocación; dependencia de AWS Lambda y EventBridge como componentes gestionados.

---

## DS-008 — Base de Datos Dedicada de Reportería

**Contexto:** El patrón Database-per-Service (DS-002) requiere que el Reporting Context gestione sus propios datos de forma exclusiva. El catálogo de esquemas de reportes y los metadatos del pipeline no deben residir en las bases de datos operacionales de los servicios de dominio.

**Decisión:** El Reporting Context dispone de una base de datos dedicada `pagofacil_reporting` que contiene el catálogo de esquemas de reportes (`report_schema_catalog`), los metadatos de ejecuciones de reportes y la configuración del pipeline. Adicionalmente, el read model `pagofacil_readmodel` es propiedad exclusiva del Reporting Context en su función de lectura (escrito exclusivamente por el Projection Service).

**Justificación:** Cumplimiento del patrón Database-per-Service; el catálogo de esquemas es parte del dominio de reportería y no debe depender de otro contexto; separación clara entre datos operacionales y datos de reportería.

**Consecuencias:** El Projection Service es el único componente con permiso de escritura sobre `pagofacil_readmodel`; MS1 tiene permiso de solo lectura; ningún otro microservicio de dominio tiene acceso a estas bases de datos.

---

## DS-CQRS-1 — Segregación Write/Read: PostgreSQL Operacional y Read Model Dedicado

*[Decisión previa — no revisable]*

**Contexto:** El patrón CQRS requiere una separación explícita entre el modelo de escritura y el modelo de lectura, con mecanismos claros de sincronización.

**Decisión:** Cada microservicio operacional de dominio escribe en su propia base de datos PostgreSQL normalizada (write model, Database-per-Service). El estado necesario para reportes y consultas analíticas se publica como eventos de dominio en Kafka. Ningún microservicio de reportería tiene acceso a las bases de datos operacionales.

**Justificación:** Aislamiento completo entre el write model (optimizado para ACID y validaciones de dominio) y el read model (optimizado para queries de alto rendimiento).

**Consecuencias:** La separación es absoluta — cualquier query que requiera datos de múltiples servicios debe resolverse a través del read model, no mediante acceso directo entre BDs.

---

## DS-CQRS-2 — Projection Service como Único Escritor del Read Model

*[Decisión previa — no revisable]*

**Contexto:** El read model `pagofacil_readmodel` debe reflejar el estado agregado de múltiples bounded contexts de forma consistente y con alto rendimiento para consultas.

**Decisión:** El Projection Service es un microservicio dedicado (Spring Boot reactivo) que consume eventos de dominio de todos los microservicios desde Kafka y construye tablas PostgreSQL desnormalizadas y optimizadas para consulta en `pagofacil_readmodel`. Es el único componente con permiso de escritura sobre esta base de datos.

**Justificación:** Separación de responsabilidades entre producción de eventos (servicios de dominio) y proyección de estado (Projection Service); el read model puede reconstruirse completamente reprocesando el historial de eventos de Kafka.

**Consecuencias:**
- **Ganancia:** Read model optimizado para queries SQL sin JOINs cross-service; alto rendimiento en consultas.
- **Costo aceptado:** Consistencia eventual — el read model refleja el estado con un lag proporcional al throughput de Kafka y la velocidad de procesamiento del Projection Service.

---

## DS-CQRS-3 — Read Model Relacional como Fuente Exclusiva del Pipeline ETL

*[Decisión previa — no revisable]*

**Contexto:** MS1 (Spark) necesita una fuente de datos para extraer información de reportes. Acceder directamente a las BDs operacionales de los servicios de dominio violaría el patrón Database-per-Service y acoplaría el pipeline ETL a los modelos internos de cada servicio.

**Decisión:** MS1 lee exclusivamente de `pagofacil_readmodel` vía JDBC (SparkJdbcSourceAdapter, `--source jdbc`). Está prohibido apuntar queries de extracción a las bases de datos operacionales de los servicios de dominio. Los queries de extracción son SQL expresivo directamente sobre las tablas desnormalizadas del read model.

**Justificación:** El read model fue diseñado específicamente para consultas analíticas; los queries SQL son expresivos, verificables y performantes sobre tablas desnormalizadas; elimina la necesidad de transformaciones de esquema intermedias; respeta el aislamiento de datos de cada bounded context.

**Consecuencias:** MS1 tiene una dependencia de disponibilidad del read model; si el read model está desactualizado (lag de proyección), los reportes reflejan un estado ligeramente anterior al tiempo real — aceptable para reportes regulatorios periódicos y para ROS/SAR donde la consistencia del período ya cerrado es suficiente.

---

## 3. Riesgos y Tradeoffs

### Riesgos

| ID | Riesgo | Probabilidad | Impacto | Mitigación |
|----|--------|-------------|---------|-----------|
| R-001 | El `integration-service` se convierte en cuello de botella al centralizar toda la conectividad externa y la orquestación de sagas | Media | Alto | Diseño sin estado de sesión en Camel routes; HPA para escalar horizontalmente; circuit breaker por ruta de integración externa |
| R-002 | Lag de consistencia del read model impacta la exactitud de reportes cuando se solicitan inmediatamente después de una transacción de alta carga | Media | Medio | El lag es inherente al diseño CQRS; es aceptable para reportes regulatorios periódicos; documentar el SLA de consistencia del read model |
| R-003 | Fallo parcial de una saga sin que el Narayana LRA coordine correctamente la compensación deja el sistema en estado inconsistente | Baja | Alto | Narayana LRA gestiona el ciclo de vida de las sagas; drill periódico de escenarios de fallo documentado; pruebas de caos en staging |
| R-004 | Los proveedores externos críticos (KYC, AML) no tienen SLAs definidos antes del inicio del desarrollo del módulo de compliance | Alta | Alto | El SRS identifica esto como dependencia bloqueante (§9); escalarlo al Oficial de Cumplimiento y al Project Manager antes de iniciar el módulo de compliance |
| R-005 | Los volúmenes transaccionales baseline no están definidos, impidiendo dimensionar correctamente el sistema para pruebas de carga y HPA | Alta | Medio | Bloqueante para el plan de pruebas de carga; requiere definición por el Sponsor y el Oficial de Cumplimiento antes del diseño técnico de pruebas |
| R-006 | La normativa KYC/AML específica de la jurisdicción de operación no está documentada antes del inicio del módulo de compliance | Alta | Alto | Dependencia explícita del SRS §9; el Oficial de Cumplimiento debe documentarla antes del desarrollo del módulo de compliance |
| R-007 | La complejidad del stack (Kubernetes, Kafka, CQRS, Saga, ETL Spark, Lambda) excede la capacidad del equipo si su tamaño o experiencia es menor a lo supuesto | Media | Alto | El SRS asume equipo con experiencia en microservicios y seguridad financiera; validar composición real del equipo con el Sponsor antes de iniciar el diseño técnico |
| R-008 | El diseño multitenancy con aislamiento por `tenant_id` tiene una brecha de implementación si no todos los microservicios propagan correctamente el claim en todas las operaciones | Media | Alto | Definir como control de calidad en el Technical Design: lint / test automático que verifique la propagación del `tenant_id` en cada endpoint y evento |

---

### Tradeoffs Aceptados

| Tradeoff | Ganancia | Costo Aceptado |
|----------|----------|----------------|
| Microservicios vs. monolito | Escalabilidad independiente por servicio; despliegue independiente; aislamiento de fallos; multitenancy nativo | Complejidad operacional (red, observabilidad distribuida, consistencia eventual, gestión de secretos por servicio) |
| Database-per-Service | Autonomía completa de datos por bounded context; independencia de despliegue; fallos aislados | Sin JOINs entre BDs de diferentes servicios; consistencia eventual cross-service; mayor complejidad en queries analíticos (mitigado por el read model CQRS) |
| CQRS + Transactional Outbox | Consistencia ACID en write model; alto rendimiento en read model; pipeline ETL simplificado via JDBC | Consistencia eventual entre write y read model; lag de proyección; complejidad adicional del Projection Service y el outbox |
| Saga por orquestación (vs. coreografía) | Visibilidad centralizada del estado; lógica de compensación concentrada; debugging simplificado | Acoplamiento del orquestador con los participantes; el `integration-service` es un punto de coordinación crítico; mayor complejidad operacional |
| Integración centralizada en `integration-service` | Dominio limpio; gobierno central de credenciales y SLAs; ACL bien definido; un único punto de cambio ante reemplazo de proveedor | `integration-service` como componente crítico de alta disponibilidad; hop de red adicional para todas las operaciones que involucran sistemas externos |
| ETL batch (Spark) vs. streaming en tiempo real | Simplicidad operacional del modelo batch; jobs sin estado HTTP; Parquet como contrato tipado; compatibilidad JDBC nativa | Latencia inherente al batch; los reportes no son en tiempo real; el schedule introduce lag entre el estado del sistema y el contenido del reporte |
| Read model PostgreSQL (vs. MongoDB — ADR-002) | Compatibilidad nativa con SparkJdbcSourceAdapter; queries SQL expresivos sin adaptadores adicionales; un único motor relacional para write y read model | Menor flexibilidad de esquema respecto a MongoDB para documentos semiestructurados; requiere gestión explícita de migraciones del read model |

---

## 4. Recomendación y Próximos Pasos

### Resumen Ejecutivo

Las decisiones estratégicas del SDD de PagoFacil establecen una arquitectura de microservicios orientada a dominio con separación explícita de responsabilidades por bounded context. Los pilares fundamentales son:

1. **Database-per-Service** garantiza autonomía e independencia de despliegue.
2. **CQRS + Transactional Outbox** separa la consistencia ACID de las escrituras del rendimiento de las lecturas, con el Projection Service como puente confiable.
3. **Integration-service centralizado** (Apache Camel + Narayana LRA) mantiene el dominio limpio y centraliza la orquestación de sagas y la conectividad con sistemas externos.
4. **Pipeline ETL de dos etapas** (MS1 + MS2 Spark) y capa serverless Lambda resuelven la reportería regulatoria con separación clara de extracción, transformación y generación de formatos.

Todas las decisiones previas del ADC (stack tecnológico, CQRS, PostgreSQL como read model, orquestación Narayana LRA, Apache Camel) están incorporadas como restricciones fijas en este SDD.

---

### Validaciones Pendientes antes de Iniciar el Diseño Técnico

| Ítem | Responsable | Criticidad |
|------|-------------|-----------|
| Definición de la normativa KYC/AML específica de la jurisdicción de operación | Oficial de Cumplimiento | Bloqueante para el módulo de compliance |
| Definición de SLAs y contratos con el proveedor de validación KYC | Project Manager + Legal | Bloqueante para el módulo de onboarding |
| Definición de volúmenes transaccionales baseline y proyectados (usuarios concurrentes, req/s) | Sponsor + Oficial de Cumplimiento | Bloqueante para el plan de pruebas de carga y el dimensionamiento de HPA |
| Confirmación de disponibilidad de APIs o mecanismos de integración de las entidades financieras | Project Manager | Bloqueante para el diseño técnico del `integration-service` |
| Confirmación del tamaño y perfil real del equipo de desarrollo | Sponsor | Necesario para ajustar el plan de desarrollo en 6 etapas |
| Verificación de aplicabilidad GDPR (usuarios en la UE) y SOC 2 / ISO 27001 (tenants enterprise) | Oficial de Cumplimiento + Legal | Necesario antes del diseño técnico de seguridad y datos |

---

### Próximos Pasos — Etapa de Diseño Técnico

1. **Diseño de APIs por bounded context:** Contratos REST versionados para Identity, Wallet, Transaction y Fraud; contratos de eventos Kafka (Avro/JSON Schema) por bounded context.
2. **Diseño de esquemas de base de datos:** Write model PostgreSQL por servicio; tablas del read model `pagofacil_readmodel`; esquema de la BD de auditoría (MongoDB append-only); esquema de `pagofacil_reporting`.
3. **Diseño detallado de sagas:** Secuencia exacta de pasos y eventos de compensación para depósito, transferencia y retiro; manejo de timeouts y fallos parciales en Narayana LRA.
4. **Diseño del Projection Service:** Mapeo de eventos de dominio a tablas del read model; estrategia de manejo de eventos out-of-order; estrategia de reconstrucción del read model desde el historial Kafka.
5. **Diseño del pipeline ETL:** SparkJdbcSourceAdapter y configuración de conexión al read model; Factory de tipos de reporte en MS2; ADRs de implementación para MS1 y MS2.
6. **Diseño de infraestructura:** Módulos Terraform por entorno (dev, staging, prod); configuración de K3s dev y EKS prod; configuración de MSK, RDS multiAZ, Secrets Manager.
7. **Generación de scaffolding:** Ejecución de `maven_hexagonal_scaffold.py` por microservicio; `scala_hexagonal_scaffold.py` para MS1 y MS2; `integration_service_scaffold.py` para `integration-service`; `nextjs_feature_scaffold.py` para el frontend.

---

### Dependencias y Bloqueadores

- La definición de la normativa KYC/AML y los contratos con el proveedor KYC son dependencias bloqueantes para el módulo de onboarding y compliance. El desarrollo no debe iniciarse en estos módulos hasta que estén documentados.
- Los volúmenes transaccionales baseline deben estar definidos antes de completar el diseño técnico de pruebas de carga y la configuración de HPA en Kubernetes.
- La aplicabilidad de GDPR y SOC 2 debe confirmarse antes de finalizar el diseño técnico del módulo de datos y privacidad.
