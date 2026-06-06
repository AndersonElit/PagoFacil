# Strategic Design Document — Seguridad

**Proyecto:** PagoFacil — Billetera Digital | Parte del conjunto SDD v1.0 (domain / security / architecture)  
**Fecha:** 2026-06-06 | **Etapa:** Strategic Design / Pre-Design

---

## 1. Modelo de Seguridad

### Principios de Seguridad

| Principio | Aplicación en PagoFacil |
|-----------|------------------------|
| **Zero Trust** | Ningún servicio o actor es confiable por defecto. Toda comunicación inter-servicio requiere autenticación mTLS. Todo acceso externo requiere token JWT válido emitido por AWS Cognito. |
| **Defense in Depth** | Múltiples capas de control: API Gateway (validación JWT), mTLS inter-servicio, RBAC por bounded context, cifrado en tránsito (TLS 1.2+) y en reposo (AES-256), gestión centralizada de secretos en Secrets Manager. |
| **Least Privilege** | Cada microservicio posee únicamente las credenciales y permisos necesarios para su función. Los usuarios acceden exclusivamente a los recursos de su propia billetera y tenant. Los administradores no acceden a datos financieros de otros tenants. |
| **Privacy by Design** | Los datos personales (PII) se clasifican, cifran y retienen únicamente por el período regulatoriamente requerido. Los logs y eventos no exponen datos sensibles en texto plano. |
| **Inmutabilidad de Auditoría** | Los registros de operaciones financieras y decisiones de auditoría no pueden ser modificados ni eliminados una vez creados (RN-005). |
| **Separación de Responsabilidades** | Los bounded contexts tienen acceso exclusivo a sus propias bases de datos. Ningún servicio accede directamente a la base de datos de otro. |
| **Fail Secure** | Ante duda en la verificación de identidad, el sistema deniega el acceso. Una evaluación AML con resultado incierto resulta en retención, no en aprobación. |

---

### Identidad y Autenticación

El modelo de identidad sigue un esquema de dos planos:

**Plano Externo (usuarios e integraciones):**
- AWS Cognito (User Pool) gestiona la identidad de usuarios finales y entidades financieras externas.
- La autenticación de usuarios requiere dos factores: credenciales (email + contraseña con hash Argon2/bcrypt + salt) más un segundo factor (TOTP, SMS o correo).
- Las entidades financieras externas se autentican mediante OAuth 2.0 / OpenID Connect con credenciales de cliente.
- El AWS API Gateway v2 valida tokens JWT de Cognito en cada solicitud antes de enrutar a los microservicios.
- Los tokens tienen tiempo de expiración configurable; las sesiones expiran por inactividad.

**Plano Interno (inter-servicios):**
- La comunicación entre microservicios dentro del cluster Kubernetes usa autenticación mTLS.
- Cada microservicio presenta certificado de servicio para autenticación mutua.
- No se permiten llamadas inter-servicio sin certificado válido.

**Gestión de Secretos:**
- Toda credencial, clave criptográfica y secreto reside en AWS Secrets Manager.
- Los microservicios leen secretos en el arranque; queda prohibido el uso de variables de entorno no cifradas o texto plano en código y repositorios.

---

### Autorización

El control de acceso implementa RBAC (Role-Based Access Control) con el principio de mínimo privilegio. Los roles se validan en la capa de API Gateway y en cada microservicio.

| Rol | Bounded Context | Nivel de Acceso |
|-----|-----------------|-----------------|
| Usuario Final | Identity | Lectura/escritura sobre sus propios datos de perfil y credenciales |
| Usuario Final | Wallet | Lectura/escritura sobre su propia billetera y transacciones |
| Usuario Final | Notification | Solo recepción (no invoca directamente) |
| Administrador de Plataforma | Wallet | Lectura de transacciones; escritura sobre configuración de límites |
| Administrador de Plataforma | Fraud | Lectura de reglas; escritura sobre configuración de reglas |
| Administrador de Plataforma | Audit | Lectura de dashboard operacional; gestión de alertas |
| Auditor / Compliance | Audit | Lectura completa de transacciones y alertas; generación de reportes regulatorios; gestión de decisiones sobre alertas |
| Auditor / Compliance | Reporting | Disparo on-demand de generación de reportes |
| Entidad Financiera | Integration (API expuesta) | Escritura de confirmaciones de fondeo (webhook); lectura de estado de operaciones propias |
| Servicio Interno (mTLS) | Todos | Acceso acotado al contrato del servicio destino según rol de servicio |

