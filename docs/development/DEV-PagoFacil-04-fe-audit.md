# Etapa 4e — Frontend: Feature audit

**Proyecto:** PagoFacil — Billetera Digital
**Feature:** audit — Dashboard de trazabilidad de eventos inmutables
**Roles de usuario:** ADMIN, COMPLIANCE_OFFICER (solo lectura)
**Bounded context:** BC-06 audit-service

---

## 1. Contexto y Objetivo

El feature `audit` provee un dashboard de trazabilidad de solo lectura. Permite buscar y filtrar eventos inmutables por actor, tipo de evento, `correlationId`, `sagaId` y rango de fechas. Es crítico para la revisión de incidentes y el cumplimiento regulatorio.

---

## 2. Prerrequisitos

- [ ] Etapa 4a (`auth`) funcional con roles ADMIN y COMPLIANCE_OFFICER.
- [ ] Etapa 3f (`audit-service`) funcional con trazas en MongoDB.

---

## 3. Rutas y Páginas

| Path | Tipo | Componente de página | Descripción |
|---|---|---|---|
| `/audit/traces` | protected, SSR | `AuditTracesPage` | Listado paginado con filtros avanzados |
| `/audit/traces/[traceId]` | protected, SSR | `AuditTraceDetailPage` | Detalle completo de traza (todos los campos) |

Solo `ADMIN` y `COMPLIANCE_OFFICER`. `middleware.ts` rechaza otros roles.

> **TDD obligatorio — prueba Vitest FALLA (Red) antes del artefacto (Green).**

---

## 4. Componentes — test-first

| Componente | Tipo | Responsabilidad |
|---|---|---|
| `AuditTraceTable` | Client Component | Columnas: eventType, actor, actorRole, action, correlationId (truncado+copiable), sagaId (truncado), timestamp; paginación |
| `AuditTraceDetailCard` | Server Component | Todos los campos incluyendo `metadata` (JSON formateado), `sourceService`, `ipAddress`, `userAgent` |
| `AuditFilterPanel` | Client Component | Inputs: userId, eventType (select), correlationId (text), sagaId (text), dateFrom, dateTo |
| `CorrelationIdLink` | Client Component | Si `sagaId` presente: link que filtra por ese sagaId; si no, texto plano copiable |
| `TimestampDisplay` | Client Component | Muestra timestamp en zona horaria local con tooltip UTC |

---

## 5. Integración con API (TanStack Query) — test-first

| Hook | Endpoint | Tipo | staleTime | Descripción |
|---|---|---|---|---|
| `useAuditTraces` | `GET /audit/traces` | `useQuery` | 60 s | Paginado; key incluye todos los filtros activos |
| `useAuditTraceDetail` | `GET /audit/traces/{traceId}` | `useQuery` | 5 min | Detalle inmutable |

---

## 6. Estado Global (Zustand)

`auditStore`:
- `filters: AuditFilter` (userId?, eventType?, correlationId?, sagaId?, dateFrom?, dateTo?, page, size)
- `setFilter(key, value): void`
- `resetFilters(): void`

---

## 7. Esquemas de Validación (Zod) — test-first

```typescript
// auditFilterSchema
z.object({
  userId: z.string().uuid().optional(),
  eventType: z.string().min(1).optional(),
  correlationId: z.string().uuid("correlationId debe ser UUID v4").optional(),
  sagaId: z.string().uuid("sagaId debe ser UUID v4").optional(),
  dateFrom: z.string().datetime().optional(),
  dateTo: z.string().datetime().optional(),
  page: z.number().int().min(0).default(0),
  size: z.number().int().min(1).max(100).default(20),
}).refine(
  (d) => !d.dateFrom || !d.dateTo || d.dateFrom <= d.dateTo,
  { message: "dateTo debe ser posterior a dateFrom", path: ["dateTo"] }
)
```

---

## 8. Autenticación y Autorización

