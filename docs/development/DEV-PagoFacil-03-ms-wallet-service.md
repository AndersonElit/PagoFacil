# Etapa 3 — Microservicio: wallet-service

**Proyecto:** PagoFacil | **Bounded Context:** BC-02 Wallet | **Puerto local:** 8082  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Contexto y Responsabilidad

**Bounded context:** BC-02 Wallet — gestión de saldo, operaciones financieras y fuentes de fondos.

**Responsabilidad principal:**
- Mantenimiento de saldo disponible y pendiente por billetera con garantías ACID.
- Procesamiento de depósitos, retiros y transferencias.
- Aplicación de límites transaccionales por tenant.
- Garantía de idempotencia mediante `IdempotencyKey`.
- Publicación confiable de eventos de dominio vía Transactional Outbox.
- Exposición de endpoints de compensación idempotentes para las sagas DEPOSITO, RETIRO y TRANSFERENCIA.

**Dependencias de otros microservicios:**

| Dirección | Servicio | Protocolo | Propósito |
|---|---|---|---|
| Entrante (REST) | `integration-service` | mTLS | Pasos y compensaciones de saga |

**Dependencias de infraestructura:**

| Recurso | Tipo | Propósito |
|---|---|---|
| `pagofacil_wallet_service` | PostgreSQL R2DBC | Write side: billeteras, transacciones, límites |
| `pagofacil.wallet.*` | Kafka Producer (Outbox relay) | Eventos de dominio BC-02 |

---

## 2. Prerrequisitos

- Etapa 2b completa (CI/CD configurado).
- Secret `pagofacil/dev/wallet-service` en floci.
- Migraciones Liquibase de `db/wallet-service/` aplicadas (incluye `00003_outbox.yaml`).
- `integration-service` disponible para pruebas de saga completas (o WireMock como stub).

---

## 3. Ciclo de Desarrollo Incremental en K3d dev

Con CI/CD configurado, cada commit exitoso despliega el servicio automáticamente en K3d dev.

**Condición mínima para el primer despliegue:** el esqueleto Spring Boot arranca, `/actuator/health/readiness` responde `UP`, secret existe.

```
Implementar caso de uso → mvn test (Red → Green) → git push
    → Jenkins pipeline → bumpImageTag → ArgoCD sync → K3d dev
```

> **Regla TDD:** la prueba de cada capa se escribe y se ve **fallar (Red)** ANTES de implementar el código de producción. La Sección 8 especifica la prueba que precede a cada elemento de las Secciones 4-7.

---

## 4. Capa de Dominio (`domain`) — _test-first_

### Entidades

| Entidad | Campos clave | Reglas de negocio |
|---|---|---|
| `Wallet` | `walletId`, `userId`, `tenantId`, `availableBalance (Money)`, `pendingBalance (Money)`, `currency` | `availableBalance >= 0`; `pendingBalance >= 0`; un wallet por `(userId, tenantId)` |
| `Transaction` | `transactionId`, `correlationId`, `idempotencyKey`, `walletId`, `tenantId`, `operationType`, `amount`, `currency`, `status` | Inmutable tras `status = CONFIRMADA` o `FALLIDA`; `amount > 0`; `idempotencyKey` único por `tenantId` |
| `FundSource` | `sourceId`, `userId`, `tenantId`, `bankName`, `accountNumberEnc`, `accountType`, `isActive` | `accountNumberEnc` cifrado antes de persistir |
| `TransactionLimit` | `limitId`, `tenantId`, `maxPerOperation`, `maxDaily`, `maxMonthly` | Exactamente un `TransactionLimit` activo por `tenantId` |

### Value Objects

| VO | Regla de validación |
|---|---|
| `Money` | `amount >= 0`; `currency` código ISO-4217 de 3 letras |
| `IdempotencyKey` | No vacío; longitud ≤ 255 |
| `TransactionStatus` | Enum: `PENDIENTE`, `EN_PROCESO`, `CONFIRMADA`, `FALLIDA`, `RETENIDA` |

### Eventos de dominio

