# Software Requirements Specification (SRS)

**Proyecto:** PagoFacil — Billetera Digital  
**Versión:** 1.0  
**Fecha:** 2026-06-06  
**Estado:** Borrador para revisión  
**Documento base:** PID-PagoFacil v1.0  

---

## 1. Introducción

### Propósito del Sistema

PagoFacil es una plataforma de billetera digital que permite a los usuarios gestionar fondos electrónicos, ejecutar operaciones financieras (depósito, retiro, transferencia) y consultar su actividad transaccional, con garantías de seguridad, trazabilidad e integridad financiera.

### Objetivo del Documento

Este documento especifica los requerimientos funcionales y no funcionales del sistema PagoFacil, eliminando ambigüedades para permitir el diseño técnico, la implementación y la validación por parte de los stakeholders.

### Alcance del Sistema

El sistema comprende:

- Gestión de identidad y autenticación de usuarios con cumplimiento KYC/AML.
- Operaciones financieras core: depósito, retiro y transferencia entre usuarios.
- Consulta de saldo e historial de movimientos.
- APIs seguras para integración con entidades financieras y pasarelas de pago.
- Módulo de monitoreo de fraude y controles AML.
- Dashboard de auditoría y reportes regulatorios.
- Observabilidad completa y alta disponibilidad.

Quedan fuera del alcance: aplicaciones móviles nativas, integración directa con redes de tarjetas, módulo de crédito y soporte multimoneda.

### Contexto de Negocio

La organización opera en el dominio fintech y carece de una plataforma propia de pagos electrónicos. La dependencia de terceros genera riesgo regulatorio (KYC/AML), pérdida de control sobre datos transaccionales y limitaciones de escalabilidad. PagoFacil elimina esas brechas mediante una solución propia, modular y conforme a la normativa vigente.

---

## 2. Descripción General del Sistema

PagoFacil opera como una plataforma financiera centralizada que gestiona el ciclo de vida completo de los fondos electrónicos de los usuarios. Los procesos principales son:

1. **Onboarding:** El usuario se registra, valida su identidad (KYC) y activa autenticación multifactor.
2. **Fondeo:** El usuario deposita fondos desde una fuente externa vinculada a su cuenta de billetera.
3. **Operaciones financieras:** El usuario ejecuta retiros o transferencias; el sistema procesa, registra y confirma cada operación con identificador único.
4. **Consulta:** El usuario consulta su saldo actual e historial de movimientos filtrado por fecha, tipo de operación o monto.
5. **Monitoreo y cumplimiento:** El sistema evalúa cada transacción en tiempo real contra reglas de fraude y controles AML; las alertas son gestionadas por el equipo de compliance.
6. **Auditoría:** Los administradores y auditores acceden al dashboard para revisar transacciones, generar reportes regulatorios y gestionar alertas.
7. **Integración externa:** Las entidades financieras y pasarelas de pago interactúan con el sistema mediante APIs autenticadas con OAuth 2.0.

El sistema corre sobre una arquitectura de microservicios event-driven desplegada en contenedores (Kubernetes) en nube pública, con escalamiento horizontal automático y soporte para multitenancy.

---

## 3. Actores del Sistema

| Actor | Descripción | Responsabilidades Principales |
|---|---|---|
| Usuario Final | Titular de la billetera digital | Registro, autenticación, fondeo, retiro, transferencia y consulta de movimientos |
| Administrador de Plataforma | Personal interno con acceso privilegiado | Gestión de configuración, límites transaccionales, revisión de alertas y soporte operacional |
| Auditor / Compliance | Oficial de cumplimiento o auditor interno | Revisión del dashboard de auditoría, generación de reportes regulatorios, gestión de casos AML |
| Entidad Financiera | Proveedor bancario o pasarela de pago externa | Fondeo y liquidación de operaciones mediante APIs autenticadas |
| Sistema de Fraude (interno) | Motor automatizado de detección de fraude | Evaluación en tiempo real de patrones transaccionales sospechosos |
| Sistema de Notificaciones (interno) | Servicio de alertas y comunicaciones | Emisión de notificaciones a usuarios y administradores ante eventos relevantes |

