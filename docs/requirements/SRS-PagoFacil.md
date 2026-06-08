# Software Requirements Specification (SRS)

**Proyecto:** PagoFacil — Billetera Digital
**Versión:** 1.0
**Fecha:** 2026-06-08
**Estado:** Borrador — Pendiente de revisión por stakeholders

---

## 1. Introducción

### Propósito del Sistema

PagoFacil es una plataforma de billetera digital diseñada para proveer a los usuarios un entorno seguro, centralizado y auditable para la gestión de fondos electrónicos. Su propósito es operar como infraestructura financiera propia de la organización, eliminando la dependencia de terceros para las operaciones de pago.

### Objetivo del Documento

Este documento especifica los requerimientos funcionales y no funcionales del sistema PagoFacil. Sirve como contrato técnico entre los stakeholders del proyecto, el equipo de desarrollo y el equipo de diseño, y como base para la elaboración del diseño del sistema y la arquitectura.

### Alcance General

El sistema cubre el ciclo completo de gestión de fondos electrónicos: registro de usuarios con validación de identidad (KYC), operaciones financieras core (depósito, retiro, transferencia), consulta de saldo e historial, controles de cumplimiento AML, monitoreo antifraude, y exposición de APIs seguras para integración con entidades financieras y pasarelas de pago.

Quedan fuera del alcance de esta versión: aplicaciones móviles nativas, integración directa con redes de tarjetas (Visa/Mastercard), productos de crédito o préstamos, y soporte multimoneda.

### Contexto de Negocio

La ausencia de infraestructura de pagos propia expone a la organización a riesgo regulatorio por incumplimiento de normativas KYC/AML, impide la trazabilidad transaccional completa y limita el crecimiento del ecosistema de pagos. PagoFacil resuelve esta brecha estratégica y sienta las bases para la expansión futura mediante APIs propias y soporte multitenancy.

---

## 2. Descripción General del Sistema

PagoFacil opera como una plataforma fintech centralizada accesible a través de canales digitales (web y APIs). El sistema gestiona identidades de usuario, billeteras electrónicas asociadas a cada cuenta, y el procesamiento de transacciones financieras con garantías de integridad y auditoría.

### Procesos Principales

- **Onboarding de usuarios:** Registro, validación de identidad (KYC), autenticación multifactor y creación de billetera digital.
- **Operaciones financieras:** Depósito de fondos desde entidades externas, transferencias entre usuarios y retiro hacia cuentas bancarias vinculadas.
- **Consulta y reportes:** Acceso en tiempo real al saldo disponible e historial de movimientos con filtros y paginación.
- **Compliance y riesgo:** Validación continua contra listas AML, límites transaccionales configurables y monitoreo de patrones sospechosos.
- **Integración:** Exposición de APIs REST y asíncronas para entidades financieras, pasarelas de pago y canales de distribución externos.
- **Auditoría:** Dashboard centralizado para operaciones administrativas, reportes regulatorios y gestión de alertas de fraude.

### Contexto Operacional

El sistema se despliega sobre Kubernetes en nube pública bajo arquitectura de microservicios con comunicación basada en eventos. Los usuarios finales interactúan a través de interfaces web o mediante APIs expuestas a aplicaciones móviles de terceros. Los operadores y el equipo de compliance acceden a funcionalidades administrativas a través del dashboard de auditoría.

---

## 3. Actores del Sistema

| Actor                     | Descripción                                                          | Responsabilidades Principales                                                                 |
|---------------------------|----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| **Usuario Final**         | Persona natural registrada en la plataforma                          | Gestionar su billetera: consultar saldo, realizar depósitos, retiros y transferencias          |
| **Administrador**         | Operador interno con acceso al back office                           | Gestionar cuentas, resolver disputas, configurar parámetros del sistema                        |
| **Oficial de Cumplimiento** | Responsable de compliance regulatorio (KYC/AML)                   | Revisar alertas AML, aprobar excepciones, generar reportes regulatorios                        |
| **Analista de Fraude**    | Especialista en riesgo operacional                                   | Gestionar alertas de fraude, definir reglas de detección, investigar operaciones sospechosas   |
| **Entidad Financiera**    | Sistema externo (banco, proveedor de fondeo)                         | Proveer fondos, procesar retiros, liquidar operaciones mediante APIs de integración            |
| **Pasarela de Pago**      | Sistema externo para procesamiento de pagos                          | Procesar depósitos y pagos de usuarios externos                                               |
| **Sistema de Auditoría**  | Componente interno del sistema                                       | Registrar trazas de todas las operaciones con correlación y timestamps inmutables             |