| Evento | Payload mínimo | Topic Kafka |
|---|---|---|
| `DepositoIniciado` | `transactionId`, `walletId`, `amount`, `currency`, `idempotencyKey`, `correlationId` | `pagofacil.wallet.deposito-iniciado` |
| `DepositoConfirmado` | `transactionId`, `walletId`, `amount`, `resolvedAt` | `pagofacil.wallet.deposito-confirmado` |
| `DepositoRevertido` | `transactionId`, `correlationId`, `reason` | `pagofacil.wallet.deposito-revertido` |
| `RetiroIniciado` | `transactionId`, `walletId`, `amount`, `idempotencyKey` | `pagofacil.wallet.retiro-iniciado` |
| `RetiroConfirmado` | `transactionId`, `walletId`, `amount`, `resolvedAt` | `pagofacil.wallet.retiro-confirmado` |
| `TransferenciaIniciada` | `transactionId`, `walletId`, `counterpartWalletId`, `amount`, `idempotencyKey` | `pagofacil.wallet.transferencia-iniciada` |
| `TransferenciaConfirmada` | `transactionId`, `amount`, `resolvedAt` | `pagofacil.wallet.transferencia-confirmada` |
| `TransaccionIniciada` | `transactionId`, `userId`, `tenantId`, `amount`, `operationType` | `pagofacil.wallet.transaccion-iniciada` |

### Puertos secundarios (interfaces del dominio)

```java
// WalletRepository
Mono<Wallet> findByUserIdAndTenantId(UUID userId, UUID tenantId);
Mono<Wallet> save(Wallet wallet);

// TransactionRepository
Mono<Transaction> findByIdempotencyKeyAndTenantId(String key, UUID tenantId);
Mono<Transaction> findById(UUID transactionId);
Flux<Transaction> findByWalletIdPaginated(UUID walletId, int page, int size);
Mono<Transaction> save(Transaction transaction);

// TransactionLimitRepository
Mono<TransactionLimit> findByTenantId(UUID tenantId);

// FundSourceRepository
Mono<FundSource> findById(UUID sourceId);
Mono<FundSource> save(FundSource source);

// OutboxRepository
Mono<Void> save(OutboxEvent event);
```

### Invariantes de dominio

- `availableBalance` nunca puede ser negativo (checked en aggregate methods).
- Antes de reservar fondos para retiro: `availableBalance >= amount`.
- El `TransactionLimit` restringe `amount` por operación (`maxPerOperation`) y acumula en ventanas diaria/mensual.
- Una transacción con `idempotencyKey` ya existente retorna la transacción original sin crear nueva (idempotencia en el aggregate).
- El crédito (Wallet destinatario) y el débito (Wallet origen) en una transferencia deben ocurrir en la misma transacción ACID R2DBC.

---

## 5. Capa de Aplicación (`application`) — _test-first_

### Casos de uso

| Use Case | Descripción | Puerto primario | Puertos secundarios |
|---|---|---|---|
| `InitiateDepositUseCase` | Crea transacción PENDIENTE; incrementa `pendingBalance`; publica `DepositoIniciado` + `TransaccionIniciada` via Outbox | `InitiateDepositInputPort` | `WalletRepository`, `TransactionRepository`, `TransactionLimitRepository`, `OutboxRepository` |
| `ConfirmDepositUseCase` | Mueve fondos de `pendingBalance` a `availableBalance`; confirma transacción; publica `DepositoConfirmado` | `ConfirmDepositInputPort` | `WalletRepository`, `TransactionRepository`, `OutboxRepository` |
| `CompensateDepositUseCase` | Idempotente — revierte saldo pendiente de un depósito; publica `DepositoRevertido` | `CompensateDepositInputPort` | `WalletRepository`, `TransactionRepository`, `OutboxRepository` |
| `InitiateWithdrawalUseCase` | Reserva fondos (disponible → pendiente); crea transacción EN_PROCESO; publica `RetiroIniciado` + `TransaccionIniciada` | `InitiateWithdrawalInputPort` | `WalletRepository`, `TransactionRepository`, `TransactionLimitRepository`, `OutboxRepository` |
| `ConfirmWithdrawalUseCase` | Elimina fondos reservados; confirma transacción; publica `RetiroConfirmado` | `ConfirmWithdrawalInputPort` | `WalletRepository`, `TransactionRepository`, `OutboxRepository` |
| `CompensateWithdrawalUseCase` | Idempotente — libera fondos reservados | `CompensateWithdrawalInputPort` | `WalletRepository`, `TransactionRepository`, `OutboxRepository` |
| `InitiateTransferUseCase` | Débito remitente + crédito destinatario en ACID; publica `TransferenciaIniciada` + `TransaccionIniciada` | `InitiateTransferInputPort` | `WalletRepository`, `TransactionRepository`, `TransactionLimitRepository`, `OutboxRepository` |
| `ConfirmTransferUseCase` | Confirma transferencia; publica `TransferenciaConfirmada` | `ConfirmTransferInputPort` | `TransactionRepository`, `OutboxRepository` |
| `CompensateTransferUseCase` | Idempotente — ACID inversa: crédito remitente + débito destinatario | `CompensateTransferInputPort` | `WalletRepository`, `TransactionRepository`, `OutboxRepository` |
| `GetBalanceUseCase` | Retorna saldo actual desde write-side (no Read Model) | `GetBalanceInputPort` | `WalletRepository` |
| `GetTransactionHistoryUseCase` | Historial paginado de transacciones del Read Model | `GetTransactionHistoryInputPort` | `TransactionRepository` |

