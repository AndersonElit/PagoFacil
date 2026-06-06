# Strategic Design Document — Dominio y Comportamiento

**Proyecto:** PagoFacil — Billetera Digital | Parte del conjunto SDD v1.0 (domain / security / architecture)  
**Fecha:** 2026-06-06 | **Etapa:** Strategic Design / Pre-Design

---

## 1. Introducción

### Propósito

Este documento establece el modelo de dominio, el lenguaje ubicuo, los bounded contexts y el comportamiento esperado del sistema PagoFacil. Sirve como contrato conceptual entre negocio, arquitectura y desarrollo antes de iniciar el diseño técnico detallado.

### Objetivo de la Etapa

Definir los límites del sistema, el vocabulario común y los flujos de negocio relevantes con suficiente precisión para guiar las decisiones de diseño técnico, sin comprometer implementaciones específicas.

### Contexto del Sistema

PagoFacil es una plataforma fintech de billetera digital que gestiona el ciclo de vida completo de fondos electrónicos: onboarding con validación KYC, operaciones financieras (depósito, retiro, transferencia), controles de fraude y AML, auditoría regulatoria y generación de reportes. Opera como sistema multitenancy sobre arquitectura de microservicios event-driven en Kubernetes/AWS.

### Relación con el SDLC

Este documento forma parte de la etapa de Strategic Design, posterior al SRS (Análisis de Requerimientos) y anterior al Technical Design Document (TDD).

---

## 2. Visión del Dominio

El dominio central de PagoFacil es la **gestión segura y trazable de fondos electrónicos** para usuarios individuales dentro de un ecosistema fintech regulado.

### Procesos Centrales

- **Onboarding regulado:** incorporación de usuarios con validación de identidad KYC como prerequisito no negociable de activación.
- **Gestión de fondos:** depósito, retiro y transferencia con garantías de integridad financiera y trazabilidad completa.
- **Control de riesgo:** evaluación en tiempo real de transacciones contra reglas de fraude y listas de sanciones AML.
- **Cumplimiento regulatorio:** generación de reportes y gestión de alertas para el equipo de compliance.
- **Integración financiera:** conectividad bidireccional con entidades financieras y pasarelas de pago externas.

### Capacidades Principales

| Capacidad | Descripción |
|-----------|-------------|
| Gestión de Identidad | Registro, KYC, autenticación MFA y control de sesiones |
| Operaciones Financieras | Depósito, retiro y transferencia con atomicidad y trazabilidad |
| Control de Fraude y AML | Evaluación en tiempo real, verificación de sanciones, gestión de alertas |
| Auditoría y Compliance | Dashboard de revisión, reportes regulatorios exportables |
| Integración Externa | Conectividad con entidades financieras, KYC y fuentes AML |
| Reportería | Generación batch y on-demand de reportes operacionales y regulatorios |

### Objetivos del Dominio

- Garantizar que ningún fondo se pierda, duplique ni sea procesado sin autorización.
- Cumplir con los requisitos KYC y AML sin exponer fricciones regulatorias al usuario.
- Mantener trazabilidad completa e inmutable de toda operación financiera.
- Escalar las capacidades financieras sin comprometer la integridad de datos.

---

## 3. Ubiquitous Language

| Término | Definición | Contexto |
|---------|-----------|----------|
| Billetera | Cuenta de fondos electrónicos asociada a un usuario en la plataforma | Wallet |
| Saldo Disponible | Monto confirmado listo para uso inmediato en operaciones | Wallet |
| Saldo Pendiente | Fondos en tránsito cuya confirmación por parte de la entidad externa está en curso | Wallet |
| Depósito | Operación de ingreso de fondos desde una fuente externa vinculada | Wallet, Integration |
| Retiro | Operación de extracción de fondos hacia una cuenta bancaria externa registrada | Wallet, Integration |
| Transferencia | Movimiento de fondos entre dos billeteras internas de la plataforma | Wallet |
| Transacción | Registro inmutable de una operación financiera con su identificador, estado y monto | Wallet, Audit |
| CorrelationId | Identificador único que correlaciona todos los eventos, logs y trazas de una operación | Cross-cutting |
| Idempotency Key | Clave provista por el cliente para garantizar que una operación no se procese más de una vez | Wallet, Integration |
| KYC | Know Your Customer — proceso de validación de identidad obligatorio previo a la activación de cuenta | Identity |
| AML | Anti-Money Laundering — controles para prevenir el lavado de dinero, incluye verificación de listas de sanciones | Fraud |
| ROS | Reporte de Operación Sospechosa — obligación regulatoria de reportar transacciones inusuales a la autoridad competente | Fraud, Audit |
| Alerta | Notificación generada por el sistema ante un evento de riesgo, anomalía o superación de límite | Fraud, Audit |
| Límite Transaccional | Restricción configurada por el administrador sobre monto por operación o acumulado por período | Wallet |
| Tenant | Unidad de segmentación operativa — canal de distribución o cliente institucional con datos completamente aislados | Cross-cutting |
| Onboarding | Proceso completo de registro, validación KYC y activación de una cuenta de usuario | Identity |
| Sesión | Período de actividad autenticada de un usuario, acotada por expiración por inactividad | Identity |
| Motor de Fraude | Componente que evalúa transacciones en tiempo real contra un conjunto configurable de reglas | Fraud |
| Conciliación | Proceso de verificación entre registros de saldo internos y confirmaciones recibidas de entidades financieras externas | Integration, Audit |
| Entidad Financiera | Proveedor bancario o pasarela de pago externo que procesa depósitos y retiros | Integration |
| Proveedor KYC | Servicio externo de validación documental y/o biométrica usado durante el onboarding | Integration |
| Lista de Sanciones | Registros OFAC, ONU u otras fuentes de personas/entidades prohibidas para operar | Integration, Fraud |
| Outbox | Tabla auxiliar que garantiza la publicación confiable de eventos de dominio sin pérdida ante fallos | Wallet, Integration |
| Saga | Flujo transaccional distribuido compuesto por pasos locales con eventos de compensación para garantizar consistencia eventual | Integration |
| Read Model | Vista desnormalizada en MongoDB, optimizada para consultas de historial, dashboard y reportería | Audit, Reporting |
| ReportSchema | Declaración de estructura (columnas, fuente, tipos) de un tipo de reporte específico | Reporting |
| ReportType | Categoría de reporte (transacciones-diario, reporte-aml, alertas-fraude, saldo-usuarios, conciliacion) | Reporting |
| FuenteFondos | Cuenta bancaria o instrumento de pago externo registrado y validado para fondear la billetera | Wallet |
| EstadoCuenta | Condición actual de la cuenta de usuario: PENDIENTE_KYC, ACTIVA, SUSPENDIDA, BLOQUEADA | Identity |
| EstadoTransaccion | Ciclo de vida de una transacción: PENDIENTE → EN_PROCESO → CONFIRMADA \| FALLIDA \| RETENIDA | Wallet |

