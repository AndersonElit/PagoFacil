# Etapa 4d — Frontend: Feature compliance

**Proyecto:** PagoFacil — Billetera Digital
**Feature:** compliance — Dashboard de alertas de fraude y AML; resolución manual
**Roles de usuario:** FRAUD_ANALYST, COMPLIANCE_OFFICER (gestión); ADMIN (solo lectura)
**Bounded context:** BC-03 fraud-compliance-service

---

## 1. Contexto y Objetivo

El feature `compliance` es el dashboard interno para analistas y oficiales de cumplimiento. Permite visualizar alertas AML y de fraude, filtrarlas por estado/nivel de riesgo/tipo y resolverlas manualmente. El acceso está restringido por rol.

---

## 2. Prerrequisitos

- [ ] Etapa 4a (`auth`) funcional con roles configurados en Cognito.
- [ ] Etapa 3d (`fraud-compliance-service`) funcional.
- [ ] API Gateway accesible en `http://VPS_IP:8080`.

---

## 3. Rutas y Páginas

| Path | Tipo | Componente de página | Descripción |
|---|---|---|---|
| `/compliance/alerts` | protected, SSR | `AlertsListPage` | Listado paginado de alertas con filtros |
| `/compliance/alerts/[alertId]` | protected, SSR | `AlertDetailPage` | Detalle de alerta + formulario de resolución |

Solo accesible para `FRAUD_ANALYST`, `COMPLIANCE_OFFICER`, `ADMIN`. `middleware.ts` rechaza otros roles con 403.

> **TDD obligatorio — prueba Vitest FALLA (Red) antes del artefacto (Green).**

---

## 4. Componentes — test-first

| Componente | Tipo | Responsabilidad |
|---|---|---|
| `AlertsTable` | Client Component | Columnas: alert_type, risk_level (badge), status (badge), user_id, created_at; acciones: Ver detalle; paginación |
| `RiskLevelBadge` | Client Component | CRITICAL=rojo oscuro, HIGH=naranja, MEDIUM=amarillo, LOW=verde |
| `AlertStatusBadge` | Client Component | OPEN=azul, UNDER_REVIEW=morado, APPROVED=verde, REJECTED=rojo, ESCALATED=naranja |
| `AlertFilters` | Client Component | Selects: status, risk_level, alert_type; date range (created_at from/to) |
| `AlertDetailCard` | Server Component | Muestra todos los campos: alert_type, risk_level, status, user_id, transaction_id, correlation_id, triggered_rule, resolution_actor, resolution_reason |
| `AlertResolutionForm` | Client Component | Select status (APPROVED\|REJECTED\|ESCALATED), textarea resolution_reason; submit → `useResolveAlert`; **deshabilitado para ADMIN** |

---

## 5. Integración con API (TanStack Query) — test-first

| Hook | Endpoint | Tipo | staleTime | Descripción |
|---|---|---|---|---|
| `useComplianceAlerts` | `GET /compliance/alerts` | `useQuery` | 30 s | Paginado; query key incluye filtros activos |
| `useAlertDetail` | `GET /compliance/alerts/{id}` | `useQuery` | 30 s | Detalle completo |
| `useResolveAlert` | `PUT /compliance/alerts/{id}/resolve` | `useMutation` | — | Invalida `useComplianceAlerts` y `useAlertDetail` tras éxito |

---

## 6. Estado Global (Zustand)

`complianceStore`:
- `filters: AlertFilter` (status?, risk_level?, alert_type?, dateFrom?, dateTo?, page, size)
- `setFilter(key, value): void`
- `resetFilters(): void`

---

## 7. Esquemas de Validación (Zod) — test-first

```typescript
// resolveAlertSchema
z.object({
  status: z.enum(["APPROVED", "REJECTED", "ESCALATED"], { required_error: "Seleccione una resolución" }),
  resolution_reason: z.string().optional(),
}).refine(
  (d) => d.status !== "REJECTED" || (d.resolution_reason && d.resolution_reason.length >= 10),
  { message: "Razón requerida (mínimo 10 caracteres) cuando se rechaza", path: ["resolution_reason"] }
)

// alertFilterSchema
z.object({
  status: z.enum(["OPEN","UNDER_REVIEW","APPROVED","REJECTED","ESCALATED"]).optional(),
  risk_level: z.enum(["LOW","MEDIUM","HIGH","CRITICAL"]).optional(),
  alert_type: z.enum(["AML","FRAUD"]).optional(),
  dateFrom: z.string().datetime().optional(),
  dateTo: z.string().datetime().optional(),
})
```

