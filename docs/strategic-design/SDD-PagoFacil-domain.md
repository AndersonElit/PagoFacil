# Strategic Design Document — Dominio y Comportamiento

**Proyecto:** PagoFacil — Billetera Digital
**Conjunto SDD:** Este documento forma parte del Strategic Design Document junto con `SDD-PagoFacil-security.md` y `SDD-PagoFacil-architecture.md`.
**Versión:** 1.0
**Fecha:** 2026-06-08

---

## 1. Introducción

**Propósito:** Modelar el dominio de negocio de PagoFacil, establecer el lenguaje ubicuo, definir los bounded contexts y sus relaciones, documentar los eventos de dominio relevantes y capturar el comportamiento esperado del sistema mediante escenarios verificables.

**Objetivo de la etapa:** Establecer las bases conceptuales y estratégicas del dominio antes de iniciar el diseño técnico detallado. Este documento traduce los requerimientos funcionales del SRS en un modelo de dominio cohesivo, claro y orientado al negocio.

**Contexto del sistema:** PagoFacil es una plataforma fintech de billetera digital multitenancy que gestiona el ciclo completo de fondos electrónicos: onboarding con validación KYC, operaciones financieras (depósito, transferencia, retiro), controles de compliance AML, monitoreo antifraude en tiempo real, integración con el ecosistema financiero externo y generación de reportes regulatorios.

**Relación con SDLC:** Esta etapa es la transición entre Análisis de Requerimientos (SRS) y Diseño Técnico. Su propósito es definir dominio, comportamiento y límites — no implementación.

---

## 2. Visión del Dominio

**Dominio de negocio:** Infraestructura financiera para gestión de fondos electrónicos con controles regulatorios integrados.

**Procesos centrales:**
- Incorporación de usuarios con validación de identidad (KYC/AML)
- Gestión de billeteras digitales y operaciones financieras
- Control de riesgo y compliance en tiempo real
- Integración con el ecosistema financiero externo (entidades financieras, pasarelas de pago)
- Auditoría inmutable de eventos de negocio y reportería regulatoria

**Capacidades principales:**
- Onboarding verificado y seguro de usuarios con validación KYC biométrica
- Operaciones financieras confiables, idempotentes y trazables
- Detección de fraude y validación AML antes de ejecutar cada operación
- Conciliación automática con sistemas financieros externos
- Generación de reportes regulatorios (ROS/SAR, volumen transaccional, alertas AML)
- Soporte multitenancy con aislamiento de datos y configuración por organización

**Objetivo del dominio:** Proveer a las organizaciones (tenants) una infraestructura de pagos propia, auditable y compliant, eliminando la dependencia de terceros para operaciones financieras críticas y sentando las bases para la expansión futura del ecosistema de pagos.

---

## 3. Ubiquitous Language

| Término | Definición | Contexto |
|---------|-----------|---------|
| Usuario | Persona natural registrada en la plataforma con identidad verificada | Identity, Wallet |
| Billetera Digital | Cuenta electrónica que almacena fondos virtuales asociada a un usuario registrado | Wallet |
| Saldo Disponible | Monto de fondos confirmados y operativos en una billetera; excluye fondos en reserva | Wallet |
| KYC | Proceso de verificación de identidad (*Know Your Customer*) exigido para operar financieramente | Identity, Compliance |
| Estado KYC | Estado actual del proceso de validación de identidad del usuario: Pendiente, Aprobado, Rechazado, Suspendido | Identity, Compliance |
| Onboarding | Proceso de registro, verificación de identidad y activación de cuenta del usuario | Identity |
| Operación Financiera | Evento de negocio que modifica el saldo de una o más billeteras: depósito, transferencia o retiro | Transaction, Wallet |
| Depósito | Operación que acredita fondos externos a una billetera tras confirmación válida del origen | Transaction |
| Transferencia | Operación que mueve fondos entre dos billeteras dentro de la plataforma de forma atómica | Transaction |
| Retiro | Operación que transfiere fondos desde una billetera hacia una cuenta bancaria vinculada | Transaction |
| Reserva de Fondos | Monto apartado en la billetera durante el procesamiento de un retiro; no disponible para otras operaciones | Wallet |
| Idempotency Key | Identificador único enviado por el cliente para garantizar que una operación no sea procesada más de una vez | Transaction |
| CorrelationId | Identificador que agrupa todos los eventos y trazas relacionadas con una misma operación de negocio | Audit, Transaction |
| AML | Controles anti-lavado de dinero aplicados en onboarding y en cada operación financiera | Compliance |
| Alerta de Fraude | Notificación generada por el motor de riesgo ante patrones transaccionales sospechosos | Fraud |
| Alerta AML | Notificación generada ante coincidencia positiva en listas de sanciones internacionales o locales | Compliance |
| Nivel de Riesgo | Clasificación del riesgo operacional de una operación: Bajo, Medio, Alto, Crítico | Fraud |
| Límite Transaccional | Monto máximo permitido para un tipo de operación en un período configurado (diario, semanal, mensual) | Wallet, Compliance |
| Cuenta Bancaria Vinculada | Cuenta bancaria externa verificada y autorizada como destino exclusivo de retiros para un usuario | Wallet |
| Tenant | Organización que opera sobre la infraestructura compartida con aislamiento completo de datos y configuración propia | Multitenancy |
| Saga | Secuencia coordinada de transacciones locales con compensación ante fallos para garantizar consistencia distribuida | Transaction |
| Evento de Compensación | Hecho de negocio que revierte el efecto de un evento previo cuando una saga falla en un paso posterior | Transaction |
| Conciliación | Proceso periódico que compara el estado interno de transacciones con registros de entidades externas | Integration |
| ROS / SAR | Reporte de Operación Sospechosa — documento regulatorio para notificar operaciones potencialmente ilícitas | Reporting |
| Read Model | Vista desnormalizada del estado del sistema, construida a partir de eventos de dominio y optimizada para consultas | Reporting |
| Traza de Auditoría | Registro inmutable de un evento de negocio con actor, acción, timestamp, IP de origen y correlationId | Audit |
| ReportSchema | Definición declarativa de las columnas, tipos y fuente de datos de un tipo de reporte | Reporting |
| ReportType | Clasificador del propósito y formato de salida de un reporte: `volumen-transaccional`, `alertas-aml`, `sar-ros`, etc. | Reporting |
| Anti-Corruption Layer | Capa de traducción que aísla el modelo interno de PagoFacil de los modelos de sistemas externos | Integration |

---

## 4. Bounded Contexts

### BC-01 — Identity Context

**Propósito:** Gestionar el ciclo de vida de identidades de usuario: registro, verificación KYC, autenticación MFA, sesiones y perfil.

**Responsabilidades:**
- Registro y validación de datos personales del usuario
- Coordinación del proceso KYC con el proveedor externo (a través del Integration Context)
- Autenticación multifactor (MFA) y emisión de tokens de sesión
- Gestión del estado de cuenta: Pendiente, Activo, Suspendido, Bloqueado
- Recuperación de contraseña y actualización de perfil

