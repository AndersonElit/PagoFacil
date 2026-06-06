# Strategic Design Document — Estrategia Arquitectónica

**Proyecto:** PagoFacil — Billetera Digital | Parte del conjunto SDD v1.0 (domain / security / architecture)  
**Fecha:** 2026-06-06 | **Etapa:** Strategic Design / Pre-Design

---

## 1. Drivers Arquitectónicos

### Atributos de Calidad Prioritarios

| Atributo | Prioridad | Justificación |
|----------|-----------|---------------|
| Disponibilidad | Alta | SLA de 99.9% mensual (≤ 43.8 min downtime no planificado). RTO < 1 hora, RPO < 15 minutos. Plataforma financiera de producción; una interrupción tiene impacto regulatorio y reputacional directo. |
| Seguridad | Alta | Sistema financiero con datos PII, operaciones monetarias y obligaciones KYC/AML. Sujeto a GDPR, normativas KYC/AML y potencialmente PCI-DSS. Pentest externo sin vulnerabilidades críticas/altas requerido antes de producción. |
| Consistencia Financiera | Alta | Garantías ACID para operaciones locales. Patrón Saga con compensación para transacciones distribuidas. Outbox Pattern para publicación confiable de eventos. Ningún fondo puede perderse o duplicarse. |
| Rendimiento | Alta | p95 < 500 ms para consultas (saldo, historial). p95 < 2 000 ms para validación + encolamiento de operaciones financieras. Validado mediante pruebas de carga previas al despliegue. |
| Escalabilidad | Alta | Escalamiento horizontal automático por microservicio. Diseño para soportar ≥ 10x el volumen transaccional inicial sin rediseño estructural (RNF-006). |
| Auditabilidad | Alta | Registros inmutables de todas las operaciones financieras y decisiones de cumplimiento. Retención mínima de 5 años. CorrelationId en logs, trazas y eventos. Requisito regulatorio no negociable. |
| Mantenibilidad | Alta | Arquitectura hexagonal por microservicio. Cobertura ≥ 80% en módulos financieros y de seguridad. Despliegue y escalamiento independiente por contexto. |
| Observabilidad | Media | Logging estructurado JSON con CorrelationId. Métricas Prometheus. Trazas distribuidas OpenTelemetry. Requerido para operar el sistema en producción con SLAs comprometidos. |
| Aislamiento Multitenancy | Media | Datos, configuraciones y límites completamente aislados por tenant. Impide que la operación de un tenant afecte a otro. |

---

### Restricciones

Las siguientes restricciones son fijas y no negociables, derivadas del ADC:

- **Lenguaje backend (servicios de dominio):** Java 21 + Spring Boot 3.4.1 (WebFlux reactivo). Arquitectura hexagonal obligatoria usando template `maven_hexagonal_scaffold.py`.
- **Lenguaje backend (ETL / reportería):** Scala 2.13 + Apache Spark 3.5.1. Template `scala_hexagonal_scaffold.py`.
- **Lenguaje de integración / saga:** Java 21 + Apache Camel 4.10.2 + Narayana LRA. Template `integration_service_scaffold.py`.
- **Frontend:** TypeScript 5 + Next.js 15.3 + React 19. Desplegado exclusivamente en Vercel; Jenkins es el único disparador de despliegues.
- **Bases de datos:** PostgreSQL 16.3 (escritura ACID) + MongoDB 7 (read model / auditoría). No se permiten otras bases de datos en esta fase.
- **Mensajería:** Apache Kafka 3.7.0 (modo KRaft). No se permiten otras plataformas de mensajería.
- **Identidad y autenticación:** AWS Cognito + OAuth 2.0 / OpenID Connect. No se permiten esquemas propietarios.
- **API Gateway:** AWS API Gateway v2 (HTTP).
- **Gestión de secretos:** AWS Secrets Manager. Variables de entorno no cifradas y texto plano están explícitamente prohibidos.
- **Orquestación de contenedores:** K3d (dev) / AWS EKS (staging/prod). GitOps con ArgoCD.
- **CI/CD:** Jenkins (controller EC2 + agentes pods Kubernetes) + ArgoCD. No se permiten otras herramientas.
- **Infraestructura como código:** Terraform ≥ 1.6.0 con estructura de módulos definida en `terraform/backend` y `terraform/frontend`.
- **Región AWS:** `us-east-1`. Residencia de datos fijada.
- **Reportería serverless:** AWS Lambda + AWS EventBridge.
- **KYC como prerequisito:** El proceso KYC no puede desactivarse por configuración. Es un invariante del dominio.
- **Inmutabilidad de auditoría:** No se puede implementar UPDATE ni DELETE sobre eventos de auditoría y transacciones confirmadas.