---

## 4. Requerimientos Funcionales

### RF-001 — Registro de Usuario

Descripción:  
El sistema debe permitir que un nuevo usuario cree una cuenta proporcionando nombre completo, correo electrónico, número de documento de identidad y contraseña. El registro queda en estado pendiente hasta completar la validación KYC.

---

### RF-002 — Validación de Identidad (KYC)

Descripción:  
El sistema debe ejecutar un proceso de validación de identidad (Know Your Customer) como requisito previo a la activación de la cuenta. El proceso incluye verificación documental y, según la configuración del tenant, verificación biométrica o por terceros. El resultado (aprobado / rechazado / en revisión) debe quedar registrado de forma auditable.

---

### RF-003 — Autenticación con MFA

Descripción:  
El sistema debe autenticar a los usuarios mediante credenciales (correo + contraseña) más un segundo factor de autenticación (TOTP, SMS o correo electrónico). La sesión debe expirar tras un período configurable de inactividad. El sistema debe bloquear la cuenta tras N intentos fallidos consecutivos configurables.

---

### RF-004 — Recuperación de Contraseña

Descripción:  
El sistema debe proveer un flujo seguro de recuperación de contraseña mediante verificación del correo registrado y token de uso único con expiración. El cambio de contraseña debe invalidar todas las sesiones activas del usuario.

---

### RF-005 — Consulta de Saldo

Descripción:  
El sistema debe permitir al usuario consultar su saldo disponible en tiempo real. El saldo mostrado debe reflejar únicamente fondos confirmados; los fondos en proceso (transacciones pendientes) deben presentarse por separado.

---

### RF-006 — Depósito de Fondos

Descripción:  
El sistema debe permitir al usuario depositar fondos desde una fuente externa vinculada (cuenta bancaria o pasarela de pago). Cada depósito debe generar un identificador único de operación (UUID/correlationId), registrar la fuente, el monto, la fecha y el estado. El saldo se actualiza únicamente tras confirmación de la entidad financiera externa.

---

### RF-007 — Retiro de Fondos

Descripción:  
El sistema debe permitir al usuario solicitar el retiro de fondos hacia una cuenta de destino previamente registrada y validada. El sistema debe verificar disponibilidad de saldo, aplicar los límites configurados y registrar la operación con identificador único. El retiro debe estar sujeto a evaluación del motor de fraude antes de su procesamiento.

---

### RF-008 — Transferencia entre Usuarios

Descripción:  
El sistema debe permitir transferir fondos de una billetera a otra dentro de la plataforma, identificando al destinatario por correo electrónico o alias. Cada transferencia debe tener identificador único, confirmación explícita del remitente y registro auditable. La operación debe ser atómica: el débito del remitente y el crédito del destinatario deben procesarse en la misma unidad transaccional (garantías ACID).

---

### RF-009 — Historial de Movimientos

Descripción:  
El sistema debe proveer al usuario acceso a su historial de movimientos con paginación y filtros por: rango de fechas, tipo de operación (depósito, retiro, transferencia) y rango de monto. Cada registro debe incluir: identificador de operación, fecha/hora, tipo, monto, estado y descripción.

---

### RF-010 — Identificadores Únicos de Operación

Descripción:  
El sistema debe generar un identificador único (UUID v4) y un correlationId para cada operación financiera. Estos identificadores deben incluirse en todos los registros, respuestas de API, logs y trazas distribuidas asociados a la operación.

---

### RF-011 — Idempotencia de Operaciones Financieras

Descripción:  
El sistema debe garantizar que una operación financiera enviada múltiples veces con el mismo idempotency key sea procesada una sola vez. Los reintentos con idempotency key existente deben devolver el resultado original sin generar operaciones duplicadas.