**Entidades principales:** User, KYCRecord, Session, MFADevice

**Límites:**
- No gestiona operaciones financieras ni saldos
- No accede a billeteras directamente; comunica el resultado KYC mediante evento de dominio
- La comunicación con el proveedor KYC externo se realiza exclusivamente a través del Integration Context

**Datos propios (exclusivos):**
- Datos personales, credenciales con hash, estado de cuenta y preferencias de perfil
- Registros KYC: documentos verificados, resultado y timestamps
- Sesiones activas, refresh tokens y dispositivos MFA registrados

---

### BC-02 — Wallet Context

**Propósito:** Gestionar billeteras digitales, saldos y límites transaccionales.

**Responsabilidades:**
- Creación de billetera al recibir el evento `KYCApproved`
- Consulta de saldo disponible en tiempo real
- Historial paginado de movimientos con filtros
- Aplicación y validación de límites transaccionales por perfil KYC, tipo de operación y período
- Gestión de cuentas bancarias vinculadas como destino de retiros
- Ejecución de débitos, créditos y reservas de fondos bajo instrucción del Integration Context

**Entidades principales:** Wallet, WalletTransaction, TransactionLimit, LinkedBankAccount

**Límites:**
- No orquesta sagas; ejecuta instrucciones atómicas del Integration Context
- No evalúa riesgo ni cumplimiento; delega en el Fraud & Compliance Context

**Datos propios (exclusivos):**
- Wallets: identificador, saldo disponible, moneda, estado, tenant_id
- Transacciones de billetera: movimientos confirmados con idempotency_key
- Límites transaccionales por perfil, tipo y período
- Cuentas bancarias vinculadas y verificadas

---

### BC-03 — Fraud & Compliance Context

**Propósito:** Evaluar operaciones y usuarios contra políticas de riesgo, detectar fraude en tiempo real y gestionar el ciclo de vida de alertas de compliance.

**Responsabilidades:**
- Validación AML de usuarios durante el onboarding
- Evaluación AML en tiempo real para cada operación financiera antes de ejecutarse
- Análisis de patrones de fraude: velocidad de operaciones, montos inusuales, geolocalización, comportamiento fuera de patrón
- Gestión del ciclo de vida de alertas: creación, revisión, aprobación, rechazo y escalamiento
- Soporte a la generación de Reportes de Operaciones Sospechosas (ROS/SAR)

**Entidades principales:** ComplianceAlert, FraudAlert, AMLResult, RiskEvaluation, FraudRule

**Límites:**
- No modifica saldos; emite decisiones: aprobar, bloquear o escalar
- No accede directamente a datos de identidad; recibe el contexto necesario de la operación vía evento o query al contexto propietario
- La consulta a listas AML externas se realiza exclusivamente a través del Integration Context

**Datos propios (exclusivos):**
- Alertas de fraude y compliance: nivel de riesgo, regla disparada, estado
- Reglas de detección configuradas por el Analista de Fraude
- Resultados de validaciones AML por usuario y operación

---

### BC-04 — Notification Context

**Propósito:** Gestionar el envío de notificaciones a usuarios a través de los canales configurados: email, SMS o push.

**Responsabilidades:**
- Envío de confirmaciones de operaciones financieras
- Envío de códigos MFA (OTP, TOTP) bajo solicitud del Identity Context
- Notificaciones de resultado KYC, alertas de seguridad y estado de cuentas
- Gestión de preferencias de canal por usuario

**Entidades principales:** Notification, NotificationTemplate, NotificationPreference

**Límites:**
- Solo envía notificaciones; no toma decisiones de negocio
- Recibe instrucciones exclusivamente a través de eventos de dominio publicados en el bus
- El envío físico mediante SMS y email se realiza a través del proveedor externo vía Integration Context

**Datos propios (exclusivos):**
- Historial de notificaciones enviadas con estado de entrega
- Preferencias de canal por usuario y tenant

---

### BC-05 — Integration Context

**Propósito:** Centralizar la conectividad con sistemas externos y orquestar las sagas de negocio distribuidas entre bounded contexts.

**Responsabilidades:**
- Anti-Corruption Layer (ACL) para todos los sistemas externos: KYC, AML, entidades financieras, pasarelas de pago, SMS/Email
- Orquestación de sagas con compensación: depósito, transferencia, retiro (Narayana LRA)
- Traducción de modelos externos al lenguaje ubicuo de PagoFacil
- Gobierno centralizado de credenciales y SLAs de terceros
- Conciliación automática periódica con entidades financieras

**Entidades principales:** SagaInstance, SagaStep, ExternalIntegrationEvent, ReconciliationRecord

**Límites:**
- Es el único contexto que se comunica directamente con sistemas externos
- Los demás contextos de dominio no tienen acoplamiento con terceros
- No posee lógica financiera de dominio; coordina sin ejecutar operaciones de saldo

**Datos propios (exclusivos):**
- Estado e historial de sagas activas y completadas
- Outbox transaccional para publicación confiable de eventos
- Registros de conciliación con entidades externas

---

### BC-06 — Audit Context

**Propósito:** Registrar de forma inmutable todas las trazas de eventos de negocio para auditoría regulatoria y operacional.

**Responsabilidades:**
- Ingesta y almacenamiento inmutable de trazas con actor, acción, timestamp, IP y correlationId
- Dashboard de consulta para Administradores y Oficiales de Cumplimiento
- Consulta filtrada del historial por usuario, tipo de evento, rango de fechas y estado
- Visualización de alertas activas y reportes de actividad del sistema

**Entidades principales:** AuditTrace, AuditEvent

**Límites:**
- Solo registra eventos; nunca los modifica ni elimina
- No tiene acceso directo a las bases de datos operacionales de otros contextos
- Es un consumidor pasivo del bus de eventos

**Datos propios (exclusivos):**
- Trazas inmutables en almacenamiento append-only con todos los campos exigidos por RF-027
- Índices de consulta para filtros del dashboard de auditoría

---

### BC-07 — Reporting Context

**Propósito:** Generar reportes regulatorios y analíticos a partir del read model CQRS mediante un pipeline ETL de dos etapas.

**Responsabilidades:**
- Proyección del estado de dominio en el read model PostgreSQL (Projection Service — consume eventos de todos los contextos)
- Extracción y validación de datos del read model según el schema declarado (MS1 — Spark batch)
- Transformación de datos por tipo de reporte con el patrón Factory (MS2 — Spark batch)
- Generación de formatos de salida: PDF, XLS, CSV (capa Lambda serverless + EventBridge)
- Gestión del catálogo de esquemas de reportes

**Entidades principales:** ReportSchema, ReportExecution, ReportCatalog, ProjectedView

