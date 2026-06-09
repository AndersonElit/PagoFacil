# Etapa 4b — Frontend: Feature wallets

**Proyecto:** PagoFacil — Billetera Digital
**Feature:** wallets — Saldo, historial de movimientos, cuentas bancarias vinculadas
**Roles de usuario:** USER, ADMIN
**Bounded context:** BC-02 Wallet
**Microservicios:** wallet-service (`:8082`), identity-service (`:8081`)

---

## 1. Contexto y Objetivo

El feature `wallets` permite al usuario consultar su saldo disponible y reservado, navegar el historial paginado de movimientos con filtros, y visualizar las cuentas bancarias vinculadas. La billetera se crea automáticamente tras el `KYCApproved` — el usuario llega aquí después de autenticarse.

---

## 2. Prerrequisitos

- [ ] Etapa 4a (`auth`) funcional — usuario puede autenticarse.
- [ ] Etapa 3b (`wallet-service`) funcional con al menos una billetera creada.
- [ ] API Gateway accesible en `http://VPS_IP:8080`.

---

## 3. Rutas y Páginas

| Path | Tipo | Componente de página | Descripción |
|---|---|---|---|
| `/wallets/[walletId]` | protected, SSR | `WalletDashboardPage` | Saldo disponible/reservado + últimas 5 transacciones + acciones rápidas |
| `/wallets/[walletId]/transactions` | protected, CSR | `TransactionHistoryPage` | Historial paginado de movimientos con filtros avanzados |
| `/wallets/[walletId]/linked-accounts` | protected, CSR | `LinkedAccountsPage` | Lista de cuentas bancarias vinculadas con estado |

> **TDD obligatorio — prueba Vitest FALLA (Red) antes de implementar el artefacto (schema, hook, componente).**

---

## 4. Componentes — test-first

| Componente | Tipo | Responsabilidad |
|---|---|---|
| `WalletBalanceCard` | Client Component | Muestra `available_balance`, `reserved_balance`, `currency`, `status` badge; si `SUSPENDED` muestra banner de alerta rojo |
| `TransactionTable` | Client Component | Columnas: tipo, monto, currency, status badge, fecha, correlationId (truncado); paginación; filtros activos visibles como chips |
| `TransactionStatusBadge` | Client Component | CONFIRMED=verde, PENDING=amarillo, REVERSED=naranja, FAILED=rojo |
| `TransactionFilters` | Client Component | Selects tipo (DEPOSIT\|TRANSFER_DEBIT\|TRANSFER_CREDIT\|WITHDRAWAL\|REVERSAL), status, date desde/hasta |
| `LinkedAccountsList` | Client Component | Lista con bank_name, últimos 4 dígitos de account_number, account_type, status badge |
| `LinkedAccountStatusBadge` | Client Component | PENDING_VERIFICATION=gris, VERIFIED=verde, REJECTED=rojo |
| `EmptyStateCard` | Server Component | Mensaje "Sin movimientos" cuando historial vacío |
| `WalletSuspendedBanner` | Client Component | Banner visible cuando `wallet.status === SUSPENDED` |

---

## 5. Integración con API (TanStack Query) — test-first

| Hook | Endpoint | Tipo | staleTime | gcTime | Descripción |
|---|---|---|---|---|---|
| `useWallet` | `GET /wallets/{id}` | `useQuery` | 30 s | 5 min | Saldo y estado; refetch automático cada 30 s via `refetchInterval` |
| `useTransactions` | `GET /wallets/{id}/transactions` | `useQuery` | 60 s | 5 min | Paginado; query key incluye filtros; page y size |
| `useLinkedBankAccounts` | `GET /wallets/{id}/linked-bank-accounts` | `useQuery` | 5 min | 10 min | Lista de cuentas vinculadas |

Invalidaciones: ninguna automática (datos de solo lectura).

---

## 6. Estado Global (Zustand)

`walletStore`:
- `filters: TransactionFilter` (type?, status?, dateFrom?, dateTo?, page: number, size: number)
- `setFilter(key, value): void`
- `resetFilters(): void`
- `setPage(page: number): void`

---

## 7. Esquemas de Validación (Zod) — test-first