---

### RF-012 — Conciliación Automática

Descripción:  
El sistema debe ejecutar procesos de conciliación automática para detectar y registrar discrepancias entre el saldo interno y los registros de entidades financieras externas. Las discrepancias detectadas deben generar una alerta para revisión manual por el equipo de operaciones o compliance.

---

### RF-013 — Gestión de Límites Transaccionales

Descripción:  
El sistema debe permitir configurar límites por usuario para: monto máximo por operación, monto acumulado diario/mensual y número máximo de operaciones por período. Los límites deben ser configurables por tipo de operación y aplicarse de forma automática antes del procesamiento. La superación de un límite debe rechazar la operación con mensaje de error descriptivo.

---

### RF-014 — Monitoreo de Fraude en Tiempo Real

Descripción:  
El sistema debe evaluar cada transacción financiera en tiempo real contra un conjunto de reglas de detección de fraude configurable. Las reglas deben poder definirse sobre atributos como monto, frecuencia, ubicación geográfica, destinatario y patrones históricos. Una transacción marcada como sospechosa debe ser bloqueada o puesta en revisión según la configuración de la regla.

---

### RF-015 — Controles AML

Descripción:  
El sistema debe implementar controles Anti-Money Laundering (AML) que incluyan: verificación de usuarios y contrapartes contra listas de sanciones internacionales (OFAC, ONU u otras configuradas), y detección y reporte de operaciones inusuales (ROS). Los reportes AML deben poder exportarse en el formato exigido por la normativa aplicable.

---

### RF-016 — Gestión de Alertas

Descripción:  
El sistema debe generar alertas automáticas ante eventos configurables: transacciones sospechosas, superación de límites, fallos de conciliación, intentos de autenticación fallidos y degradación de disponibilidad. Las alertas deben clasificarse por severidad y ser gestionables desde el dashboard de auditoría.

---

### RF-017 — Dashboard de Auditoría

Descripción:  
El sistema debe proveer a administradores y auditores un dashboard para: búsqueda y revisión de transacciones por identificador, usuario, fecha o estado; gestión de alertas de fraude y AML; visualización de métricas operacionales; y generación de reportes regulatorios exportables (PDF/CSV).

---

### RF-018 — APIs de Integración Externa

Descripción:  
El sistema debe exponer APIs REST autenticadas con OAuth 2.0 / OpenID Connect para integración con entidades financieras y pasarelas de pago. Las APIs deben soportar operaciones de fondeo, liquidación, consulta de saldo y estado de operaciones. Toda respuesta de API debe incluir el correlationId de la operación.

---

### RF-019 — Procesamiento Asíncrono de Transacciones

Descripción:  
El sistema debe procesar transacciones financieras mediante un bus de eventos con garantías de entrega (at-least-once delivery). Los consumidores de eventos deben implementar idempotencia para manejar reentregas sin efectos secundarios. El estado de cada transacción (pendiente, en proceso, confirmada, fallida) debe ser consultable en todo momento.

---

### RF-020 — Soporte Multitenancy

Descripción:  
El sistema debe soportar segmentación operativa por tenant (canal de distribución o cliente institucional). Los datos, configuraciones y límites de cada tenant deben estar completamente aislados. El modelo de datos debe garantizar que consultas y operaciones de un tenant no accedan a datos de otro.

---

## 5. Requerimientos No Funcionales

### RNF-001 — Disponibilidad

Categoría: Disponibilidad

El sistema debe mantener un uptime mínimo del 99.9% mensual, equivalente a un máximo de 43.8 minutos de inactividad no planificada por mes. El plan de recuperación ante desastres debe garantizar RTO < 1 hora y RPO < 15 minutos.

---

### RNF-002 — Rendimiento

Categoría: Rendimiento