**Límites:**
- Lee exclusivamente del read model `pagofacil_readmodel`; acceso directo a bases de datos operacionales prohibido
- No modifica datos de dominio de ningún contexto
- MS1 y MS2 son jobs batch ejecutados por schedule o evento de comando; no exponen endpoints HTTP

**Datos propios (exclusivos):**
- Base de datos de reportería: catálogo `report_schema_catalog` y metadatos de ejecuciones
- Read model PostgreSQL `pagofacil_readmodel`: tablas desnormalizadas proyectadas por el Projection Service

---

## 5. Context Map

### Relaciones entre Bounded Contexts Internos

| Contexto Upstream | Contexto Downstream | Tipo de Relación | Mecanismo | Descripción |
|-------------------|---------------------|-----------------|-----------|-------------|
| Identity Context | Wallet Context | Customer / Supplier | Evento Kafka `KYCApproved` | Wallet crea la billetera digital al recibir la aprobación KYC |
| Identity Context | Fraud & Compliance Context | Customer / Supplier | Evento Kafka `UserRegistered` | Fraud evalúa AML en onboarding al recibir el registro del usuario |
| Identity Context | Audit Context | Publisher → Subscriber | Evento Kafka | Audit registra eventos de ciclo de vida de identidad (registro, activación, suspensión) |
| Wallet Context | Audit Context | Publisher → Subscriber | Evento Kafka | Audit registra movimientos de saldo confirmados y transiciones de estado |
| Wallet Context | Reporting Context | Publisher → Subscriber | Evento Kafka → Projection Service | Projection Service consume eventos de wallet para proyectar `rm_transactions` |
| Fraud & Compliance Context | Audit Context | Publisher → Subscriber | Evento Kafka | Audit registra alertas generadas, decisiones y resoluciones |
| Fraud & Compliance Context | Reporting Context | Publisher → Subscriber | Evento Kafka → Projection Service | Projection Service consume alertas para proyectar `rm_compliance_alerts` |
| Integration Context | Identity Context | Orquestador → Participante | Kafka / REST interno | Integration coordina la saga de onboarding notificando el resultado del proveedor KYC |
| Integration Context | Wallet Context | Orquestador → Participante | Kafka / REST interno | Integration instruye débitos, créditos y reservas durante sagas financieras |
| Integration Context | Fraud & Compliance Context | Orquestador → Participante | Kafka / REST interno | Integration solicita evaluación de riesgo como paso de las sagas financieras |
| Integration Context | Notification Context | Publisher → Subscriber | Evento Kafka | Integration publica confirmaciones de sagas que desencadenan notificaciones al usuario |
| Integration Context | Audit Context | Publisher → Subscriber | Evento Kafka | Integration publica el resultado de sagas para trazabilidad end-to-end |
| Reporting Context | Todos los contextos | Conformist (lectura) | Proyección desde Kafka | Projection Service consume eventos de todos los contextos para construir el read model |

### Sistemas Externos con ACL (a través del Integration Context)

| Sistema Externo | Dirección | Criticidad | Descripción |
|----------------|-----------|------------|-------------|
| Proveedor KYC | Bidireccional | Alta | Solicitud de validación de documentos e identidad biométrica; recepción de resultado vía webhook |
| Entidades Financieras | Bidireccional | Alta | Recepción de notificaciones de depósito; solicitud y confirmación de retiros; liquidación |
| Pasarelas de Pago | Entrante | Alta | Recepción de notificaciones de pago firmadas digitalmente |
| Proveedor AML | Saliente | Alta | Consulta de listas de sanciones en tiempo real o como batch periódico |
| Proveedor SMS / Email | Saliente | Media | Envío de notificaciones MFA, confirmaciones de operaciones y alertas de seguridad |

> **Principio ACL:** El Integration Context es el único punto de contacto con sistemas externos. Traduce todos los modelos externos al lenguaje ubicuo de PagoFacil. Ningún bounded context de dominio tiene acoplamiento directo con terceros.

### Flujos de Saga — Coordinación Cross-Context

| Saga | Contextos Participantes | Orquestador | Pasos con Compensación |
|------|------------------------|-------------|----------------------|
| Depósito de Fondos | Integration → Wallet → Fraud → Notification → Entidad Financiera (ACL) | Integration Context | Reversión de acreditación si la confirmación externa falla después del crédito |
| Transferencia entre Usuarios | Integration → Fraud → Wallet (débito emisor) → Wallet (crédito receptor) → Notification | Integration Context | Reversión del débito del emisor si el crédito al receptor falla |
| Retiro de Fondos | Integration → Wallet (reserva) → Entidad Financiera (ACL) → Wallet (confirmar/liberar) → Notification | Integration Context | Liberación de la reserva si la entidad financiera reporta fallo |

---

## 6. Modelos de Dominio

## Aggregate: User

### Responsabilidad
Gestionar la identidad, credenciales y estado del ciclo de vida de un usuario en la plataforma.

### Entidades
- User (raíz del agregado)
- KYCRecord
- MFADevice

### Value Objects
- Email
- DocumentId
- PhoneNumber
- HashedPassword
- UserStatus (Pendiente | Activo | Suspendido | Bloqueado)

### Reglas importantes
- Un User no puede alcanzar el estado Activo hasta que su KYCRecord tenga estado Aprobado.
- Una coincidencia positiva en listas AML durante el KYC transiciona el UserStatus automáticamente a Suspendido.
- Cambios en datos de identidad (DocumentId) requieren re-validación KYC; el UserStatus retrocede a Pendiente.
- El sistema bloquea al User que supere el umbral configurado de intentos fallidos de autenticación; el desbloqueo es explícito.

---

## Aggregate: Wallet

### Responsabilidad
Gestionar el saldo disponible y los movimientos financieros de un usuario.

### Entidades
- Wallet (raíz del agregado)
- WalletTransaction
- TransactionLimit
- LinkedBankAccount

### Value Objects
- Balance (saldo + moneda)
- Money (monto + moneda)
- WalletId
- TransactionStatus (Pendiente | Confirmada | Revertida | Fallida)
- LimitPeriod (Diario | Semanal | Mensual)
- WalletStatus (Activa | Suspendida | Cerrada)

### Reglas importantes
- El Balance nunca puede ser negativo; una operación que genere Balance negativo es rechazada antes de ejecutarse.
- Un WalletTransaction confirmado es inmutable; no puede modificarse ni eliminarse.
- Los límites transaccionales son acumulativos dentro del período activo; se calcula el remanente sumando operaciones confirmadas del período.
- LinkedBankAccount solo puede usarse como destino de retiro si su estado es Verificada y el titular coincide con el propietario de la Wallet.

---

## Aggregate: Transaction

### Responsabilidad
Representar una operación financiera con garantías de idempotencia, trazabilidad y consistencia.

### Entidades
- Transaction (raíz del agregado)
- IdempotencyRecord

### Value Objects
- TransactionId (UUID v4 — inmutable desde creación)
- IdempotencyKey
- CorrelationId
- Money
- TransactionType (Depósito | Transferencia | Retiro)
- TransactionStatus (Iniciada | Pendiente | Confirmada | Fallida | Revertida)