---

## 4. Requerimientos Funcionales

---

### Gestión de Identidad y Acceso

---

#### RF-001 — Registro de Usuario

Descripción:
El sistema debe permitir que nuevos usuarios se registren proporcionando nombre completo, documento de identidad, fecha de nacimiento, correo electrónico, número de teléfono y contraseña. El registro inicia el proceso de validación KYC.

---

#### RF-002 — Autenticación con MFA

Descripción:
El sistema debe autenticar a los usuarios mediante correo electrónico y contraseña, seguido de verificación mediante un segundo factor (TOTP, SMS o email OTP). El acceso queda bloqueado si el segundo factor no es verificado.

---

#### RF-003 — Validación de Identidad (KYC)

Descripción:
El sistema debe validar la identidad del usuario mediante la verificación de documentos de identidad y, opcionalmente, validación biométrica. La cuenta queda en estado pendiente hasta que la validación sea aprobada. Sin aprobación KYC, el usuario no puede operar financieramente.

---

#### RF-004 — Gestión de Sesiones

Descripción:
El sistema debe emitir tokens de acceso (JWT) con tiempo de expiración configurable. Debe soportar renovación de sesión mediante refresh token y revocación explícita de tokens ante logout o detección de anomalías.

---

#### RF-005 — Recuperación de Contraseña

Descripción:
El sistema debe permitir al usuario recuperar acceso a su cuenta mediante un flujo verificado por correo electrónico o SMS, con enlace o código de uso único y expiración configurada.

---

#### RF-006 — Gestión de Perfil de Usuario

Descripción:
El sistema debe permitir al usuario actualizar datos de contacto (correo, teléfono). Cambios en datos de identidad deben requerir re-validación KYC. El usuario puede configurar preferencias de notificación.

---

### Gestión de Billetera

---

#### RF-007 — Creación de Billetera Digital

Descripción:
El sistema debe crear automáticamente una billetera digital asociada a la cuenta del usuario una vez que el proceso KYC sea aprobado. Cada billetera tiene un identificador único, saldo inicial cero y moneda base definida por configuración del sistema.

---

#### RF-008 — Consulta de Saldo

Descripción:
El sistema debe proveer al usuario la consulta de su saldo disponible en tiempo real. El saldo debe reflejar solo fondos confirmados y disponibles para operar.

---

#### RF-009 — Consulta de Historial de Movimientos

Descripción:
El sistema debe proveer un historial paginado de movimientos financieros con filtros por rango de fechas, tipo de operación y estado. Cada movimiento debe incluir: identificador de operación, tipo, monto, saldo resultante, timestamp y estado.

---

#### RF-010 — Configuración de Límites Transaccionales

Descripción:
El sistema debe permitir definir y aplicar límites transaccionales configurables por perfil de usuario (nivel KYC), tipo de operación (depósito, retiro, transferencia) y período (diario, semanal, mensual). Los límites pueden ser ajustados por el administrador. El sistema debe rechazar operaciones que excedan los límites activos.

---

### Operaciones Financieras

---

#### RF-011 — Depósito de Fondos

Descripción:
El sistema debe permitir al usuario depositar fondos en su billetera desde una entidad financiera o pasarela de pago externa. El sistema debe registrar el depósito con un identificador único de operación, validar el monto contra los límites configurados, y acreditar el saldo solo tras confirmación del origen de fondos.

---

#### RF-012 — Transferencia entre Usuarios

Descripción:
El sistema debe permitir a un usuario transferir fondos a otro usuario de la plataforma identificado por correo electrónico, número de teléfono o identificador de cuenta. La operación debe validar saldo suficiente, límites transaccionales y estado KYC de ambas partes antes de ejecutarse.

---

#### RF-013 — Retiro de Fondos

Descripción:
El sistema debe permitir al usuario retirar fondos hacia una cuenta bancaria previamente vinculada y verificada. El retiro debe validar saldo disponible, límites transaccionales y requerir confirmación explícita del usuario antes de ejecutarse.

---

#### RF-014 — Vinculación de Cuenta Bancaria

Descripción:
El sistema debe permitir al usuario vincular cuentas bancarias externas verificadas como destino de retiros. La vinculación debe verificar la titularidad de la cuenta mediante depósito de verificación o certificado bancario.

---

#### RF-015 — Confirmación y Notificación de Operación