El sistema debe responder al 95% de las solicitudes de consulta (saldo, historial) en menos de 500 ms bajo carga nominal. Las operaciones financieras (depósito, retiro, transferencia) deben completar su validación y encolamiento en menos de 2 segundos bajo carga nominal. Las pruebas de carga deben validar estos umbrales antes del despliegue productivo.

---

### RNF-003 — Seguridad en Tránsito y Reposo

Categoría: Seguridad

Toda comunicación externa e interna entre servicios debe cifrarse con TLS 1.2 o superior. Los datos sensibles en reposo (datos personales, información financiera, credenciales) deben cifrarse con AES-256. Las claves y secretos deben gestionarse mediante un servicio vault dedicado; queda prohibido almacenar credenciales en texto plano, variables de entorno no cifradas o repositorios de código.

---

### RNF-004 — Autenticación y Autorización

Categoría: Seguridad

Todas las APIs externas deben implementar autenticación OAuth 2.0 / OpenID Connect. Los servicios internos deben usar autenticación mTLS o equivalente. El control de acceso debe implementar el principio de mínimo privilegio. Los tokens de acceso deben tener tiempo de expiración configurable.

---

### RNF-005 — Consistencia Financiera

Categoría: Integridad

Todas las operaciones financieras críticas (débito, crédito, transferencia) deben ejecutarse con garantías ACID. Las transacciones distribuidas deben implementarse mediante el patrón Saga con compensación. Las operaciones de escritura hacia sistemas externos deben usar el outbox pattern para garantizar consistencia sin pérdida de eventos.

---

### RNF-006 — Escalabilidad

Categoría: Escalabilidad

El sistema debe escalar horizontalmente de forma automática ante incrementos de carga, sin intervención manual. La arquitectura de microservicios debe permitir escalar componentes individualmente. El diseño debe soportar al menos 10x el volumen transaccional inicial proyectado sin rediseño estructural.

---

### RNF-007 — Observabilidad

Categoría: Observabilidad

El sistema debe implementar: logging estructurado en formato JSON con correlationId en cada entrada, métricas de negocio y técnicas expuestas para recolección (Prometheus o equivalente), y trazas distribuidas mediante OpenTelemetry. Los logs y trazas de operaciones financieras deben retenerse por el período mínimo exigido por la normativa regulatoria.

---

### RNF-008 — Idempotencia de API

Categoría: Confiabilidad

Toda operación financiera expuesta por API debe soportar un idempotency key provisto por el cliente. El sistema debe garantizar que operaciones reintentadas con el mismo key no generen efectos duplicados, independientemente del número de reintentos.

---

### RNF-009 — Mantenibilidad

Categoría: Mantenibilidad

El sistema debe implementarse en una arquitectura de microservicios con separación clara de responsabilidades por dominio (identidad, pagos, fraude, auditoría). Cada microservicio debe ser desplegable y escalable de forma independiente. La cobertura de pruebas automatizadas en módulos críticos (núcleo financiero, seguridad) debe ser igual o superior al 80%.

---

### RNF-010 — Cumplimiento Regulatorio

Categoría: Compliance

El sistema debe cumplir con la legislación de protección de datos personales vigente en la jurisdicción de operación (GDPR u equivalente aplicable) y con las normativas KYC y AML aplicables. Los registros de auditoría deben ser inmutables y conservarse por el período legalmente requerido. El sistema debe pasar auditoría externa de cumplimiento sin observaciones críticas antes del despliegue productivo.

---

### RNF-011 — Resistencia a Fallos

Categoría: Confiabilidad

El sistema debe implementar patrones de resiliencia: circuit breakers para dependencias externas, reintentos con backoff exponencial, timeouts configurables y degradación controlada ante fallos parciales. Una falla en un microservicio no debe propagarse y derribar el sistema completo.

---

## 6. Reglas de Negocio

**RN-001:** Una cuenta de usuario solo puede activarse tras la aprobación exitosa del proceso KYC.