---

## 4. Bounded Contexts

### BC-01 — Identity

**Propósito:** Gestionar el ciclo de vida de la identidad del usuario, incluyendo registro, validación KYC, autenticación multifactor y recuperación de credenciales.

**Responsabilidades:**
- Registro y creación de cuentas en estado pendiente KYC
- Coordinación del proceso de validación KYC con el proveedor externo (vía Integration)
- Autenticación con segundo factor (MFA: TOTP, SMS, correo)
- Gestión de sesiones y expiración por inactividad
- Recuperación segura de contraseña con token de uso único

**Entidades principales:** Usuario, RegistroKYC, CredencialAutenticacion, SesionMFA

**Límites:**
- No tiene acceso directo a billeteras ni transacciones
- La activación de cuenta requiere aprobación KYC; esta regla no puede desactivarse por configuración

**Datos que posee (propietario exclusivo):**
- Tabla de usuarios (estado, datos personales, documentos de identidad)
- Registros de resultados KYC (inmutables)
- Credenciales (hash bcrypt/Argon2 + salt, nunca texto plano)
- Sesiones activas y configuración MFA

---

### BC-02 — Wallet

**Propósito:** Gestionar el saldo y las operaciones financieras de las billeteras de usuario, garantizando integridad, atomicidad e idempotencia.

**Responsabilidades:**
- Mantenimiento del saldo disponible y saldo pendiente de cada billetera
- Procesamiento de depósitos, retiros y transferencias
- Aplicación de límites transaccionales configurados
- Garantía de idempotencia mediante Idempotency Key
- Publicación de eventos de dominio vía Outbox Pattern

**Entidades principales:** Billetera, Transaccion, FuenteFondos, LimiteTransaccional

**Límites:**
- No invoca directamente a sistemas externos; delega al Integration Context
- No evalúa fraude; publica eventos para que Fraud Context los consuma
- El saldo no puede ser negativo bajo ninguna circunstancia

**Datos que posee (propietario exclusivo):**
- Tabla de billeteras (saldo disponible, saldo pendiente, tenant)
- Registro de transacciones financieras (inmutable una vez confirmada)
- Tabla outbox para publicación confiable de eventos
- Fuentes de fondos registradas por usuario

---

### BC-03 — Fraud

**Propósito:** Evaluar en tiempo real cada transacción financiera contra reglas de fraude configurables y controles AML, y gestionar el estado de las alertas generadas.

**Responsabilidades:**
- Evaluación de transacciones contra reglas de fraude (monto, frecuencia, patrón, destinatario)
- Verificación de usuarios y contrapartes contra listas de sanciones AML (OFAC, ONU)
- Clasificación y bloqueo o retención de transacciones sospechosas
- Generación de alertas con severidad clasificada
- Preparación de datos para ROS (Reporte de Operación Sospechosa)

**Entidades principales:** ReglaFraude, AlertaFraude, VerificacionAML, ResultadoEvaluacion

**Límites:**
- No modifica el saldo de billeteras; emite decisiones que el Wallet Context aplica
- No expone la razón regulatoria AML al usuario final

**Datos que posee (propietario exclusivo):**
- Catálogo de reglas de fraude y su configuración
- Resultados de evaluaciones (inmutables)
- Alertas generadas y su historial de estado
- Cache de listas de sanciones (sincronizado desde Integration)

---

### BC-04 — Notification

**Propósito:** Emitir comunicaciones a usuarios y administradores ante eventos relevantes del sistema.

**Responsabilidades:**
- Envío de notificaciones transaccionales (depósito confirmado, retiro procesado, transferencia recibida)
- Notificación de eventos de seguridad (nuevo acceso, cambio de contraseña, bloqueo de cuenta)
- Alertas operacionales a administradores (degradación, discrepancias de conciliación)

**Entidades principales:** Notificacion, PlantillaNotificacion, Canal

**Límites:**
- Contexto consumidor puro; no inicia operaciones financieras
- No persiste estado de negocio; sus datos son de entrega, no de auditoría

**Datos que posee (propietario exclusivo):**
- Registro de notificaciones enviadas (estado, canal, timestamp)
- Plantillas por tipo de evento

---

### BC-05 — Audit

**Propósito:** Proveer capacidades de revisión, gestión de alertas y generación de reportes regulatorios para auditores y administradores.

