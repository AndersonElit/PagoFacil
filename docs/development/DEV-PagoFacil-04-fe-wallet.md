# Etapa 4 — Frontend: Feature wallet

**Proyecto:** PagoFacil | **Frontend:** pagofacil-web (Next.js 15.3)  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Contexto y Objetivo

Implementar el dashboard principal del usuario: visualización de saldo en tiempo real, historial de transacciones paginado, y los formularios de depósito, retiro y transferencia que inician las sagas correspondientes.

**Roles de usuario que acceden:** Usuario Final (cliente autenticado).

**Bounded contexts del backend consumidos:** BC-02 Wallet (`wallet-service`), BC-01 Identity (`identity-service`, para estado KYC).

---

## 2. Prerrequisitos

- Feature `auth` completo (Etapa 4a).
- `wallet-service` activo en K3d dev.
- `projection-service` proyectando transacciones en `pagofacil_readmodel` (para el historial).
- `integration-service` activo (para procesar las sagas).

---

## 3. Rutas y Páginas

| Path | Tipo | Componente de página | Descripción | Renderizado |
|---|---|---|---|---|
| `/dashboard` | Protegida (usuario) | `app/dashboard/page.tsx` | Saldo + acciones rápidas + últimas transacciones | SSR (saldo inicial) |
| `/deposit` | Protegida (usuario) | `app/deposit/page.tsx` | Formulario de depósito de fondos | CSR |
| `/withdraw` | Protegida (usuario) | `app/withdraw/page.tsx` | Formulario de retiro de fondos | CSR |
| `/transfer` | Protegida (usuario) | `app/transfer/page.tsx` | Formulario de transferencia entre billeteras | CSR |
| `/transactions` | Protegida (usuario) | `app/transactions/page.tsx` | Historial paginado de transacciones | SSR con paginación |
| `/transactions/[id]` | Protegida (usuario) | `app/transactions/[id]/page.tsx` | Detalle de una transacción | SSR |

> **Regla TDD:** cada schema Zod, hook y componente tiene su prueba Vitest en la Sección 9, escrita y vista fallar **ANTES** de implementar el artefacto.

---

## 4. Componentes — _test-first_

| Componente | Tipo | Responsabilidad |
|---|---|---|
| `BalanceCard` | Client Component | Muestra `availableBalance` y `pendingBalance` con formato de moneda; botón de refresh; estado de carga skeleton |
| `TransactionList` | Client Component | Lista paginada de transacciones con filtros (estado, fecha); muestra estado con badge de color |
| `TransactionCard` | Client Component | Item de la lista: operationType, amount, status, createdAt |
| `TransactionDetail` | Server Component | Detalle completo de una transacción |
| `DepositForm` | Client Component | Campos: `amount`, `fundSourceId` (select), `idempotencyKey` (generado automáticamente UUID); submit → `useDeposit` |
| `WithdrawForm` | Client Component | Campos: `amount`, `fundSourceId`, `idempotencyKey`; valida saldo disponible antes de submit; submit → `useWithdraw` |
| `TransferForm` | Client Component | Campos: `amount`, `destinatarioIdentifier` (email/alias), `idempotencyKey`; submit → `useTransfer` |
| `OperationStatusBanner` | Client Component | Muestra el estado de la saga en curso (PENDIENTE → EN_PROCESO → CONFIRMADA / FALLIDA) con polling automático |
| `KycPendingBanner` | Client Component | Aviso no bloqueante si `accountStatus = PENDIENTE_KYC`; desaparece al activar cuenta |

---

## 5. Integración con API (TanStack Query) — _test-first_