**RN-002:** Un usuario no puede ejecutar operaciones financieras (depósito, retiro, transferencia) si su cuenta está en estado suspendido, bloqueado o pendiente de KYC.

**RN-003:** El saldo de una billetera no puede ser negativo bajo ninguna circunstancia. Toda operación que resulte en saldo negativo debe ser rechazada antes de su procesamiento.

**RN-004:** Los fondos depositados no están disponibles hasta recibir confirmación de la entidad financiera externa. Los fondos en tránsito se presentan como saldo pendiente, separados del saldo disponible.

**RN-005:** Toda operación financiera debe registrarse con identificador único, timestamp, actor, monto, estado y resultado. Este registro es inmutable una vez creado.

**RN-006:** Una operación en estado confirmada no puede revertirse de forma unilateral. Cualquier reversión requiere un proceso de disputa formal con registro auditable y aprobación de un auditor autorizado.

**RN-007:** El sistema debe rechazar operaciones de usuarios o contrapartes presentes en listas de sanciones activas (AML). El rechazo debe generar un evento auditable sin exponer al usuario la razón regulatoria específica.

**RN-008:** Los límites transaccionales configurados por el administrador tienen precedencia sobre cualquier solicitud del usuario. Un usuario no puede elevar sus propios límites.

**RN-009:** Toda transacción marcada como sospechosa por el motor de fraude debe quedar retenida hasta resolución manual por un auditor autorizado. La retención no expira automáticamente.

**RN-010:** Las contraseñas deben almacenarse con hash usando bcrypt, Argon2 o equivalente con salt único por usuario. Queda prohibido almacenar contraseñas en texto plano o con hash reversible.

**RN-011:** Una sesión de usuario expira tras el período de inactividad configurado. La expiración de sesión no cancela ni revierte operaciones ya encoladas.

**RN-012:** La retención mínima de registros de transacciones y auditoría es la exigida por la normativa regulatoria aplicable. En ausencia de normativa específica, no será inferior a 5 años.

---

## 7. Casos de Uso Principales

### CU-001 — Registro y Activación de Cuenta

Actores:  
Usuario Final

Precondiciones:  
El usuario no posee cuenta activa en la plataforma.

Flujo principal:  
1. El usuario completa el formulario de registro con nombre, correo electrónico, documento de identidad y contraseña.
2. El sistema valida unicidad del correo y del documento.
3. El sistema crea la cuenta en estado pendiente KYC y envía confirmación al correo registrado.
4. El usuario completa el proceso de validación de identidad (KYC).
5. El sistema evalúa el resultado KYC y activa la cuenta si es aprobado.
6. El usuario configura el segundo factor de autenticación (MFA).

Resultado esperado:  
Cuenta activa con MFA habilitado, lista para operar.

---

### CU-002 — Autenticación de Usuario

Actores:  
Usuario Final

Precondiciones:  
El usuario posee cuenta activa con MFA configurado.

Flujo principal:  
1. El usuario ingresa correo electrónico y contraseña.
2. El sistema valida las credenciales.
3. El sistema solicita el segundo factor de autenticación.
4. El usuario provee el código MFA.
5. El sistema valida el código y emite el token de sesión.

Resultado esperado:  
Sesión autenticada con token de acceso emitido.

---

### CU-003 — Depósito de Fondos

Actores:  
Usuario Final, Entidad Financiera (externa)

Precondiciones:  
Usuario autenticado con cuenta activa. Fuente de fondos registrada y validada.

Flujo principal:  
1. El usuario selecciona la fuente de fondos y el monto a depositar.
2. El sistema verifica que el monto cumple los límites configurados.
3. El sistema genera un identificador único de operación y registra el depósito en estado pendiente.
4. El sistema envía la solicitud de fondeo a la entidad financiera externa vía API.
5. La entidad financiera confirma o rechaza la operación.
6. El sistema actualiza el estado del depósito y el saldo del usuario según el resultado.
7. El sistema notifica al usuario el resultado de la operación.

