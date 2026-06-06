# PagoFacil — Billetera Digital

Plataforma de billetera digital segura, escalable y de alta disponibilidad para la gestión de fondos electrónicos con garantías de integridad, trazabilidad y cumplimiento regulatorio.

> Documento de referencia: [`docs/planning/PID-PagoFacil.md`](docs/planning/PID-PagoFacil.md)

---

## Descripcion del proyecto

| Campo | Detalle |
|---|---|
| Tipo de proyecto | Nuevo desarrollo |
| Dominio de negocio | Finanzas / Fintech |
| Sponsor | Por definir |
| Project Manager | Por definir |
| Duracion estimada | ~36-46 semanas (sujeto a aprobacion tras estimacion detallada) |
| Modalidad de despliegue | Nube publica — contenedores (Kubernetes) |
| Metodologia | Agil con hitos por fases |

PagoFacil provee una plataforma centralizada y propia para gestionar fondos electrónicos, ejecutar transferencias y consultar movimientos, eliminando la dependencia de soluciones de terceros con limitada integración y control.

---

## Problema que resuelve

- Ausencia de trazabilidad y auditoría transaccional completa, dificultando conciliación y reporte regulatorio.
- Falta de controles antifraude integrados, exponiendo la operación a pérdidas financieras y sanciones.
- Incapacidad para cumplir normativas KYC/AML de forma sistemática y auditable.
- Ausencia de APIs propias para integración con entidades financieras y pasarelas de pago.
- Arquitectura no escalable horizontalmente ante incrementos de volumen transaccional.

---

## Objetivos

**General:** Desarrollar una plataforma de billetera digital segura, escalable y de alta disponibilidad que permita a los usuarios gestionar fondos electrónicos con garantías de integridad, trazabilidad y cumplimiento regulatorio.

**Específicos:**

1. Implementar registro y autenticación con MFA y gestión de identidad bajo estándares KYC/AML.
2. Habilitar operaciones financieras core: depósito, retiro, transferencia y consulta de saldos con registro auditable.
3. Garantizar integridad y no repudio de transacciones mediante UUID/correlationId, registros inmutables y conciliación automática.
4. Implementar controles de seguridad: cifrado TLS 1.2+ en tránsito, AES-256 en reposo y gestión de secretos mediante vault.
5. Exponer APIs seguras (OAuth 2.0 / OpenID Connect) para integración con entidades financieras y pasarelas de pago.
6. Garantizar consistencia financiera con garantías ACID, procesamiento asíncrono e idempotencia.
7. Implementar monitoreo de fraude en tiempo real con alertas y controles AML.
8. Proveer observabilidad completa: logging estructurado, métricas y trazas distribuidas (OpenTelemetry).
9. Alcanzar disponibilidad de 99.9% con escalamiento horizontal y plan DR (RTO < 1h, RPO < 15min).
10. Cumplir con legislación de protección de datos personales y normativas regulatorias financieras vigentes.

---

## Alcance

### Incluido

| Area | Detalle |
|---|---|
| Identidad | Registro y autenticacion con MFA; modulo KYC y controles AML |
| Operaciones | Deposito, retiro y transferencia entre usuarios |
| Consultas | Saldo actual e historial auditable con paginacion y filtros |
| Seguridad | Cifrado TLS 1.2+ en transito, AES-256 en reposo, vault para secretos |
| APIs | REST/async autenticadas (OAuth 2.0 / OpenID Connect) para integraciones externas |
| Transacciones | Procesamiento asincrono con idempotencia y conciliacion automatica |
| Fraude | Monitoreo y deteccion en tiempo real; alertas ante patrones sospechosos |
| Limites | Configurables por usuario, tipo de operacion y periodo |
| Auditoria | Dashboard para revision de transacciones y reportes regulatorios |
| Observabilidad | Logging estructurado, metricas, trazas distribuidas (OpenTelemetry) y alertas |
| Disponibilidad | Alta disponibilidad, escalamiento horizontal y plan DR |
| Compliance | Proteccion de datos personales, normativas KYC/AML |
| Multitenancy | Segmentacion por canal de distribucion para alianzas futuras |

### Fuera del alcance (fase inicial)

- Aplicaciones moviles nativas (iOS/Android) — se proveen APIs para integracion posterior.
- Integracion directa con redes de tarjetas (Visa/Mastercard).
- Modulo de credito o prestamos.
- Soporte multimoneda.

---

## Requerimientos no funcionales

| Atributo | Meta |
|---|---|
| Disponibilidad | 99.9% uptime minimo |
| Rendimiento | < 500 ms para el 95% de consultas bajo carga nominal |
| Seguridad | TLS 1.2+ en transito · AES-256 en reposo · vault para secretos |
| Consistencia | Garantias ACID para operaciones financieras criticas |
| Recuperacion | RTO < 1 hora · RPO < 15 minutos |
| Escalabilidad | Escalamiento horizontal automatico |
| Observabilidad | Logging + metricas + trazas distribuidas (OpenTelemetry) |
| Idempotencia | Toda operacion financiera reintentable sin generar duplicados |
| Compliance | GDPR / Ley de proteccion de datos · KYC · AML |
| Mantenibilidad | Microservicios modulares con separacion clara de responsabilidades |

---

## Arquitectura y principios de diseño

- **Security by Design** y **Privacy by Design** desde las etapas iniciales.
- **Arquitectura hexagonal / puertos y adaptadores** para separar logica de negocio de infraestructura y facilitar pruebas automatizadas.
- **Event-driven architecture** con bus de eventos para procesamiento asincrono, trazabilidad y desacoplamiento con sistemas externos.
- **Idempotencia** en todas las operaciones financieras: cada operacion puede reintentarse de forma segura sin generar duplicados.
- **Multitenancy / segmentacion por canal** para alianzas futuras con entidades financieras.
- **Dashboard de auditoria** para revision de transacciones, reportes regulatorios y gestion de alertas.
- Despliegue en nube publica con contenedores (**Kubernetes**).

