# PagoFacil — Billetera Digital

Plataforma de billetera digital segura, escalable y de alta disponibilidad para la gestión de fondos electrónicos con garantías de integridad, trazabilidad y cumplimiento regulatorio.

---

## Descripcion del proyecto

PagoFacil es un nuevo desarrollo en el dominio **Finanzas / Fintech** que provee a los usuarios una plataforma centralizada y propia para gestionar fondos electrónicos, realizar transferencias entre usuarios y consultar movimientos, eliminando la dependencia de soluciones de terceros con limitada integración y control.

### Problema que resuelve

- Ausencia de trazabilidad y auditoría transaccional completa.
- Falta de controles antifraude integrados.
- Dificultad para cumplir normativas KYC/AML.
- Ausencia de APIs propias para integración con entidades financieras y pasarelas de pago.
- Incapacidad de escalar horizontalmente ante incrementos de volumen de operaciones.

---

## Objetivos

**General:** Desarrollar una plataforma de billetera digital segura, escalable y de alta disponibilidad que permita a los usuarios gestionar fondos electrónicos con garantías de integridad, trazabilidad y cumplimiento regulatorio.

**Específicos:**

- Implementar registro, autenticación con MFA y gestión de identidad bajo estándares KYC/AML.
- Habilitar operaciones financieras core: depósito, retiro, transferencia y consulta de saldos.
- Garantizar integridad y no repudio de transacciones mediante identificadores únicos (UUID/correlationId) y registros auditables.
- Implementar controles de seguridad avanzados: cifrado en tránsito y en reposo, gestión segura de credenciales y monitoreo de fraude.
- Exponer APIs seguras para integración con entidades financieras, pasarelas de pago y sistemas externos.
- Garantizar consistencia financiera mediante mecanismos transaccionales, procesamiento asíncrono e idempotencia.
- Proveer capacidades de observabilidad, auditoría, recuperación ante desastres y escalamiento horizontal.

---

## Alcance

### Incluido

| Area | Detalle |
|---|---|
| Identidad | Registro y autenticación con MFA; módulo KYC y controles AML |
| Operaciones | Depósito, retiro y transferencia entre usuarios |
| Consultas | Saldo actual e historial auditable con paginación y filtros |
| Seguridad | Cifrado TLS 1.2+ en tránsito, AES-256 en reposo, gestión de secretos (vault) |
| APIs | REST/async autenticadas (OAuth 2.0 / OpenID Connect) para integraciones externas |
| Transacciones | Procesamiento asíncrono con idempotencia y conciliación automática |
| Fraude | Monitoreo y detección en tiempo real; alertas ante patrones sospechosos |
| Limites | Configurables por usuario, tipo de operación y período |
| Observabilidad | Logging estructurado, métricas, trazas distribuidas (OpenTelemetry) y alertas |
| Disponibilidad | Plan DR (RTO < 1h, RPO < 15min), alta disponibilidad y escalamiento horizontal |
| Compliance | Protección de datos personales, normativas KYC/AML |

### Fuera del alcance (fase inicial)

- Aplicaciones móviles nativas (iOS/Android) — se proveen APIs para integración posterior.
- Integración directa con redes de tarjetas (Visa/Mastercard).
- Módulo de crédito o préstamos.
- Soporte multimoneda.

---

## Requerimientos no funcionales

| Atributo | Meta |
|---|---|
| Disponibilidad | 99.9% uptime mínimo |
| Rendimiento | < 500 ms en operaciones de consulta bajo carga nominal |
| Seguridad | TLS 1.2+ en tránsito · AES-256 en reposo · vault para secretos |
| Consistencia | Garantías ACID para operaciones financieras críticas |
| Recuperación | RTO < 1 hora · RPO < 15 minutos |
| Escalabilidad | Escalamiento horizontal automático |
| Observabilidad | Logging + métricas + trazas distribuidas (OpenTelemetry) |
| Compliance | GDPR / Ley de protección de datos · KYC · AML |
| Arquitectura | Microservicios modulares con separación clara de responsabilidades |