---

## 6. Capa de Infraestructura (`infrastructure`) — _test-first_

### Adaptadores R2DBC

| Adaptador | Tablas | Operaciones principales |
|---|---|---|
| `WalletR2dbcAdapter` | `wallets` | `findByUserIdAndTenantId`, `save` |
| `TransactionR2dbcAdapter` | `transactions` | `findByIdempotencyKeyAndTenantId`, `findById`, `save`, paginación |
| `TransactionLimitR2dbcAdapter` | `transaction_limits` | `findByTenantId` |
| `FundSourceR2dbcAdapter` | `fund_sources` | `findById`, `save` |
| `OutboxR2dbcAdapter` | `outbox` | `save` (en misma transacción R2DBC) |
| `ProcessedMessageR2dbcAdapter` | `processed_message` | Idempotencia: `findByMessageIdAndConsumer`, `save` |

**Transacción ACID en transferencia:** el adaptador ejecuta el débito remitente + crédito destinatario dentro de `transactionalOperator.transactional(...)` de Spring R2DBC. Si cualquier operación falla, el rollback revierte ambos.

### Productores Kafka (Outbox relay)

El relay hace polling de la tabla `outbox` (status=PENDING) y publica a Kafka. Al publicar exitosamente marca `status=PUBLISHED`.

### Configuración de seguridad

- `GET /v1/wallet/me/balance`: requiere JWT Bearer; valida `wallet.userId == JWT.sub`.
- `POST /v1/wallet/deposits|withdrawals|transfers`: requiere JWT Bearer; `tenantId` del JWT.
- `GET /v1/wallet/transactions*`: requiere JWT Bearer.
- `POST /v1/wallet/{type}/{id}/compensar`: requiere mTLS (solo `integration-service`).

---

## 7. API REST (`rest-api`) — _test-first_

Especificación completa: `docs/design/api/SDD-PagoFacil-openapi.yaml` — tag `Wallet` y `Compensaciones`

| Método | Ruta | Request Body | Response | Códigos HTTP |
|---|---|---|---|---|
| GET | `/v1/wallet/me/balance` | — | `SaldoResponse` | 200, 401, 403 |
| POST | `/v1/wallet/deposits` | `DepositoRequest` | `TransaccionResponse` | 202, 400, 422 |
| POST | `/v1/wallet/withdrawals` | `RetiroRequest` | `TransaccionResponse` | 202, 400, 422 |
| POST | `/v1/wallet/transfers` | `TransferenciaRequest` | `TransaccionResponse` | 202, 400, 422 |
| GET | `/v1/wallet/transactions` | — (query params) | `TransaccionPageResponse` | 200, 401 |
| GET | `/v1/wallet/transactions/{transactionId}` | — | `TransaccionResponse` | 200, 404 |
| POST | `/v1/wallet/deposits/{transactionId}/compensar` | `CompensacionRequest` | — | 200, 404 |
| POST | `/v1/wallet/withdrawals/{transactionId}/compensar` | `CompensacionRequest` | — | 200, 404 |
| POST | `/v1/wallet/transfers/{transactionId}/compensar` | `CompensacionRequest` | — | 200, 404 |

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> Todos los tipos reactivos se verifican con `StepVerifier`, nunca con `block()`.

### Dominio