**Responsabilidades:**
- Dashboard de búsqueda y revisión de transacciones por identificador, usuario, fecha o estado
- Gestión de alertas de fraude y AML (aprobar/rechazar con justificación registrada)
- Generación y exportación de reportes regulatorios (PDF/CSV)
- Visualización de métricas operacionales

**Entidades principales:** EntradaAuditoria, AlertaGestionada, ReporteRegulatorio

**Límites:**
- Contexto de lectura; opera sobre el Read Model (MongoDB) proyectado desde Wallet y Fraud
- Los registros de auditoría son inmutables; no se permite update ni delete

**Datos que posee (propietario exclusivo):**
- Read Model MongoDB: colecciones `transacciones`, `alertas`, `alertas_aml`, `billeteras`, `conciliaciones`
- Decisiones de auditoría sobre alertas (inmutables)

---

### BC-06 — Integration

**Propósito:** Centralizar toda la conectividad con sistemas externos, aplicar el patrón ACL para proteger el modelo de dominio interno, y orquestar las sagas transaccionales distribuidas mediante Apache Camel y Narayana LRA.

**Responsabilidades:**
- Comunicación saliente con entidades financieras (fondeo, instrucción de pago)
- Recepción de webhooks de confirmación de entidades financieras
- Integración saliente con proveedor KYC
- Sincronización de listas de sanciones AML
- Orquestación de sagas: Saga-Deposito, Saga-Retiro, Saga-Transferencia
- Coordinación de la conciliación automática
- Traducción de modelos externos al lenguaje ubicuo interno (ACL)

**Entidades principales:** SolicitudExterna, ConfirmacionExterna, EstadoSaga, RegistroConciliacion

**Límites:**
- Único contexto autorizado para comunicarse directamente con sistemas externos
- Los demás bounded contexts no hablan directamente con sistemas fuera del cluster

**Datos que posee (propietario exclusivo):**
- Estado de instancias de saga (LRA)
- Registro de solicitudes y confirmaciones externas
- Outbox de mensajes salientes

---

### BC-07 — Reporting

**Propósito:** Gestionar el subsistema de reportería: extracción batch de datos desde el Read Model, transformación por tipo de reporte y entrega en los formatos requeridos.

**Responsabilidades:**
- Definición y mantenimiento del catálogo de esquemas de reporte (`report_schema_catalog`)
- Extracción de datos desde el Read Model MongoDB (MS1 — `report-extraction-service`, Spark batch)
- Transformación y validación por tipo de reporte (MS2 — `report-processing-service`, Spark batch)
- Publicación de eventos `ReporteExtraido` y `ReporteProcesado` a Kafka
- Entrega de formatos finales (PDF, XLS, CSV) mediante capa serverless Lambda + EventBridge

**Entidades principales:** ReportSchema, ReportJob, ReportOutput

**Límites:**
- Contexto consumidor del Read Model de Audit; no accede directamente a las bases de datos operacionales de dominio
- MS1 y MS2 son jobs batch ejecutados por schedule (CronJob K8s) o por evento de comando on-demand; no son servicios REST persistentes

**Datos que posee (propietario exclusivo):**
- Tabla `report_schema_catalog` (PostgreSQL dedicada del contexto de reportería)
- Archivos Parquet intermedios (S3, contrato entre MS1 y MS2)
- Archivos de reporte finales (S3, bucket `pagofacil-reports`)

---

## 5. Context Map

### Relaciones entre Contextos Internos

| Contexto Upstream | Contexto Downstream | Tipo de Relación | Mecanismo | Notas |
|---|---|---|---|---|
| Identity | Wallet | Customer / Supplier | Evento de dominio Kafka (`CuentaActivada`) | Wallet valida estado de cuenta antes de operar |
| Wallet | Fraud | Publisher / Subscriber | Evento Kafka (`TransaccionIniciada`) | Fraud evalúa y publica decisión |
| Fraud | Wallet | Callback via Saga | Evento Kafka (`EvaluacionAprobada`, `TransaccionRetenida`) | Integration orquesta la coordinación |
| Wallet | Notification | Publisher / Subscriber | Evento Kafka | Notificaciones de operaciones confirmadas/fallidas |
| Fraud | Notification | Publisher / Subscriber | Evento Kafka (`AlertaGenerada`) | Notificación de retención a usuario y admin |
| Wallet | Audit | Publisher → Projection | Evento Kafka → Read Model MongoDB | Projection Service proyecta estado a Read Model |
| Fraud | Audit | Publisher → Projection | Evento Kafka → Read Model MongoDB | Alertas y resultados AML proyectados |
| Identity | Audit | Publisher → Projection | Evento Kafka → Read Model MongoDB | Eventos de acceso y KYC proyectados |
| Audit | Reporting | Customer / Supplier | Read Model MongoDB compartido | Reporting es conformista; lee sin escritura |
| Integration | Wallet | Orquestador / Saga | REST interno + Kafka | Coordina débito/crédito en sagas de depósito y retiro |
| Integration | Fraud | Coordinación Saga | REST interno | Solicita evaluación de fraude en flujo de retiro |
| Integration | Identity | Coordinación | REST interno | Transmite resultado KYC al contexto de identidad |
| Integration | Notification | Publisher | Evento Kafka | Notificaciones de resultado de integración externa |

### Sistemas Externos (ACL — Anti-Corruption Layer)

Todos los sistemas externos se modelan como contextos upstream. El Integration Context actúa como ACL que traduce sus modelos al lenguaje ubicuo de PagoFacil. Ningún bounded context interno se comunica directamente con sistemas externos.