| Hook | Endpoint | Tipo | Descripción | Caché |
|---|---|---|---|---|
| `useBalance` | `GET /v1/wallet/me/balance` | `useQuery` | Saldo en tiempo real del write-side | `staleTime: 10s`, `refetchInterval: 30s` |
| `useTransactions` | `GET /v1/wallet/transactions` | `useQuery` | Historial paginado con filtros | `staleTime: 30s` |
| `useTransaction` | `GET /v1/wallet/transactions/{id}` | `useQuery` | Detalle de transacción | `staleTime: 60s` |
| `useDeposit` | `POST /v1/wallet/deposits` | `useMutation` | Iniciar depósito; en éxito invalida `useBalance` y `useTransactions` | Invalida en éxito |
| `useWithdraw` | `POST /v1/wallet/withdrawals` | `useMutation` | Iniciar retiro | Invalida en éxito |
| `useTransfer` | `POST /v1/wallet/transfers` | `useMutation` | Iniciar transferencia | Invalida en éxito |

---

## 6. Estado Global (Zustand)

| Slice | Estado | Acciones |
|---|---|---|
| `walletSlice` | `pendingOperationId: string \| null`, `operationStatus: TransactionStatus \| null` | `setPendingOperation(id, status)`, `clearPendingOperation()` |

El `pendingOperationId` se usa por `OperationStatusBanner` para hacer polling del estado de la transacción en curso.

---

## 7. Esquemas de Validación (Zod) — _test-first_

```typescript
// schemas/wallet.ts

const depositSchema = z.object({
  amount: z.number({ required_error: "Monto requerido" })
    .positive("El monto debe ser mayor a 0")
    .max(99999999, "Monto máximo excedido"),
  fundSourceId: z.string().uuid("Selecciona una fuente de fondos válida"),
  currency: z.string().length(3).default("USD")
});

const withdrawSchema = depositSchema; // mismos campos

const transferSchema = z.object({
  amount: z.number().positive("Monto debe ser mayor a 0").max(99999999),
  destinatarioIdentifier: z.string()
    .min(1, "Destinatario requerido")
    .max(320, "Identificador demasiado largo"),
  currency: z.string().length(3).default("USD")
});
```

---

## 8. Autenticación y Autorización

- Todas las rutas del feature `wallet` requieren sesión NextAuth activa (rol `USUARIO_FINAL`).
- El middleware NextAuth en `middleware.ts` redirige a `/login` si la sesión no existe o expiró.
- El `accessToken` JWT del usuario se adjunta al header `Authorization: Bearer <token>` en cada llamada a `wallet-service`.
- `wallet-service` valida que `wallet.userId == JWT.sub` antes de retornar datos.
- Si `accountStatus == PENDIENTE_KYC`, se muestra `KycPendingBanner` pero no se bloquea el dashboard.

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> Cada prueba se escribe y se ve **fallar (Red)** antes de implementar el artefacto.

### Schemas Zod

| Archivo de test | Caso | Schema |
|---|---|---|
| `schemas/wallet.test.ts` | `depositSchema válido con amount positivo y fundSourceId UUID` | `depositSchema` |
| `schemas/wallet.test.ts` | `depositSchema inválido — amount negativo` | `depositSchema` |
| `schemas/wallet.test.ts` | `depositSchema inválido — amount = 0` | `depositSchema` |
| `schemas/wallet.test.ts` | `transferSchema válido — email como destinatario` | `transferSchema` |
| `schemas/wallet.test.ts` | `transferSchema inválido — destinatario vacío` | `transferSchema` |

### Hooks (MSW)

| Archivo de test | Escenario (MSW) | Hook |
|---|---|---|
| `hooks/useBalance.test.ts` | `GET /v1/wallet/me/balance` → 200 con saldo | `useBalance` (loading → success) |
| `hooks/useBalance.test.ts` | `GET /v1/wallet/me/balance` → 401 | `useBalance` (error state) |
| `hooks/useDeposit.test.ts` | `POST /v1/wallet/deposits` → 202 con `transactionId` | `useDeposit` (success) |
| `hooks/useDeposit.test.ts` | `POST /v1/wallet/deposits` → 400 (límite excedido) | `useDeposit` (error handling) |
| `hooks/useWithdraw.test.ts` | `POST /v1/wallet/withdrawals` → 400 (saldo insuficiente) | `useWithdraw` (error) |
| `hooks/useTransactions.test.ts` | `GET /v1/wallet/transactions` → 200 con `content[]` paginado | `useTransactions` |
| `hooks/useTransfer.test.ts` | `POST /v1/wallet/transfers` → 202 | `useTransfer` (success) |