Descripción:
El sistema debe generar confirmación de cada operación financiera ejecutada, incluyendo identificador único, monto, timestamp y saldo resultante. La confirmación debe ser notificada al usuario mediante el canal configurado (email, SMS o push).

---

#### RF-016 — Idempotencia de Transacciones

Descripción:
El sistema debe garantizar que operaciones financieras enviadas con el mismo identificador de idempotencia (idempotency key) no sean procesadas más de una vez. Reintentos con el mismo identificador deben retornar el resultado de la operación original sin ejecutarla de nuevo.

---

#### RF-017 — Conciliación Automática

Descripción:
El sistema debe ejecutar procesos periódicos de conciliación para comparar el estado interno de transacciones con el estado reportado por entidades externas. Discrepancias deben generar alertas automáticas para revisión por el equipo de operaciones.

---

### Compliance y Control de Riesgo

---

#### RF-018 — Validación AML en Onboarding

Descripción:
El sistema debe validar al usuario contra listas de sanciones internacionales y listas negras locales durante el proceso de registro. Un resultado positivo debe bloquear la aprobación KYC y generar una alerta para revisión por el oficial de cumplimiento.

---

#### RF-019 — Validación AML en Operaciones

Descripción:
El sistema debe evaluar las partes involucradas en cada transacción financiera contra listas de sanciones vigentes antes de ejecutar la operación. Coincidencias deben bloquear la operación y generar alerta de compliance.

---

#### RF-020 — Monitoreo de Fraude en Tiempo Real

Descripción:
El sistema debe analizar el patrón transaccional de cada operación en tiempo real contra reglas de detección de fraude configuradas (velocidad de operaciones, montos inusuales, geolocalización, comportamiento fuera de patrón). Operaciones de alto riesgo deben ser marcadas para revisión o bloqueadas según el nivel de riesgo calculado.

---

#### RF-021 — Gestión de Alertas de Fraude

Descripción:
El sistema debe registrar y notificar alertas de fraude al analista de fraude responsable. Las alertas deben incluir identificador, operación asociada, regla disparada, nivel de riesgo y timestamp. El analista debe poder aprobar, rechazar o escalar cada alerta.

---

#### RF-022 — Reporte de Operaciones Inusuales

Descripción:
El sistema debe permitir al oficial de cumplimiento generar reportes de operaciones inusuales (ROS/SAR) en el formato requerido por la normativa regulatoria aplicable, con exportación en formatos estándar.

---

### Integración y APIs

---

#### RF-023 — API de Integración con Entidades Financieras

Descripción:
El sistema debe exponer APIs REST seguras, autenticadas mediante OAuth 2.0 / OIDC, para que entidades financieras puedan notificar depósitos, confirmar retiros y consultar el estado de operaciones. Las APIs deben implementar versionado y contratos estables (anti-corruption layer).

---

#### RF-024 — API de Integración con Pasarelas de Pago

Descripción:
El sistema debe exponer endpoints para la recepción de notificaciones de pago desde pasarelas externas. El sistema debe validar la autenticidad de las notificaciones mediante firma digital o token de webhook antes de acreditar fondos.

---

#### RF-025 — Bus de Eventos

Descripción:
El sistema debe publicar eventos de dominio (depósito completado, transferencia iniciada, fraude detectado, KYC aprobado) en un bus de eventos para consumo por otros microservicios y sistemas suscriptores. Los eventos deben incluir correlationId, timestamp y versión de esquema.

---

### Auditoría y Observabilidad

---

#### RF-026 — Dashboard de Auditoría

Descripción:
El sistema debe proveer un dashboard para administradores y oficiales de cumplimiento que permita consultar el historial de operaciones del sistema, filtrar por usuario, tipo de evento, rango de fechas y estado. Debe incluir vistas de alertas activas y reportes de actividad.

---

#### RF-027 — Trazabilidad de Operaciones

Descripción:
El sistema debe registrar una traza auditable e inmutable de cada evento de negocio (creación de cuenta, inicio y resultado de operaciones financieras, cambios de estado KYC, alertas de fraude). Las trazas deben incluir actor, acción, timestamp, IP de origen y correlationId.

---

#### RF-028 — Generación de Reportes Regulatorios

Descripción:
El sistema debe permitir generar reportes periódicos requeridos por la normativa regulatoria aplicable, incluyendo volumen transaccional, operaciones bloqueadas, alertas AML y estado del proceso KYC por período.

---

## 5. Requerimientos No Funcionales

---

### RNF-001 — Rendimiento

**Categoría:** Rendimiento