### Reglas importantes
- Cada Transaction recibe un TransactionId único e inmutable en el momento de su creación; no puede reutilizarse.
- Dos solicitudes con el mismo IdempotencyKey producen un único registro; la segunda retorna el resultado de la primera sin procesar nuevamente.
- Una Transaction confirmada no puede revertirse unilateralmente por el usuario; requiere proceso formal de disputa gestionado por el Administrador.

---

## Aggregate: ComplianceAlert

### Responsabilidad
Gestionar el ciclo de vida de alertas de cumplimiento y fraude generadas por el motor de riesgo.

### Entidades
- ComplianceAlert (raíz del agregado)
- FraudAlert

### Value Objects
- AlertId
- RiskLevel (Bajo | Medio | Alto | Crítico)
- AlertStatus (Abierta | En Revisión | Aprobada | Rechazada | Escalada)
- AlertType (AML | Fraude)
- TriggeredRule

### Reglas importantes
- Una alerta con RiskLevel Crítico bloquea automáticamente la operación asociada sin intervención humana.
- Una alerta con AlertStatus Escalada solo puede ser resuelta por el Oficial de Cumplimiento; el Analista de Fraude no puede cerrarla directamente.
- La resolución de una alerta queda registrada con actor, timestamp y motivo — inmutable.

---

## Aggregate: SagaInstance

### Responsabilidad
Coordinar el estado de una transacción distribuida a lo largo de múltiples bounded contexts, garantizando completitud o compensación total.

### Entidades
- SagaInstance (raíz del agregado)
- SagaStep

### Value Objects
- SagaId (propagado como CorrelationId en todos los eventos de la saga)
- SagaType (Depósito | Transferencia | Retiro)
- SagaStatus (Iniciada | En Progreso | Completada | Compensando | Fallida)

### Reglas importantes
- Una SagaInstance en estado Compensando debe completar todos sus SagaStep de compensación antes de pasar a Fallida.
- El SagaId se propaga como CorrelationId en todos los eventos publicados durante la saga para garantizar trazabilidad end-to-end.

---

## 7. Eventos de Dominio

## DE-001 — UserRegistered

Descripción:
Un nuevo usuario ha completado el formulario de registro y el sistema ha verificado la unicidad del correo electrónico.

Disparadores:
- El usuario completa el proceso de registro con datos válidos y acepta los términos.

Consecuencias:
- El sistema inicia el proceso KYC (coordina con el proveedor externo vía Integration Context).
- El sistema envía un código de verificación al correo electrónico del usuario.
- Audit registra el evento de creación de cuenta.

---

## DE-002 — KYCApproved

Descripción:
El proveedor externo de validación KYC ha aprobado la identidad del usuario.

Disparadores:
- El proveedor KYC notifica resultado de aprobación (webhook o polling) al Integration Context.

Consecuencias:
- Identity Context transiciona el estado de la cuenta a Activo.
- Wallet Context crea la billetera digital con saldo cero.
- Notification Context envía notificación de cuenta activa al usuario.

---

## DE-003 — KYCRejected

Descripción:
El proveedor externo de validación KYC ha rechazado la identidad del usuario.

Disparadores:
- El proveedor KYC notifica resultado de rechazo.

Consecuencias:
- La cuenta permanece o transiciona a estado Rechazado.
- Notification Context notifica al usuario el rechazo con las instrucciones aplicables.

---

## DE-004 — AccountSuspendedByAML

Descripción:
Una coincidencia positiva en listas de sanciones AML ha generado la suspensión automática de la cuenta.

Disparadores:
- El resultado de validación AML retorna coincidencia positiva durante onboarding u operación financiera.

Consecuencias:
- El UserStatus transiciona automáticamente a Suspendido.
- Se genera una ComplianceAlert para revisión del Oficial de Cumplimiento.
- Las operaciones financieras quedan bloqueadas hasta resolución manual.
- Audit registra la suspensión con el resultado AML como evidencia.

---

## DE-005 — WalletCreated

Descripción:
Se ha creado una billetera digital para un usuario cuyo KYC fue aprobado.

Disparadores:
- Evento DE-002 `KYCApproved` recibido por el Wallet Context.

Consecuencias:
- La billetera queda disponible con Balance en cero.
- Notification Context notifica al usuario que su billetera está activa.

---

## DE-006 — DepositCompleted

Descripción:
Un depósito de fondos fue confirmado por la entidad externa y acreditado en la billetera del usuario.

Disparadores:
- La entidad financiera o pasarela notifica confirmación válida del pago (autenticidad verificada).

Consecuencias:
- El Balance de la billetera se incrementa por el monto depositado.
- Audit registra el movimiento con correlationId.
- Notification Context envía confirmación al usuario.

**Evento de compensación:** DE-006C — DepositReverted

---

## DE-006C — DepositReverted

Descripción:
Un depósito previamente acreditado fue revertido por fallo en la confirmación externa o por compensación de la saga.

Disparadores:
- La saga de depósito falla en un paso posterior a la acreditación inicial.

Consecuencias:
- El Balance de la billetera se reduce al valor previo a la acreditación.
- Audit registra la reversión con el motivo y el CorrelationId de la saga.
- Notification Context notifica al usuario la reversión y el motivo.

---

## DE-007 — TransferCompleted

Descripción:
Una transferencia de fondos entre dos usuarios fue ejecutada de forma atómica y exitosa.

Disparadores:
- El débito del emisor y el crédito del receptor se completan satisfactoriamente dentro de la saga.

Consecuencias:
- Balance del emisor reducido por el monto transferido.
- Balance del receptor incrementado por el mismo monto.
- Ambos usuarios reciben notificación de la operación.
- Audit registra la operación con correlationId único.

**Evento de compensación:** DE-007C — TransferReverted

---

## DE-007C — TransferReverted

Descripción:
Una transferencia fue revertida porque el crédito al receptor falló después de ejecutar el débito del emisor.

Disparadores:
- La saga de transferencia falla en el paso de crédito al receptor.

Consecuencias:
- El débito del emisor es compensado; su Balance se restaura al valor previo.
- Audit registra la compensación con el motivo.
- Notification Context notifica al emisor del fallo y la reversión.

---

## DE-008 — WithdrawalCompleted

Descripción:
Un retiro de fondos fue procesado exitosamente por la entidad financiera y la reserva se confirmó como débito permanente.

Disparadores:
- La entidad financiera confirma el procesamiento del retiro.

Consecuencias:
- La reserva de fondos se convierte en débito permanente en la billetera.
- Notification Context notifica al usuario la confirmación del retiro.
- Audit registra la operación.

**Evento de compensación:** DE-008C — WithdrawalReverted

---

## DE-008C — WithdrawalReverted

Descripción:
Un retiro falló y la reserva de fondos fue liberada, restaurando el saldo disponible del usuario.