Resultado esperado:  
Fondos acreditados en la billetera del usuario con registro confirmado.

---

### CU-004 — Transferencia entre Usuarios

Actores:  
Usuario Final (remitente), Usuario Final (destinatario)

Precondiciones:  
Remitente autenticado con saldo disponible suficiente. Destinatario con cuenta activa en la plataforma.

Flujo principal:  
1. El remitente ingresa el identificador del destinatario (correo o alias) y el monto.
2. El sistema resuelve y muestra los datos del destinatario para confirmación del remitente.
3. El remitente confirma la operación.
4. El sistema verifica saldo disponible, límites y evaluación del motor de fraude.
5. El sistema ejecuta el débito del remitente y el crédito del destinatario de forma atómica.
6. El sistema registra la operación con identificador único y notifica a ambas partes.

Resultado esperado:  
Transferencia registrada y confirmada; saldo actualizado en ambas billeteras.

---

### CU-005 — Retiro de Fondos

Actores:  
Usuario Final, Entidad Financiera (externa)

Precondiciones:  
Usuario autenticado con saldo disponible suficiente y cuenta de destino registrada.

Flujo principal:  
1. El usuario selecciona la cuenta de destino y el monto a retirar.
2. El sistema verifica saldo disponible, límites configurados y evaluación de fraude.
3. El sistema registra el retiro en estado pendiente y reserva los fondos.
4. El sistema envía la instrucción de pago a la entidad financiera externa.
5. La entidad financiera confirma o rechaza la operación.
6. El sistema actualiza el estado y libera o devuelve los fondos según el resultado.

Resultado esperado:  
Retiro confirmado con fondos enviados a la cuenta de destino.

---

### CU-006 — Revisión de Alerta de Fraude

Actores:  
Auditor / Compliance

Precondiciones:  
Existe al menos una transacción retenida por el motor de fraude.

Flujo principal:  
1. El auditor accede al dashboard de auditoría y filtra alertas pendientes.
2. El auditor revisa el detalle completo de la transacción retenida.
3. El auditor aprueba o rechaza la transacción con justificación registrada.
4. El sistema procesa o cancela la transacción según la decisión y notifica al usuario afectado.

Resultado esperado:  
Alerta resuelta con decisión y justificación registradas de forma auditable.

---

### CU-007 — Generación de Reporte Regulatorio

Actores:  
Auditor / Compliance

Precondiciones:  
Acceso autorizado al dashboard de auditoría.

Flujo principal:  
1. El auditor selecciona el tipo de reporte y el período de tiempo.
2. El sistema recopila los datos transaccionales y los formatea según el estándar requerido.
3. El auditor descarga el reporte en formato PDF o CSV.

Resultado esperado:  
Reporte generado y descargado con información completa y verificable.

---

## 8. Restricciones Técnicas

- **Plataforma de despliegue:** Kubernetes en nube pública. No se consideran despliegues on-premise en esta fase.
- **Comunicación inter-servicios:** Bus de eventos para procesamiento asíncrono (Kafka o equivalente). Las comunicaciones síncronas deben usar HTTP/REST o gRPC con TLS.
- **Autenticación externa:** Obligatoria mediante OAuth 2.0 / OpenID Connect. No se permiten esquemas de autenticación propietarios para APIs externas.
- **Gestión de secretos:** Obligatoria mediante servicio vault (HashiCorp Vault o equivalente cloud-native). Prohibido el uso de variables de entorno no cifradas para credenciales.
- **Consistencia de datos:** Las transacciones financieras críticas requieren garantías ACID. Las transacciones distribuidas usarán el patrón Saga con compensación y outbox pattern para publicación de eventos.
- **Aplicaciones cliente:** No se desarrollan apps móviles nativas en esta fase; el acceso móvil se realiza mediante las APIs expuestas.
- **Integraciones excluidas:** No incluye integración directa con redes de tarjetas (Visa/Mastercard) ni soporte multimoneda en esta fase.

