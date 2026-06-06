# Etapa 4 — Frontend: Feature audit

**Proyecto:** PagoFacil | **Frontend:** pagofacil-web (Next.js 15.3)  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Contexto y Objetivo

Implementar el dashboard de auditoría para el equipo de compliance y auditoría: búsqueda de transacciones, revisión y resolución de alertas de fraude/AML, y gestión de reportes regulatorios (disparo on-demand y descarga).

**Roles de usuario que acceden:**
- `AUDITOR` / `COMPLIANCE`: acceso a transacciones, alertas (resolución), reportes.
- `ADMINISTRADOR`: acceso a reglas de fraude (feature separado `fraud-admin` — no cubre este documento).

**Bounded contexts del backend consumidos:**
- BC-05 Audit / BC-07 Reporting (`audit-service`).

---

## 2. Prerrequisitos

- Feature `auth` completo (Etapa 4a).
- `audit-service` activo con datos proyectados en Read Model (`projection-service` activo).
- Bucket S3 `pagofacil-reports` en floci (para URLs de descarga).

---

## 3. Rutas y Páginas

| Path | Tipo | Componente de página | Descripción | Renderizado |
|---|---|---|---|---|
| `/audit` | Protegida (auditor) | `app/audit/page.tsx` | Redirect a `/audit/transactions` | — |
| `/audit/transactions` | Protegida (auditor) | `app/audit/transactions/page.tsx` | Dashboard de búsqueda de transacciones | SSR inicial |
| `/audit/alerts` | Protegida (auditor) | `app/audit/alerts/page.tsx` | Listado de alertas pendientes y resueltas | SSR inicial |
| `/audit/alerts/[alertId]` | Protegida (auditor) | `app/audit/alerts/[alertId]/page.tsx` | Detalle + formulario de resolución | SSR |
| `/audit/reports` | Protegida (auditor) | `app/audit/reports/page.tsx` | Gestión de reportes: historial + disparo | SSR inicial |
| `/audit/reports/[reportId]` | Protegida (auditor) | `app/audit/reports/[reportId]/page.tsx` | Estado y descarga de reporte | SSR con polling |

> **Regla TDD:** cada schema Zod, hook y componente tiene su prueba Vitest en la Sección 9, escrita y vista fallar **ANTES** de implementar el artefacto.

---

## 4. Componentes — _test-first_

| Componente | Tipo | Responsabilidad |
|---|---|---|
| `TransactionSearchPanel` | Client Component | Filtros: userId, status, fecha from/to, tenantId; submit → actualiza query params → invalida `useAuditTransactions` |
| `AuditTransactionTable` | Client Component | Tabla paginada de transacciones del Read Model; columnas: transactionId, userId, operationType, amount, status, createdAt |
| `AlertsTable` | Client Component | Tabla paginada de alertas; columnas: alertId, transactionId, severity (badge), status, alertType, createdAt; filtro por status |
| `AlertDetailCard` | Server Component | Detalle inmutable de la alerta: transactionId, userId, severity, alertType, ruleTriggered, evaluationData |
| `AlertResolutionForm` | Client Component | Select de decisión (APROBADA / RECHAZADA) + textarea de justificación (mínimo 10 caracteres); submit → `useResolveAlert`; deshabilita si alerta ya resuelta |
| `ReportTriggerForm` | Client Component | Select de tipo de reporte, date range pickers, checkboxes de formato (PDF, XLS, CSV); submit → `useTriggerReport` |
| `ReportJobStatusCard` | Client Component | Estado del job (badge animado si EXTRAYENDO/PROCESANDO); botón de descarga si COMPLETADO; polling automático cada 10s |
| `AuditLayout` | Server Component | Layout con barra de navegación lateral: Transacciones / Alertas / Reportes |

---

## 5. Integración con API (TanStack Query) — _test-first_