Disparadores:
- La entidad financiera reporta fallo en el procesamiento del retiro.

Consecuencias:
- La reserva de fondos es liberada; el Balance disponible se restaura.
- Notification Context notifica al usuario el fallo en el retiro.
- Audit registra la compensación.

---

## DE-009 — FraudAlertCreated

Descripción:
El motor de detección de fraude identificó un patrón sospechoso en una operación financiera.

Disparadores:
- Una operación activa una o más reglas de detección de fraude configuradas.

Consecuencias:
- La operación es marcada para revisión o bloqueada según el RiskLevel calculado.
- Se genera una FraudAlert asignada al Analista de Fraude.
- Notification Context notifica al analista en el dashboard.

---

## DE-010 — ComplianceAlertResolved

Descripción:
Un Analista de Fraude o Analista de Compliance ha tomado una decisión sobre una alerta abierta.

Disparadores:
- El analista aprueba, rechaza o escala la alerta desde el dashboard de auditoría.

Consecuencias:
- Si se aprueba: la operación asociada es liberada para ejecución.
- Si se rechaza: la operación es cancelada y se notifica al usuario.
- Si se escala: la alerta pasa al Oficial de Cumplimiento para resolución.
- Audit registra la decisión con actor, timestamp y motivo — inmutable.

---

## DE-011 — ReportExtracted

Descripción:
MS1 (Spark) completó la extracción y validación del esquema de un reporte desde el read model.

Disparadores:
- Schedule programado o comando on-demand de generación de reporte.

Consecuencias:
- El archivo Parquet con los datos extraídos y validados está disponible como contrato de entrada para MS2.
- Se publica el evento `report.extracted` en el bus de eventos Kafka.

**Evento de fallo:** DE-011F — ReportExtractionFailed

---

## DE-011F — ReportExtractionFailed

Descripción:
MS1 falló en la extracción o validación del esquema de un reporte.

Disparadores:
- Error de conexión JDBC al read model, esquema inconsistente o validación fallida en MS1.

Consecuencias:
- La ejecución del reporte se marca como fallida en el catálogo.
- Se genera alerta para el equipo de operaciones.

---

## DE-012 — ReportProcessed

Descripción:
MS2 (Spark) completó la transformación del reporte según su ReportType.

Disparadores:
- Evento `report.extracted` consumido por MS2.

Consecuencias:
- Los datos transformados están disponibles para la capa serverless de generación de formatos.
- Se publica el evento `report.processed` en el bus de eventos Kafka.

**Evento de fallo:** DE-012F — ReportProcessingFailed

---

## DE-012F — ReportProcessingFailed

Descripción:
MS2 falló en la transformación de un reporte.

Disparadores:
- Error de transformación, datos inválidos o fallo del job Spark en MS2.

Consecuencias:
- La ejecución del reporte se marca como fallida en el catálogo.
- Se genera alerta para el equipo de operaciones.

---

## 8. Workflows de Negocio

## Workflow: Onboarding de Usuario

1. El usuario completa el formulario de registro con datos personales y credenciales.
2. El sistema valida formato y unicidad del correo electrónico.
3. El sistema envía un código de verificación; el usuario lo confirma.
4. El sistema valida al usuario contra listas AML; si hay coincidencia positiva, suspende el proceso y genera alerta.
5. El sistema coordina con el proveedor KYC la validación de documentos de identidad (a través del Integration Context).
6. El proveedor KYC notifica el resultado: aprobado o rechazado.
7. Si es aprobado: el sistema activa la cuenta y la billetera digital es creada automáticamente.
8. El usuario recibe notificación y puede iniciar sesión y operar financieramente.

---

## Workflow: Autenticación con MFA

1. El usuario ingresa correo electrónico y contraseña.
2. El sistema valida las credenciales; si son incorrectas, incrementa el contador de intentos fallidos.
3. Si se supera el umbral configurado de intentos fallidos, la cuenta queda bloqueada automáticamente.
4. Si las credenciales son válidas, el sistema solicita el segundo factor de autenticación.
5. El usuario proporciona el código (TOTP, SMS OTP o email OTP).
6. El sistema valida el código; si es incorrecto o expirado, rechaza el acceso.
7. El sistema emite tokens de sesión (access token + refresh token) y registra la sesión activa.

---

## Workflow: Depósito de Fondos

1. El usuario selecciona la opción de depósito e indica el monto.
2. El sistema valida el monto contra los límites transaccionales activos del usuario.
3. El sistema crea una orden de depósito con identificador único y redirige al canal de pago externo.
4. La entidad financiera o pasarela procesa el pago y notifica el resultado al sistema.
5. El sistema valida la autenticidad de la notificación (firma digital o token de webhook).
6. Si la notificación es válida, el Integration Context coordina la evaluación AML y de fraude.
7. Si no hay alertas bloqueantes, el sistema acredita el monto en la billetera del usuario.
8. El sistema publica el evento `DepositCompleted` y notifica al usuario.

---

## Workflow: Transferencia entre Usuarios

1. El usuario ingresa el identificador del destinatario (correo, teléfono o ID de cuenta) y el monto.
2. El sistema resuelve la cuenta del destinatario y presenta un resumen de la operación para confirmación.
3. El usuario confirma la operación explícitamente.
4. El sistema valida: saldo suficiente del emisor, límites transaccionales y estado KYC activo de ambas partes.
5. El Integration Context coordina la evaluación de fraude de la operación.
6. Si no hay alertas bloqueantes, el sistema ejecuta atómicamente el débito del emisor y el crédito del receptor.
7. El sistema publica el evento `TransferCompleted` y notifica a ambas partes.

---

## Workflow: Retiro de Fondos

1. El usuario selecciona la cuenta bancaria vinculada de destino e indica el monto.
2. El sistema valida saldo disponible y límites transaccionales del usuario.
3. El sistema presenta el resumen de la operación para confirmación explícita del usuario.
4. El usuario confirma el retiro.
5. El sistema reserva el monto en la billetera y encola la instrucción hacia la entidad financiera.
6. La entidad financiera procesa el retiro y notifica el resultado.
7. Si exitoso: la reserva se confirma como débito permanente; el usuario recibe notificación de éxito.
8. Si falla: la reserva es liberada, el saldo disponible se restaura; el usuario recibe notificación del fallo.

---

## Workflow: Resolución de Alerta de Fraude

1. El motor de detección identifica un patrón sospechoso; la operación queda marcada o bloqueada según el RiskLevel.
2. El Analista de Fraude recibe notificación en el dashboard de auditoría.
3. El analista revisa el detalle de la operación, el historial del usuario y las reglas disparadas.
4. El analista toma una decisión: aprobar (liberar), rechazar (cancelar) o escalar al Oficial de Cumplimiento.
5. El sistema ejecuta la decisión, notifica al usuario si corresponde y registra la resolución en la traza de auditoría de forma inmutable.

---

## Workflow: Generación de Reporte Regulatorio