| Sistema Externo | Dirección | Criticidad | Notas |
|---|---|---|---|
| Entidades Financieras / Pasarelas de Pago | Saliente + Entrante (webhook) | Alta | Fondeo, instrucción de pago, confirmaciones; contratos pendientes de firma |
| Proveedor KYC | Saliente | Alta | Validación documental/biométrica en onboarding; proveedor por definir |
| Listas de Sanciones AML (OFAC, ONU) | Saliente | Alta | Sincronización periódica; REST o file según proveedor |
| AWS Cognito | Entrante (autenticación) | Alta | Identity Provider externo; emite JWT validados por API Gateway |

### Flujos de Saga (Coordinación entre Contextos)

| Saga | Contextos Participantes | Orquestador | Pasos con Compensación |
|---|---|---|---|
| Saga-Deposito | Integration, Wallet, Notification | Integration (Narayana LRA) | Reversión de saldo pendiente si entidad financiera rechaza fondeo |
| Saga-Retiro | Integration, Wallet, Fraud, Notification | Integration (Narayana LRA) | Liberación de fondos reservados si entidad financiera rechaza instrucción de pago; cancelación de retención si fraude retiene post-reserva |
| Saga-Transferencia | Wallet (ACID), Fraud, Notification | Integration (Narayana LRA) | Débito+crédito atómico en PostgreSQL; compensación aplica si fraude retiene post-débito (retención tardía) |
| Conciliacion | Integration, Wallet, Audit | Integration | Registro de discrepancia y alerta; no requiere rollback de saldo |

---

## 6. Modelos de Dominio

### Aggregate: Usuario

**Responsabilidad:** Gestionar el ciclo de vida de la identidad del usuario, desde el registro hasta la activación y el mantenimiento de sus credenciales.

**Entidades:**
- CredencialAutenticacion
- RegistroKYC

**Value Objects:**
- Email (único en la plataforma)
- DocumentoIdentidad (único en la plataforma)
- EstadoCuenta (PENDIENTE_KYC | ACTIVA | SUSPENDIDA | BLOQUEADA)
- TenantId
- ConfiguracionMFA

**Reglas importantes:**
- La transición a ACTIVA solo es posible cuando el RegistroKYC tiene resultado APROBADO.
- Las contraseñas se almacenan únicamente como hash (bcrypt o Argon2) con salt único; nunca en texto plano.
- El bloqueo de cuenta se activa automáticamente tras N intentos fallidos consecutivos (N configurable).

---

### Aggregate: Billetera

**Responsabilidad:** Mantener el estado financiero del usuario y garantizar que toda operación cumpla las reglas de integridad (saldo no negativo, límites, atomicidad).

**Entidades:**
- MovimientoFondos
- FuenteFondos

**Value Objects:**
- Saldo (disponible: Decimal, pendiente: Decimal)
- LimitesTransaccionales (maxPorOperacion, maxDiario, maxMensual, maxOperacionesPorPeriodo)
- UsuarioId
- TenantId

**Reglas importantes:**
- El Saldo disponible no puede ser negativo bajo ninguna circunstancia.
- Los LimitesTransaccionales configurados por el administrador tienen precedencia; el usuario no puede elevarlos.
- Los fondos depositados incrementan el Saldo pendiente hasta recibir confirmación externa; solo entonces pasan a disponible.

---

### Aggregate: Transaccion

**Responsabilidad:** Representar el registro inmutable de una operación financiera individual con su ciclo de vida completo.

**Value Objects:**
- TransaccionId (UUID v4)
- CorrelationId
- IdempotencyKey
- Monto (Decimal, positivo)
- TipoOperacion (DEPOSITO | RETIRO | TRANSFERENCIA)
- EstadoTransaccion (PENDIENTE → EN_PROCESO → CONFIRMADA | FALLIDA | RETENIDA)
- FechaHoraCreacion
- FechaHoraResolucion

**Reglas importantes:**
- Una Transaccion en estado CONFIRMADA es inmutable; no puede modificarse ni revertirse unilateralmente.
- La idempotencia se garantiza por IdempotencyKey: reintentos devuelven el resultado original.
- Cada Transaccion genera un evento de dominio que se persiste en la tabla Outbox antes de confirmar la operación local.

---

### Aggregate: AlertaFraude

**Responsabilidad:** Representar una transacción retenida por el motor de fraude, incluyendo la justificación, severidad y la decisión del auditor.

**Entidades:**
- EvaluacionRegla (regla disparada, valor de activación)
- DecisionAuditor (aprobada/rechazada, justificación, timestamp, auditorId)

**Value Objects:**
- AlertaId
- SeveridadAlerta (BAJA | MEDIA | ALTA | CRITICA)
- EstadoAlerta (PENDIENTE | APROBADA | RECHAZADA)
- TransaccionId

**Reglas importantes:**
- Una AlertaFraude en estado PENDIENTE no expira automáticamente; requiere acción de un auditor autorizado.
- La DecisionAuditor es inmutable una vez registrada.

---

### Aggregate: SagaInstance

**Responsabilidad:** Rastrear el estado de una transacción distribuida orquestada por el Integration Context, incluyendo los pasos completados y los eventos de compensación pendientes.

**Entidades:**
- PasoSaga (nombre, estado, timestamp)
- EventoCompensacion (tipo, payload, estado)

**Value Objects:**
- SagaId
- TipoSaga (DEPOSITO | RETIRO | TRANSFERENCIA | CONCILIACION)
- EstadoSaga (INICIADA | EN_PROGRESO | COMPLETADA | COMPENSANDO | COMPENSADA | FALLIDA)
- CorrelationId