| Hook | Endpoint | Tipo | Descripción | Caché |
|---|---|---|---|---|
| `useAuditTransactions` | `GET /v1/audit/transactions` | `useQuery` | Búsqueda paginada con filtros | `staleTime: 60s` |
| `useAuditAlerts` | `GET /v1/audit/alerts` | `useQuery` | Lista alertas por status | `staleTime: 30s` |
| `useAlertDetail` | `GET /v1/audit/alerts/{alertId}` | `useQuery` | Detalle de alerta | `staleTime: 120s` |
| `useResolveAlert` | `PUT /v1/audit/alerts/{alertId}/resolve` | `useMutation` | Resolver alerta; invalida `useAuditAlerts` y `useAlertDetail` | Invalida en éxito |
| `useTriggerReport` | `POST /v1/audit/reports/trigger` | `useMutation` | Disparar reporte; invalida lista de reports | Invalida en éxito |
| `useReportStatus` | `GET /v1/audit/reports/{reportId}/status` | `useQuery` | Estado del job; polling activo si status ∈ [ENCOLADO, EXTRAYENDO, PROCESANDO] | `refetchInterval: 10s` si en proceso |
| `useReportDownload` | `GET /v1/audit/reports/{reportId}/download` | Fetch directo | Redirige al browser a la URL presignada S3 | No cache |

---

## 6. Estado Global (Zustand)

No se usa estado global Zustand en este feature — los filtros de búsqueda se gestionan con query params de URL y el estado de TanStack Query. Esto permite compartir links directos a búsquedas específicas.

---

## 7. Esquemas de Validación (Zod) — _test-first_

```typescript
// schemas/audit.ts

const alertResolutionSchema = z.object({
  decision: z.enum(["APROBADA", "RECHAZADA"], { required_error: "Selecciona una decisión" }),
  justification: z.string()
    .min(10, "La justificación debe tener al menos 10 caracteres")
    .max(1000, "Máximo 1000 caracteres")
});

const reportTriggerSchema = z.object({
  reportType: z.enum([
    "transacciones-diario",
    "reporte-aml",
    "alertas-fraude",
    "saldo-usuarios",
    "conciliacion"
  ]),
  periodFrom: z.string().date("Fecha inicio inválida"),
  periodTo: z.string().date("Fecha fin inválida"),
  formats: z.array(z.enum(["PDF", "XLS", "CSV"])).min(1, "Selecciona al menos un formato")
}).refine(
  d => new Date(d.periodFrom) <= new Date(d.periodTo),
  { message: "La fecha inicio debe ser anterior a la fecha fin", path: ["periodFrom"] }
);
```

---

## 8. Autenticación y Autorización

- Todas las rutas de este feature requieren rol `AUDITOR` o `COMPLIANCE` en el JWT.
- El middleware NextAuth verifica el claim de rol y redirige a `/unauthorized` si el rol no es suficiente.
- El `accessToken` JWT se adjunta a cada llamada a `audit-service`.
- `audit-service` revalida el claim de rol en cada endpoint sensible (resolución de alertas, disparo de reportes).

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> Cada prueba se escribe y se ve **fallar (Red)** antes de implementar el artefacto.

### Schemas Zod

| Archivo de test | Caso | Schema |
|---|---|---|
| `schemas/audit.test.ts` | `alertResolutionSchema válido — APROBADA + justificación de 15 chars` | `alertResolutionSchema` |
| `schemas/audit.test.ts` | `alertResolutionSchema inválido — justificación de 5 chars` | `alertResolutionSchema` |
| `schemas/audit.test.ts` | `alertResolutionSchema inválido — sin decisión` | `alertResolutionSchema` |
| `schemas/audit.test.ts` | `reportTriggerSchema válido — todos los campos correctos` | `reportTriggerSchema` |
| `schemas/audit.test.ts` | `reportTriggerSchema inválido — formats vacío` | `reportTriggerSchema` |
| `schemas/audit.test.ts` | `reportTriggerSchema inválido — periodFrom > periodTo` | `reportTriggerSchema` |

### Hooks (MSW)