1. Un schedule programado o un comando on-demand (ante alerta AML/fraude para ROS/SAR) inicia la ejecución del reporte.
2. MS1 (Spark) extrae los datos del read model `pagofacil_readmodel` vía JDBC según el ReportSchema declarado en el catálogo.
3. MS1 valida el esquema de los datos extraídos y genera un archivo Parquet como contrato de salida.
4. MS1 publica el evento `report.extracted` en Kafka; MS2 lo consume.
5. MS2 (Spark) transforma los datos según el ReportType con el patrón Factory.
6. MS2 publica el evento `report.processed` en Kafka; el Kafka Consumer Lambda lo consume.
7. EventBridge enruta el evento a la lambda correspondiente al formato de salida solicitado (PDF, XLS o CSV).
8. La lambda genera el archivo final; el resultado queda disponible para descarga.

---

## 9. Criterios de Aceptación (ATDD)

---

## AC-001 — Registro y Activación de Cuenta

**Caso de uso / Capacidad:** RF-01 — Registro de usuario con validación KYC y control AML en onboarding.

**Bounded Context:** Identity.

**Regla de negocio asociada:** Una cuenta solo puede activarse cuando el proceso KYC finaliza con estado Aprobado. El control AML se evalúa antes de solicitar validación KYC; una coincidencia positiva suspende el proceso de forma automática.

### Criterios de aceptación — Éxito
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-001-S1 | Usuario completa el registro con datos válidos, confirma correo electrónico y el proveedor KYC aprueba la validación de documentos | La cuenta queda en estado Activo, se crea una billetera digital con saldo cero y el usuario recibe notificación de cuenta operativa |
| AC-001-S2 | El usuario ingresa el código de verificación de correo válido dentro del período de expiración | El paso de verificación queda completado y el proceso de onboarding avanza al estado siguiente |

### Criterios de aceptación — Error
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-001-E1 | El proveedor KYC devuelve resultado Rechazado tras evaluar los documentos del usuario | La cuenta queda en estado Rechazado; el usuario no puede realizar ninguna operación financiera |
| AC-001-E2 | El sistema detecta coincidencia positiva en listas de sanciones AML durante el onboarding | La cuenta queda en estado Suspendido automáticamente, el proceso se detiene y se genera una alerta de compliance para el Oficial de Cumplimiento |
| AC-001-E3 | El usuario intenta registrarse con un correo electrónico ya existente en la plataforma | El sistema rechaza la creación sin generar registros parciales y retorna un error de identidad duplicada |

---

## AC-002 — Autenticación con MFA

**Caso de uso / Capacidad:** RF-02 — Autenticación multifactor con bloqueo automático por intentos fallidos.

**Bounded Context:** Identity.

**Regla de negocio asociada:** La autenticación requiere credenciales válidas más código MFA. Si el número de intentos fallidos consecutivos supera el umbral configurado, la cuenta se bloquea automáticamente; solo puede desbloquearse por flujo de recuperación o por el Administrador.

### Criterios de aceptación — Éxito
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-002-S1 | Usuario con cuenta Activa ingresa credenciales correctas y código MFA válido y no expirado | El sistema emite access token y refresh token, registra la sesión activa y concede acceso a la plataforma |

### Criterios de aceptación — Error
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-002-E1 | El usuario supera el umbral configurado de intentos fallidos de autenticación | La cuenta queda bloqueada automáticamente y no acepta ningún intento adicional hasta desbloqueo explícito |
| AC-002-E2 | El usuario ingresa un código MFA incorrecto o expirado | El sistema rechaza el acceso sin emitir tokens y contabiliza el intento fallido |
| AC-002-E3 | El usuario intenta autenticarse con una cuenta en estado Bloqueado | El sistema rechaza la autenticación e indica que la cuenta requiere desbloqueo explícito |

---

## AC-003 — Depósito de Fondos

**Caso de uso / Capacidad:** RF-03 — Acreditación de fondos con confirmación de entidad financiera y evaluación AML/fraude.

**Bounded Context:** Wallet, Integration.

**Regla de negocio asociada:** El saldo solo se acredita tras recibir confirmación auténtica de la entidad financiera y solo si no hay alertas AML ni de fraude bloqueantes. La autenticidad de la notificación se valida mediante firma digital o token de webhook antes de procesar.

### Criterios de aceptación — Éxito
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-003-S1 | La entidad financiera confirma el depósito con firma válida y el motor de fraude no genera alertas bloqueantes | El saldo de la billetera del usuario se incrementa en el monto confirmado, se publica `DepositCompleted` y el usuario recibe notificación |

### Criterios de aceptación — Error
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-003-E1 | El monto del depósito supera el Límite Transaccional configurado para el usuario | El sistema rechaza la operación antes de crear la orden de depósito; el saldo no se modifica |
| AC-003-E2 | La notificación de la entidad financiera contiene firma digital inválida o token de webhook incorrecto | El sistema rechaza la notificación sin modificar saldos ni emitir eventos de dominio |
| AC-003-E3 | El motor de fraude genera una alerta bloqueante para la operación de depósito | El depósito queda en estado Pendiente de revisión manual; el saldo no se acredita hasta resolución del Analista de Fraude |

---

## AC-004 — Transferencia entre Usuarios

**Caso de uso / Capacidad:** RF-04 — Transferencia atómica de fondos entre cuentas con validación de prerrequisitos y evaluación de fraude.

**Bounded Context:** Wallet, Integration.

**Regla de negocio asociada:** La transferencia se ejecuta de forma atómica: el débito del emisor y el crédito del receptor ocurren en la misma operación o ninguno se aplica. Ambas partes deben tener KYC en estado Aprobado; el emisor debe tener Saldo Disponible suficiente.

### Criterios de aceptación — Éxito
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-004-S1 | Emisor con saldo suficiente y KYC Aprobado confirma transferencia a receptor con KYC Aprobado y el motor de fraude no genera alertas bloqueantes | El saldo del emisor se reduce atómicamente y el del receptor se incrementa; se publica `TransferCompleted`; ambas partes reciben notificación |

### Criterios de aceptación — Error
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-004-E1 | El Saldo Disponible del emisor es menor al monto solicitado para la transferencia | El sistema rechaza la operación antes de ejecutar cualquier débito; ningún saldo es modificado |
| AC-004-E2 | El receptor tiene estado KYC distinto de Aprobado (Pendiente, Rechazado o Suspendido) | El sistema rechaza la transferencia sin modificar ningún saldo |
| AC-004-E3 | El motor de fraude genera una alerta bloqueante sobre la operación de transferencia | La transferencia es detenida y marcada para revisión manual; ningún saldo es modificado hasta resolución del Analista de Fraude |

---

## AC-005 — Retiro de Fondos

**Caso de uso / Capacidad:** RF-05 — Retiro de fondos hacia cuenta bancaria vinculada con compensación de saga ante fallo externo.