---

### Cross-Cutting Concerns

- **Logging:** Estructurado en JSON con CorrelationId obligatorio en cada entrada. Sin datos PII en texto libre. Retención mínima 5 años para operaciones financieras.
- **Trazas distribuidas:** OpenTelemetry en todos los microservicios. El CorrelationId propaga la traza entre servicios.
- **Métricas:** Prometheus en todos los microservicios. CloudWatch para logs de MongoDB y Jenkins en staging/prod.
- **Seguridad:** mTLS inter-servicio. JWT validado en API Gateway. Secretos en Secrets Manager. TLS 1.2+ en tránsito externo. AES-256 en reposo.
- **Idempotencia:** Todos los consumers Kafka y endpoints de operaciones financieras implementan idempotencia. Idempotency Key por operación.
- **Resiliencia:** Circuit breakers para dependencias externas. Reintentos con backoff exponencial. Timeouts configurables. Degradación controlada.
- **Calidad de código:** SonarQube LTS Community como quality gate en el pipeline Jenkins. Cobertura ≥ 80% en módulos críticos.
- **Multitenancy:** TenantId como predicado obligatorio en todas las consultas. Aislamiento validado en cada operación.

---

## 2. Decisiones Estratégicas

---

### DS-001 — Microservicios Event-Driven como Estilo Arquitectónico

`[Decisión previa — no revisable]`

**Contexto:** El SRS §2 describe explícitamente una arquitectura de microservicios event-driven sobre Kubernetes. Los templates y scripts del ADC implementan este estilo con scaffolding listo para uso.

**Decisión:** PagoFacil se implementa como un conjunto de microservicios independientes, cada uno responsable de un bounded context, comunicados mediante eventos asíncronos (Kafka) para procesamiento desacoplado y REST/HTTP síncronos para operaciones que requieren respuesta inmediata.

**Justificación:** El dominio financiero multitenancy exige escalamiento independiente por capacidad (Wallet puede escalar sin escalar Fraud), despliegue sin downtime por componente, y aislamiento de fallos que evite que un servicio degrade toda la plataforma.

**Consecuencias:** Complejidad operacional mayor que un monolito. Requiere gestión de consistencia eventual, trazabilidad distribuida y operación de Kubernetes. El equipo debe tener experiencia demostrada en estos patrones.

---

### DS-002 — Database-per-Service

**Contexto:** Con múltiples bounded contexts implementados como microservicios, cada uno requiere autonomía completa de datos para garantizar independencia de despliegue y evolución del esquema.

**Decisión:** Cada microservicio es propietario exclusivo de su base de datos. Ningún otro servicio accede directamente a la base de datos de otro. La comunicación de datos entre contextos ocurre exclusivamente mediante eventos de dominio (Kafka) o llamadas REST al servicio propietario.

**Justificación:** El patrón Database-per-Service es la consecuencia natural de la arquitectura de microservicios. Garantiza que los equipos puedan evolucionar el esquema de datos de su contexto sin coordinación con otros equipos, y que los fallos de una base de datos no afecten directamente a otros servicios.

**Consecuencias:** Se eliminan los JOINs entre bases de datos de diferentes contextos. La consistencia entre servicios es eventual, no inmediata. Los reportes y dashboards que necesitan datos de múltiples contextos dependen del Read Model proyectado.

---

### DS-003 — CQRS: Segregación de Modelos de Escritura y Lectura

`[Decisión previa — no revisable]`

**Contexto:** El sistema tiene patrones de acceso radicalmente distintos: escrituras financieras con garantías ACID (baja concurrencia, alta consistencia) y lecturas de historial, dashboard y reportería (alta concurrencia, consistencia eventual aceptable).