**Reglas importantes:**
- Ante fallo en cualquier paso, la saga debe ejecutar los eventos de compensación en orden inverso.
- El estado de la saga es consultable en todo momento para diagnóstico operacional.

---

## 7. Eventos de Dominio

### BC-01 — Identity

---

#### DE-001 — UsuarioRegistrado

**Descripción:** Un nuevo usuario completó el formulario de registro con datos válidos y únicos.

**Disparadores:**
- El sistema valida unicidad de email y documento de identidad.
- El sistema crea la cuenta en estado PENDIENTE_KYC.

**Consecuencias:**
- Se envía correo de confirmación al email registrado.
- Se inicia el proceso KYC.

---

#### DE-002 — KYCAprobado

**Descripción:** El proveedor KYC devolvió resultado satisfactorio para el proceso de validación de identidad del usuario.

**Disparadores:**
- Integration Context recibe respuesta de aprobación del proveedor KYC.

**Consecuencias:**
- Identity Context actualiza el estado de cuenta a ACTIVA.
- Se publica DE-003 (CuentaActivada).

---

#### DE-003 — CuentaActivada

**Descripción:** La cuenta del usuario quedó habilitada para ejecutar operaciones financieras.

**Disparadores:**
- KYCAprobado fue procesado correctamente.

**Consecuencias:**
- Wallet Context crea la billetera asociada con saldo cero.
- El usuario puede configurar MFA y operar en la plataforma.

---

#### DE-004 — KYCRechazado

**Descripción:** El proveedor KYC devolvió resultado de rechazo para el proceso de validación de identidad.

**Disparadores:**
- Integration Context recibe respuesta de rechazo del proveedor KYC.

**Consecuencias:**
- La cuenta permanece en estado PENDIENTE_KYC o pasa a BLOQUEADA según configuración.
- Se notifica al usuario sin exponer la razón regulatoria específica.

---

#### DE-005 — SesionIniciada

**Descripción:** Un usuario completó exitosamente la autenticación con ambos factores.

**Disparadores:**
- Credenciales válidas + código MFA verificado.

**Consecuencias:**
- Se emite token de sesión con tiempo de expiración configurable.
- Se registra el evento para auditoría de accesos.

---

#### DE-006 — ContrasenaRestablecida

**Descripción:** El usuario completó el flujo de recuperación y estableció una nueva contraseña.

**Disparadores:**
- Token de recuperación válido y no expirado utilizado.

**Consecuencias:**
- Todas las sesiones activas previas son invalidadas inmediatamente.
- Se notifica al usuario del cambio.

---

### BC-02 — Wallet

---

#### DE-007 — DepositoIniciado

**Descripción:** El usuario solicitó un depósito de fondos desde una fuente externa; el sistema registró la operación en estado PENDIENTE.

**Disparadores:**
- Usuario autenticado solicita depósito con monto dentro de límites configurados.

**Consecuencias:**
- Se incrementa el Saldo pendiente.
- Integration Context inicia la saga de depósito.

---

#### DE-008 — DepositoConfirmado

**Descripción:** La entidad financiera externa confirmó el fondeo; los fondos están disponibles en la billetera.

**Disparadores:**
- Integration Context recibe confirmación de la entidad financiera.

**Consecuencias:**
- Saldo pendiente se convierte en Saldo disponible.
- Se notifica al usuario.
- Se proyecta al Read Model.

**Evento de compensación:** DE-009 — DepositoRevertido

---

#### DE-009 — DepositoRevertido

**Descripción:** El depósito fue revertido por rechazo de la entidad financiera o fallo de la saga.

**Disparadores:**
- Integration Context recibe rechazo de la entidad financiera durante Saga-Deposito.

**Consecuencias:**
- El Saldo pendiente vuelve a cero para esta operación.
- La transacción queda en estado FALLIDA.
- Se notifica al usuario.

---

#### DE-010 — RetiroIniciado

**Descripción:** El usuario solicitó un retiro; los fondos fueron reservados del Saldo disponible.

**Disparadores:**
- Usuario autenticado solicita retiro con saldo suficiente y dentro de límites.

**Consecuencias:**
- Saldo disponible decrementado; fondos reservados.
- Integration Context inicia Saga-Retiro.

---

#### DE-011 — RetiroConfirmado

**Descripción:** La entidad financiera procesó exitosamente la instrucción de pago del retiro.

**Disparadores:**
- Integration Context recibe confirmación de la entidad financiera.

**Consecuencias:**
- Fondos reservados eliminados definitivamente.
- Se notifica al usuario.

**Evento de compensación:** DE-012 — FondosLiberados

---

#### DE-012 — FondosLiberados

**Descripción:** Los fondos reservados para un retiro fueron liberados de vuelta al Saldo disponible por fallo del proceso externo.

**Disparadores:**
- Saga-Retiro detecta rechazo de la instrucción de pago.

**Consecuencias:**
- Saldo disponible restaurado.
- Transacción marcada como FALLIDA.
- Se notifica al usuario.

---

#### DE-013 — TransferenciaIniciada

**Descripción:** El remitente confirmó una transferencia; el débito y el crédito se ejecutarán de forma atómica.

**Disparadores:**
- Remitente confirma explícitamente la operación con saldo disponible suficiente.

**Consecuencias:**
- Débito del remitente y crédito del destinatario ejecutados en la misma transacción ACID de PostgreSQL.
- Evaluación de fraude iniciada.

---

#### DE-014 — TransferenciaConfirmada

**Descripción:** La transferencia fue procesada exitosamente y ambas billeteras actualizadas.

**Disparadores:**
- Motor de fraude aprobó la operación.

**Consecuencias:**
- Saldos actualizados en ambas billeteras.
- Ambas partes notificadas.
- Proyectado al Read Model.

