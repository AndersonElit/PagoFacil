# PagoFacil — Billetera Digital

Proyecto de desarrollo de una plataforma de billetera digital segura, escalable y de alta disponibilidad para la gestión de fondos electrónicos con cumplimiento regulatorio (KYC/AML).

---

## Framework SDLC

Este repositorio sigue un framework de ciclo de vida de desarrollo de software (SDLC) asistido por Claude Code. Cada etapa produce artefactos estructurados que alimentan la siguiente, garantizando trazabilidad desde el requerimiento inicial hasta la implementación.

```
Etapa 0 — Requerimiento del cliente    ✓ completada
Etapa 1 — Planeación (PID)             ✓ completada
Etapa 2 — Análisis de Requerimientos (SRS)  ← estamos aquí
Etapa 3 — Pre-Diseño (Strategic SDD)
Etapa 4 — Diseño Técnico (Technical SDD)
Etapa 5 — Implementación
```

---

## Etapa 0 — Requerimiento del Cliente

### Proceso

1. Se diligencia el formato base ubicado en `.claude/formatos/input-template.md`.
2. El documento completado se guarda en `requerimiento/` con el nombre del proyecto.
3. Este documento sirve como entrada para la skill `/plan-pid` en la siguiente etapa.

### Artefacto generado

| Archivo | Descripción |
|---------|-------------|
| [`requerimiento/input-pagofacil.md`](requerimiento/input-pagofacil.md) | Requerimiento del cliente diligenciado — entrada para la etapa de Planeación |

### Resumen del requerimiento

| Campo | Valor |
|-------|-------|
| **Proyecto** | PagoFacil — Billetera Digital |
| **Tipo** | Nuevo desarrollo |
| **Dominio** | Finanzas / Fintech |
| **Objetivo** | Plataforma de billetera digital segura, escalable y de alta disponibilidad |
| **Alcance funcional** | Registro/autenticación MFA, depósito/retiro/transferencia, KYC/AML, APIs para integración financiera, monitoreo de fraude, observabilidad |
| **Fuera del alcance** | Apps móviles nativas, integración directa Visa/Mastercard, módulo de crédito, soporte multimoneda (fase inicial) |
| **Disponibilidad requerida** | 99.9% uptime |
| **Rendimiento** | Respuesta < 500ms bajo carga nominal |
| **RTO / RPO** | < 1 hora / < 15 minutos |

---

## Etapa 1 — Planeación (PID)

### Proceso

1. Se ejecuta la skill `/plan-pid` con el requerimiento del cliente como entrada.
2. El PID generado se guarda en `docs/planning/`.
3. Este documento sirve como entrada para la skill `/requirements-srs` en la siguiente etapa.

### Artefacto generado

| Archivo | Descripción |
|---------|-------------|
| [`docs/planning/PID-PagoFacil.md`](docs/planning/PID-PagoFacil.md) | Project Initiation Document — define alcance, stakeholders, riesgos, viabilidad y cronograma de alto nivel |

### Resumen del PID

| Campo | Valor |
|-------|-------|
| **Tipo de proyecto** | Nuevo desarrollo |
| **Duración estimada** | 9–12 meses |
| **Disponibilidad** | 99.9% uptime |
| **Recuperación** | RTO < 1h / RPO < 15min |
| **Etapas planificadas** | 8 fases (planeación → lanzamiento MVP) |
| **Riesgos identificados** | 7 (regulatorio, seguridad, integración, escalabilidad, consistencia, fraude, scope creep) |

---

## Etapa 2 — Análisis de Requerimientos (SRS)

### Proceso

1. Se ejecuta la skill `/requirements-srs` con el PID como entrada.
2. El SRS generado se guarda en `docs/requirements/`.
3. Este documento sirve como entrada para la skill `/strategic-design-sdd` en la siguiente etapa.

### Artefacto generado

| Archivo | Descripción |
|---------|-------------|
| [`docs/requirements/SRS-PagoFacil.md`](docs/requirements/SRS-PagoFacil.md) | Software Requirements Specification — define actores, requerimientos funcionales y no funcionales, restricciones y criterios de aceptación |

### Resumen del SRS

| Campo | Valor |
|-------|-------|
| **Versión** | 1.0 |
| **Estado** | Borrador — pendiente revisión por stakeholders |
| **Actores identificados** | 7 (Usuario Final, Administrador, Oficial de Cumplimiento, Analista de Fraude, Entidad Financiera, Pasarela de Pago, Sistema de Auditoría) |
| **Procesos principales** | Onboarding/KYC, operaciones financieras (depósito/retiro/transferencia), consulta/reportes, compliance AML, integración APIs, auditoría |
| **Fuera del alcance** | Apps móviles nativas, integración directa Visa/Mastercard, crédito/préstamos, multimoneda (fase inicial) |
| **Arquitectura operacional** | Microservicios sobre Kubernetes en nube pública, comunicación basada en eventos |

---

## Próximo paso

Con el SRS generado, ejecutar la skill de pre-diseño estratégico:

```
/strategic-design-sdd
```

Esto generará el **Strategic Design Document (SDD)** en `docs/strategic-design/`.