El percentil 95 del tiempo de respuesta para operaciones de consulta (saldo, historial) debe ser inferior a 500ms bajo carga nominal. Las operaciones financieras (transferencia, depósito, retiro) deben completarse o encolarse con confirmación en menos de 2 segundos desde la recepción de la solicitud.

---

### RNF-002 — Disponibilidad

**Categoría:** Disponibilidad

El sistema debe mantener una disponibilidad mínima del 99.9% mensual (equivalente a menos de 44 minutos de downtime mensual). Los componentes críticos (autenticación, procesamiento de transacciones) deben implementar redundancia activa-activa.

---

### RNF-003 — Seguridad en Tránsito

**Categoría:** Seguridad

Toda comunicación externa e interna entre microservicios debe cifrarse mediante TLS 1.2 o superior. Certificados caducados o protocolos inferiores deben rechazarse en todos los puntos de entrada.

---

### RNF-004 — Seguridad en Reposo

**Categoría:** Seguridad

Los datos sensibles (PII, credenciales, datos financieros) deben almacenarse cifrados con AES-256. Claves de cifrado deben gestionarse mediante un sistema de vault externo (e.g., HashiCorp Vault) con rotación automática configurada.

---

### RNF-005 — Autenticación y Autorización

**Categoría:** Seguridad

Todos los endpoints de APIs externas e internas deben implementar autenticación OAuth 2.0 / OpenID Connect. El control de acceso debe seguir el principio de mínimo privilegio con roles bien definidos. Tokens de acceso deben tener expiración corta (máximo 15 minutos para tokens de operación).

---

### RNF-006 — Escalabilidad Horizontal

**Categoría:** Escalabilidad

Los microservicios críticos (gateway, transacciones, notificaciones) deben escalar horizontalmente de forma automática mediante HPA de Kubernetes ante incremento de carga. El sistema debe soportar al menos 10x el volumen transaccional base sin rediseño arquitectónico.

---

### RNF-007 — Consistencia Financiera

**Categoría:** Consistencia

Las operaciones financieras que impliquen modificación de saldos deben ejecutarse con garantías ACID. En operaciones distribuidas entre microservicios, el sistema debe implementar patrones de consistencia eventual con compensación (Saga Pattern) y mecanismos de reconciliación.

---

### RNF-008 — Recuperación ante Desastres

**Categoría:** Recuperación

El sistema debe cumplir un RTO (Recovery Time Objective) menor a 1 hora y un RPO (Recovery Point Objective) menor a 15 minutos ante fallo de cualquier componente crítico. El plan de DR debe ser probado mediante drill periódico documentado.

---

### RNF-009 — Observabilidad

**Categoría:** Observabilidad

El sistema debe implementar logging estructurado (JSON), métricas de negocio y técnicas exportadas a un sistema de monitoreo centralizado, y trazas distribuidas mediante OpenTelemetry. Cada operación debe poder rastrearse de extremo a extremo mediante su correlationId.

---

### RNF-010 — Cumplimiento Normativo

**Categoría:** Cumplimiento

El sistema debe cumplir con la legislación de protección de datos personales aplicable (GDPR o equivalente local), normativas KYC/AML vigentes y los períodos mínimos de retención de datos financieros exigidos por la regulación. El diseño debe facilitar el derecho al olvido para datos no financieros.

---

### RNF-011 — Multitenancy

**Categoría:** Arquitectura

El sistema debe soportar multitenancy desde el diseño inicial, permitiendo la operación de múltiples entidades financieras aliadas sobre la misma infraestructura con aislamiento de datos y configuración por tenant.

---

### RNF-012 — Mantenibilidad

**Categoría:** Mantenibilidad

La arquitectura de microservicios debe garantizar separación clara de responsabilidades con contratos de API versionados. Cada servicio debe poder desplegarse, escalarse y actualizarse de forma independiente sin afectar la disponibilidad del sistema.

---

### RNF-013 — Idempotencia

**Categoría:** Confiabilidad

Todas las operaciones financieras expuestas mediante API deben ser idempotentes. El sistema debe soportar reintentos seguros de operaciones sin riesgo de duplicación de transacciones.

---

## 6. Reglas de Negocio

**RN-001** — Un usuario no puede realizar operaciones financieras hasta que su proceso KYC esté completamente aprobado.

**RN-002** — El saldo de una billetera no puede ser negativo bajo ninguna circunstancia. Operaciones que generen saldo negativo deben ser rechazadas antes de ejecutarse.

**RN-003** — Cada operación financiera debe recibir un identificador único (UUID v4) e inmutable en el momento de su creación. Este identificador no puede reutilizarse ni modificarse.