| Archivo de test | Escenario (MSW) | Hook |
|---|---|---|
| `hooks/useAuditTransactions.test.ts` | `GET /v1/audit/transactions` → 200 con paginación | `useAuditTransactions` (loading → success) |
| `hooks/useAuditAlerts.test.ts` | `GET /v1/audit/alerts?status=PENDIENTE` → 200 con lista | `useAuditAlerts` |
| `hooks/useResolveAlert.test.ts` | `PUT /v1/audit/alerts/{id}/resolve` → 200 | `useResolveAlert` (success + invalida cache) |
| `hooks/useResolveAlert.test.ts` | `PUT /v1/audit/alerts/{id}/resolve` → 409 (ya resuelta) | `useResolveAlert` (error handling) |
| `hooks/useTriggerReport.test.ts` | `POST /v1/audit/reports/trigger` → 202 con `reportId` | `useTriggerReport` (success) |
| `hooks/useReportStatus.test.ts` | `GET /v1/audit/reports/{id}/status` → 200 status PROCESANDO → polling cada 10s | `useReportStatus` (refetch automático) |
| `hooks/useReportStatus.test.ts` | `GET /v1/audit/reports/{id}/status` → 200 status COMPLETADO → polling se detiene | `useReportStatus` (polling stop) |

### Componentes (React Testing Library)

| Archivo de test | Interacción / estado | Componente |
|---|---|---|
| `components/AlertsTable.test.tsx` | Renderiza tabla con 3 alertas mock; badges de severidad con color correcto | `AlertsTable` |
| `components/AlertsTable.test.tsx` | Filtro por status PENDIENTE muestra solo alertas pendientes | `AlertsTable` |
| `components/AlertResolutionForm.test.tsx` | Renderiza select de decisión y textarea vacíos | `AlertResolutionForm` |
| `components/AlertResolutionForm.test.tsx` | Muestra error si justificación < 10 chars al submit | `AlertResolutionForm` |
| `components/AlertResolutionForm.test.tsx` | Formulario deshabilitado si alerta ya resuelta | `AlertResolutionForm` |
| `components/ReportTriggerForm.test.tsx` | Renderiza select de tipo y checkboxes de formato | `ReportTriggerForm` |
| `components/ReportTriggerForm.test.tsx` | Error si ningún formato seleccionado al submit | `ReportTriggerForm` |
| `components/ReportJobStatusCard.test.tsx` | Badge animado visible si status EXTRAYENDO | `ReportJobStatusCard` |
| `components/ReportJobStatusCard.test.tsx` | Botón de descarga visible solo si status COMPLETADO | `ReportJobStatusCard` |

**Umbral de cobertura del feature:** ≥ 80%.

---

## 10. Pruebas E2E (Playwright, ATDD)

| Nombre del test | Flujo | Precondiciones | Resultado esperado |
|---|---|---|---|
| `audit-search-transactions.spec.ts` | Auditor navega a `/audit/transactions` → aplica filtros de fecha → ve tabla con resultados | projection-service con datos proyectados | Tabla muestra filas filtradas; paginación funciona |
| `audit-resolve-alert.spec.ts` | Auditor navega a alerta PENDIENTE → abre detalle → selecciona APROBADA + justificación → submit → alerta queda APROBADA | Alerta PENDIENTE en BD | Alerta en tabla cambia a APROBADA; no puede resolverse de nuevo |
| `audit-trigger-and-download-report.spec.ts` | Auditor dispara reporte `transacciones-diario` → ve estado ENCOLADO → espera COMPLETADO → descarga PDF | MS1 y MS2 activos; datos en readmodel | Archivo descargado correctamente desde S3 |
| `audit-unauthorized-access.spec.ts` | Usuario con rol USUARIO_FINAL intenta acceder a `/audit/transactions` | Usuario autenticado sin rol AUDITOR | Redirigido a `/unauthorized` |

---

## 11. Criterios de Aceptación

- [ ] Cada schema, hook y componente tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] `npm run test` finaliza en verde.
- [ ] La cobertura del feature ≥ 80%.
- [ ] Los flujos E2E de la Sección 10 pasan en Playwright.
- [ ] Solo usuarios con rol `AUDITOR` o `COMPLIANCE` pueden acceder a `/audit/**`.
- [ ] `AlertResolutionForm` está deshabilitado si la alerta ya fue resuelta.
- [ ] `ReportJobStatusCard` hace polling automático mientras el job está en proceso; se detiene al llegar a COMPLETADO o FALLIDO.
- [ ] El botón de descarga redirige a la URL pre-firmada de S3 (válida 15 minutos).
- [ ] El pipeline CI despliega el frontend a Vercel preview URL correctamente.