**Evento de compensación:** DE-015 — TransferenciaCompensada

---

#### DE-015 — TransferenciaCompensada

**Descripción:** La transferencia fue revertida tras retención tardía por el motor de fraude post-débito.

**Disparadores:**
- Fraud Context retiene la transacción después de que el débito+crédito ACID fue ejecutado.

**Consecuencias:**
- Se ejecuta transacción compensatoria ACID: crédito al remitente, débito al destinatario.
- Transacción marcada como RETENIDA pendiente revisión auditor.

---

### BC-03 — Fraud

---

#### DE-016 — TransaccionRetenidaPorFraude

**Descripción:** El motor de fraude determinó que una transacción es sospechosa y la retuvo para revisión manual.

**Disparadores:**
- Una regla de fraude configurada como "revisión" fue activada por la transacción.

**Consecuencias:**
- La transacción pasa a estado RETENIDA.
- Se genera una AlertaFraude con severidad correspondiente.
- El usuario es notificado sin exponer la razón regulatoria.

---

#### DE-017 — TransaccionRechazadaPorAML

**Descripción:** El sistema detectó que el usuario o contraparte figura en una lista de sanciones activa.

**Disparadores:**
- Verificación AML retorna match con lista de sanciones (OFAC, ONU u otras configuradas).

**Consecuencias:**
- La transacción es rechazada inmediatamente.
- Se genera evento auditable sin exponer la razón regulatoria al usuario.
- Se registra para potencial generación de ROS.

---

#### DE-018 — AlertaResuelta

**Descripción:** Un auditor autorizado tomó una decisión sobre una alerta de fraude pendiente.

**Disparadores:**
- El auditor aprueba o rechaza la transacción desde el dashboard con justificación registrada.

**Consecuencias:**
- Integration Context procesa o cancela la transacción según la decisión.
- El usuario es notificado del resultado.
- La DecisionAuditor queda registrada de forma inmutable.

---

### BC-04 — Integration

---

#### DE-019 — DiscrepanciaDetectada

**Descripción:** El proceso de conciliación automática identificó una diferencia entre el saldo interno y los registros de la entidad financiera.

**Disparadores:**
- Proceso de conciliación programado (timer Camel) detecta diferencia.

**Consecuencias:**
- Se genera una alerta para revisión manual por el equipo de operaciones o compliance.
- Se registra la discrepancia en el Read Model de Audit.

---

### BC-07 — Reporting

---

#### DE-020 — ReporteExtraido

**Descripción:** El job MS1 (`report-extraction-service`) completó exitosamente la extracción de datos desde el Read Model y generó el archivo Parquet intermedio.

**Disparadores:**
- Schedule CronJob K8s dispara MS1 según expresión configurada, o evento de comando on-demand desde el dashboard.

**Consecuencias:**
- Archivo Parquet disponible en S3 como contrato de entrada para MS2.
- Evento publicado en Kafka topic `report.extracted` para consumo de MS2.

**Evento de compensación:** DE-022 — ExtracionFallida

---

#### DE-021 — ReporteProcesado

**Descripción:** El job MS2 (`report-processing-service`) transformó el Parquet según el ReportSchema y generó el archivo de reporte final.

**Disparadores:**
- MS2 consume `ReporteExtraido` desde Kafka y completa la transformación.

**Consecuencias:**
- Archivo de reporte publicado en S3 bucket `pagofacil-reports`.
- Evento publicado en topic `report.processed` para consumo de la capa serverless Lambda.
- Lambda + EventBridge entregan el reporte en el formato requerido (PDF/XLS/CSV).

**Evento de compensación:** DE-023 — ProcesamientoFallido

---

#### DE-022 — ExtracionFallida

**Descripción:** MS1 no pudo completar la extracción de datos por error de conectividad con el Read Model o esquema inválido.

**Disparadores:**
- Excepción no recuperable en el job Spark MS1.

**Consecuencias:**
- Se registra el fallo con CorrelationId y causa.
- Se genera alerta operacional.
- No se publica `ReporteExtraido`; el flujo no avanza a MS2.

---

#### DE-023 — ProcesamientoFallido

**Descripción:** MS2 no pudo transformar el Parquet al formato de reporte requerido.

**Disparadores:**
- Excepción en transformación Spark (esquema incompatible, datos corruptos).

**Consecuencias:**
- Se registra el fallo.
- Se genera alerta operacional.
- El archivo Parquet intermedio se conserva para reintento manual.

---

## 8. Workflows de Negocio

### Workflow: Onboarding y Activación de Cuenta

1. El usuario completa el formulario de registro (nombre, email, documento, contraseña).
2. El sistema valida unicidad de email y documento; rechaza duplicados con mensaje descriptivo.
3. La cuenta se crea en estado PENDIENTE_KYC; se envía confirmación al email registrado.
4. El usuario inicia el proceso KYC proveyendo documentación requerida.
5. Integration Context envía la solicitud al proveedor KYC externo.
6. El proveedor KYC retorna resultado (APROBADO / RECHAZADO / EN_REVISION).
7. Si APROBADO: la cuenta pasa a ACTIVA y se crea la billetera con saldo cero.
8. El usuario configura el segundo factor de autenticación (MFA).
9. La cuenta queda lista para operar.

---

### Workflow: Depósito de Fondos (Saga-Deposito)