---

## Stakeholders

| Stakeholder | Rol | Responsabilidad |
|---|---|---|
| Sponsor ejecutivo | Patrocinador | Aprobacion de presupuesto y priorizacion estrategica |
| Project Manager | Gestion de proyecto | Planificacion, seguimiento y control |
| Arquitecto de software | Diseno tecnico | Arquitectura, estandares y revision de diseno |
| Equipo de desarrollo | Implementacion | Construccion, pruebas unitarias e integracion |
| Equipo de seguridad | Seguridad de la informacion | Revision de controles, pentesting y cumplimiento |
| Oficial de cumplimiento | Compliance / Regulatorio | Validacion KYC, AML y proteccion de datos |
| Equipo de operaciones | DevOps / SRE | Infraestructura, despliegue y observabilidad |
| Usuarios finales | Usuarios de la plataforma | Gestion de fondos y transacciones |
| Entidades financieras | Integracion externa | Proveedores de fondeo, liquidacion y servicios financieros |

---

## Cronograma de alto nivel

| Fase | Descripcion | Duracion Estimada |
|---|---|---|
| 0 — Iniciacion | Designacion de sponsor y PM; marco regulatorio; conformacion del equipo | 2 semanas |
| 1 — Analisis de Requerimientos | Levantamiento de requerimientos; casos de uso core | 3-4 semanas |
| 2 — Diseno Estrategico | Arquitectura de alto nivel; contratos de APIs; estrategia de seguridad | 3-4 semanas |
| 3 — Diseno Tecnico | Diseno detallado de microservicios; especificaciones de integracion | 3-4 semanas |
| 4 — Implementacion Fase 1 | Nucleo financiero: identidad, operaciones core, seguridad base | 10-12 semanas |
| 5 — Implementacion Fase 2 | Fraude, AML, dashboard de auditoria, integraciones externas | 8-10 semanas |
| 6 — QA y Seguridad | Pruebas funcionales, de carga, penetracion y cumplimiento | 4-6 semanas |
| 7 — Despliegue y Estabilizacion | Produccion, monitoreo intensivo y ajustes post-lanzamiento | 3-4 semanas |
| **Total estimado** | | **~36-46 semanas** |

---

## Riesgos conocidos

| Riesgo | Probabilidad | Impacto | Mitigacion |
|---|---|---|---|
| Cambios regulatorios KYC/AML durante el desarrollo | Media | Alto | Oficial de cumplimiento desde analisis; diseno modular |
| Vulnerabilidades en componentes de terceros | Media | Critico | SBOM, pentesting por fase, revision criptografica |
| APIs de entidades financieras no disponibles | Alta | Alto | Contratos previos al inicio; adaptadores desacoplados; mocks |
| Subestimacion del volumen transaccional | Media | Alto | Pruebas de carga desde QA; escalamiento horizontal desde el origen |
| Debilidad en controles antifraude | Media | Critico | Motor de reglas configurable; revision periodica con oficial de cumplimiento |
| Inconsistencias en transacciones distribuidas | Baja | Critico | Saga / outbox pattern; idempotencia; conciliacion automatica; pruebas de caos |
| Retrasos por falta de sponsor y PM | Alta | Alto | Designacion como condicion previa al arranque |

---

## Criterios de exito

| Criterio | Indicador Medible |
|---|---|
| Disponibilidad | Uptime >= 99.9% en 90 dias post-lanzamiento |
| Rendimiento | < 500 ms para el 95% de consultas bajo carga nominal |
| Cumplimiento regulatorio | Cero observaciones criticas en auditoria KYC/AML en primer ciclo |
| Seguridad | Cero vulnerabilidades criticas no resueltas al momento del despliegue |
| Integridad financiera | Tasa de discrepancias en conciliacion < 0.01% del total diario |
| Cobertura de pruebas | >= 80% en modulos criticos (nucleo financiero, seguridad) |
| Recuperacion ante desastres | RTO < 1h y RPO < 15min verificados en ejercicio previo al lanzamiento |
| Incidentes de fraude | Tasa de transacciones fraudulentas no detectadas < umbral regulatorio |

---

## Supuestos y restricciones

**Supuestos:**

- Conectividad con entidades bancarias o proveedores de fondeo mediante APIs disponibles y contratadas.
- El equipo cuenta con experiencia en microservicios y seguridad en aplicaciones financieras.
- Las normativas regulatorias aplicables se definen con el oficial de cumplimiento antes del inicio de la implementacion.
- Infraestructura en nube publica con soporte completo a contenedores (Kubernetes).

**Restricciones:**

- Cumplimiento con legislacion de proteccion de datos personales vigente en la jurisdiccion de operacion.
- Credenciales y datos sensibles no pueden almacenarse en texto plano bajo ninguna circunstancia.
- APIs externas deben implementar autenticacion OAuth 2.0 / OpenID Connect sin excepcion.
- Datos de transacciones financieras deben conservarse por el periodo minimo exigido por normativa.
- Presupuesto y plazos sujetos a aprobacion formal del sponsor ejecutivo.

---

## Documentacion

| Documento | Ruta | Etapa SDLC |
|---|---|---|
| Project Initiation Document (PID) | [`docs/planning/PID-PagoFacil.md`](docs/planning/PID-PagoFacil.md) | Planeacion |