---

### Datos Sensibles

| Dato | Clasificación | Justificación |
|------|--------------|---------------|
| Contraseñas | Crítico | Vector de acceso; almacenamiento exclusivo como hash Argon2/bcrypt con salt único |
| Documentos de identidad (DNI, pasaporte) | Alto — PII Regulado | Dato personal regulado por GDPR/normativa local y KYC |
| Datos biométricos (si aplica KYC biométrico) | Alto — Categoría Especial GDPR | Dato personal de categoría especial; manejo exclusivo por proveedor KYC certificado |
| Saldo de billetera | Alto — Financiero | Dato financiero personal; acceso restringido al titular y auditores autorizados |
| Historial de transacciones | Alto — Financiero + PII | Combina montos, fechas, contrapartes; sujeto a retención mínima de 5 años |
| Tokens de sesión JWT | Alto | Vector de acceso; tiempo de expiración configurable; invalidados ante cambio de contraseña |
| Claves criptográficas y secretos | Crítico | Infraestructura de seguridad; gestionados exclusivamente por AWS Secrets Manager |
| Resultado de evaluación AML / listas de sanciones | Alto — Regulatorio | Información regulatoria sensible; el motivo de rechazo no se expone al usuario |
| Correlación de operaciones (CorrelationId + logs) | Medio | Potencial de correlación de identidad si se expone sin control; acceso restringido a operaciones y auditoría |
| Datos de fuentes de fondos (cuentas bancarias vinculadas) | Alto — Financiero | Instrumentos de pago del usuario; cifrados en reposo |
| Tokens de recuperación de contraseña | Alto | Uso único con expiración; acceso al canal de email del usuario |

---

### Auditoría

Los siguientes eventos requieren trazabilidad completa e inmutable. Los registros incluyen timestamp, actor (userId o serviceId), CorrelationId, y resultado:

- Toda operación financiera ejecutada o rechazada (depósito, retiro, transferencia).
- Inicio y cierre de sesión de usuario.
- Intentos de autenticación fallidos y bloqueos de cuenta.
- Cambios de contraseña o configuración MFA.
- Resultado del proceso KYC (aprobado / rechazado / en revisión).
- Evaluaciones del motor de fraude con la regla activada y la decisión.
- Verificaciones AML con el resultado (match / no match).
- Decisiones de auditor sobre alertas de fraude (quién, cuándo, justificación).
- Generación de reportes regulatorios (quién solicitó, período, tipo).
- Detección de discrepancias en conciliación.

La retención mínima de registros de auditoría es de 5 años (RN-012); el período exacto lo confirma el oficial de compliance según normativa aplicable.

---

## 2. Threat Modeling

El análisis de amenazas utiliza el marco STRIDE. Las amenazas están ordenadas por impacto descendente.