**Bounded Context:** Wallet, Integration.

**Regla de negocio asociada:** Durante el procesamiento, el monto queda en Reserva de Fondos (no disponible para otras operaciones). Si la entidad financiera reporta fallo, la saga ejecuta compensación automática liberando la reserva y restaurando el Saldo Disponible. (Evento de compensación: `DE-009 — FundsReservationReleased`.)

### Criterios de aceptación — Éxito
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-005-S1 | La entidad financiera confirma el retiro exitosamente | La Reserva de Fondos se convierte en débito permanente, el Saldo Disponible refleja el retiro definitivo y el usuario recibe notificación de éxito |

### Criterios de aceptación — Error
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-005-E1 | La entidad financiera reporta fallo en el procesamiento del retiro | La saga ejecuta compensación automática (`DE-009`): la Reserva de Fondos es liberada y el Saldo Disponible se restaura al valor previo; el usuario recibe notificación del fallo |
| AC-005-E2 | El Saldo Disponible del usuario es insuficiente para cubrir el monto solicitado considerando Reservas de Fondos activas existentes | El sistema rechaza la solicitud sin crear ninguna Reserva de Fondos |
| AC-005-E3 | La cuenta bancaria de destino indicada no está vinculada ni verificada para el usuario | El sistema rechaza la operación antes de crear la reserva |

---

## AC-006 — Idempotencia de Operaciones Financieras

**Caso de uso / Capacidad:** RF-06 — Garantía de idempotencia mediante Idempotency Key en operaciones financieras.

**Bounded Context:** Wallet, Integration.

**Regla de negocio asociada:** Toda operación financiera enviada con un Idempotency Key ya procesado retorna el resultado original sin volver a ejecutar la operación. Esto previene duplicación de efectos ante reintentos del cliente.

### Criterios de aceptación — Éxito
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-006-S1 | Un cliente reintenta una operación con el mismo Idempotency Key de una operación previamente completada | El sistema retorna el resultado original sin crear una nueva transacción ni modificar saldos |

### Criterios de aceptación — Error
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-006-E1 | Un cliente envía una segunda solicitud con el mismo Idempotency Key mientras la operación original está aún en curso | El sistema detecta la condición de concurrencia y rechaza el segundo intento indicando que la operación está siendo procesada |

---

## AC-007 — Detección y Resolución de Alertas de Fraude/AML

**Caso de uso / Capacidad:** RF-07 — Detección automática de fraude y AML; resolución manual por Analista de Fraude u Oficial de Cumplimiento.

**Bounded Context:** Fraud & Compliance.

**Regla de negocio asociada:** El motor de riesgo evalúa cada operación financiera antes de su ejecución. Las alertas de Nivel de Riesgo Crítico bloquean la operación de forma automática. Toda resolución queda registrada de forma inmutable en la Traza de Auditoría.

### Criterios de aceptación — Éxito
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-007-S1 | El Analista de Fraude revisa y aprueba una operación previamente marcada como sospechosa | El sistema libera la operación, notifica al usuario del resultado y registra la resolución de forma inmutable en la Traza de Auditoría |

### Criterios de aceptación — Error
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-007-E1 | El motor de riesgo clasifica una operación financiera con Nivel de Riesgo Crítico | La operación es bloqueada automáticamente sin ejecutar débitos ni créditos; se genera una alerta de alta prioridad para el Analista de Fraude |
| AC-007-E2 | El Oficial de Cumplimiento confirma una alerta AML como positiva para un usuario | La cuenta del usuario es suspendida, todas sus operaciones financieras pendientes son canceladas y se genera un registro regulatorio (ROS/SAR candidato) |

---

## AC-008 — Generación de Reporte Regulatorio

**Caso de uso / Capacidad:** RF-08 — Pipeline ETL de reportería regulatoria por schedule programado o on-demand.

**Bounded Context:** Reporting.

**Regla de negocio asociada:** Los datos se extraen exclusivamente del Read Model (`pagofacil_readmodel`) siguiendo el ReportSchema declarado en el catálogo. El pipeline no modifica datos de servicios operacionales. Los fallos generan eventos observables y alertas al equipo de operaciones.

### Criterios de aceptación — Éxito
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-008-S1 | El schedule dispara el pipeline ETL y todas las etapas (MS1 extracción, MS2 transformación, Lambda formato) se completan sin errores | El reporte queda disponible en el formato solicitado (PDF/XLS/CSV), la ejecución se registra como completada en el catálogo y se notifica al solicitante |

### Criterios de aceptación — Error
| ID | Criterio (condición verificable) | Resultado esperado |
|----|----------------------------------|--------------------|
| AC-008-E1 | MS1 falla al extraer datos del Read Model por error de conectividad JDBC | Se publica `ReportExtractionFailed`, la ejecución se marca como fallida en el catálogo, se genera alerta para el equipo de operaciones; los datos operacionales no son afectados |
| AC-008-E2 | Los datos extraídos por MS1 no cumplen el ReportSchema declarado en el catálogo (columnas faltantes o tipos incompatibles) | MS1 rechaza la ejecución y publica `ReportExtractionFailed` sin generar archivo Parquet; la ejecución queda marcada como fallida por validación de esquema |

---

## 10. Escenarios BDD

```gherkin
Feature: Onboarding y Activación de Cuenta
# Valida: AC-001

  # --- Escenario de éxito ---
  Scenario: Registro exitoso con KYC aprobado
    Given un usuario no registrado en la plataforma
    When el usuario completa el formulario de registro con datos válidos
    And confirma su correo electrónico mediante el código enviado
    And el proveedor KYC aprueba la validación de documentos
    Then la cuenta del usuario queda en estado Activo
    And se crea una billetera digital con saldo cero
    And el usuario recibe notificación de cuenta activa y lista para operar

  # --- Escenario de error ---
  Scenario: Registro bloqueado por coincidencia AML durante onboarding
    Given un usuario en proceso de onboarding con datos válidos
    When el sistema detecta una coincidencia positiva en listas de sanciones AML
    Then la cuenta queda en estado Suspendido automáticamente
    And se genera una alerta de compliance para el Oficial de Cumplimiento
    And el usuario no puede realizar operaciones financieras hasta resolución manual
```

```gherkin
Feature: Transferencia entre Usuarios
# Valida: AC-004

  # --- Escenario de éxito ---
  Scenario: Transferencia exitosa entre cuentas activas con KYC aprobado
    Given un usuario emisor con saldo de 1000 unidades y KYC aprobado
    And un usuario receptor con cuenta activa y KYC aprobado
    When el emisor solicita transferir 500 unidades al receptor
    And el motor de fraude evalúa la operación sin alertas bloqueantes
    Then el saldo del emisor se reduce en 500 unidades
    And el saldo del receptor se incrementa en 500 unidades
    And ambos usuarios reciben notificación de la operación
    And la transacción queda registrada con identificador único e inmutable

  # --- Escenario de error ---
  Scenario: Transferencia rechazada por saldo insuficiente
    Given un usuario emisor con saldo de 100 unidades
    When el emisor solicita transferir 200 unidades a otro usuario
    Then el sistema rechaza la operación antes de ejecutar cualquier débito
    And el saldo del emisor no se modifica
    And el receptor no recibe ningún crédito

  Scenario: Transferencia rechazada por KYC pendiente del receptor
    Given un usuario emisor con saldo suficiente y KYC aprobado
    And un usuario receptor con estado KYC Pendiente
    When el emisor solicita transferir fondos al receptor
    Then el sistema rechaza la operación
    And ningún saldo es modificado
```