**RN-004** — Una operación financiera confirmada no puede revertirse unilateralmente por el usuario. Las reversiones requieren proceso formal de disputa gestionado por el administrador.

**RN-005** — Los límites transaccionales son acumulativos dentro del período configurado. Una operación que exceda el límite remanente del período debe ser rechazada parcial o totalmente.

**RN-006** — Una cuenta vinculada a una coincidencia positiva en listas AML queda suspendida automáticamente hasta resolución manual por el oficial de cumplimiento.

**RN-007** — Los datos de transacciones financieras deben conservarse durante el período mínimo exigido por la normativa regulatoria aplicable. No pueden eliminarse antes de cumplido dicho período.

**RN-008** — Las credenciales de usuarios y tokens de sesión no pueden almacenarse en texto plano en ningún componente del sistema.

**RN-009** — Las transferencias entre usuarios requieren que ambas cuentas tengan estado KYC aprobado y estén activas en el momento de la operación.

**RN-010** — El sistema debe bloquear preventivamente cuentas que superen el umbral de intentos fallidos de autenticación configurado, requiriendo desbloqueo explícito.

**RN-011** — Un retiro solo puede ejecutarse hacia una cuenta bancaria previamente vinculada y verificada a nombre del titular de la billetera.

**RN-012** — Eventos de dominio publicados en el bus de mensajes deben incluir siempre el correlationId de la operación que los originó para garantizar trazabilidad end-to-end.

---

## 7. Casos de Uso Principales

---

### CU-001 — Registro y Onboarding de Usuario

**Actores:** Usuario Final, Sistema KYC (externo)

**Precondiciones:**
El usuario no tiene cuenta registrada en el sistema.

**Flujo principal:**
1. El usuario proporciona datos personales, correo electrónico, contraseña y acepta los términos de servicio.
2. El sistema valida formato y unicidad del correo electrónico.
3. El sistema envía un código de verificación al correo electrónico.
4. El usuario confirma su correo mediante el código.
5. El sistema inicia el proceso KYC solicitando documentos de identidad.
6. El sistema integrado de KYC valida los documentos y notifica el resultado.
7. Si el KYC es aprobado, el sistema activa la cuenta y crea la billetera digital asociada.
8. El usuario recibe notificación de cuenta activa y puede iniciar sesión.

**Resultado esperado:**
Cuenta de usuario activa con billetera digital creada, saldo cero, lista para operar.

---

### CU-002 — Autenticación con MFA

**Actores:** Usuario Final

**Precondiciones:**
El usuario tiene cuenta activa con KYC aprobado.

**Flujo principal:**
1. El usuario ingresa correo electrónico y contraseña.
2. El sistema valida las credenciales.
3. El sistema solicita el segundo factor de autenticación.
4. El usuario proporciona el código TOTP, SMS o email OTP.
5. El sistema valida el segundo factor y emite los tokens de sesión (access token + refresh token).
6. El usuario accede a la plataforma.

**Resultado esperado:**
Sesión activa con acceso a la plataforma según el rol del usuario.

---

### CU-003 — Depósito de Fondos

**Actores:** Usuario Final, Entidad Financiera / Pasarela de Pago

**Precondiciones:**
Usuario autenticado con cuenta activa y KYC aprobado.

**Flujo principal:**
1. El usuario selecciona la opción de depósito e indica el monto.
2. El sistema valida el monto contra los límites transaccionales vigentes.
3. El sistema genera una orden de depósito con identificador único y redirige al usuario a la entidad financiera o pasarela seleccionada.
4. La entidad financiera procesa el pago y notifica el resultado al sistema mediante webhook o API.
5. El sistema valida la autenticidad de la notificación.
6. El sistema acredita el monto en la billetera del usuario, registra la transacción y publica el evento correspondiente.
7. El sistema notifica al usuario la confirmación del depósito.

**Resultado esperado:**
Saldo de billetera incrementado por el monto depositado. Transacción registrada con identificador único.

---

### CU-004 — Transferencia entre Usuarios

**Actores:** Usuario Emisor, Usuario Receptor

**Precondiciones:**
Ambos usuarios autenticados y con cuentas activas, KYC aprobado y saldo suficiente en el emisor.