| ID | Categoría STRIDE | Amenaza | Componente Afectado | Impacto | Mitigación Propuesta |
|----|-----------------|---------|---------------------|---------|----------------------|
| TH-001 | Tampering | Modificación del monto o destino de una transacción en tránsito entre el cliente y el API Gateway | Integration (API expuesta), Wallet | Alto | TLS 1.2+ en todas las comunicaciones externas; validación de integridad de payload en API Gateway y microservicio receptor; firma de mensajes para webhooks de entidades financieras |
| TH-002 | Tampering | Alteración o eliminación de registros de auditoría o transacciones ya confirmadas | Audit (Read Model), Wallet (PostgreSQL) | Alto | Registros inmutables por diseño (RN-005); control de acceso que impide UPDATE/DELETE sobre tablas de auditoría; checksums sobre eventos almacenados |
| TH-003 | Spoofing | Suplantación de usuario autenticado mediante robo de token JWT | Identity, Wallet | Alto | Tiempo de expiración corto de tokens; invalidación de sesiones ante cambio de contraseña; MFA obligatorio; detección de tokens desde IPs o agentes inusuales |
| TH-004 | Spoofing | Entidad financiera falsa inyectando confirmaciones fraudulentas de fondeo (webhook envenenado) | Integration | Alto | Validación de firma HMAC o certificado del webhook; lista blanca de IPs de entidades financieras; idempotencia de confirmaciones |
| TH-005 | Information Disclosure | Exposición de datos de billetera de usuario A accediendo a recursos de usuario B (IDOR) | Wallet | Alto | Validación estricta de ownership en cada operación: el UsuarioId del token JWT debe coincidir con el propietario del recurso solicitado |
| TH-006 | Information Disclosure | Filtración de datos PII o financieros en logs, trazas distribuidas o mensajes de error | Cross-cutting | Alto | Logs estructurados sin datos sensibles en campos de texto libre; enmascaramiento de PII en logs (email, documento, saldo); política de logging revisada antes del despliegue |
| TH-007 | Elevation of Privilege | Bypass del requisito KYC mediante manipulación del estado de cuenta | Identity | Alto | El estado de cuenta es controlado exclusivamente por Identity Context; la regla KYC está codificada como invariante del dominio, no como configuración; auditoría de cambios de estado |
| TH-008 | Elevation of Privilege | Escalada de rol de usuario a administrador o auditor mediante manipulación de claims JWT | Identity, Audit | Alto | Claims de rol gestionados exclusivamente por AWS Cognito; validación de claims en API Gateway y en cada microservicio; no se confía en claims del cliente |
| TH-009 | Repudiation | Usuario niega haber ejecutado una transferencia o retiro | Wallet, Audit | Medio | Confirmación explícita requerida antes de ejecutar transferencias; registro inmutable con timestamp, IP, agente y CorrelationId; MFA como factor de no repudio |
| TH-010 | Denial of Service | Saturación del sistema con operaciones financieras masivas para agotar recursos | Wallet, Integration | Medio | Rate limiting por usuario y tenant en API Gateway; límites transaccionales configurables (RF-013); circuit breakers en dependencias externas (RNF-011); escalamiento horizontal automático |
| TH-011 | Denial of Service | Agotamiento de cuota o SLA de entidades financieras externas mediante flood de solicitudes de fondeo/retiro | Integration | Medio | Rate limiting saliente por entidad financiera en Integration Context (Camel throttle); gestión de backoff exponencial; monitoreo de cuotas |
| TH-012 | Information Disclosure | Exposición de la razón regulatoria AML o de la regla de fraude al usuario mediante mensajes de error | Fraud, Audit | Medio | Los mensajes de rechazo a usuarios son genéricos; la razón específica solo es visible en el dashboard de auditoría para roles autorizados |
| TH-013 | Tampering | Inyección de eventos maliciosos en el bus Kafka por un servicio comprometido | Cross-cutting (Kafka) | Medio | mTLS para producers y consumers Kafka; esquemas Avro/JSON Schema Registry para validación de estructura; autorización por topic (ACL Kafka) |
| TH-014 | Spoofing | Acceso no autorizado a AWS Secrets Manager desde un proceso externo al cluster | Cross-cutting (Secrets) | Medio | IAM roles con least privilege para acceso a Secrets Manager; acceso restringido a pods del cluster con Service Accounts específicos; rotación periódica de secretos |
| TH-015 | Information Disclosure | Exposición de datos de un tenant a través de consultas de otro tenant (fallo de aislamiento multitenancy) | Wallet, Audit | Medio | TenantId incluido como predicado obligatorio en todas las consultas; validación de TenantId del JWT contra el recurso solicitado; tests de aislamiento entre tenants antes del despliegue |

---

## 3. Trust Boundaries

### Zonas de Confianza