---

## Arquitectura y principios de diseño

- **Security by Design** y **Privacy by Design** desde las etapas iniciales.
- **Arquitectura hexagonal / puertos y adaptadores** para separar la lógica de negocio de los mecanismos de infraestructura y facilitar pruebas automatizadas.
- **Event-driven architecture** con bus de eventos para procesamiento asíncrono, trazabilidad y desacoplamiento con sistemas externos.
- **Idempotencia** en todas las operaciones financieras: cada operación puede reintentarse de forma segura sin generar duplicados.
- **Multitenancy / segmentación por canal** para permitir futuras alianzas con entidades financieras que operen bajo la plataforma.
- **Dashboard de auditoría** para revisión de transacciones, reportes regulatorios y gestión de alertas de fraude.
- Despliegue en nube pública con soporte a contenedores (**Kubernetes**).

---

## Stakeholders

| Stakeholder | Rol | Responsabilidad |
|---|---|---|
| Sponsor ejecutivo | Patrocinador | Aprobación de presupuesto y priorización estratégica |
| Project Manager | Gestión de proyecto | Planificación, seguimiento y control |
| Arquitecto de software | Diseño técnico | Arquitectura, estándares y revisión de diseño |
| Equipo de desarrollo | Implementación | Construcción, pruebas unitarias e integración |
| Equipo de seguridad | Seguridad de la información | Revisión de controles, pentesting y cumplimiento |
| Oficial de cumplimiento | Compliance / Regulatorio | Validación KYC, AML y protección de datos |
| Equipo de operaciones | DevOps / SRE | Infraestructura, despliegue y observabilidad |
| Usuarios finales | Usuarios de la plataforma | Gestión de fondos y transacciones |
| Entidades financieras | Integración externa | Proveedores de fondeo, liquidación y servicios financieros |

---

## Riesgos conocidos

| Riesgo | Descripcion |
|---|---|
| Regulatorio | Cambios en normativas KYC/AML o protección de datos pueden requerir ajustes de alcance |
| Seguridad | Vulnerabilidades en componentes de terceros o errores criptográficos pueden comprometer la plataforma |
| Integración | Dependencia de APIs de entidades financieras externas con disponibilidad no garantizada |
| Escalabilidad | Subestimación del volumen transaccional puede impactar rendimiento y disponibilidad |
| Fraude | Debilidad en controles antifraude puede exponer la plataforma a pérdidas y sanciones |
| Consistencia | Fallos en transacciones distribuidas pueden generar inconsistencias financieras |

---

## Supuestos y restricciones

**Supuestos:**

- Conectividad con entidades bancarias o proveedores de fondeo mediante APIs disponibles.
- El equipo cuenta con experiencia en microservicios y seguridad en aplicaciones financieras.
- Las normativas regulatorias aplicables se definirán junto al oficial de cumplimiento antes del inicio de implementación.
- La infraestructura de despliegue será en nube pública con soporte a contenedores (Kubernetes).

**Restricciones:**

- Cumplimiento con la legislación de protección de datos personales vigente en la jurisdicción de operación.
- Las credenciales y datos sensibles no podrán almacenarse en texto plano bajo ninguna circunstancia.
- Las APIs externas deben implementar autenticación OAuth 2.0 / OpenID Connect.
- Los datos de transacciones financieras deben conservarse por el período mínimo exigido por la normativa regulatoria.
- El presupuesto y los plazos están sujetos a aprobación del sponsor ejecutivo.

---

## Presupuesto

Por definir tras estimación detallada. Categorías principales:

- Desarrollo de software
- Infraestructura cloud
- Licencias de herramientas y servicios
- Seguridad y auditoría
- Capacitación y certificaciones de cumplimiento