**Flujo principal:**
1. El usuario emisor ingresa el identificador del destinatario (correo, teléfono o ID de cuenta) y el monto.
2. El sistema resuelve la cuenta del destinatario y presenta un resumen de la operación para confirmación.
3. El usuario emisor confirma la operación.
4. El sistema valida saldo disponible, límites transaccionales y estado AML de ambas partes.
5. El sistema ejecuta la operación: débita el saldo del emisor y acredita el saldo del receptor de forma atómica.
6. El sistema registra la transacción con identificador único y publica los eventos de dominio.
7. Ambos usuarios reciben notificación de la operación.

**Resultado esperado:**
Saldo del emisor reducido y saldo del receptor incrementado por el monto transferido. Transacción registrada con identificador único en ambas cuentas.

---

### CU-005 — Retiro de Fondos

**Actores:** Usuario Final, Entidad Financiera

**Precondiciones:**
Usuario autenticado con cuenta activa, KYC aprobado, cuenta bancaria vinculada y saldo suficiente.

**Flujo principal:**
1. El usuario selecciona la cuenta bancaria de destino e indica el monto de retiro.
2. El sistema valida saldo disponible y límites transaccionales.
3. El sistema presenta un resumen para confirmación explícita del usuario.
4. El usuario confirma el retiro.
5. El sistema registra la solicitud de retiro, reserva el monto en la billetera y encola la operación hacia la entidad financiera.
6. La entidad financiera procesa el retiro y notifica el resultado.
7. Si el retiro es exitoso, el sistema confirma la operación y actualiza el saldo. Si falla, el sistema revierte la reserva y notifica al usuario.

**Resultado esperado:**
Fondos transferidos a la cuenta bancaria del usuario. Saldo de billetera reducido por el monto retirado.

---

### CU-006 — Gestión de Alerta de Fraude

**Actores:** Analista de Fraude, Sistema de Monitoreo

**Precondiciones:**
El motor de detección de fraude ha generado una alerta sobre una operación.

**Flujo principal:**
1. El sistema de monitoreo detecta un patrón sospechoso y genera una alerta con nivel de riesgo.
2. La operación es marcada para revisión (o bloqueada si el riesgo es crítico).
3. El analista de fraude recibe notificación de la alerta en el dashboard.
4. El analista revisa el detalle de la operación, el historial del usuario y las reglas disparadas.
5. El analista decide: aprobar la operación (liberarla), rechazarla o escalar al oficial de cumplimiento.
6. El sistema ejecuta la decisión, notifica al usuario si corresponde y registra la resolución en la traza de auditoría.

**Resultado esperado:**
Alerta resuelta con decisión documentada. Operación liberada, rechazada o escalada según el análisis.

---

### CU-007 — Integración con Entidad Financiera

**Actores:** Entidad Financiera (sistema externo)

**Precondiciones:**
La entidad financiera está registrada como integración autorizada con credenciales OAuth 2.0 válidas.

**Flujo principal:**
1. La entidad financiera obtiene un token de acceso mediante flujo OAuth 2.0 (client credentials).
2. La entidad financiera invoca el endpoint correspondiente (notificación de depósito, confirmación de retiro, consulta de estado).
3. El sistema valida el token, verifica permisos y procesa la solicitud.
4. El sistema retorna la respuesta con el estado de la operación e identificadores de correlación.
5. En caso de operación financiera, el sistema publica el evento de dominio correspondiente.

**Resultado esperado:**
Operación procesada correctamente con respuesta documentada. Evento publicado en el bus para consumo interno.

---

## 8. Restricciones Técnicas

- **Arquitectura:** El sistema debe implementarse como un conjunto de microservicios desplegados en Kubernetes. No se permite una arquitectura monolítica.
- **Comunicación interna:** Los microservicios deben comunicarse mediante APIs REST síncronas (para operaciones que requieren respuesta inmediata) y un bus de mensajes asíncrono (para eventos de dominio y procesamiento eventual).
- **Autenticación externa:** Todas las APIs expuestas externamente deben implementar OAuth 2.0 / OpenID Connect. No se permiten esquemas de autenticación propietarios sin estándar.
- **Cifrado:** TLS 1.2 o superior obligatorio en toda comunicación. AES-256 obligatorio para datos en reposo sensibles.
- **Gestión de secretos:** Las credenciales, claves y tokens no pueden almacenarse en código fuente, repositorios de configuración no cifrados ni variables de entorno en texto plano. Se requiere un sistema de vault dedicado.
- **Idempotencia:** Todas las APIs de operaciones financieras deben aceptar y respetar un header de idempotency key.
- **Multitenancy:** El modelo de datos y los servicios deben implementar aislamiento por tenant desde el diseño inicial.
- **Observabilidad:** Uso obligatorio de OpenTelemetry para trazas distribuidas. Los logs deben emitirse en formato JSON estructurado.
- **Infraestructura:** La infraestructura de despliegue es nube pública con soporte Kubernetes. No se contempla infraestructura on-premise en esta fase.