| Zona | Descripción | Nivel de Confianza |
|------|------------|-------------------|
| Zona Pública (Internet) | Usuarios finales, aplicaciones cliente, integradores externos (entidades financieras), webhooks entrantes | Externo — Sin confianza implícita |
| Zona DMZ | AWS API Gateway v2 — punto único de entrada; valida tokens JWT de Cognito antes de enrutar | Bajo — Tráfico validado pero no de confianza interna |
| Zona de Aplicación | Cluster Kubernetes (K3d en dev / EKS en staging/prod); microservicios autenticados con mTLS | Medio — Confianza basada en certificados de servicio |
| Zona de Integración | `integration-service` — único punto de comunicación saliente con sistemas externos; aplica ACL | Medio — Controlado, pero interactúa con sistemas externos |
| Zona de Datos | Bases de datos PostgreSQL, MongoDB; bus Kafka | Alto — Acceso restringido exclusivamente a microservicios propietarios vía mTLS |
| Zona de Secretos | AWS Secrets Manager | Crítico — Acceso controlado por IAM roles con least privilege; solo pods autorizados |
| Zona de Identidad | AWS Cognito (User Pool) | Alto — Proveedor de identidad gestionado; fuente de verdad para tokens JWT |

---

### Flujos que Cruzan Trust Boundaries

| Origen | Destino | Dato / Acción | Riesgo | Control Requerido |
|--------|---------|--------------|--------|-------------------|
| Usuario Final (Zona Pública) | API Gateway (Zona DMZ) | Credenciales, solicitudes financieras, datos PII | Alto | TLS 1.2+; rate limiting; validación de input en API Gateway |
| API Gateway (Zona DMZ) | Microservicios (Zona de Aplicación) | Token JWT validado + payload de solicitud | Medio | mTLS; validación de claims JWT en cada microservicio; autorización RBAC |
| Entidad Financiera (Zona Pública) | Integration Service (Zona de Integración) | Webhook de confirmación de fondeo/retiro | Alto | Validación de firma HMAC o certificado; lista blanca de IPs; idempotencia |
| Integration Service (Zona de Integración) | Entidades Financieras (Zona Pública) | Solicitudes de fondeo e instrucciones de pago | Alto | TLS 1.2+; credenciales en Secrets Manager; timeouts configurables; circuit breaker |
| Integration Service (Zona de Integración) | Proveedor KYC (Zona Pública) | Documentos de identidad y datos personales del usuario | Alto | TLS 1.2+; cifrado de payload si el proveedor lo requiere; credenciales en Secrets Manager |
| Integration Service (Zona de Integración) | Listas de Sanciones AML (Zona Pública) | Consultas de verificación de usuario/contraparte | Alto | TLS 1.2+; credenciales en Secrets Manager; cache local para reducir exposición de datos |
| Microservicio (Zona de Aplicación) | PostgreSQL / MongoDB (Zona de Datos) | Datos financieros, PII, eventos de dominio | Alto | Credenciales en Secrets Manager; cifrado en reposo AES-256; acceso exclusivo del microservicio propietario |
| Microservicio (Zona de Aplicación) | Kafka (Zona de Datos) | Eventos de dominio | Medio | mTLS producer/consumer; ACL por topic; validación de esquema |
| Microservicio (Zona de Aplicación) | AWS Secrets Manager (Zona de Secretos) | Lectura de credenciales en arranque | Medio | IAM role con least privilege; acceso acotado a los secretos del servicio propio |
| Reporting (Zona de Aplicación) | Read Model MongoDB (Zona de Datos) | Lectura de datos para extracción ETL | Medio | Credenciales read-only; acceso exclusivo del `report-extraction-service`; prohibido acceso a BDs operacionales |
| Lambda (Zona de Integración serverless) | S3 `pagofacil-reports` (Zona de Datos) | Escritura de reportes generados | Medio | IAM role con least privilege; bucket privado; acceso de lectura solo para roles autorizados |
| Auditor (Zona Pública) | API Gateway → Audit Service | Descarga de reportes regulatorios | Medio | JWT con claim de rol Auditor/Compliance; log de acceso a reportes |
