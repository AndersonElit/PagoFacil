# Strategic Design Document — Seguridad

**Proyecto:** PagoFacil — Billetera Digital
**Conjunto SDD:** Este documento forma parte del Strategic Design Document junto con `SDD-PagoFacil-domain.md` y `SDD-PagoFacil-architecture.md`.
**Versión:** 1.0
**Fecha:** 2026-06-08

---

## 1. Modelo de Seguridad

### Principios de Seguridad

| Principio | Aplicación en PagoFacil |
|-----------|------------------------|
| **Zero Trust** | Ningún componente interno es confiable por defecto. Toda comunicación entre microservicios y desde el exterior requiere autenticación y autorización explícita. |
| **Least Privilege** | Cada servicio, rol y token tiene acceso únicamente a los recursos y operaciones estrictamente necesarios para su función. |
| **Defense in Depth** | La seguridad se implementa en capas: API Gateway, capa de autenticación, capa de autorización, cifrado en tránsito, cifrado en reposo y auditoría inmutable. Una capa comprometida no expone el sistema completo. |
| **Secure by Design** | Los controles de seguridad (MFA, KYC, AML, límites transaccionales) son parte del flujo de negocio, no capas añadidas posteriores. |
| **Fail Secure** | Ante fallo o incertidumbre en una evaluación de seguridad o riesgo, el sistema rechaza la operación y genera una alerta. No se opera en modo degradado sin controles activos. |
| **Immutable Audit Trail** | Toda acción de negocio queda registrada con actor, acción, timestamp, IP y correlationId. Los registros de auditoría no pueden ser modificados ni eliminados desde ninguna interfaz. |
| **Data Minimization** | Solo se recopila y retiene la información necesaria para operar y cumplir regulaciones. El diseño facilita el derecho al olvido para datos PII no financieros. |

---

### Identidad y Autenticación

El modelo de identidad de PagoFacil distingue dos planos de autenticación:

**Plano de usuarios finales y operadores internos:**
- Autenticación gestionada por AWS Cognito (User Pool) con soporte OAuth 2.0 / OpenID Connect.
- Acceso protegido por autenticación multifactor obligatoria (MFA): TOTP, SMS OTP o email OTP.
- Los tokens de acceso tienen expiración corta (máximo 15 minutos para tokens de operación).
- Los refresh tokens permiten renovación de sesión sin re-autenticación completa, con revocación explícita ante logout o anomalía.
- El sistema bloquea cuentas que superen el umbral configurado de intentos fallidos; el desbloqueo es explícito.

**Plano de sistemas externos (entidades financieras, pasarelas):**
- Autenticación machine-to-machine mediante OAuth 2.0 (client credentials flow).
- Las notificaciones de pago desde pasarelas se validan mediante firma digital o token de webhook antes de procesar cualquier acreditación de fondos.
- Las credenciales de integración se gestionan exclusivamente en AWS Secrets Manager; prohibido almacenarlas en código fuente o variables de entorno en texto plano.

---

### Autorización

El control de acceso sigue el principio de mínimo privilegio. Los roles están definidos por bounded context y nivel de acceso.

| Rol | Bounded Context | Nivel de Acceso |
|-----|-----------------|----------------|
| Usuario Final | Wallet Context | Lectura de saldo propio, historial propio; escritura de operaciones financieras sobre su billetera |
| Usuario Final | Identity Context | Lectura y actualización de perfil propio; gestión de MFA propio |
| Administrador | Identity Context | Lectura y gestión de cuentas; desbloqueo y suspensión manual |
| Administrador | Wallet Context | Lectura de transacciones; gestión de disputas |
| Administrador | Audit Context | Lectura completa del dashboard de auditoría; sin escritura |
| Oficial de Cumplimiento | Fraud & Compliance Context | Lectura y resolución de alertas AML; aprobación de excepciones |
| Oficial de Cumplimiento | Audit Context | Lectura completa; generación de reportes regulatorios |
| Oficial de Cumplimiento | Reporting Context | Solicitud y descarga de reportes regulatorios |
| Analista de Fraude | Fraud & Compliance Context | Lectura, resolución y escalamiento de alertas de fraude |
| Analista de Fraude | Audit Context | Lectura del dashboard con filtros de fraude |
| Entidad Financiera (sistema externo) | Integration Context | Escritura de notificaciones de depósito/retiro; consulta de estado de operaciones propias |
| Pasarela de Pago (sistema externo) | Integration Context | Escritura de notificaciones de pago validadas |