---

## 9. Supuestos y Dependencias

### Supuestos

- Los usuarios acceden a la plataforma a través de canales digitales (web o apps móviles de terceros que consumen las APIs expuestas).
- El equipo de desarrollo tiene experiencia demostrada en arquitecturas de microservicios y sistemas financieros.
- El oficial de cumplimiento participa activamente en la definición del marco KYC/AML antes del inicio de la implementación.
- Las normativas regulatorias aplicables serán formalmente delimitadas antes del inicio del diseño técnico.
- La infraestructura cloud con soporte completo a Kubernetes estará disponible antes del inicio de la fase de implementación.

### Dependencias Externas

- **APIs de entidades financieras:** Para fondeo, liquidación y confirmación de operaciones de depósito y retiro. Los contratos de servicio deben estar firmados antes del inicio de la implementación.
- **Proveedor KYC:** Servicio externo o interno de validación documental y/o biométrica para el proceso de onboarding.
- **Listas de sanciones AML:** Fuentes de datos actualizadas (OFAC, ONU u otras según normativa) para evaluación de contrapartes.
- **Servicio vault:** Solución de gestión de secretos y claves criptográficas operativa antes del inicio del desarrollo.
- **Infraestructura de mensajería:** Bus de eventos (Kafka o equivalente) para procesamiento asíncrono de transacciones.

---

## 10. Criterios de Aceptación

### RF-001 / RF-002 — Registro y KYC

- El usuario puede completar el registro con datos válidos y únicos.
- El sistema rechaza registros con correo o documento duplicado con mensaje de error descriptivo.
- La cuenta permanece inactiva hasta la aprobación del proceso KYC.
- El resultado del proceso KYC (aprobado / rechazado / en revisión) queda registrado de forma auditable.

---

### RF-003 — Autenticación con MFA

- El usuario no puede acceder sin proporcionar ambos factores (contraseña + código MFA).
- El sistema bloquea la cuenta tras el número configurado de intentos fallidos consecutivos.
- La sesión expira correctamente tras el período de inactividad configurado.
- Tras cambio de contraseña, todas las sesiones activas previas quedan invalidadas.

---

### RF-006 — Depósito de Fondos

- El saldo disponible del usuario se actualiza únicamente tras confirmación de la entidad financiera externa.
- Cada depósito genera un identificador único de operación no repetible.
- Los fondos en tránsito se presentan como saldo pendiente, separados del saldo disponible.
- Los depósitos que superan los límites configurados son rechazados antes de enviarse a la entidad financiera.

---

### RF-007 — Retiro de Fondos

- El sistema rechaza retiros cuando el saldo disponible es insuficiente.
- Los retiros que superan los límites configurados son rechazados con mensaje descriptivo.
- Los retiros evaluados como sospechosos por el motor de fraude quedan retenidos para revisión manual.
- El estado del retiro es consultable en tiempo real.

---

### RF-008 — Transferencia entre Usuarios

- El débito del remitente y el crédito del destinatario son atómicos; no existe estado intermedio donde uno esté debitado y el otro no acreditado.
- El sistema rechaza transferencias a usuarios inexistentes o con cuenta inactiva.
- Las transferencias con idempotency key duplicada devuelven el resultado original sin generar operaciones adicionales.

---

### RF-011 — Idempotencia

- Una operación reintentada con el mismo idempotency key devuelve el resultado original.
- No se generan registros duplicados ni débitos o créditos adicionales por reintentos.

---

### RF-014 — Monitoreo de Fraude

- Las transacciones que disparan reglas de fraude configuradas como bloqueo son rechazadas inmediatamente.
- Las transacciones que disparan reglas configuradas como revisión quedan retenidas y visibles en el dashboard en menos de 30 segundos.

---

### RF-017 — Dashboard de Auditoría