**Decisión:** Las escrituras operacionales se realizan en PostgreSQL 16.3 (modelo normalizado, ACID). Las lecturas de historial, dashboard de auditoría y reportería se realizan sobre un Read Model desnormalizado en MongoDB 7. La sincronización entre ambos modelos ocurre mediante el Transactional Outbox Pattern + Kafka, procesados por un Projection Service dedicado.

**Justificación:** PostgreSQL provee las garantías ACID necesarias para las operaciones financieras críticas. MongoDB provee el modelo de documento desnormalizado óptimo para consultas de historial paginadas, dashboard de auditoría y extracción ETL de reportería, sin afectar el rendimiento del modelo de escritura.

**Consecuencias:** El Read Model refleja el estado con latencia proporcional al throughput de Kafka (consistencia eventual). Las consultas de historial y dashboard pueden mostrar un estado levemente desfasado respecto a la escritura. Este tradeoff es aceptable para estos casos de uso.

---

### DS-004 — Transactional Outbox Pattern para Publicación Confiable de Eventos

**Contexto:** En una arquitectura event-driven, es crítico garantizar que los eventos de dominio se publiquen a Kafka si y solo si la transacción local de base de datos fue confirmada. Sin este patrón, existe riesgo de pérdida de eventos o publicación de eventos sin transacción correspondiente.

**Decisión:** Cada microservicio que publica eventos de dominio persiste el evento en una tabla `outbox` dentro de la misma transacción local de PostgreSQL antes de confirmar el cambio de estado. Un proceso dedicado lee la tabla outbox y publica los eventos pendientes a Kafka con garantía at-least-once.

**Justificación:** El Outbox Pattern elimina el problema del doble commit (two-phase commit) entre la base de datos y el bus de mensajes, garantizando consistencia sin transacciones distribuidas XA. Los consumers implementan idempotencia para manejar reentregas sin efectos duplicados.

**Consecuencias:** Latencia adicional mínima por el proceso de relay. Complejidad de implementación manejable con los templates existentes. Cumple el requisito RNF-005.

---

### DS-005 — Integration-Service Centralizado con Apache Camel como ACL

`[Decisión previa — no revisable]`

**Contexto:** El sistema tiene múltiples integraciones con sistemas externos (entidades financieras, proveedor KYC, listas AML) con protocolos, formatos y SLAs heterogéneos. Cada bounded context de dominio no debe conocer los detalles de los sistemas externos.

**Decisión:** Toda la conectividad con sistemas externos se centraliza en un microservicio dedicado `integration-service` implementado con Apache Camel 4.10.2. Este servicio actúa como Anti-Corruption Layer (ACL), traduciendo los modelos externos al lenguaje ubicuo de PagoFacil. Ningún otro bounded context se comunica directamente con sistemas fuera del cluster.

**Justificación:** La centralización permite gobierno unificado de credenciales (todas en Secrets Manager), aplicación consistente de circuit breakers y timeouts, observabilidad centralizada de todas las integraciones externas, y evolución del protocolo externo sin afectar los contextos de dominio.

**Consecuencias:** El `integration-service` es un punto único de fallo para las integraciones externas; requiere alta disponibilidad y resiliencia robusta. Introduce un hop de red adicional para operaciones que requieren integración. Complejidad del servicio mayor que un microservicio de dominio típico.

---

### DS-006 — Saga por Orquestación con Narayana LRA

`[Decisión previa — no revisable]`

**Contexto:** Las operaciones financieras principales (depósito, retiro, transferencia) involucran múltiples microservicios y sistemas externos. Sin coordinación distribuida, un fallo parcial puede dejar el sistema en estado inconsistente (fondos debitados sin acreditar, fondos reservados indefinidamente).

**Decisión:** Las transacciones distribuidas se implementan mediante el patrón Saga con estilo de **orquestación**. El orquestador reside en el `integration-service` utilizando Apache Camel Saga EIP y Narayana LRA (Long Running Actions) como coordinador. Cada paso de la saga tiene un evento de compensación definido que revierte el efecto ante fallo.

**Justificación:** La orquestación centraliza la lógica del flujo en un único lugar, facilitando la visibilidad, el diagnóstico operacional y la auditoría del estado de cada transacción distribuida. Narayana LRA provee infraestructura probada para la gestión del ciclo de vida de las sagas.