> Los claims del JWT emitido por AWS Cognito incluyen el rol y el `tenant_id`. Cada microservicio verifica estos claims en cada solicitud antes de ejecutar cualquier operación.

---

### Datos Sensibles

| Dato | Clasificación | Justificación |
|------|--------------|---------------|
| Contraseñas de usuario | Crítico | Credencial de acceso; almacenada únicamente como hash (bcrypt / Argon2); nunca en texto plano |
| Documentos de identidad (KYC) | Crítico | PII de alta sensibilidad; sujeto a normativas de protección de datos y acceso restringido al proceso KYC |
| Datos biométricos (si aplica) | Crítico | PII de máxima sensibilidad; procesados por el proveedor KYC externo; no almacenados en PagoFacil |
| Saldo de billetera | Alto | Dato financiero personal; acceso restringido al titular y roles autorizados |
| Historial de transacciones | Alto | Dato financiero regulado; período de retención mínimo exigido por normativa (RN-007); no eliminable antes de cumplido dicho período |
| Información personal (nombre, fecha de nacimiento, email, teléfono) | Alto | PII protegida bajo normativas de privacidad; sujeta a derecho al olvido para datos no financieros (RNF-010) |
| Números de cuenta bancaria vinculada | Alto | Dato financiero sensible; acceso restringido al titular y al proceso de retiro |
| Tokens de sesión (access token, refresh token) | Alto | Credenciales de sesión; expiración corta; revocación ante logout o anomalía; nunca en texto plano |
| Claves de cifrado | Crítico | Gestionadas exclusivamente en AWS Secrets Manager con rotación automática; nunca en código fuente ni repositorios |
| Credenciales de integración (client credentials OAuth) | Crítico | Claves de acceso de sistemas externos; gestionadas en AWS Secrets Manager |
| Resultados de validación AML | Alto | Dato de compliance regulatorio; acceso restringido al Oficial de Cumplimiento y al sistema |
| Alertas de fraude y resoluciones | Alto | Dato operacional sensible; acceso restringido a roles de compliance y fraude |
| IP de origen de operaciones | Medio | Requerida para trazabilidad de auditoría (RF-027); no expuesta en interfaces de usuario |

---

### Auditoría

Los siguientes eventos requieren registro de traza inmutable con actor, acción, timestamp, IP de origen y correlationId:

- Creación, activación, suspensión y bloqueo de cuentas de usuario
- Inicio y resultado del proceso KYC (aprobación, rechazo, suspensión AML)
- Inicio de sesión exitoso y fallido; bloqueo por intentos fallidos
- Revocación de tokens de sesión
- Creación y cambio de estado de toda operación financiera (depósito, transferencia, retiro)
- Eventos de compensación de sagas
- Creación, asignación, resolución y escalamiento de alertas de fraude y AML
- Acceso al dashboard de auditoría por rol
- Generación y descarga de reportes regulatorios
- Cambios de configuración del sistema (límites transaccionales, reglas de fraude)
- Vinculación y verificación de cuentas bancarias

> Los registros de auditoría son inmutables desde el momento de su creación. No pueden editarse ni eliminarse desde ninguna interfaz del sistema. El período de retención de datos de transacciones financieras se rige por la normativa regulatoria aplicable (RN-007).

---

## 2. Threat Modeling

Identificación de amenazas mediante el marco STRIDE, ordenadas por impacto descendente.