```gherkin
Feature: Idempotencia de Operaciones Financieras
# Valida: AC-006

  # --- Escenario de éxito ---
  Scenario: Reintento con el mismo Idempotency Key no duplica la operación
    Given una transferencia completada con idempotency-key "txn-abc-123"
    When el cliente reintenta la misma solicitud con idempotency-key "txn-abc-123"
    Then el sistema retorna el resultado de la operación original sin procesarla nuevamente
    And no se crea una segunda transacción
    And los saldos de emisor y receptor no se modifican adicionalmente

  # --- Escenario de error ---
  Scenario: Segundo reintento con Idempotency Key de operación en curso es rechazado
    Given una transferencia en estado Procesando con idempotency-key "txn-xyz-456"
    When el cliente envía una segunda solicitud con el mismo idempotency-key "txn-xyz-456"
    Then el sistema detecta la condición de concurrencia y rechaza el segundo intento
    And retorna un error indicando que la operación está siendo procesada
    And no se crea ninguna segunda instancia de la operación
```

```gherkin
Feature: Retiro de Fondos
# Valida: AC-005

  # --- Escenario de éxito ---
  Scenario: Retiro exitoso confirmado por la entidad financiera
    Given un usuario con saldo disponible de 500 unidades y una cuenta bancaria vinculada verificada
    When el usuario solicita un retiro de 300 unidades y confirma la operación
    And el sistema crea una Reserva de Fondos de 300 unidades
    And la entidad financiera confirma el procesamiento exitoso del retiro
    Then la Reserva de Fondos se convierte en débito permanente
    And el saldo disponible del usuario refleja la reducción definitiva de 300 unidades
    And el usuario recibe notificación de retiro completado

  # --- Escenario de error ---
  Scenario: Compensación automática ante fallo reportado por la entidad financiera
    Given un usuario con saldo suficiente que solicita un retiro de 300 unidades
    And el sistema ha reservado 300 unidades en la billetera
    When la entidad financiera reporta fallo en el procesamiento del retiro
    Then la saga de retiro ejecuta la compensación automáticamente
    And la reserva de 300 unidades es liberada en la billetera
    And el saldo disponible del usuario se restaura al valor previo a la reserva
    And el usuario recibe notificación del fallo en el retiro
```

```gherkin
Feature: Autenticación con MFA
# Valida: AC-002

  # --- Escenario de éxito ---
  Scenario: Autenticación exitosa con credenciales válidas y código MFA correcto
    Given un usuario con cuenta en estado Activo
    When el usuario ingresa credenciales correctas y el código MFA válido no expirado
    Then el sistema emite access token y refresh token
    And registra la sesión activa del usuario
    And concede acceso a la plataforma

  # --- Escenario de error ---
  Scenario: Cuenta bloqueada automáticamente tras superar el umbral de intentos fallidos
    Given un usuario con cuenta activa
    When el usuario ingresa credenciales incorrectas el número de veces igual al umbral configurado
    Then la cuenta queda bloqueada automáticamente
    And el usuario no puede iniciar sesión con credenciales correctas mientras la cuenta esté bloqueada
    And el sistema requiere desbloqueo explícito por flujo de recuperación o por el Administrador
```

```gherkin
Feature: Generación de Reporte Regulatorio
# Valida: AC-008

  # --- Escenario de éxito ---
  Scenario: Pipeline ETL exitoso para reporte de alertas AML
    Given un schedule mensual configurado para el reporte "alertas-aml"
    When el job MS1 se ejecuta y extrae datos del read model según el ReportSchema declarado
    Then se genera un archivo Parquet con los datos validados
    And se publica el evento ReportExtracted en el bus de eventos
    And el job MS2 transforma los datos según el tipo "alertas-aml"
    And la capa Lambda genera el formato de salida solicitado (PDF, XLS o CSV)
    And la ejecución queda registrada como completada en el catálogo de reportes

  # --- Escenario de error ---
  Scenario: Fallo en extracción notifica al equipo de operaciones
    Given un schedule de reporte activo para "volumen-transaccional"
    When MS1 falla al conectar con el read model por error JDBC
    Then se publica el evento ReportExtractionFailed
    And la ejecución del reporte se marca como fallida en el catálogo
    And se genera una alerta para el equipo de operaciones
```

```gherkin
Feature: Depósito de Fondos
# Valida: AC-003

  # --- Escenario de éxito ---
  Scenario: Depósito exitoso con confirmación válida de entidad financiera
    Given un usuario con cuenta Activa y KYC Aprobado
    And un monto de depósito dentro del límite transaccional configurado
    When la entidad financiera envía notificación de confirmación con firma válida
    And el motor de fraude evalúa la operación sin generar alertas bloqueantes
    Then el saldo de la billetera del usuario se incrementa en el monto confirmado
    And se publica el evento DepositCompleted
    And el usuario recibe notificación del depósito acreditado

  # --- Escenario de error ---
  Scenario: Depósito rechazado por firma inválida en la notificación de la entidad financiera
    Given una notificación de confirmación de depósito recibida del canal externo
    When la firma digital de la notificación no coincide con la esperada
    Then el sistema rechaza la notificación sin modificar el saldo de ninguna billetera
    And no se emite ningún evento de dominio relacionado con el depósito
```

```gherkin
Feature: Detección de Fraude y AML
# Valida: AC-007

  # --- Escenario de éxito ---
  Scenario: Analista aprueba operación marcada como sospechosa y el sistema la libera
    Given una operación financiera en estado Pendiente de revisión por alerta de fraude
    And el Analista de Fraude ha revisado el detalle de la operación y el historial del usuario
    When el Analista de Fraude aprueba la operación
    Then el sistema libera la operación para su ejecución
    And registra la resolución de forma inmutable en la Traza de Auditoría
    And el usuario recibe notificación del resultado

  # --- Escenario de error ---
  Scenario: Motor de riesgo bloquea automáticamente una operación con nivel de riesgo Crítico
    Given un usuario con cuenta activa que solicita una operación financiera
    When el motor de riesgo clasifica la operación con Nivel de Riesgo Crítico
    Then la operación es bloqueada automáticamente sin ejecutar ningún débito ni crédito
    And se genera una alerta de alta prioridad para el Analista de Fraude
    And el estado de la operación queda en Bloqueado pendiente de revisión manual
```