**Consecuencias:** El `integration-service` concentra la lógica de coordinación y se convierte en componente crítico. El acoplamiento entre el orquestador y los participantes de la saga es mayor que en coreografía. La complejidad operacional de Narayana LRA requiere capacitación del equipo. El tradeoff es aceptable por la ganancia en visibilidad y control.

---

### DS-007 — ETL Spark de Dos Etapas para Reportería

**Contexto:** El sistema requiere generación de reportes regulatorios y operacionales (RF-017, RF-015) en múltiples formatos (PDF, CSV, XLS) con fuentes de datos en el Read Model MongoDB. Los reportes pueden dispararse por schedule o on-demand desde el dashboard.

**Decisión:** El subsistema de reportería implementa un pipeline ETL de dos etapas con jobs Spark batch:

- **MS1 (`report-extraction-service`, Scala + Spark):** Extrae datos del Read Model MongoDB usando el ReportSchema declarado en `report_schema_catalog`. Valida el esquema y genera un archivo Parquet en S3 como contrato de salida. Publica evento `ReporteExtraido` a Kafka.
- **MS2 (`report-processing-service`, Scala + Spark):** Consume el Parquet de S3, aplica transformaciones específicas por ReportType usando el patrón Factory, y publica el resultado a S3. Emite evento `ReporteProcesado` a Kafka.

MS1 y MS2 son **jobs batch ejecutados por schedule** (CronJob Kubernetes) o por evento de comando on-demand. No son servicios REST persistentes ni exponen endpoints HTTP.

**Justificación:** La separación en dos etapas con Parquet como contrato desacopla la extracción de la transformación, facilitando el reintento independiente ante fallos y la evolución del esquema sin afectar la extracción. Spark provee la capacidad de procesamiento necesaria para volúmenes regulatorios.

**Consecuencias:** Latencia batch introducida por el schedule (no es reportería en tiempo real). La naturaleza batch simplifica la operación (sin gestión de estado de servicios persistentes) a cambio de latencia en el resultado.

---

### DS-008 — Capa Serverless de Formatos: Lambda + EventBridge

**Contexto:** Una vez procesados los datos por MS2, el reporte debe entregarse en múltiples formatos (PDF, XLS, CSV) según el tipo de reporte. La generación de formatos es una operación puntual sin estado persistente que no justifica un servicio siempre activo.

**Decisión:** Un Lambda Kafka Consumer recibe el evento `ReporteProcesado` y lo publica a EventBridge (`pagofacil-report-bus`). EventBridge enruta el evento mediante rules independientes a lambdas especializadas por formato (lambda-pdf, lambda-xls, lambda-csv). Cada lambda genera el archivo en el formato correspondiente y lo deposita en el bucket S3 `pagofacil-reports`.

**Justificación:** El modelo serverless es óptimo para cargas puntuales e impredecibles. El desacople mediante EventBridge permite agregar nuevos formatos de salida sin modificar el pipeline ETL ni los consumidores existentes.

**Consecuencias:** Las lambdas tienen límites de memoria y tiempo de ejecución que deben validarse contra el tamaño máximo de reportes esperado. La latencia de cold start de Lambda puede afectar reportes on-demand si el tráfico es bajo. Monitoreo adicional requerido para el bus EventBridge.

---

### DS-009 — Base de Datos Dedicada de Reportería

**Contexto:** El bounded context de Reporting requiere persistir el catálogo de esquemas de reportes (`report_schema_catalog`) y los metadatos del subsistema de forma independiente de las bases de datos operacionales de los demás servicios.

**Decisión:** El contexto de Reporting posee una base de datos PostgreSQL dedicada (`pagofacil_reporting`) que aloja el catálogo de esquemas de reportes. Esta base de datos es propiedad exclusiva del bounded context de Reporting; ningún otro servicio accede directamente a ella.

**Justificación:** El patrón Database-per-Service requiere que cada bounded context sea propietario exclusivo de sus datos. El `report_schema_catalog` es un dato de dominio del contexto de Reporting; su aislamiento garantiza que la evolución del esquema de reportes no afecte a otros servicios.