### Componentes (React Testing Library)

| Archivo de test | Interacción / estado | Componente |
|---|---|---|
| `components/BalanceCard.test.tsx` | Renderiza skeleton mientras carga | `BalanceCard` |
| `components/BalanceCard.test.tsx` | Muestra `availableBalance` formateado en USD | `BalanceCard` |
| `components/TransactionList.test.tsx` | Renderiza lista con 3 transacciones mock | `TransactionList` |
| `components/TransactionList.test.tsx` | Filtra por estado CONFIRMADA | `TransactionList` |
| `components/DepositForm.test.tsx` | Genera `idempotencyKey` automáticamente al renderizar | `DepositForm` |
| `components/DepositForm.test.tsx` | Muestra error de validación si amount negativo | `DepositForm` |
| `components/DepositForm.test.tsx` | Deshabilita el botón mientras la mutación está cargando | `DepositForm` |
| `components/OperationStatusBanner.test.tsx` | Muestra badge PENDIENTE cuando `operationStatus = PENDIENTE` | `OperationStatusBanner` |
| `components/OperationStatusBanner.test.tsx` | Oculta el banner cuando `pendingOperationId = null` | `OperationStatusBanner` |

### Slices Zustand

| Archivo de test | Acción | Slice |
|---|---|---|
| `store/walletSlice.test.ts` | `setPendingOperation` guarda id y status | `walletSlice` |
| `store/walletSlice.test.ts` | `clearPendingOperation` deja estado en null | `walletSlice` |

**Umbral de cobertura del feature:** ≥ 80%.

---

## 10. Pruebas E2E (Playwright, ATDD)

| Nombre del test | Flujo | Precondiciones | Resultado esperado |
|---|---|---|---|
| `wallet-view-balance.spec.ts` | Usuario autenticado → navega a `/dashboard` → ve saldo disponible | Usuario activo con wallet | Dashboard muestra `availableBalance` no nulo |
| `wallet-deposit.spec.ts` | Usuario llena formulario de depósito → submit → ve banner de estado EN_PROCESO → espera confirmación | Cuenta activa, fuente de fondos registrada, WireMock confirma entidad financiera | Transacción en historial con status CONFIRMADA |
| `wallet-insufficient-balance.spec.ts` | Usuario intenta retiro mayor al saldo disponible | Cuenta con saldo insuficiente | Formulario muestra error "saldo insuficiente"; no se crea transacción |
| `wallet-transfer.spec.ts` | Usuario transfiere a destinatario válido → ve confirmación | Dos cuentas activas en el sistema | Historial de ambas cuentas actualizado |
| `wallet-idempotent-deposit.spec.ts` | Usuario envía el mismo formulario de depósito dos veces (sin recargar) | Mismo `idempotencyKey` en ambos submits | Solo una transacción creada; segunda respuesta igual a la primera |

---

## 11. Criterios de Aceptación

- [ ] Cada schema, hook y componente tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] `npm run test` finaliza en verde.
- [ ] La cobertura del feature ≥ 80%.
- [ ] Los flujos E2E de la Sección 10 pasan en Playwright.
- [ ] `BalanceCard` muestra saldo actualizado en tiempo real (polling cada 30s).
- [ ] Formulario de depósito genera `idempotencyKey` único automáticamente (no manual del usuario).
- [ ] Submit doble del mismo formulario no crea dos transacciones.
- [ ] El estado de la transacción cambia de `EN_PROCESO` a `CONFIRMADA` cuando la saga completa.
- [ ] La página de historial `/transactions` carga con datos del Read Model (projection-service).