1. El usuario selecciona la fuente de fondos y especifica el monto.
2. El sistema verifica que el monto cumple los límites transaccionales configurados.
3. Se genera un TransaccionId único y se registra el depósito en estado PENDIENTE; el Saldo pendiente incrementa.
4. Integration Context inicia Saga-Deposito y envía la solicitud de fondeo a la entidad financiera.
5. La entidad financiera responde (confirmación o rechazo).
6. Si confirmado: el saldo pendiente pasa a disponible; transacción en CONFIRMADA; usuario notificado.
7. Si rechazado: saga ejecuta compensación — saldo pendiente revertido; transacción en FALLIDA; usuario notificado.

---

### Workflow: Retiro de Fondos (Saga-Retiro)

1. El usuario selecciona la cuenta de destino y el monto a retirar.
2. El sistema verifica saldo disponible suficiente y límites configurados.
3. Se genera TransaccionId; fondos reservados del Saldo disponible; transacción en PENDIENTE.
4. Integration Context solicita evaluación al motor de Fraud.
5. Si Fraud retiene: transacción pasa a RETENIDA; fondos permanecen reservados hasta resolución de auditor.
6. Si Fraud aprueba: Integration envía instrucción de pago a la entidad financiera.
7. La entidad financiera responde (confirmación o rechazo).
8. Si confirmado: fondos reservados liberados definitivamente; transacción en CONFIRMADA; usuario notificado.
9. Si rechazado: saga ejecuta compensación — fondos liberados al Saldo disponible; transacción en FALLIDA.

---

### Workflow: Transferencia entre Usuarios

1. El remitente ingresa el identificador del destinatario (email o alias) y el monto.
2. El sistema resuelve y muestra los datos del destinatario; el remitente confirma explícitamente.
3. El sistema verifica saldo disponible, límites y ejecuta evaluación de fraude previa.
4. Si aprobado por Fraud: débito del remitente y crédito del destinatario se ejecutan de forma atómica en una transacción ACID.
5. Ambas billeteras actualizadas; ambas partes notificadas; transacción en CONFIRMADA.
6. Si Fraud retiene post-débito (retención tardía): saga ejecuta compensación ACID — crédito al remitente, débito al destinatario; transacción en RETENIDA.

---

### Workflow: Evaluación de Fraude en Tiempo Real

1. Wallet Context publica evento `TransaccionIniciada` a Kafka.
2. Fraud Context consume el evento y evalúa contra el conjunto de reglas activas.
3. Reglas evaluadas: monto inusual, frecuencia, destinatario nuevo, geolocalización, patrones históricos.
4. Verificación AML: usuario y contraparte evaluados contra listas de sanciones activas.
5. Si todas las reglas pasan: se publica `EvaluacionAprobada`; la transacción continúa.
6. Si una regla de bloqueo activa: transacción rechazada inmediatamente; se genera alerta.
7. Si una regla de revisión activa: transacción retenida; alerta generada para dashboard de auditoría.

---

### Workflow: Revisión de Alerta de Fraude (Manual)

1. El auditor accede al dashboard y filtra alertas en estado PENDIENTE.
2. El auditor revisa el detalle completo de la transacción retenida (historial, reglas activadas, contexto del usuario).
3. El auditor toma una decisión: APROBAR o RECHAZAR, con justificación obligatoria registrada.
4. Si APROBADA: Integration Context procesa la transacción; usuario notificado.
5. Si RECHAZADA: transacción cancelada; fondos liberados o revertidos según corresponda; usuario notificado.
6. La decisión queda registrada de forma inmutable con el auditorId y timestamp.

---

### Workflow: Generación de Reporte Regulatorio

1. El CronJob K8s dispara MS1 (`report-extraction-service`) según schedule, o el auditor dispara on-demand desde el dashboard.
2. MS1 (Spark batch) extrae datos del Read Model MongoDB usando el ReportSchema declarado.
3. MS1 publica el archivo Parquet a S3 y emite evento `ReporteExtraido` a Kafka.
4. MS2 (`report-processing-service`, Spark batch) consume el evento, aplica las transformaciones del ReportType usando el patrón Factory.
5. MS2 publica el archivo procesado a S3 y emite evento `ReporteProcesado` a Kafka.
6. Lambda Kafka Consumer recibe el evento; EventBridge lo enruta a la lambda del formato correspondiente (PDF/XLS/CSV).
7. La lambda genera el archivo en el formato requerido y lo deposita en el bucket `pagofacil-reports`.
8. El auditor descarga el reporte desde el dashboard.

---

## 9. Escenarios BDD

```gherkin
Feature: Registro y Activación de Cuenta

  Scenario: Registro exitoso con KYC aprobado
    Given un usuario nuevo con email "usuario@ejemplo.com" no registrado en la plataforma
    When el usuario completa el formulario con datos válidos y únicos
    Then el sistema crea la cuenta en estado PENDIENTE_KYC
    And envía un correo de confirmación al email registrado

  Scenario: Activación de cuenta tras aprobación KYC
    Given una cuenta en estado PENDIENTE_KYC con proceso KYC enviado
    When el proveedor KYC retorna resultado APROBADO
    Then la cuenta pasa a estado ACTIVA
    And se crea la billetera con saldo disponible de 0
    And el usuario puede configurar MFA y operar en la plataforma

  Scenario: Registro rechazado por email duplicado
    Given un usuario registrado con email "existente@ejemplo.com"
    When un nuevo usuario intenta registrarse con el mismo email
    Then el sistema rechaza el registro con mensaje de error descriptivo
    And no se crea ninguna cuenta nueva

  Scenario: Cuenta permanece inactiva hasta aprobación KYC
    Given una cuenta en estado PENDIENTE_KYC
    When el usuario intenta ejecutar un depósito
    Then el sistema rechaza la operación con mensaje indicando cuenta no activa
    And no se genera ninguna transacción
```