| ID | Categoría STRIDE | Amenaza | Componente Afectado | Impacto | Mitigación Propuesta |
|----|------------------|---------|---------------------|---------|----------------------|
| TH-001 | Tampering | Alteración del monto de una notificación de depósito o retiro en tránsito desde una entidad financiera o pasarela | Integration Context — endpoints de webhook | Alto | Validación obligatoria de firma digital o token de webhook antes de procesar cualquier notificación; rechazo sin procesamiento si la firma es inválida |
| TH-002 | Tampering | Manipulación del saldo de una billetera mediante solicitudes directas a la API del Wallet Context sin pasar por la orquestación del Integration Context | Wallet Context | Alto | El Wallet Context solo acepta instrucciones de débito/crédito autenticadas con token de servicio interno; los usuarios finales no tienen acceso directo a endpoints de modificación de saldo |
| TH-003 | Elevation of Privilege | Un usuario final obtiene acceso a endpoints o datos de otros usuarios o de roles administrativos mediante manipulación de claims en el JWT | API Gateway, todos los bounded contexts | Alto | Validación de claims JWT en cada microservicio; el `tenant_id` y el `userId` se extraen del token firmado por Cognito — nunca del body de la solicitud; tokens de corta duración (máximo 15 minutos) |
| TH-004 | Spoofing | Suplantación de identidad de una entidad financiera o pasarela para acreditar fondos fraudulentos | Integration Context — endpoints de integración | Alto | Autenticación machine-to-machine con OAuth 2.0 (client credentials); validación de firma en webhooks; los client credentials se gestionan en Secrets Manager con rotación periódica |
| TH-005 | Information Disclosure | Exposición de datos PII o transaccionales de usuarios en logs, trazas distribuidas o respuestas de error detalladas | Todos los microservicios | Alto | Logs estructurados en JSON sin campos PII ni datos financieros en texto plano; masking de datos sensibles en logs y trazas OpenTelemetry; respuestas de error genéricas hacia el exterior |
| TH-006 | Repudiation | Un usuario o sistema externo niega haber ejecutado una operación financiera o modificado datos | Transaction Context, Audit Context | Alto | Trazas de auditoría inmutables con actor, acción, timestamp, IP y correlationId; tokens JWT firmados como evidencia de autoría; el registro de auditoría no puede ser modificado ni eliminado |
| TH-007 | Spoofing | Suplantación de identidad de un usuario mediante robo de credenciales (credential stuffing, phishing) | Identity Context — autenticación | Alto | MFA obligatorio para todos los usuarios; bloqueo automático de cuenta ante umbral de intentos fallidos; tokens de acceso de corta duración |
| TH-008 | Information Disclosure | Exposición de datos de transacciones financieras de un tenant a otro tenant en un entorno multitenancy | Wallet Context, Reporting Context, todos | Alto | Aislamiento por `tenant_id` en todas las queries; el `tenant_id` se extrae exclusivamente del claim JWT; controles a nivel de aplicación y a nivel de base de datos |
| TH-009 | Tampering | Modificación de registros de auditoría por un actor interno con acceso privilegiado a la base de datos | Audit Context | Alto | Almacenamiento audit en modo append-only; sin interfaz de modificación ni eliminación; acceso a la base de datos de auditoría restringido a un único servicio con permisos de solo escritura |
| TH-010 | Denial of Service | Saturación de los endpoints de operaciones financieras con solicitudes masivas para degradar el servicio | API Gateway, Transaction Context, Wallet Context | Alto | Rate limiting a nivel de API Gateway por usuario y por tenant; HPA de Kubernetes para escalar ante incremento legítimo de carga; circuit breaker en integraciones externas |
| TH-011 | Tampering | Inyección de eventos fraudulentos en el bus Kafka para acreditar fondos o alterar el estado del sistema sin pasar por la lógica de dominio | Kafka — todos los topics de dominio | Alto | Autenticación de productores Kafka con credenciales de servicio; validación de schema (Avro / JSON Schema) en consumidores; eventos firmados con correlationId trazable |
| TH-012 | Elevation of Privilege | Escalada de privilegios dentro del pipeline de reportería para acceder a datos operacionales fuera del read model | Reporting Context — MS1 Spark | Medio | MS1 solo tiene credenciales de lectura sobre `pagofacil_readmodel`; prohibido el acceso a BDs operacionales desde el contexto de reportería; validación de queries en el SparkJdbcSourceAdapter |
| TH-013 | Information Disclosure | Exposición de claves de cifrado o credenciales de sistemas externos almacenadas en variables de entorno, código fuente o repositorios de configuración | Todos los servicios | Alto | Gestión exclusiva de secretos en AWS Secrets Manager; prohibido texto plano en repositorio, variables de entorno y logs; rotación automática configurada |
| TH-014 | Repudiation | Un Analista de Fraude u Oficial de Cumplimiento niega haber tomado una decisión sobre una alerta | Fraud & Compliance Context, Audit Context | Medio | Toda resolución de alerta registrada en la traza de auditoría con actor autenticado (JWT), timestamp y motivo; inmutable desde el momento de escritura |
| TH-015 | Denial of Service | Solicitudes repetidas de generación de reportes pesados para saturar el pipeline ETL | Reporting Context — MS1/MS2 Spark | Medio | Control de acceso por rol para la solicitud de reportes; cola de ejecución con límite de concurrencia; jobs batch no exponen endpoints HTTP públicos |

