# PagoFacil — Billetera Digital

Proyecto de desarrollo de una plataforma de billetera digital segura, escalable y de alta disponibilidad para la gestión de fondos electrónicos con cumplimiento regulatorio (KYC/AML).

---

## Framework SDLC

Este repositorio sigue un framework de ciclo de vida de desarrollo de software (SDLC) asistido por Claude Code. Cada etapa produce artefactos estructurados que alimentan la siguiente, garantizando trazabilidad desde el requerimiento inicial hasta la implementación.

```
Etapa 0 — Requerimiento del cliente    ← estamos aquí
Etapa 1 — Planeación (PID)
Etapa 2 — Análisis de Requerimientos (SRS)
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

## Próximo paso

Con el requerimiento diligenciado, ejecutar la skill de planeación:

```
/plan-pid requerimiento/input-pagofacil.md
```

Esto generará el **Project Initiation Document (PID)** en `docs/planning/`.