**Consecuencias:** Una base de datos adicional en la infraestructura. La gestión del catálogo de esquemas requiere acceso al contexto de Reporting, no a las bases de datos operacionales.

---

### DS-CQRS-1 — Segregación Write/Read: PostgreSQL como Lado Escritura, MongoDB como Read Model

`[Decisión previa — no revisable]`

**Contexto:** El patrón CQRS requiere modelos de datos independientes para escrituras y lecturas. Las escrituras necesitan consistencia ACID; las lecturas necesitan rendimiento y flexibilidad de consulta.

**Decisión:** Cada microservicio operacional (Wallet, Identity, Fraud) escribe en su propia base de datos PostgreSQL 16.3 (Database-per-Service, lado write) con modelo normalizado y transacciones ACID. El estado que necesitan las consultas de historial, dashboard y reportería se publica como eventos de dominio en Kafka. El Read Model en MongoDB 7 es la fuente de verdad para el lado de lectura. Ningún microservicio de reportería ni de auditoría accede a las bases de datos operacionales PostgreSQL.

**Justificación:** PostgreSQL garantiza la consistencia financiera requerida por RNF-005. MongoDB provee el modelo de documento flexible y optimizado para las consultas de historial paginadas y el acceso del ETL de reportería. La separación física garantiza que las consultas de lectura intensiva no degraden el rendimiento de las escrituras financieras.

**Consecuencias:** Consistencia eventual entre escritura y lectura — el Read Model refleja el estado con latencia proporcional al throughput de Kafka. Este lag es aceptable para historial, dashboard y reportería. No lo es para la consulta de saldo disponible en tiempo real, que debe servirse directamente desde el lado write.

---

### DS-CQRS-2 — Projection Service: Construcción del Read Model en MongoDB

**Contexto:** Los eventos de dominio publicados por los microservicios operacionales en Kafka deben proyectarse hacia el Read Model en MongoDB para que estén disponibles para el dashboard de auditoría, el historial de movimientos y el ETL de reportería.

**Decisión:** Un `projection-service` dedicado (Spring Boot reactivo) consume eventos de dominio de todos los microservicios desde Kafka y construye colecciones desnormalizadas en MongoDB 7 (`pagofacil_readmodel`): `transacciones`, `alertas`, `alertas_aml`, `billeteras`, `conciliaciones`. Es el único escritor de esta base de datos. Los consumidores de lectura (Audit, Reporting) solo leen.

**Justificación:** La proyección centralizada en un único servicio garantiza consistencia del Read Model, facilita el manejo de idempotencia en la proyección (clave de evento + MongoDB upsert), y simplifica el modelo de acceso de datos para los contextos consumidores.

**Consecuencias:** El `projection-service` es un componente adicional que debe ser altamente disponible para mantener el Read Model actualizado. Su retraso impacta directamente la frescura del dashboard y los reportes. Debe diseñarse para reprocessar eventos desde un offset en caso de fallo.

---

### DS-CQRS-3 — Read Model MongoDB como Fuente Exclusiva del ETL de Reportería

**Contexto:** El `report-extraction-service` (MS1 Spark) necesita acceder a los datos históricos para construir los reportes. Debe existir una fuente canónica, optimizada para lectura masiva, sin impactar los sistemas operacionales.

**Decisión:** MS1 lee exclusivamente del Read Model MongoDB (`pagofacil_readmodel`) usando el Spark MongoDB Connector. Queda **prohibido** que MS1 o cualquier componente del subsistema de reportería apunte directamente a las bases de datos operacionales PostgreSQL de los servicios de dominio. La fuente alternativa JDBC sobre PostgreSQL se usa únicamente como fallback de último recurso documentado operacionalmente, nunca como fuente primaria.

**Justificación:** El Read Model MongoDB está diseñado y desnormalizado para acceso de lectura masiva. Al aislar la extracción del ETL del sistema operacional, se garantiza que los jobs Spark batch no generen presión sobre las bases de datos transaccionales, preservando los SLAs de latencia de las operaciones financieras.

**Consecuencias:** La calidad de los reportes depende de la completitud y frescura del Read Model. Si el `projection-service` tiene retraso, los reportes reflejarán ese desfase. Los jobs Spark deben validar el esquema de las colecciones MongoDB antes de procesar para detectar cambios estructurales.

