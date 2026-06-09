# Etapa 4c — Frontend: Feature transactions

**Proyecto:** PagoFacil — Billetera Digital
**Feature:** transactions — Depósito, transferencia, retiro y seguimiento de estado
**Roles de usuario:** USER (inicia), ADMIN (solo lectura)
**Bounded contexts:** BC-02 Wallet, BC-05 Integration
**Header obligatorio en operaciones financieras:** `Idempotency-Key: <UUID v4>`

---

## 1. Contexto y Objetivo

El feature `transactions` permite al usuario iniciar operaciones financieras (depósito, transferencia, retiro) y hacer seguimiento del estado de la saga de forma asíncrona. El `Idempotency-Key` se genera en el cliente con `crypto.randomUUID()` al montar el formulario; el backend garantiza que el mismo key no produzca doble efecto.

---

## 2. Prerrequisitos

- [ ] Etapas 4a (`auth`) y 4b (`wallets`) funcionales.
- [ ] Etapa 3b (`wallet-service`) y 3e (`integration-service`) funcionales.
- [ ] Cuentas bancarias vinculadas disponibles en `wallet-service` para el formulario de retiro.

---

## 3. Rutas y Páginas

| Path | Tipo | Componente de página | Descripción |
|---|---|---|---|
| `/transactions/deposit` | protected, CSR | `DepositPage` | Formulario de inicio de depósito |
| `/transactions/transfer` | protected, CSR | `TransferPage` | Formulario de transferencia entre usuarios |
| `/transactions/withdrawal` | protected, CSR | `WithdrawalPage` | Formulario de retiro a cuenta bancaria |
| `/transactions/[transactionId]` | protected, CSR | `TransactionStatusPage` | Seguimiento de estado con polling |

> **TDD obligatorio — prueba Vitest FALLA (Red) antes del artefacto (Green).**

---

## 4. Componentes — test-first

| Componente | Tipo | Responsabilidad |
|---|---|---|
| `DepositForm` | Client Component | Campos: amount (numérico), currency (select USD por defecto). Genera `Idempotency-Key` UUID v4 al montar. Submit → `useInitiateDeposit`. Muestra estado PENDING → `TransactionStatusTracker` |
| `TransferForm` | Client Component | Campos: amount, currency, recipientUserId (input UUID). Genera `Idempotency-Key`. Submit → `useInitiateTransfer` |
| `WithdrawalForm` | Client Component | Campos: amount, currency, linkedBankAccountId (select de cuentas VERIFIED). Genera `Idempotency-Key`. Submit → `useInitiateWithdrawal` |
| `TransactionStatusTracker` | Client Component | Muestra progreso QUEUED→PENDING→CONFIRMED\|REVERSED\|FAILED. Polling automático cada 3 s via `useTransactionStatus`. Spinner cuando PENDING; checkmark cuando CONFIRMED; alerta cuando FAILED\|REVERSED |
| `IdempotencyErrorAlert` | Client Component | Banner amarillo: "Operación en curso. Por favor espere." cuando backend retorna 409 |
| `AmountInput` | Client Component | Input numérico con 2 decimales máx; prefijo de moneda; rechaza negativo |

---

## 5. Integración con API (TanStack Query) — test-first

| Hook | Endpoint | Tipo | Descripción |
|---|---|---|---|
| `useInitiateDeposit` | `POST /transactions/deposits` | `useMutation` | Inyecta `Idempotency-Key` en header; en 202 redirige a `/transactions/{transactionId}` |
| `useInitiateTransfer` | `POST /transactions/transfers` | `useMutation` | Ídem |
| `useInitiateWithdrawal` | `POST /transactions/withdrawals` | `useMutation` | Ídem |
| `useTransactionStatus` | `GET /transactions/{id}` | `useQuery` | `refetchInterval: 3000` cuando `status === PENDING`; `false` cuando terminal (CONFIRMED\|REVERSED\|FAILED) |

---

## 6. Estado Global (Zustand)

`transactionStore`:
- `pendingTransactions: Map<string, { transactionId: string; status: string }>` (idempotencyKey → estado)
- `addPendingTransaction(idempotencyKey, transactionId): void`
- `updateTransactionStatus(idempotencyKey, status): void`
- `clearCompleted(): void`

---

## 7. Esquemas de Validación (Zod) — test-first

```typescript
// depositSchema
z.object({
  amount: z.number({ message: "Ingrese un monto" }).positive("Debe ser positivo")
    .multipleOf(0.01, "Máximo 2 decimales"),
  currency: z.enum(["USD"]),
})

// transferSchema
z.object({
  amount: z.number().positive().multipleOf(0.01),
  currency: z.enum(["USD"]),
  recipientUserId: z.string().uuid("ID de destinatario inválido"),
})

// withdrawalSchema
z.object({
  amount: z.number().positive().multipleOf(0.01),
  currency: z.enum(["USD"]),
  linkedBankAccountId: z.string().uuid("Seleccione una cuenta bancaria válida"),
})
```