```typescript
// transactionFilterSchema
z.object({
  type: z.enum(["DEPOSIT","TRANSFER_DEBIT","TRANSFER_CREDIT","WITHDRAWAL","REVERSAL"]).optional(),
  status: z.enum(["PENDING","CONFIRMED","REVERSED","FAILED"]).optional(),
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

- Todas las rutas son protegidas. `middleware.ts` redirige a `/auth/login` si no hay sesión.
- El `walletId` se obtiene del perfil del usuario autenticado (`GET /users/{userId}` → wallet asociada).
- Header `Authorization: Bearer <access_token>` inyectado automáticamente por `getServerSession()` / `useSession()` de NextAuth.js.

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> Prueba FALLA (Red) antes del artefacto (Green).

### Schemas Zod

| Archivo de test | Caso | Schema que precede |
|---|---|---|
| `transactionFilterSchema.test.ts` | `should reject dateTo before dateFrom` | `transactionFilterSchema` |
| `transactionFilterSchema.test.ts` | `should accept filter with only type` | `transactionFilterSchema` |

### Hooks (con MSW)

| Archivo de test | Escenario | Hook que precede |
|---|---|---|
| `useWallet.test.ts` | `should return wallet balance on success` | `useWallet` |
| `useWallet.test.ts` | `should show suspended warning when status is SUSPENDED` | `useWallet` |
| `useTransactions.test.ts` | `should return paginated transactions` | `useTransactions` |
| `useTransactions.test.ts` | `should refetch when filters change` | `useTransactions` |
| `useLinkedBankAccounts.test.ts` | `should return linked accounts list` | `useLinkedBankAccounts` |

### Componentes (React Testing Library)

| Archivo de test | Interacción / estado | Componente que precede |
|---|---|---|
| `WalletBalanceCard.test.tsx` | `should display available_balance formatted with 2 decimals` | `WalletBalanceCard` |
| `WalletBalanceCard.test.tsx` | `should show suspended banner when status is SUSPENDED` | `WalletSuspendedBanner` via `WalletBalanceCard` |
| `TransactionTable.test.tsx` | `should render correct number of rows` | `TransactionTable` |
| `TransactionStatusBadge.test.tsx` | `should apply green class for CONFIRMED` | `TransactionStatusBadge` |
| `TransactionFilters.test.tsx` | `should call setFilter when type changes` | `TransactionFilters` |
| `EmptyStateCard.test.tsx` | `should render empty message when no data` | `EmptyStateCard` |

### Slices Zustand

| Archivo de test | Caso | Slice que precede |
|---|---|---|
| `walletStore.test.ts` | `should update filter.type on setFilter` | `walletStore` |
| `walletStore.test.ts` | `should reset all filters on resetFilters` | `walletStore` |

**Umbral de cobertura:** ≥ 80%

---

## 10. Pruebas E2E (Playwright, ATDD)

| Test | Flujo | Resultado esperado |
|---|---|---|
| `wallet-balance.spec.ts` | Login → navegar a `/wallets/{id}` | `WalletBalanceCard` muestra saldo con 2 decimales |
| `wallet-transactions.spec.ts` | Seleccionar filtro tipo `DEPOSIT` → aplicar | Solo filas con tipo DEPOSIT visibles |
| `wallet-suspended.spec.ts` | Wallet con `status=SUSPENDED` | `WalletSuspendedBanner` visible en la página |
| `wallet-empty-history.spec.ts` | Wallet sin transacciones | `EmptyStateCard` visible |
| `wallet-pagination.spec.ts` | Historial con > 20 filas → navegar a página 2 | Segunda página cargada correctamente |

---

## 11. Criterios de Aceptación

### TDD

- [ ] Cada schema, hook y componente tuvo su prueba escrita y vista fallar (Red) antes de la implementación (Green).
- [ ] `npm run test` finaliza en verde.
- [ ] Cobertura del feature ≥ 80%.
- [ ] Flujos E2E de Playwright pasan.

### Funcionales

- [ ] `WalletBalanceCard` muestra `available_balance` y `reserved_balance` con 2 decimales.
- [ ] Billetera suspendida muestra banner de alerta prominente.
- [ ] Historial paginado con filtros por tipo, status y rango de fechas funcional.
- [ ] `dateFrom > dateTo` en filtros muestra error de validación Zod.
- [ ] Feature desplegado como pod en K3s via Ingress Traefik.