---

## 3. Riesgos y Tradeoffs

### Riesgos

| ID | Riesgo | Probabilidad | Impacto | Mitigación |
|----|--------|-------------|---------|-----------|
| R-001 | Contratos y SLAs con entidades financieras sin firmar antes del inicio de la implementación. Los protocolos de integración pueden diferir de lo asumido, generando retrabajo en Integration Context. | Alta | Alto | Priorizar la firma de contratos antes del sprint de implementación de `integration-service`. Usar WireMock para desarrollo paralelo sin bloquear al proveedor. |
| R-002 | Proyección de escala de usuarios no definida. El dimensionamiento de infraestructura (EKS, MSK, RDS) puede quedar subestimado o sobredimensionado. | Alta | Medio | Ejecutar pruebas de carga con volúmenes estimados conservadores antes del lanzamiento. Usar autoescaling horizontal y revisar métricas en staging antes de producción. |
| R-003 | Marco KYC/AML no completamente definido por el oficial de compliance antes del inicio del diseño técnico. Puede requerir cambios en Identity y Fraud Context ya implementados. | Media | Alto | Involucrar al oficial de compliance como stakeholder activo antes del cierre del Technical Design. Modelar el marco KYC/AML como configuración donde sea posible sin comprometer la invariante de obligatoriedad. |
| R-004 | Complejidad operacional de Narayana LRA. Fallos en el coordinador LRA pueden dejar sagas en estado indeterminado, requiriendo intervención manual. | Media | Alto | Implementar monitoreo de sagas en estado STUCK con alerta automática. Documentar runbooks de intervención manual. Validar el comportamiento de compensación en pruebas de caos antes del lanzamiento. |
| R-005 | Consistencia eventual del Read Model puede generar reportes desfasados en ventanas de alta carga, afectando la percepción de confiabilidad de los reportes regulatorios. | Media | Medio | Monitorear el lag de proyección como métrica de negocio. Establecer SLA interno para el lag máximo tolerable del Read Model. Documentar el comportamiento eventual para el equipo de compliance. |
| R-006 | Aplicabilidad de PCI-DSS no confirmada por el oficial de compliance. Si aplica, puede requerir controles adicionales no planificados en el diseño actual. | Media | Alto | El oficial de compliance debe emitir dictamen sobre el nivel de PCI-DSS antes del cierre del diseño técnico. |
| R-007 | Volúmenes de datos de auditoría y transacciones a 5+ años en MongoDB pueden requerir estrategia de archivado no planificada actualmente. | Baja | Medio | Definir estrategia de archivado (cold storage S3) durante el diseño técnico antes de comprometer el modelo de datos de MongoDB. |

---

### Tradeoffs Aceptados

| Tradeoff | Ganancia | Costo Aceptado |
|----------|----------|----------------|
| Microservicios vs. monolito modular | Escalamiento independiente por capacidad, despliegue sin downtime por componente, aislamiento de fallos | Complejidad operacional significativamente mayor (Kubernetes, Kafka, mTLS, trazabilidad distribuida, sagas) |
| CQRS (PostgreSQL write + MongoDB read) | Rendimiento óptimo de consultas sin afectar escrituras financieras; modelo de lectura optimizado para cada caso de uso | Consistencia eventual entre escritura y lectura; lag en historial y dashboard; operación de dos tecnologías de base de datos distintas |
| Database-per-Service | Autonomía total de cada bounded context; evolución independiente de esquemas; aislamiento de fallos de infraestructura | Ausencia de JOINs directos entre bases de datos de servicios distintos; complejidad de agregación de datos en el Read Model |
| Saga por orquestación (vs. coreografía) | Visibilidad centralizada del estado de cada transacción distribuida; facilidad de diagnóstico y auditoría; lógica de compensación en un lugar | Acoplamiento del orquestador (`integration-service`) con todos los participantes de la saga; cuello de botella potencial si el orquestador no escala adecuadamente |
| Reportería batch (vs. streaming) | Simplicidad operacional de jobs batch sin estado persistente; menor complejidad de infraestructura | Latencia del schedule en la disponibilidad de reportes; no apto para alertas en tiempo real (que se manejan por otro canal) |
| ETL batch como jobs Spark sin endpoints HTTP | No hay superficie de ataque HTTP adicional; los jobs se invocan desde CronJob K8s o por evento de comando; operación simplificada | Los jobs no son invocables directamente vía REST; la trazabilidad requiere logs Spark y correlación por CorrelationId |
| Centralización de integraciones en integration-service | Gobierno unificado de credenciales y SLAs externos; ACL que protege el modelo de dominio; observabilidad centralizada | Hop de red adicional para toda operación que requiera integración externa; el integration-service es un componente crítico cuya indisponibilidad bloquea depósitos, retiros y KYC |

