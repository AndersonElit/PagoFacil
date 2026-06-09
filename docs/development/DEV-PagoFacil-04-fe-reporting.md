# Etapa 4f — Frontend: Feature reporting

**Proyecto:** PagoFacil — Billetera Digital
**Feature:** reporting — Catálogo de reportes, solicitud on-demand, seguimiento y descarga
**Roles de usuario:** ADMIN, COMPLIANCE_OFFICER
**Bounded context:** BC-07 Reporting

---

## 1. Contexto y Objetivo

El feature `reporting` permite solicitar reportes regulatorios (TRANSACTIONS, COMPLIANCE_ALERTS, USERS) en formato PDF, XLS o CSV. El pipeline ETL es asíncrono (MS1→MS2→Lambda) y el usuario hace seguimiento del estado via polling hasta `COMPLETED`, momento en que puede descargar el archivo.

---

## 2. Prerrequisitos

- [ ] Etapa 4a (`auth`) funcional.
- [ ] Etapas 3g, 3h, 3i y capa serverless funcionales (pipeline ETL completo).
- [ ] `pagofacil_reporting.report_schema_catalog` populado con 3 tipos de reporte.

---

## 3. Rutas y Páginas

| Path | Tipo | Componente de página | Descripción |
|---|---|---|---|
| `/reports` | protected, SSR | `ReportsCatalogPage` | Catálogo de tipos de reporte disponibles |
| `/reports/executions` | protected, CSR | `ExecutionsListPage` | Historial de ejecuciones del usuario |
| `/reports/executions/[executionId]` | protected, CSR | `ExecutionStatusPage` | Estado con polling + botón de descarga |

Solo `ADMIN` y `COMPLIANCE_OFFICER`. `middleware.ts` rechaza otros roles.

> **TDD obligatorio — prueba Vitest FALLA (Red) antes del artefacto (Green).**

---

## 4. Componentes — test-first

| Componente | Tipo | Responsabilidad |
|---|---|---|
| `ReportSchemaCard` | Server Component | Muestra: report_type, description, formatos disponibles (PDF/XLS/CSV), botón "Solicitar" → abre `ReportRequestForm` |
| `ReportRequestForm` | Client Component | Selects: output_format (PDF\|XLS\|CSV), period_from (date), period_to (date); validación Zod; submit → `useRequestReport` |
| `ExecutionStatusTracker` | Client Component | Estados: QUEUED → EXTRACTING → PROCESSING → GENERATING_FORMAT → COMPLETED\|FAILED. Barra de progreso visual. Polling cada 5 s hasta terminal |
| `DownloadButton` | Client Component | Botón "Descargar {format}" activo solo cuando `status === COMPLETED`; spinner mientras descarga; llama `useDownloadReport` |
| `ExecutionStatusBadge` | Client Component | QUEUED=gris, EXTRACTING/PROCESSING=azul pulsante, GENERATING_FORMAT=morado, COMPLETED=verde, FAILED=rojo |
| `ExecutionsTable` | Client Component | Historial: report_type, output_format, status badge, period, created_at, link a detalle |

---

## 5. Integración con API (TanStack Query) — test-first

| Hook | Endpoint | Tipo | refetchInterval | Descripción |
|---|---|---|---|---|
| `useReportSchemas` | `GET /reports/schemas` | `useQuery` | — (staleTime 5 min) | Catálogo de tipos disponibles |
| `useRequestReport` | `POST /reports/executions` | `useMutation` | — | 202 → redirect a `/reports/executions/{executionId}` |
| `useExecutionStatus` | `GET /reports/executions/{id}` | `useQuery` | 5000 ms cuando no terminal, `false` cuando COMPLETED\|FAILED | Polling de estado |
| `useDownloadReport` | `GET /reports/executions/{id}/download` | `useMutation` | — | Retorna blob → `URL.createObjectURL()` → descarga automática |
| `useExecutionsList` | `GET /reports/executions` | `useQuery` | — (staleTime 60 s) | Historial paginado del usuario |

---

## 6. Estado Global (Zustand)

`reportingStore`:
- `activeExecutions: Map<string, ExecutionStatus>` (executionId → status)
- `setExecutionStatus(executionId, status): void`
- `removeExecution(executionId): void`

---

## 7. Esquemas de Validación (Zod) — test-first