- El auditor puede buscar cualquier transacción por su identificador único y acceder a su historial completo de estados.
- Los reportes regulatorios son exportables en formato PDF y CSV con información completa.
- Las alertas pendientes son gestionables (aprobar/rechazar) con registro obligatorio de justificación.

---

### RNF-001 — Disponibilidad

- El sistema mantiene uptime ≥ 99.9% medido en un período de 90 días post-lanzamiento.
- Un ejercicio de DR verificado previo al lanzamiento demuestra RTO < 1 hora y RPO < 15 minutos.

---

### RNF-002 — Rendimiento

- Las pruebas de carga demuestran tiempo de respuesta ≤ 500 ms en el percentil 95 para consultas bajo carga nominal.

---

### RNF-003 — Seguridad

- Ninguna credencial o dato sensible se almacena en texto plano o en repositorios de código.
- Un pentest externo no identifica vulnerabilidades críticas o altas sin resolver al momento del despliegue productivo.
- La cobertura de pruebas automatizadas en módulos del núcleo financiero y seguridad es ≥ 80%.

---

## 11. Glosario

| Término | Definición |
|---|---|
| AML | Anti-Money Laundering. Conjunto de controles y procedimientos para prevenir el lavado de dinero. |
| ACID | Atomicity, Consistency, Isolation, Durability. Propiedades que garantizan la integridad de transacciones en bases de datos. |
| Circuit Breaker | Patrón de resiliencia que interrumpe llamadas a un servicio degradado para evitar fallos en cascada. |
| CorrelationId | Identificador único que permite correlacionar eventos, logs y trazas de una misma operación a lo largo de múltiples servicios. |
| DR | Disaster Recovery. Plan y capacidad de recuperación del sistema ante eventos catastróficos. |
| GDPR | General Data Protection Regulation. Reglamento europeo de protección de datos personales. |
| Idempotencia | Propiedad de una operación que garantiza que ejecutarla múltiples veces produce el mismo resultado que ejecutarla una sola vez. |
| KYC | Know Your Customer. Proceso de validación de identidad del usuario requerido por normativas financieras. |
| MFA | Multi-Factor Authentication. Autenticación mediante dos o más factores de verificación independientes. |
| Microservicio | Componente de software autónomo y desplegable de forma independiente, responsable de un dominio funcional específico. |
| mTLS | Mutual TLS. Variante de TLS donde tanto cliente como servidor se autentican mutuamente mediante certificados. |
| OAuth 2.0 | Protocolo estándar de autorización para APIs. |
| OFAC | Office of Foreign Assets Control. Agencia del Tesoro de EE.UU. que mantiene listas de sanciones internacionales. |
| OpenID Connect | Capa de identidad sobre OAuth 2.0 para autenticación federada. |
| OpenTelemetry | Estándar abierto para instrumentación, recolección y exportación de telemetría (trazas, métricas, logs). |
| Outbox Pattern | Patrón de diseño para garantizar la publicación confiable de eventos en arquitecturas event-driven sin pérdida de datos. |
| RPO | Recovery Point Objective. Máxima pérdida de datos tolerable medida en tiempo. |
| ROS | Reporte de Operación Sospechosa. Obligación regulatoria de reportar transacciones inusuales a la autoridad competente. |
| RTO | Recovery Time Objective. Tiempo máximo tolerable para restaurar el servicio tras un fallo. |
| Saga | Patrón de diseño para gestionar transacciones distribuidas mediante una secuencia de transacciones locales con compensaciones. |
| Tenant | Unidad de segmentación operativa en un sistema multitenancy (canal de distribución o cliente institucional). |
| TOTP | Time-based One-Time Password. Algoritmo de contraseña de un solo uso basado en tiempo, usado en MFA. |
| UUID | Universally Unique Identifier. Identificador único de 128 bits usado para identificar operaciones sin colisión. |
| Vault | Servicio centralizado para gestión segura de secretos, credenciales y claves criptográficas. |