- Solo `ADMIN` y `COMPLIANCE_OFFICER` tienen acceso.
- `middleware.ts` verifica el claim `role` del JWT. Otros roles → redirect a `/dashboard`.
- Las trazas son de solo lectura; no hay ninguna acción de modificación disponible en la UI.

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

### Schemas Zod

| Archivo de test | Caso | Schema que precede |
|---|---|---|
| `auditFilterSchema.test.ts` | `should reject correlationId with non-UUID format` | `auditFilterSchema` |
| `auditFilterSchema.test.ts` | `should reject dateTo before dateFrom` | `auditFilterSchema` |
| `auditFilterSchema.test.ts` | `should accept empty filter (all optional)` | `auditFilterSchema` |

### Hooks (con MSW)

| Archivo de test | Escenario | Hook que precede |
|---|---|---|
| `useAuditTraces.test.ts` | `should return paginated traces on success` | `useAuditTraces` |
| `useAuditTraces.test.ts` | `should filter by correlationId` | `useAuditTraces` |
| `useAuditTraceDetail.test.ts` | `should return full trace detail` | `useAuditTraceDetail` |
| `useAuditTraceDetail.test.ts` | `should handle 404 trace not found` | `useAuditTraceDetail` |

### Componentes (React Testing Library)

| Archivo de test | Interacción / estado | Componente que precede |
|---|---|---|
| `AuditTraceTable.test.tsx` | `should render eventType, actor, action columns` | `AuditTraceTable` |
| `AuditTraceTable.test.tsx` | `should truncate correlationId to 8 chars with ellipsis` | `AuditTraceTable` |
| `CorrelationIdLink.test.tsx` | `should render as link when sagaId is present` | `CorrelationIdLink` |
| `CorrelationIdLink.test.tsx` | `should render as plain text when no sagaId` | `CorrelationIdLink` |
| `AuditFilterPanel.test.tsx` | `should call setFilter on correlationId input change` | `AuditFilterPanel` |

### Slices Zustand

| Archivo de test | Caso | Slice que precede |
|---|---|---|
| `auditStore.test.ts` | `should set correlationId filter` | `auditStore` |
| `auditStore.test.ts` | `should reset all filters to defaults` | `auditStore` |

**Umbral de cobertura:** ≥ 80%

---

## 10. Pruebas E2E (Playwright, ATDD)

| Test | Flujo | Resultado esperado |
|---|---|---|
| `audit-list.spec.ts` | Login como ADMIN → `/audit/traces` | Lista de trazas visible con paginación |
| `audit-filter-correlation.spec.ts` | Ingresar correlationId en filtro → apply | Solo trazas con ese correlationId |
| `audit-detail.spec.ts` | Click en una traza → `/audit/traces/{traceId}` | `AuditTraceDetailCard` con todos los campos |
| `audit-saga-link.spec.ts` | Traza con sagaId presente | `CorrelationIdLink` muestra como link clickable |
| `audit-forbidden.spec.ts` | Login como USER → `/audit/traces` | Redirige (rol no autorizado) |

---

## 11. Criterios de Aceptación

### TDD

- [ ] Cada schema, hook y componente tuvo su prueba escrita y vista fallar (Red) antes de la implementación (Green).
- [ ] `npm run test` finaliza en verde.
- [ ] Cobertura del feature ≥ 80%.
- [ ] Flujos E2E de Playwright pasan.

### Funcionales

- [ ] Solo `ADMIN` y `COMPLIANCE_OFFICER` acceden al dashboard.
- [ ] Filtro por `correlationId` retorna solo trazas de esa operación.
- [ ] `CorrelationIdLink` activa filtro por `sagaId` cuando está presente.
- [ ] Detalle de traza muestra todos los campos incluyendo `metadata` (JSON formateado).
- [ ] Los datos de auditoría son de solo lectura (sin botones de edición ni eliminación).
- [ ] Feature desplegado como pod en K3s via Ingress Traefik.