---

## 9. Supuestos y Dependencias

### Supuestos

- Los usuarios accederán a la plataforma desde canales digitales (navegador web o APIs expuestas a apps móviles de terceros) con conexión estable a internet.
- Las normativas KYC/AML específicas de la jurisdicción de operación serán definidas y documentadas por el oficial de cumplimiento antes del inicio del desarrollo del módulo de compliance.
- El equipo de desarrollo cuenta con experiencia en arquitecturas de microservicios, patrones de consistencia distribuida (Saga, CQRS) y seguridad en aplicaciones financieras.
- El equipo de operaciones estará disponible para la configuración y mantenimiento de la infraestructura desde las fases tempranas del proyecto.
- Los volúmenes transaccionales iniciales y proyectados serán definidos antes del diseño técnico para establecer baselines de rendimiento y pruebas de carga.
- El sponsor ejecutivo aprobará el inicio del proyecto y designará al Project Manager antes del inicio de la fase de diseño.

### Dependencias

- **Proveedor de validación KYC:** Servicio externo para verificación de documentos de identidad y validación biométrica. Los contratos y SLAs deben estar definidos antes del desarrollo del módulo de onboarding.
- **Entidades financieras:** Disponibilidad de APIs o mecanismos de integración documentados para depósitos, retiros y liquidación. Se requieren acuerdos previos al desarrollo de las integraciones.
- **Pasarelas de pago:** APIs de notificación de pago con soporte para webhooks firmados o mecanismos equivalentes de autenticación.
- **Listas de sanciones AML:** Proveedor de listas actualizadas (OFAC, ONU, locales) con API de consulta en tiempo real o actualizaciones periódicas.
- **Servicio de mensajería:** Proveedor de envío de SMS y correo electrónico para notificaciones y MFA.
- **Sistema de vault:** HashiCorp Vault u equivalente para gestión de secretos y claves de cifrado.
- **Infraestructura cloud:** Proveedor de nube pública con soporte Kubernetes gestionado, storage persistente y servicios de red.

---

## 10. Criterios de Aceptación

---

### RF-001 — Registro de Usuario

- El usuario puede completar el registro proporcionando todos los campos requeridos.
- El sistema rechaza correos electrónicos duplicados con mensaje de error claro.
- El sistema no permite acceso operacional hasta completar verificación de correo y aprobación KYC.
- Las contraseñas son almacenadas con hash seguro (bcrypt o Argon2); nunca en texto plano.

---

### RF-002 — Autenticación con MFA

- El sistema rechaza el acceso si el segundo factor no es proporcionado o es incorrecto.
- Los códigos OTP/TOTP tienen un tiempo de validez máximo de 5 minutos.
- Tras el número configurado de intentos fallidos (mínimo 5), la cuenta queda bloqueada automáticamente.
- Los tokens de sesión expiran según el tiempo configurado y no son reutilizables tras logout.

---

### RF-003 — Validación de Identidad (KYC)

- El sistema bloquea operaciones financieras en cuentas con KYC pendiente o rechazado.
- Una coincidencia positiva en listas AML durante el KYC genera alerta y suspende la activación de la cuenta.
- El resultado del KYC queda registrado con timestamp y auditable.

---

### RF-011 — Depósito de Fondos

- El saldo se acredita únicamente tras confirmación válida de la entidad externa.
- Notificaciones de depósito con firma inválida o token no autorizado son rechazadas sin procesar.
- El sistema no acredita dos veces el mismo depósito (idempotencia verificada).
- El sistema rechaza depósitos que excedan el límite transaccional configurado.

---

### RF-012 — Transferencia entre Usuarios

- El sistema no ejecuta la transferencia si el saldo del emisor es insuficiente.
- El débito del emisor y el crédito del receptor ocurren de forma atómica; no puede existir un estado intermedio donde un saldo esté modificado y el otro no.
- La operación es rechazada si cualquiera de las dos partes tiene estado KYC no aprobado o cuenta suspendida.
- Reintentos con el mismo idempotency key retornan el resultado original sin duplicar la operación.

---

### RF-013 — Retiro de Fondos

- El sistema no ejecuta el retiro si el saldo disponible es insuficiente.
- Solo se permite retiro hacia cuentas bancarias vinculadas y verificadas a nombre del titular.
- Si la entidad financiera reporta fallo en el retiro, el saldo reservado es liberado en la billetera.
- El retiro queda registrado con identificador único, estado y timestamps de cada transición.