---

## 4. Recomendación y Próximos Pasos

### Resumen Ejecutivo

Las decisiones estratégicas de esta etapa establecen PagoFacil como una plataforma financiera de microservicios event-driven con separación clara de responsabilidades por bounded context, consistencia financiera garantizada mediante Saga + Outbox, y un subsistema de reportería batch desacoplado. El stack tecnológico está completamente definido por el ADC y no es revisable. Las decisiones de CQRS (DS-CQRS-1/2/3), Database-per-Service (DS-002) y centralización de integración (DS-005) son las de mayor impacto arquitectónico y deben ser el punto de partida del Technical Design Document.

### Validaciones Pendientes Antes del Diseño Técnico

| Validación | Responsable | Prioridad |
|-----------|-------------|-----------|
| Firma de contratos con entidades financieras y definición de protocolos de integración (REST, webhooks, firma de mensajes) | Equipo de negocio / Legal | Crítica |
| Dictamen del oficial de compliance sobre el marco KYC/AML aplicable y la aplicabilidad de PCI-DSS | Oficial de Compliance | Crítica |
| Selección del proveedor KYC y confirmación de su protocolo de integración | Equipo de negocio | Alta |
| Selección de las fuentes de listas de sanciones AML y su protocolo de consumo (REST / file) | Oficial de Compliance | Alta |
| Definición del volumen inicial de usuarios activos y proyección a 12 meses para dimensionamiento de infraestructura | Equipo de negocio / Arquitectura | Alta |
| Confirmación del período exacto de retención de datos por normativa (≥ 5 años base según RN-012) | Oficial de Compliance | Media |
| Definición de la estrategia de archivado de datos históricos a largo plazo en MongoDB | Arquitectura / Infraestructura | Media |

### Próximos Pasos para el Diseño Técnico

1. **Modelado de APIs internas:** Definir los contratos REST/gRPC entre microservicios para cada bounded context, incluyendo endpoints de saga del `integration-service`.
2. **Diseño de esquemas de base de datos:** Definir el modelo de datos PostgreSQL (por servicio), el modelo de documentos MongoDB (Read Model), y la tabla `report_schema_catalog`.
3. **Diseño de topics Kafka y esquemas de eventos:** Definir los topics, grupos de consumers, esquemas Avro/JSON, y estrategia de retención de mensajes.
4. **Diseño detallado de sagas:** Especificar cada paso, su evento de compensación, y los timeouts de Narayana LRA para Saga-Deposito, Saga-Retiro y Saga-Transferencia.
5. **Diseño de la arquitectura hexagonal por servicio:** Definir ports, adapters primarios y secundarios para cada microservicio usando el template Maven.
6. **Diseño de la infraestructura Terraform:** Confirmar los módulos y variables para dev (K3d + Floci) y staging/prod (EKS + MSK + RDS + MongoDB EC2).
7. **Definición de ADRs técnicos:** Formalizar como `ADR-xxx` las decisiones técnicas de implementación que surjan del diseño detallado.

### Dependencias y Bloqueadores

- **Bloqueador crítico:** Los protocolos de integración con entidades financieras deben estar definidos antes de iniciar el diseño técnico del `integration-service`.
- **Bloqueador crítico:** El marco KYC/AML y la aplicabilidad de PCI-DSS deben confirmarse antes de diseñar el módulo de compliance de Identity y Fraud Context.
- **Dependencia:** La infraestructura dev (K3d + Floci + Kafka Docker + MongoDB Docker) debe estar operativa antes del inicio del desarrollo de microservicios.
- **Dependencia:** El proveedor KYC debe estar seleccionado antes de implementar el flujo de onboarding completo.