---

## 8. Autenticación y Autorización

- Rutas protegidas: solo `FRAUD_ANALYST`, `COMPLIANCE_OFFICER`, `ADMIN`.
- `middleware.ts` verifica el claim `role` del JWT; redirige a `/dashboard` si el rol no tiene acceso.
- `AlertResolutionForm` verifica el rol del usuario antes de habilitar el submit: si `role === ADMIN` el formulario se muestra como `disabled`.

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> Prueba FALLA (Red) antes del artefacto (Green).

### Schemas Zod

| Archivo de test | Caso | Schema que precede |
|---|---|---|
| `resolveAlertSchema.test.ts` | `should require resolution_reason when status is REJECTED` | `resolveAlertSchema` |
| `resolveAlertSchema.test.ts` | `should accept APPROVED without resolution_reason` | `resolveAlertSchema` |
| `resolveAlertSchema.test.ts` | `should reject resolution_reason shorter than 10 chars on REJECTED` | `resolveAlertSchema` |

### Hooks (con MSW)

| Archivo de test | Escenario | Hook que precede |
|---|---|---|
| `useComplianceAlerts.test.ts` | `should return paginated alerts on success` | `useComplianceAlerts` |
| `useComplianceAlerts.test.ts` | `should filter alerts by risk_level` | `useComplianceAlerts` |
| `useResolveAlert.test.ts` | `should invalidate query cache on success` | `useResolveAlert` |
| `useResolveAlert.test.ts` | `should handle 403 unauthorized response` | `useResolveAlert` |

### Componentes (React Testing Library)

| Archivo de test | Interacción / estado | Componente que precede |
|---|---|---|
| `RiskLevelBadge.test.tsx` | `should apply red class for CRITICAL` | `RiskLevelBadge` |
| `RiskLevelBadge.test.tsx` | `should apply green class for LOW` | `RiskLevelBadge` |
| `AlertStatusBadge.test.tsx` | `should apply blue class for OPEN` | `AlertStatusBadge` |
| `AlertResolutionForm.test.tsx` | `should be disabled when role is ADMIN` | `AlertResolutionForm` |
| `AlertResolutionForm.test.tsx` | `should require resolution_reason for REJECTED` | `AlertResolutionForm` |
| `AlertsTable.test.tsx` | `should render all expected columns` | `AlertsTable` |

### Slices Zustand

| Archivo de test | Caso | Slice que precede |
|---|---|---|
| `complianceStore.test.ts` | `should update filter.status on setFilter` | `complianceStore` |
| `complianceStore.test.ts` | `should reset all filters on resetFilters` | `complianceStore` |

**Umbral de cobertura:** ≥ 80%

---

## 10. Pruebas E2E (Playwright, ATDD)

| Test | Flujo | Resultado esperado |
|---|---|---|
| `compliance-list.spec.ts` | Login como COMPLIANCE_OFFICER → `/compliance/alerts` | Lista de alertas visible con badges de riesgo |
| `compliance-filter.spec.ts` | Filtrar por risk_level=CRITICAL | Solo alertas CRITICAL visibles |
| `compliance-resolve.spec.ts` | Abrir alerta OPEN → select APPROVED → submit | Toast de éxito; alerta resuelta desaparece de la lista OPEN |
| `compliance-forbidden.spec.ts` | Login como USER → intentar acceder a `/compliance/alerts` | Redirige a `/dashboard` (rol no autorizado) |
| `compliance-admin-readonly.spec.ts` | Login como ADMIN → abrir detalle de alerta | `AlertResolutionForm` visible pero `disabled` |

---

## 11. Criterios de Aceptación

### TDD

- [ ] Cada schema, hook y componente tuvo su prueba escrita y vista fallar (Red) antes de la implementación (Green).
- [ ] `npm run test` finaliza en verde.
- [ ] Cobertura del feature ≥ 80%.
- [ ] Flujos E2E de Playwright pasan.

### Funcionales

- [ ] Solo `FRAUD_ANALYST` y `COMPLIANCE_OFFICER` pueden resolver alertas.
- [ ] `ADMIN` ve el formulario de resolución deshabilitado.
- [ ] `USER` es rechazado con redirect al intentar acceder.
- [ ] Resolución con status REJECTED requiere `resolution_reason` ≥ 10 caracteres.
- [ ] Tras resolución exitosa, la caché de TanStack Query se invalida y la lista se recarga.
- [ ] Feature desplegado como pod en K3s via Ingress Traefik.