---

## 3. Trust Boundaries

### Zonas de Confianza

| Zona | Descripción | Nivel de Confianza |
|------|-------------|-------------------|
| **Internet / Usuarios Externos** | Usuarios finales desde navegadores; aplicaciones móviles de terceros | Externo — sin confianza implícita |
| **Sistemas Financieros Externos** | Entidades financieras, pasarelas de pago, proveedor KYC, proveedor AML, proveedor SMS/Email | Externo — autenticados, confianza condicionada a firma/OAuth |
| **DMZ — API Gateway** | AWS API Gateway v2 con JWT authorizer Cognito; punto de entrada único para tráfico externo | Bajo — validación de token; no trusted por defecto |
| **Service Mesh — Kubernetes** | Microservicios internos desplegados en K8s con comunicación TLS mutua | Medio — autenticados con token de servicio; comunicación cifrada |
| **Capa de Datos Operacional** | Bases de datos PostgreSQL de cada bounded context (write model) | Alto — acceso exclusivo del servicio propietario |
| **Read Model** | PostgreSQL `pagofacil_readmodel`; acceso de lectura exclusivo del Projection Service y MS1 | Alto — sin acceso desde contextos de dominio externos |
| **Capa de Auditoría** | MongoDB append-only del Audit Context | Alto — acceso de escritura exclusivo del Audit Service; lectura restringida a roles autorizados |
| **Vault de Secretos** | AWS Secrets Manager | Crítico — acceso exclusivo por identidad de servicio; rotación automática |

---

### Flujos que Cruzan Trust Boundaries

| Origen | Destino | Dato / Acción | Riesgo | Control Requerido |
|--------|---------|---------------|--------|-------------------|
| Usuario Final (Internet) | API Gateway (DMZ) | Credenciales de login, solicitudes de operación | Alto | TLS 1.2+; validación de token JWT; rate limiting |
| API Gateway (DMZ) | Identity Context | Solicitud de autenticación y datos de usuario | Alto | JWT authorizer Cognito; claims verificados en servicio |
| API Gateway (DMZ) | Wallet Context | Solicitud de consulta o inicio de operación financiera | Alto | JWT authorizer; tenant_id del claim; autorización a nivel de servicio |
| Entidad Financiera / Pasarela (Externo) | Integration Context | Notificación de pago, confirmación de retiro | Alto | OAuth 2.0 client credentials; validación de firma de webhook; ACL |
| Integration Context | Proveedor KYC (Externo) | Datos de identidad del usuario para validación | Crítico | TLS 1.2+; OAuth 2.0; datos mínimos necesarios; credenciales en Secrets Manager |
| Integration Context | Proveedor AML (Externo) | Datos de usuario para validación de listas de sanciones | Alto | TLS 1.2+; autenticación API key en Secrets Manager; validación de respuesta |
| Microservicio (Kafka productor) | Kafka | Eventos de dominio | Alto | Autenticación de productor; schema registry; correlationId obligatorio |
| Kafka | Microservicio (Kafka consumidor) | Eventos de dominio | Alto | Autenticación de consumidor; validación de schema en consumo; idempotencia de procesamiento |
| Projection Service | Read Model PostgreSQL | Escritura de proyecciones | Medio | Credenciales de escritura exclusivas del Projection Service; otros servicios sin acceso de escritura |
| MS1 Spark | Read Model PostgreSQL | Lectura vía JDBC para extracción de reportes | Medio | Credenciales de solo lectura; acceso restringido a `pagofacil_readmodel`; prohibido acceso a BDs operacionales |
| Lambda (serverless) | S3 / destino de reporte | Archivo PDF/XLS/CSV generado | Medio | Permisos IAM de mínimo privilegio; cifrado del archivo en reposo (AES-256) |
| Administrador / Oficial de Cumplimiento (interno) | Audit Context (dashboard) | Consulta de trazas y alertas | Medio | Autenticación JWT; autorización por rol; acceso de solo lectura; sin operaciones de escritura o eliminación |