---

## 8. Autenticación y Autorización

- Rutas protegidas solo para USER. ADMIN no puede iniciar operaciones.
- `Idempotency-Key` generado con `crypto.randomUUID()` en el evento `onMount` del formulario.
- JWT incluido automáticamente en todos los requests por la configuración de NextAuth.js.
- `tenant_id` del claim JWT propagado automáticamente por el backend (no se envía en el body).

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> Prueba FALLA (Red) antes del artefacto (Green).

### Schemas Zod

| Archivo de test | Caso | Schema que precede |
|---|---|---|
| `depositSchema.test.ts` | `should reject negative amount` | `depositSchema` |
| `depositSchema.test.ts` | `should reject amount with more than 2 decimal places` | `depositSchema` |
| `transferSchema.test.ts` | `should reject invalid recipientUserId (non-UUID)` | `transferSchema` |
| `withdrawalSchema.test.ts` | `should reject empty linkedBankAccountId` | `withdrawalSchema` |

### Hooks (con MSW)

| Archivo de test | Escenario | Hook que precede |
|---|---|---|
| `useInitiateDeposit.test.ts` | `should return 202 and transactionId on success` | `useInitiateDeposit` |
| `useInitiateDeposit.test.ts` | `should handle 409 in-progress (same idempotency key)` | `useInitiateDeposit` |
| `useInitiateDeposit.test.ts` | `should handle 422 amount exceeds limit` | `useInitiateDeposit` |
| `useTransactionStatus.test.ts` | `should poll every 3s when status is PENDING` | `useTransactionStatus` |
| `useTransactionStatus.test.ts` | `should stop polling when status is CONFIRMED` | `useTransactionStatus` |

### Componentes (React Testing Library)

| Archivo de test | Interacción / estado | Componente que precede |
|---|---|---|
| `DepositForm.test.tsx` | `should generate unique idempotencyKey on mount` | `DepositForm` |
| `DepositForm.test.tsx` | `should disable submit button while mutation is pending` | `DepositForm` |
| `TransactionStatusTracker.test.tsx` | `should show spinner when status is PENDING` | `TransactionStatusTracker` |
| `TransactionStatusTracker.test.tsx` | `should show success indicator when CONFIRMED` | `TransactionStatusTracker` |
| `IdempotencyErrorAlert.test.tsx` | `should display warning message on 409 response` | `IdempotencyErrorAlert` |
| `AmountInput.test.tsx` | `should reject negative value input` | `AmountInput` |

### Slices Zustand

| Archivo de test | Caso | Slice que precede |
|---|---|---|
| `transactionStore.test.ts` | `should add pending transaction with idempotencyKey` | `transactionStore` |
| `transactionStore.test.ts` | `should update status of existing pending transaction` | `transactionStore` |

**Umbral de cobertura:** ≥ 80%

---

## 10. Pruebas E2E (Playwright, ATDD)

| Test | Flujo | Resultado esperado |
|---|---|---|
| `deposit-success.spec.ts` | Login → `/transactions/deposit` → amount=100 → submit → polling → CONFIRMED | `TransactionStatusTracker` muestra CONFIRMED; saldo en wallet actualizado |
| `transfer-insufficient-balance.spec.ts` | Transferencia con amount > saldo disponible → 422 | Error "Saldo insuficiente" en formulario |
| `withdrawal-idempotency.spec.ts` | Submit del mismo formulario dos veces rápidamente | Segundo submit retorna 409; `IdempotencyErrorAlert` visible |
| `deposit-amount-limit.spec.ts` | Depósito que excede límite transaccional → 422 | Error de límite visible en formulario |

---

## 11. Criterios de Aceptación

### TDD

- [ ] Cada schema, hook y componente tuvo su prueba escrita y vista fallar (Red) antes de la implementación (Green).
- [ ] `npm run test` finaliza en verde.
- [ ] Cobertura del feature ≥ 80%.
- [ ] Flujos E2E de Playwright pasan.

### Funcionales

- [ ] Formulario de depósito genera `Idempotency-Key` único al montar.
- [ ] Submit exitoso → redirect a `/transactions/{transactionId}` con polling activo.
- [ ] Polling para automáticamente cuando el status es terminal (CONFIRMED/REVERSED/FAILED).
- [ ] Doble submit con mismo `Idempotency-Key` → 409 → `IdempotencyErrorAlert` visible.
- [ ] Monto que excede límite transaccional → 422 → error en formulario.
- [ ] Feature desplegado como pod en K3s via Ingress Traefik.