```typescript
// reportRequestSchema
z.object({
  report_type: z.enum(["TRANSACTIONS", "COMPLIANCE_ALERTS", "USERS"], {
    required_error: "Seleccione un tipo de reporte",
  }),
  output_format: z.enum(["PDF", "XLS", "CSV"], {
    required_error: "Seleccione un formato",
  }),
  period_from: z.string().date("Fecha de inicio inválida"),
  period_to: z.string().date("Fecha de fin inválida"),
}).refine(
  (d) => d.period_from <= d.period_to,
  { message: "Fecha fin debe ser posterior a fecha inicio", path: ["period_to"] }
)
```

---

## 8. Autenticación y Autorización

- Solo `ADMIN` y `COMPLIANCE_OFFICER`.
- `middleware.ts` verifica el claim `role` del JWT; redirect a `/dashboard` si el rol no tiene acceso.
- El `tenant_id` del claim JWT es propagado automáticamente por el backend al crear la ejecución.

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

### Schemas Zod

| Archivo de test | Caso | Schema que precede |
|---|---|---|
| `reportRequestSchema.test.ts` | `should reject period_to before period_from` | `reportRequestSchema` |
| `reportRequestSchema.test.ts` | `should require report_type` | `reportRequestSchema` |
| `reportRequestSchema.test.ts` | `should accept valid request with all fields` | `reportRequestSchema` |

### Hooks (con MSW)

| Archivo de test | Escenario | Hook que precede |
|---|---|---|
| `useRequestReport.test.ts` | `should return 202 and executionId on success` | `useRequestReport` |
| `useExecutionStatus.test.ts` | `should poll every 5s when status is not terminal` | `useExecutionStatus` |
| `useExecutionStatus.test.ts` | `should stop polling when status is COMPLETED` | `useExecutionStatus` |
| `useExecutionStatus.test.ts` | `should stop polling when status is FAILED` | `useExecutionStatus` |
| `useDownloadReport.test.ts` | `should trigger file download on success` | `useDownloadReport` |

### Componentes (React Testing Library)

| Archivo de test | Interacción / estado | Componente que precede |
|---|---|---|
| `ExecutionStatusTracker.test.tsx` | `should show blue progress bar when PROCESSING` | `ExecutionStatusTracker` |
| `ExecutionStatusTracker.test.tsx` | `should show green complete state when COMPLETED` | `ExecutionStatusTracker` |
| `DownloadButton.test.tsx` | `should be disabled when status is not COMPLETED` | `DownloadButton` |
| `DownloadButton.test.tsx` | `should be enabled when status is COMPLETED` | `DownloadButton` |
| `ExecutionStatusBadge.test.tsx` | `should apply correct class for each status` | `ExecutionStatusBadge` |
| `ReportRequestForm.test.tsx` | `should show error when period_to before period_from` | `ReportRequestForm` |

### Slices Zustand

| Archivo de test | Caso | Slice que precede |
|---|---|---|
| `reportingStore.test.ts` | `should add execution to activeExecutions` | `reportingStore` |
| `reportingStore.test.ts` | `should remove execution on removeExecution` | `reportingStore` |

**Umbral de cobertura:** ≥ 80%

---

## 10. Pruebas E2E (Playwright, ATDD)

| Test | Flujo | Resultado esperado |
|---|---|---|
| `reporting-request-success.spec.ts` | Login → `/reports` → "Solicitar" TRANSACTIONS PDF → period → submit → polling QUEUED→COMPLETED | `DownloadButton` habilitado; descarga inicia |
| `reporting-failed-execution.spec.ts` | Solicitar reporte → pipeline falla → FAILED | `ExecutionStatusBadge` muestra FAILED; `DownloadButton` permanece deshabilitado |
| `reporting-invalid-period.spec.ts` | period_to < period_from → submit | Error de validación Zod en `period_to` |
| `reporting-forbidden.spec.ts` | Login como USER → `/reports` | Redirige a `/dashboard` |

---

## 11. Criterios de Aceptación

### TDD

- [ ] Cada schema, hook y componente tuvo su prueba escrita y vista fallar (Red) antes de la implementación (Green).
- [ ] `npm run test` finaliza en verde.
- [ ] Cobertura del feature ≥ 80%.
- [ ] Flujos E2E de Playwright pasan.

### Funcionales

- [ ] Solicitud de reporte retorna 202 y redirige al seguimiento.
- [ ] Polling se detiene automáticamente cuando el estado es terminal (COMPLETED o FAILED).
- [ ] `DownloadButton` habilitado exclusivamente cuando `status === COMPLETED`.
- [ ] Descarga genera el archivo correcto (PDF, XLS o CSV según el formato solicitado).
- [ ] `period_to < period_from` muestra error de validación sin enviar la solicitud.
- [ ] Feature desplegado como pod en K3s via Ingress Traefik.