| Clase de test | Método | Invariante / regla | Elemento de Sección 4 |
|---|---|---|---|
| `WalletTest` | `shouldNotAllowNegativeAvailableBalance` | `availableBalance >= 0` siempre | Entidad `Wallet` |
| `WalletTest` | `shouldRejectWithdrawalExceedingBalance` | Retiro > saldo → excepción | Entidad `Wallet` |
| `TransactionTest` | `shouldReturnExistingTransactionOnDuplicateIdempotencyKey` | Idempotencia en aggregate | Entidad `Transaction` |
| `TransactionTest` | `shouldNotAllowStateChangeOnConfirmedTransaction` | Inmutabilidad post-confirmación | Entidad `Transaction` |
| `MoneyTest` | `shouldRejectNegativeAmount` | `amount > 0` | VO `Money` |
| `TransactionLimitTest` | `shouldRejectAmountExceedingMaxPerOperation` | Límite por operación | Entidad `TransactionLimit` |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case |
|---|---|---|---|---|
| `InitiateDepositUseCaseTest` | `shouldCreatePendingTransactionAndIncreasePendingBalance` | Happy path | `WalletRepository`, `TransactionRepository`, `OutboxRepository` (Mockito) | `InitiateDepositUseCase` |
| `InitiateDepositUseCaseTest` | `shouldReturnExistingTransactionOnDuplicateKey` | Idempotencia | `TransactionRepository` (devuelve transacción existente) | `InitiateDepositUseCase` |
| `InitiateDepositUseCaseTest` | `shouldRejectAmountExceedingLimits` | Excede `maxPerOperation` | `TransactionLimitRepository` (mock) | `InitiateDepositUseCase` |
| `InitiateTransferUseCaseTest` | `shouldDebitAndCreditAtomically` | Happy path | `WalletRepository`, `TransactionRepository` (mock) | `InitiateTransferUseCase` |
| `InitiateTransferUseCaseTest` | `shouldFailOnInsufficientBalance` | Saldo insuficiente | `WalletRepository` (mock devuelve saldo bajo) | `InitiateTransferUseCase` |
| `CompensateDepositUseCaseTest` | `shouldBeIdempotentOnRepeatedCompensation` | Segunda compensación → sin efecto | `TransactionRepository` (ya compensado) | `CompensateDepositUseCase` |
| `CompensateTransferUseCaseTest` | `shouldReverseDebitAndCreditAtomically` | Reversión ACID | `WalletRepository`, `TransactionRepository` (mock) | `CompensateTransferUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador |
|---|---|---|---|
| `WalletR2dbcAdapterTest` | `shouldSaveAndFindWallet` | INSERT + SELECT con Testcontainers PostgreSQL | `WalletR2dbcAdapter` |
| `TransactionR2dbcAdapterTest` | `shouldReturnExistingOnDuplicateIdempotencyKey` | SELECT por idempotencyKey | `TransactionR2dbcAdapter` |
| `TransactionR2dbcAdapterTest` | `shouldDebitAndCreditInSameTransaction` | Transacción ACID R2DBC | `WalletR2dbcAdapter` + `TransactionR2dbcAdapter` |
| `OutboxR2dbcAdapterTest` | `shouldPersistEventAtomicallyWithWalletUpdate` | INSERT wallet + INSERT outbox en mismo `transactionalOperator` | `OutboxR2dbcAdapter` |
| `OutboxRelayTest` | `shouldPublishOnlyPendingMessages` | Relay no re-publica PUBLISHED | Outbox relay |

### REST

| Clase de test | Método | Endpoint | Status / body | Elemento |
|---|---|---|---|---|
| `WalletControllerTest` | `shouldReturn202OnValidDeposit` | `POST /v1/wallet/deposits` | 202 + `transactionId`, `status: EN_PROCESO` | POST deposits |
| `WalletControllerTest` | `shouldReturn400OnExceedingLimits` | `POST /v1/wallet/deposits` | 400 | POST deposits |
| `WalletControllerTest` | `shouldReturn202OnValidWithdrawal` | `POST /v1/wallet/withdrawals` | 202 | POST withdrawals |
| `WalletControllerTest` | `shouldReturn400OnInsufficientBalance` | `POST /v1/wallet/withdrawals` | 400 | POST withdrawals |
| `WalletControllerTest` | `shouldReturn200IdempotentOnDepositCompensacion` | `POST /v1/wallet/deposits/{id}/compensar` | 200 (2da llamada también) | POST compensar |
| `WalletControllerTest` | `shouldReturn200OnGetBalance` | `GET /v1/wallet/me/balance` | 200 + `availableBalance`, `pendingBalance` | GET balance |

### Umbrales de cobertura mínima

| Capa | Umbral |
|---|---|
| `domain` | ≥ 90% |
| `application` | ≥ 85% |
| `infrastructure` | ≥ 80% |
| `rest-api` | ≥ 80% |

---

## 9. Criterios de Aceptación

- [ ] Cada elemento de cada capa tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] `mvn test` finaliza en verde.
- [ ] La cobertura por capa cumple los umbrales declarados.
- [ ] El saldo `availableBalance` nunca es negativo tras operaciones concurrentes (invariante ACID).
- [ ] `POST /v1/wallet/deposits` con misma `idempotencyKey` dos veces retorna la misma `transaccionResponse` (idempotencia).
- [ ] La transacción de transferencia es ACID: si el crédito al destinatario falla, el débito al remitente se revierte.
- [ ] Los eventos de dominio se publican vía Outbox (no dual-write): la tabla `outbox` tiene registro antes de la confirmación de Kafka.
- [ ] Los tres endpoints de compensación son idempotentes.
- [ ] El pipeline CI despliega en K3d: `kubectl get pods -n dev | grep wallet-service` muestra `Running`.
- [ ] ArgoCD muestra `wallet-service` en estado `Synced`.