```gherkin
Feature: Autenticación con MFA

  Scenario: Autenticación exitosa con dos factores
    Given un usuario con cuenta ACTIVA y MFA configurado
    When el usuario ingresa credenciales válidas y un código TOTP válido
    Then el sistema emite un token de sesión con expiración configurada
    And registra el evento de acceso para auditoría

  Scenario: Bloqueo de cuenta por intentos fallidos consecutivos
    Given un usuario con cuenta ACTIVA
    When el usuario falla la autenticación N veces consecutivas (N configurable)
    Then el sistema bloquea la cuenta automáticamente
    And notifica al usuario del bloqueo
    And registra el evento de bloqueo para auditoría

  Scenario: Expiración de sesión por inactividad
    Given un usuario con sesión activa
    When el período de inactividad configurado transcurre sin actividad
    Then el sistema expira la sesión automáticamente
    And las operaciones ya encoladas no son canceladas ni revertidas
```

```gherkin
Feature: Depósito de Fondos

  Scenario: Depósito exitoso confirmado por entidad financiera
    Given un usuario autenticado con cuenta ACTIVA y fuente de fondos registrada
    When el usuario solicita un depósito de 500 dentro de los límites configurados
    Then el sistema registra la transacción con TransaccionId único en estado PENDIENTE
    And el saldo pendiente incrementa en 500
    When la entidad financiera confirma el fondeo
    Then el saldo disponible incrementa en 500
    And el saldo pendiente vuelve a cero para esta operación
    And el usuario recibe notificación de depósito confirmado

  Scenario: Depósito rechazado por límite transaccional
    Given un usuario autenticado con límite máximo de 1000 por operación
    When el usuario solicita un depósito de 1500
    Then el sistema rechaza la solicitud con mensaje descriptivo de límite excedido
    And no se genera ninguna transacción
    And no se contacta a la entidad financiera

  Scenario: Compensación de depósito por rechazo de entidad financiera
    Given un depósito iniciado en estado PENDIENTE con saldo pendiente incrementado
    When la entidad financiera retorna rechazo del fondeo
    Then la saga ejecuta la compensación
    And el saldo pendiente vuelve al valor previo
    And la transacción queda en estado FALLIDA
    And el usuario recibe notificación del resultado
```

```gherkin
Feature: Transferencia entre Usuarios

  Scenario: Transferencia exitosa entre usuarios activos
    Given un remitente autenticado con saldo disponible de 300
    And un destinatario con cuenta ACTIVA identificado por email "destino@ejemplo.com"
    When el remitente solicita transferir 100 y confirma explícitamente la operación
    And el motor de fraude aprueba la transacción
    Then el saldo del remitente decrece en 100
    And el saldo del destinatario incrementa en 100
    And ambas operaciones son atómicas (no existe estado intermedio)
    And ambas partes reciben notificación de la transferencia

  Scenario: Transferencia rechazada por saldo insuficiente
    Given un remitente con saldo disponible de 50
    When el remitente solicita transferir 200
    Then el sistema rechaza la operación antes de cualquier débito
    And ningún saldo es modificado

  Scenario: Idempotencia en transferencia duplicada
    Given una transferencia ya confirmada con IdempotencyKey "key-abc-123"
    When el sistema recibe la misma solicitud con IdempotencyKey "key-abc-123"
    Then el sistema devuelve el resultado de la operación original
    And no se genera ninguna transacción adicional
    And ningún saldo es modificado nuevamente
```

```gherkin
Feature: Detección de Fraude

  Scenario: Transacción retenida por regla de fraude configurada como revisión
    Given una transacción de retiro iniciada por un usuario
    When el motor de fraude activa una regla de revisión (monto inusual para el perfil)
    Then la transacción pasa a estado RETENIDA
    And se genera una AlertaFraude visible en el dashboard de auditoría en menos de 30 segundos
    And el usuario recibe notificación sin exposición de la razón regulatoria

  Scenario: Transacción rechazada por coincidencia con lista de sanciones AML
    Given un usuario que intenta transferir fondos a un destinatario en lista OFAC
    When el sistema ejecuta la verificación AML
    Then la transacción es rechazada inmediatamente
    And se genera un registro auditable del rechazo
    And el usuario recibe mensaje de rechazo sin exposición de la razón regulatoria

  Scenario: Auditor resuelve alerta de fraude aprobando la transacción
    Given una AlertaFraude en estado PENDIENTE con transacción retenida
    When el auditor revisa el detalle y aprueba la transacción con justificación registrada
    Then la transacción es procesada
    And la AlertaFraude pasa a estado APROBADA
    And la decisión del auditor queda registrada de forma inmutable
    And el usuario es notificado del resultado
```

```gherkin
Feature: Generación de Reporte Regulatorio

  Scenario: Generación exitosa de reporte AML on-demand
    Given un auditor con acceso autorizado al dashboard de auditoría
    When el auditor solicita el reporte "reporte-aml" para el período del mes corriente
    Then MS1 extrae los datos del Read Model MongoDB según el ReportSchema declarado
    And MS2 transforma los datos en el formato regulatorio requerido
    And el reporte está disponible para descarga en formato CSV
    And el reporte contiene todos los campos definidos en el esquema (fecha, usuario_id, monto, tipo_operacion, resultado_aml, lista_sancion_match, estado_revision)

  Scenario: Reporte programado diario de transacciones
    Given el CronJob K8s configurado con expresión "0 * * * *"
    When el schedule se activa
    Then MS1 extrae el reporte "transacciones-diario" del Read Model
    And MS2 genera los archivos en formatos PDF y CSV
    And los archivos quedan disponibles en el bucket "pagofacil-reports"
```