---

### RF-016 — Idempotencia de Transacciones

- Dos solicitudes con el mismo idempotency key ejecutadas concurrentemente resultan en una única operación procesada.
- La segunda solicitud recibe la respuesta de la operación original sin errores de duplicación.

---

### RF-020 — Monitoreo de Fraude en Tiempo Real

- Las reglas de fraude se evalúan antes de confirmar la operación; no de forma retroactiva.
- Una operación con riesgo crítico queda bloqueada automáticamente sin intervención humana.
- Cada alerta generada es registrada con la operación asociada, la regla disparada y el nivel de riesgo.

---

### RF-026 — Dashboard de Auditoría

- El dashboard requiere autenticación y solo es accesible para roles autorizados (administrador, oficial de cumplimiento, analista de fraude).
- Los registros de auditoría son inmutables; no pueden editarse ni eliminarse desde la interfaz.
- Los filtros por usuario, fechas y tipo de evento retornan resultados correctos y consistentes con los registros del sistema.

---

## 11. Glosario

| Término                   | Definición                                                                                                                                      |
|---------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| **Billetera Digital**     | Cuenta electrónica que almacena fondos virtuales asociada a un usuario registrado en la plataforma                                              |
| **KYC**                   | Know Your Customer — proceso de verificación de identidad del usuario exigido por normativas financieras                                        |
| **AML**                   | Anti-Money Laundering — conjunto de controles y procedimientos para detectar y prevenir el lavado de dinero                                     |
| **MFA**                   | Multi-Factor Authentication — autenticación mediante dos o más factores independientes de verificación                                          |
| **TOTP**                  | Time-based One-Time Password — código de verificación generado algorítmicamente y válido por un período corto                                   |
| **OAuth 2.0 / OIDC**      | Estándares de autorización e identidad utilizados para autenticación segura en APIs                                                             |
| **JWT**                   | JSON Web Token — token firmado digitalmente que transporta claims de identidad y autorización                                                   |
| **Idempotencia**          | Propiedad de una operación que garantiza que ejecutarla múltiples veces produce el mismo resultado que ejecutarla una sola vez                  |
| **Idempotency Key**       | Identificador único enviado por el cliente para garantizar que una operación no sea procesada más de una vez                                    |
| **CorrelationId**         | Identificador único que agrupa todos los eventos y trazas relacionadas con una misma operación de negocio para facilitar su rastreo              |
| **Saga Pattern**          | Patrón de gestión de transacciones distribuidas que coordina una secuencia de transacciones locales con mecanismos de compensación ante fallos  |
| **CQRS**                  | Command Query Responsibility Segregation — patrón que separa las operaciones de escritura (comandos) de las de lectura (consultas)              |
| **Conciliación**          | Proceso de verificación periódica que compara el estado interno de transacciones con registros externos para detectar discrepancias             |
| **Multitenancy**          | Arquitectura que permite a múltiples organizaciones (tenants) compartir la misma infraestructura con aislamiento completo de datos               |
| **RTO**                   | Recovery Time Objective — tiempo máximo tolerable para restaurar el servicio tras un incidente                                                  |
| **RPO**                   | Recovery Point Objective — período máximo de pérdida de datos tolerable ante un incidente                                                      |
| **TLS**                   | Transport Layer Security — protocolo de cifrado para comunicaciones seguras en red                                                              |
| **AES-256**               | Advanced Encryption Standard con clave de 256 bits — estándar de cifrado simétrico para datos en reposo                                        |
| **OpenTelemetry**         | Framework de observabilidad para la recolección de trazas, métricas y logs en sistemas distribuidos                                            |
| **HPA**                   | Horizontal Pod Autoscaler — mecanismo de Kubernetes para escalar automáticamente el número de réplicas de un servicio según métricas de carga   |
| **Anti-corruption Layer** | Capa de traducción que aisla el modelo interno del sistema de los modelos de integraciones externas, previniendo la propagación de dependencias |
| **ROS / SAR**             | Reporte de Operación Sospechosa (Suspicious Activity Report) — documento regulatorio para notificar operaciones potencialmente ilícitas         |
| **PII**                   | Personally Identifiable Information — información personal identificable protegida bajo normativas de privacidad de datos                       |

---

*Documento generado como parte de la etapa de Análisis de Requerimientos del SDLC. Versión sujeta a revisión y aprobación por los stakeholders identificados.*
