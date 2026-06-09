# Etapa 3b — Microservicio: wallet-service

---

## 1. Contexto y Responsabilidad

`wallet-service` implementa el **Bounded Context BC-02** de la plataforma PagoFacil. Es el núcleo financiero de la billetera digital: custodia los saldos de los usuarios, garantiza la integridad de las operaciones monetarias y coordina los flujos de compensación dentro de las sagas distribuidas.

**Responsabilidades principales:**

| Responsabilidad | Descripción |
|---|---|
| Creación de billetera | Consume el evento `KYCApproved` publicado por identity-service y crea la billetera con saldo cero |
| Consulta de saldo | Lectura consistente de saldo disponible y reservado por billetera |
| Historial de movimientos | Listado paginado de transacciones con filtros por tipo, estado y rango de fechas |
| Límites transaccionales | Validación y acumulación de límites por período (DAILY/WEEKLY/MONTHLY) antes de autorizar operaciones |
| Cuentas bancarias vinculadas | Gestión del ciclo de vida: registro, verificación y rechazo de cuentas bancarias |
| Operaciones atómicas | Débito, crédito, reserva y liberación de fondos bajo instrucción de integration-service |
| Publicación de eventos | Emite eventos de dominio hacia Kafka a través del patrón Outbox |
| Compensaciones de saga | Ejecuta REVERSE_CREDIT, REVERSE_DEBIT y RELEASE_RESERVATION de forma idempotente |

**Invariante crítica:** `available_balance` **nunca puede ser negativo**. Esta restricción se aplica en la capa de dominio, en la capa de base de datos (CHECK constraint) y en la lógica de aplicación antes de cualquier débito.

**Puerto local:** `8082`

---

## 2. Prerrequisitos

Antes de iniciar el desarrollo de esta etapa deben estar completadas las siguientes etapas:

| Etapa | Documento | Motivo |
|---|---|---|
| Etapa 0 — Infraestructura VPS | DEV-PagoFacil-00-infrastructure.md | K3s, Kafka, PostgreSQL, floci y LRA Coordinator operativos |
| Etapa 0c — Observabilidad | DEV-PagoFacil-0c-observability.md | Métricas, trazas y logs disponibles para pruebas |
| Etapa 1 — Bases de datos | DEV-PagoFacil-01-databases.md | Base de datos `pagofacil_wallet_service` creada con Liquibase |
| Etapa 2 — Scaffolding | DEV-PagoFacil-02-scaffold.md | Proyecto `wallet-service` generado con estructura hexagonal |
| Etapa 2b — CI/CD | DEV-PagoFacil-02b-cicd.md | Pipeline Jenkins + ArgoCD configurado para `wallet-service` |
| Etapa 3a — identity-service | DEV-PagoFacil-03a-identity-service.md | Proveedor del evento `KYCApproved` que dispara la creación de billetera |

**Servicios de infraestructura requeridos:**

| Servicio | Descripción |
|---|---|
| PostgreSQL 16 | Base de datos `pagofacil_wallet_service` con esquema Liquibase aplicado |
| Apache Kafka 3 | Broker KRaft operativo; tópicos `pagofacil.identity.kyc-approved` y `pagofacil.wallet.*` creados |
| floci | Emulador de servicios AWS en `<VPS_IP>:4566` |
| LRA Coordinator | Narayana LRA corriendo en `<VPS_IP>:50000` para coordinar sagas distribuidas |
| Secret `pagofacil/dev/wallet-service` | Credenciales y configuración de ambiente disponibles en floci Secrets Manager |

**Verificación de prerrequisitos:**

```bash
# Verificar base de datos
psql -h <VPS_IP> -U pagofacil_app -d pagofacil_wallet_service -c "\dt"

# Verificar tópicos Kafka
kafka-topics.sh --bootstrap-server <VPS_IP>:9092 --list | grep pagofacil.wallet

# Verificar LRA Coordinator
curl -s http://<VPS_IP>:50000/lra-coordinator | jq .

# Verificar secret en floci
aws --endpoint-url=http://<VPS_IP>:4566 secretsmanager get-secret-value \
    --secret-id pagofacil/dev/wallet-service
```

---

## 3. Ciclo de Desarrollo Incremental en K3s VPS dev

El desarrollo de cada componente sigue el ciclo **Red → Green → Refactor → Deploy** sobre el ambiente K3s del VPS de desarrollo.

```
┌─────────────────────────────────────────────────────────────────────┐
│               CICLO TDD + DEPLOY — wallet-service                   │
└─────────────────────────────────────────────────────────────────────┘

  ┌──────────┐     falla      ┌──────────┐    pasa     ┌───────────┐
  │  RED     │───────────────▶│  GREEN   │────────────▶│ REFACTOR  │
  │ Escribir │                │ Código   │             │ Limpiar   │
  │ prueba   │                │ mínimo   │             │ sin romper│
  │ que falla│                │ que pasa │             │ pruebas   │
  └──────────┘                └──────────┘             └─────┬─────┘
       ▲                                                      │
       │                                                      ▼
       │                                              ┌───────────────┐
       │                                              │  mvn verify   │
       │                                              │  (all tests)  │
       │                                              └───────┬───────┘
       │                                                      │ verde
       │                                                      ▼
       │                                              ┌───────────────┐
       │                                              │ docker build  │
       │                                              │ + push Gitea  │
       │                                              └───────┬───────┘
       │                                                      │
       │                                                      ▼
       │                                              ┌───────────────┐
       │                                              │ ArgoCD sync   │
       │                                              │ K3s deploy    │
       │                                              └───────┬───────┘
       │                                                      │
       │                                                      ▼
       │                                              ┌───────────────┐
       │         nueva funcionalidad                  │ Smoke test    │
       └──────────────────────────────────────────────│ en VPS dev    │
                                                      └───────────────┘
```

> **Nota TDD obligatoria:** Ningún código de producción puede escribirse sin que exista previamente una prueba en estado **Red** (fallando). El orden estricto es: (1) escribir la prueba, (2) confirmar que falla por el motivo correcto, (3) escribir el código mínimo para hacerla pasar, (4) refactorizar manteniendo todas las pruebas en verde. Los tipos reactivos (`Mono`, `Flux`) deben verificarse con `StepVerifier`; **nunca** se permite el uso de `.block()` en las pruebas.

**Módulos internos del proyecto:**

```
wallet-service/
├── domain/           # Entidades, Value Objects, Eventos, Puertos
├── application/      # Casos de uso, DTOs, Servicios de aplicación
├── infrastructure/   # Repositorios R2DBC, Consumidores/Productores Kafka, Security
└── rest-api/         # Controladores WebFlux, Mappers, Manejadores de error
```

---

## 4. Capa de Dominio (`domain`)

Toda la lógica de negocio reside exclusivamente en esta capa. Sin dependencias de frameworks. Desarrollar test-first.

### 4.1 Entidades

#### `Wallet`

Entidad raíz del agregado. Custodia los saldos y controla las transiciones de estado.

**Reglas críticas de negocio:**

| Regla | Descripción | Mecanismo de aplicación |
|---|---|---|
| Saldo no negativo | `available_balance` nunca puede ser negativo tras ninguna operación | Invariante en `debit()`: lanza `InsufficientFundsException` si `amount > available_balance` |
| Validación atómica de débito | Antes de debitar se verifica saldo disponible en la misma transacción reactiva | Verificación en `debit()` antes de modificar el estado |
| Acumulación de límites | La suma de transacciones del período no puede superar `max_amount` del límite configurado | Delegado a `TransactionLimit.validate(sumaPeriodo, montoNuevo)` |
| Transiciones de estado | ACTIVE → SUSPENDED → CLOSED (sin retorno desde CLOSED) | Método `suspend()` y `close()` con guarda de estado previo |
| Reserva de fondos | `reserveFunds(amount)` mueve monto de `available_balance` a `reserved_balance` | Solo válido en estado ACTIVE |
| Liberación de reserva | `releaseFunds(amount)` revierte la reserva; idempotente si `reserved_balance < amount` | Emite `FundsReservationReleasedEvent` |

**Transiciones de estado permitidas:**

```
ACTIVE ──▶ SUSPENDED ──▶ CLOSED
  │                        ▲
  └────────────────────────┘
       (cierre directo)
```

#### `WalletTransaction`

Registra cada movimiento monetario asociado a una billetera.

| Campo | Descripción |
|---|---|
| `idempotency_key` | Clave única por operación; impide el procesamiento duplicado |
| `correlation_id` | Identificador de la saga o flujo de negocio que originó la transacción |
| `transaction_type` | DEPOSIT / TRANSFER_DEBIT / TRANSFER_CREDIT / WITHDRAWAL / REVERSAL |
| `status` | PENDING → CONFIRMED / REVERSED / FAILED (no hay vuelta a PENDING) |
| `reference_tx_id` | Referencia a la transacción original en reversiones |

**Transiciones de estado:**

```
PENDING ──▶ CONFIRMED
        ──▶ REVERSED
        ──▶ FAILED
```

#### `TransactionLimit`

Define el límite máximo acumulado para un tipo de transacción en un período.

**Lógica de validación:** `validate(acumuladoPeriodo, montoNuevo)` lanza `TransactionLimitExceededException` si `acumuladoPeriodo + montoNuevo > max_amount`. El acumulado se calcula consultando la suma de transacciones CONFIRMED del período vigente para el `limit_type` correspondiente.

#### `LinkedBankAccount`

Cuenta bancaria externa vinculada a una billetera.

**Estados:**

```
PENDING_VERIFICATION ──▶ VERIFIED
                     ──▶ REJECTED
```

### 4.2 Value Objects

| Value Object | Campos | Validaciones |
|---|---|---|
| `WalletId` | `UUID id` | No nulo |
| `Money` | `BigDecimal amount`, `String currency` | amount > 0; currency no vacía; escala máxima 4 decimales |
| `IdempotencyKey` | `String value` | No nulo, no vacío, longitud ≤ 128 caracteres |
| `CorrelationId` | `UUID value` | No nulo |
| `TenantId` | `String value` | No nulo, no vacío |

### 4.3 Eventos de Dominio

| Evento | Datos principales | Publicado cuando |
|---|---|---|
| `WalletCreatedEvent` | walletId, userId, tenantId, currency, createdAt | Billetera creada exitosamente |
| `DepositCompletedEvent` | walletId, transactionId, amount, currency, correlationId | Depósito confirmado |
| `TransferCompletedEvent` | walletId, transactionId, amount, currency, direction (DEBIT/CREDIT), correlationId | Transferencia confirmada |
| `WithdrawalCompletedEvent` | walletId, transactionId, amount, currency, correlationId | Retiro confirmado |
| `FundsReservationReleasedEvent` | walletId, transactionId, amount, currency, correlationId | Reserva liberada por compensación |

### 4.4 Puertos (interfaces del dominio)

```java
// Repositorio principal de billeteras
public interface WalletRepository {
    Mono<Wallet> findById(WalletId walletId);
    Mono<Wallet> findByUserAndTenant(UUID userId, String tenantId);
    Mono<Void> save(Wallet wallet);
}

// Repositorio de transacciones
public interface WalletTransactionRepository {
    Mono<WalletTransaction> findByIdempotencyKey(IdempotencyKey key);
    Mono<WalletTransaction> findById(UUID transactionId);
    Flux<WalletTransaction> findByWalletId(WalletId walletId, Pageable pageable);
    Mono<BigDecimal> sumConfirmedByWalletAndTypeAndPeriod(
        WalletId walletId, TransactionType type, LocalDateTime from, LocalDateTime to);
    Mono<Void> save(WalletTransaction transaction);
}

// Repositorio de límites transaccionales
public interface TransactionLimitRepository {
    Flux<TransactionLimit> findByWalletId(WalletId walletId);
    Mono<TransactionLimit> findByWalletAndTypeAndPeriod(
        WalletId walletId, LimitType type, Period period);
    Mono<Void> save(TransactionLimit limit);
}

// Repositorio de cuentas bancarias vinculadas
public interface LinkedBankAccountRepository {
    Flux<LinkedBankAccount> findByWalletId(WalletId walletId);
    Mono<LinkedBankAccount> findById(UUID accountId);
    Mono<Void> save(LinkedBankAccount account);
}

// Repositorio del patrón Outbox
public interface OutboxRepository {
    Mono<Void> save(OutboxMessage message);
    Flux<OutboxMessage> findUnpublished();
    Mono<Void> markAsPublished(UUID messageId);
}
```

---

## 5. Capa de Aplicación (`application`)

Orquesta los casos de uso invocando los puertos del dominio. Sin lógica de negocio propia. Desarrollar test-first.

### 5.1 Casos de Uso

| Caso de Uso | Descripción | Puerto(s) utilizado(s) |
|---|---|---|
| `CreateWalletUseCase` | Crea billetera con saldo cero para un userId+tenantId. Idempotente: si ya existe, retorna la existente | WalletRepository, OutboxRepository |
| `GetWalletBalanceUseCase` | Retorna saldo disponible, reservado, moneda y estado de la billetera | WalletRepository |
| `GetTransactionHistoryUseCase` | Retorna historial paginado de transacciones con filtros opcionales | WalletTransactionRepository |
| `InitiateDepositUseCase` | Valida límites, registra transacción PENDING, llama a integration-service para iniciar saga de depósito | WalletRepository, TransactionLimitRepository, WalletTransactionRepository |
| `InitiateTransferUseCase` | Valida saldo disponible y límites, registra transacción PENDING, llama a integration-service | WalletRepository, TransactionLimitRepository, WalletTransactionRepository |
| `InitiateWithdrawalUseCase` | Valida saldo disponible y límites, reserva fondos, registra transacción PENDING, llama a integration-service | WalletRepository, TransactionLimitRepository, WalletTransactionRepository |
| `GetTransactionStatusUseCase` | Retorna el estado actual de una transacción por su ID | WalletTransactionRepository |
| `CompensateWalletOperationUseCase` | Ejecuta la acción de compensación (REVERSE_CREDIT, REVERSE_DEBIT, RELEASE_RESERVATION) de forma idempotente | WalletRepository, WalletTransactionRepository, OutboxRepository |
| `AddLinkedBankAccountUseCase` | Registra una nueva cuenta bancaria en estado PENDING_VERIFICATION | LinkedBankAccountRepository |
| `ProcessKycApprovedEventUseCase` | Entrada desde el consumidor Kafka; invoca CreateWalletUseCase con idempotencia via processed_message | WalletRepository, OutboxRepository |

### 5.2 DTOs

**Request DTOs:**

```java
// Depósito
public record DepositRequest(
    UUID walletId,
    BigDecimal amount,
    String currency,
    String idempotencyKey,
    UUID correlationId
) {}

// Transferencia
public record TransferRequest(
    UUID sourceWalletId,
    UUID destinationWalletId,
    BigDecimal amount,
    String currency,
    String idempotencyKey,
    UUID correlationId
) {}

// Retiro
public record WithdrawalRequest(
    UUID walletId,
    BigDecimal amount,
    String currency,
    String linkedBankAccountId,
    String idempotencyKey,
    UUID correlationId
) {}

// Compensación (invocado por integration-service)
public record CompensationRequest(
    UUID walletId,
    UUID transactionId,
    CompensationAction action,  // REVERSE_CREDIT | REVERSE_DEBIT | RELEASE_RESERVATION
    UUID correlationId,
    String idempotencyKey
) {}
```

**Response DTOs:**

```java
// Saldo de billetera
public record WalletResponse(
    UUID walletId,
    UUID userId,
    String tenantId,
    BigDecimal availableBalance,
    BigDecimal reservedBalance,
    String currency,
    String status
) {}

// Transacción individual
public record TransactionResponse(
    UUID transactionId,
    UUID walletId,
    String transactionType,
    BigDecimal amount,
    String currency,
    String status,
    String idempotencyKey,
    UUID correlationId,
    UUID referenceTransactionId,
    Instant createdAt
) {}

// Historial paginado
public record TransactionPageResponse(
    List<TransactionResponse> content,
    int page,
    int size,
    long totalElements,
    int totalPages
) {}
```

---

## 6. Capa de Infraestructura (`infrastructure`)

Implementaciones concretas de los puertos. Contiene todo el código dependiente de frameworks externos. Desarrollar test-first con Testcontainers.

### 6.1 Repositorios R2DBC

#### `WalletR2dbcRepository`

Implementa `WalletRepository` usando `DatabaseClient` de Spring R2DBC.

**Consideraciones críticas:**
- Las operaciones de débito/crédito deben ejecutarse dentro de transacciones reactivas (`@Transactional` con `TransactionalOperator`).
- El `findByUserAndTenant` utiliza la clave única `UNIQUE(user_id, tenant_id)` para garantizar una sola billetera por usuario por tenant.
- El campo `available_balance` tiene CHECK constraint en BD; ante violación, R2DBC lanza `R2dbcDataIntegrityViolationException` que debe mapearse a `InsufficientFundsException`.

#### `WalletTransactionR2dbcRepository`

Implementa `WalletTransactionRepository`.

**Idempotencia por `idempotency_key`:**
- El INSERT utiliza `ON CONFLICT (idempotency_key) DO NOTHING`.
- Tras el intento de INSERT, se consulta la fila existente para retornar el estado actual, independientemente de si fue insertada o ya existía.

#### `TransactionLimitR2dbcRepository`

Implementa `TransactionLimitRepository`. Incluye la consulta de suma acumulada por período:

```sql
SELECT COALESCE(SUM(amount), 0)
FROM wallet_transactions
WHERE wallet_id = :walletId
  AND transaction_type = :type
  AND status = 'CONFIRMED'
  AND created_at BETWEEN :from AND :to
```

### 6.2 Consumidor Kafka: `KycApprovedEventConsumer`

| Atributo | Valor |
|---|---|
| Tópico consumido | `pagofacil.identity.kyc-approved` |
| Consumer group | `wallet-service-kyc-consumer` |
| Deserialización | JSON → `KycApprovedEvent` (userId, tenantId, approvedAt) |
| Idempotencia | Verifica existencia en tabla `processed_message` antes de procesar; si ya existe, descarta silenciosamente |
| Error handling | Reintento con backoff exponencial (3 intentos); tras agotar reintentos, publica en DLQ `pagofacil.wallet.dlq` |
| Acción | Invoca `ProcessKycApprovedEventUseCase` dentro de transacción reactiva |

**Flujo de procesamiento:**

```
KycApprovedEvent recibido
        │
        ▼
¿processed_message existe?
        │ sí                    no
        ▼                       ▼
   Descartar            ProcessKycApprovedUseCase
                                │
                                ▼
                        CreateWalletUseCase
                                │
                                ▼
                        Guardar processed_message
                                │
                                ▼
                        Guardar WalletCreatedEvent en outbox
```

### 6.3 Productor Kafka via Outbox Relay

El relay de outbox es un scheduled job reactivo (`@Scheduled` con `TaskScheduler` reactivo) que:

1. Consulta `outbox` WHERE `published = false` ORDER BY `created_at` ASC LIMIT 50.
2. Por cada mensaje, publica en el tópico Kafka correspondiente.
3. Tras confirmación del broker (ACK), actualiza `published = true` y `published_at`.
4. Operación idempotente: el `idempotency_key` en Kafka previene duplicados en consumidores.

**Tópicos de publicación:**

| Evento | Tópico |
|---|---|
| `WalletCreatedEvent` | `pagofacil.wallet.wallet-created` |
| `DepositCompletedEvent` | `pagofacil.wallet.deposit-completed` |
| `TransferCompletedEvent` | `pagofacil.wallet.transfer-completed` |
| `WithdrawalCompletedEvent` | `pagofacil.wallet.withdrawal-completed` |
| `FundsReservationReleasedEvent` | `pagofacil.wallet.funds-reservation-released` |

### 6.4 Spring Security

| Configuración | Detalle |
|---|---|
| Mecanismo | JWT Bearer Token (validación de firma RS256) |
| Claims extraídos | `sub` → userId, `role` → rol de autorización, `tenant_id` → identificador del tenant |
| Propagación | Los claims se inyectan en el contexto reactivo (`ReactiveSecurityContextHolder`) |
| Autorización de endpoints | `/wallets/{walletId}/**` requiere que `sub` del token coincida con el `user_id` de la billetera, excepto endpoints de compensación que requieren rol `INTERNAL_SERVICE` |

---

## 7. API REST (`rest-api`)

Desarrollar test-first con `WebTestClient`. Todos los endpoints requieren JWT Bearer válido excepto donde se indique.

### 7.1 Tabla de Endpoints

| Método | Ruta | Request | Response exitoso | Códigos de error | Descripción |
|---|---|---|---|---|---|
| GET | `/wallets/{walletId}` | — | `200 WalletResponse` | `403`, `404` | Consulta saldo y estado de la billetera |
| GET | `/wallets/{walletId}/transactions` | Query: `page`, `size`, `type`, `status`, `from`, `to` | `200 TransactionPageResponse` | `403`, `404` | Historial paginado de transacciones |
| GET | `/wallets/{walletId}/linked-bank-accounts` | — | `200 List<LinkedBankAccountResponse>` | `403`, `404` | Cuentas bancarias vinculadas |
| POST | `/transactions/deposits` | `DepositRequest` + Header `Idempotency-Key` | `202 TransactionResponse` | `409`, `422` | Inicia depósito; `409` si la operación con ese key ya está en curso |
| POST | `/transactions/transfers` | `TransferRequest` + Header `Idempotency-Key` | `202 TransactionResponse` | `409`, `422` | Inicia transferencia entre billeteras |
| POST | `/transactions/withdrawals` | `WithdrawalRequest` + Header `Idempotency-Key` | `202 TransactionResponse` | `409`, `422` | Inicia retiro a cuenta bancaria vinculada |
| GET | `/transactions/{transactionId}` | — | `200 TransactionResponse` | `403`, `404` | Consulta estado de una transacción |
| POST | `/wallets/{walletId}/compensar` | `CompensationRequest` | `200 CompensationResponse` | `404`, `422` | Ejecuta compensación de saga (idempotente); invocado por integration-service con rol `INTERNAL_SERVICE` |

### 7.2 Semántica de Códigos HTTP

| Código | Uso en wallet-service |
|---|---|
| `200 OK` | Consultas exitosas y compensaciones aplicadas (o ya aplicadas, por idempotencia) |
| `202 Accepted` | Operación financiera iniciada; el resultado final se comunica via evento Kafka |
| `403 Forbidden` | El token no autoriza al usuario a acceder a la billetera solicitada |
| `404 Not Found` | Billetera o transacción no encontrada |
| `409 Conflict` | Operación con ese `Idempotency-Key` ya está en curso (estado PENDING) |
| `422 Unprocessable Entity` | Saldo insuficiente, límite transaccional excedido, o datos de negocio inválidos |

### 7.3 Manejo de Idempotencia en Operaciones Financieras

El header `Idempotency-Key` es **obligatorio** para POST a `/transactions/*`. El comportamiento es:

1. Si no existe transacción con ese key → crear y retornar `202`.
2. Si existe transacción PENDING con ese key → retornar `409` con el estado actual.
3. Si existe transacción CONFIRMED/REVERSED/FAILED con ese key → retornar `200` con el resultado previo.

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> **Regla fundamental:** La prueba debe estar en estado **Red** (fallando) **antes** de escribir cualquier línea de código de producción. Los tipos reactivos se verifican exclusivamente con `StepVerifier`. El uso de `.block()` en pruebas está **prohibido**.

### 8.1 Capa de Dominio

| Clase de prueba | Método de prueba | Comportamiento verificado | Componente bajo prueba |
|---|---|---|---|
| `WalletTest` | `shouldNotAllowNegativeBalance` | Tras `debit()` con monto igual al saldo disponible, `available_balance` queda en 0 (no negativo) | `Wallet.debit()` |
| `WalletTest` | `shouldRejectDebitWhenInsufficientFunds` | `debit()` con monto superior al saldo disponible lanza `InsufficientFundsException` | `Wallet.debit()` |
| `WalletTest` | `shouldAccumulateTransactionLimitCorrectly` | `TransactionLimit.validate(acumulado, nuevo)` lanza `TransactionLimitExceededException` cuando `acumulado + nuevo > max_amount` | `TransactionLimit.validate()` |
| `WalletTest` | `shouldCreateWalletWithZeroBalance` | Una billetera recién creada tiene `available_balance = 0` y `reserved_balance = 0` | Constructor de `Wallet` |
| `WalletTest` | `shouldReserveFundsAndReduceAvailableBalance` | `reserveFunds(amount)` reduce `available_balance` e incrementa `reserved_balance` en el mismo monto | `Wallet.reserveFunds()` |
| `WalletTest` | `shouldReleaseFundsAndRestoreAvailableBalance` | `releaseFunds(amount)` revierte la reserva correctamente; operación idempotente si ya fue liberada | `Wallet.releaseFunds()` |
| `WalletTransactionTest` | `shouldPreventDuplicateProcessingByIdempotencyKey` | Dos transacciones con la misma `IdempotencyKey` son inválidas en el mismo contexto | `WalletTransaction` constructor |
| `MoneyTest` | `shouldRejectNegativeAmount` | `Money` con `amount <= 0` lanza `IllegalArgumentException` | `Money` constructor |

### 8.2 Capa de Aplicación

| Clase de prueba | Método de prueba | Criterio de aceptación verificado | Dependencias mockeadas |
|---|---|---|---|
| `InitiateDepositUseCaseTest` | `shouldInitiateDeposit_whenValidAmountAndLimits` | Happy path: transacción PENDING creada, integration-service notificado | `WalletRepository`, `TransactionLimitRepository`, `WalletTransactionRepository` |
| `InitiateDepositUseCaseTest` | `shouldRejectDeposit_whenAmountExceedsLimit` | AC-003-E1: monto supera límite configurado → `TransactionLimitExceededException` | `WalletRepository` (mock) |
| `InitiateDepositUseCaseTest` | `shouldReturnExistingTransaction_whenSameIdempotencyKey` | Idempotencia: segunda llamada con mismo key retorna transacción existente sin duplicar | `WalletTransactionRepository` (mock) |
| `InitiateTransferUseCaseTest` | `shouldRejectTransfer_whenInsufficientBalance` | AC-004-E1: saldo disponible insuficiente → `InsufficientFundsException` | `WalletRepository` (mock) |
| `InitiateTransferUseCaseTest` | `shouldInitiateTransfer_whenBalanceAndLimitsOk` | Happy path transferencia | `WalletRepository`, `TransactionLimitRepository`, `WalletTransactionRepository` |
| `CompensateWalletOperationUseCaseTest` | `shouldReverseCredit_whenCompensationRequested` | REVERSE_CREDIT: crédito previo es revertido, evento `FundsReservationReleasedEvent` emitido | `WalletTransactionRepository` (mock) |
| `CompensateWalletOperationUseCaseTest` | `shouldBeIdempotent_whenCompensationAppliedTwice` | Segunda aplicación de compensación retorna mismo resultado sin modificar estado | `WalletRepository`, `WalletTransactionRepository` (mocks) |
| `CreateWalletUseCaseTest` | `shouldCreateWallet_whenKycApproved` | Billetera creada con saldo cero; `WalletCreatedEvent` en outbox | `WalletRepository` (mock) |
| `CreateWalletUseCaseTest` | `shouldBeIdempotent_whenWalletAlreadyExists` | Si billetera ya existe para userId+tenantId, retorna existente sin crear duplicado | `WalletRepository` (mock) |

### 8.3 Capa de Infraestructura

Usar `@Testcontainers` con imágenes `postgres:16-alpine` y `confluentinc/cp-kafka:7.5`.

| Clase de prueba | Método de prueba | Comportamiento verificado | Infraestructura de prueba |
|---|---|---|---|
| `WalletR2dbcRepositoryTest` | `shouldSaveWalletAndQueryByUserAndTenant` | Guardar billetera y recuperarla por `(userId, tenantId)` retorna el registro correcto | Testcontainers PostgreSQL |
| `WalletR2dbcRepositoryTest` | `shouldEnforceNonNegativeBalanceConstraint` | CHECK constraint de BD rechaza UPDATE con `available_balance < 0` | Testcontainers PostgreSQL |
| `WalletTransactionIdempotencyTest` | `shouldNotDuplicateTransaction_whenSameIdempotencyKey` | INSERT con mismo `idempotency_key` no crea duplicado; retorna fila existente | Testcontainers PostgreSQL |
| `TransactionLimitR2dbcRepositoryTest` | `shouldCalculateAccumulatedAmountForPeriod` | Suma de transacciones CONFIRMED en el período retorna valor correcto | Testcontainers PostgreSQL |
| `KycApprovedEventConsumerTest` | `shouldCreateWalletOnKycApprovedEvent` | Consumir evento `KYCApproved` dispara creación de billetera y registro en `processed_message` | Testcontainers Kafka + PostgreSQL |
| `KycApprovedEventConsumerTest` | `shouldBeIdempotent_whenSameEventConsumedTwice` | Consumir el mismo evento dos veces no crea dos billeteras | Testcontainers Kafka + PostgreSQL |
| `OutboxRelayTest` | `shouldPublishOutboxMessagesToKafka` | Mensajes no publicados en outbox son enviados a Kafka y marcados como publicados | Testcontainers Kafka + PostgreSQL |

### 8.4 Capa REST

Usar `WebTestClient` con `@SpringBootTest(webEnvironment = RANDOM_PORT)` y mocks de casos de uso.

| Clase de prueba | Método de prueba | Comportamiento verificado | Endpoint |
|---|---|---|---|
| `WalletControllerTest` | `shouldReturn200WithBalance_whenWalletExists` | GET con JWT válido y billetera existente retorna `200` con saldo correcto | `GET /wallets/{walletId}` |
| `WalletControllerTest` | `shouldReturn403_whenUserAccessesOtherWallet` | GET con JWT de usuario A intentando acceder a billetera de usuario B retorna `403` | `GET /wallets/{walletId}` |
| `WalletControllerTest` | `shouldReturn404_whenWalletNotFound` | GET de billetera inexistente retorna `404` | `GET /wallets/{walletId}` |
| `TransactionControllerTest` | `shouldReturn202_whenDepositInitiated` | POST con datos válidos e `Idempotency-Key` retorna `202` | `POST /transactions/deposits` |
| `TransactionControllerTest` | `shouldReturn422_whenAmountExceedsLimit` | POST con monto que supera límite retorna `422` con mensaje descriptivo | `POST /transactions/deposits` |
| `TransactionControllerTest` | `shouldReturn409_whenSameIdempotencyKeyInFlight` | POST con `Idempotency-Key` de operación PENDING retorna `409` | `POST /transactions/deposits` |
| `WalletControllerTest` | `shouldReturn200_whenCompensationIsIdempotent` | POST de compensación aplicado dos veces retorna `200` en ambas llamadas con mismo resultado | `POST /wallets/{walletId}/compensar` |
| `TransactionControllerTest` | `shouldReturnPaginatedTransactions_withFilters` | GET con parámetros de paginación y filtros retorna lista correctamente paginada | `GET /wallets/{walletId}/transactions` |

### 8.5 Umbrales de Cobertura de Código

| Capa | Umbral mínimo | Herramienta |
|---|---|---|
| `domain` | ≥ 90% | JaCoCo |
| `application` | ≥ 85% | JaCoCo |
| `infrastructure` | ≥ 75% | JaCoCo |
| `rest-api` | ≥ 80% | JaCoCo |

Configurar en `pom.xml` con el plugin `jacoco-maven-plugin` y `<rule><limit><minimum>` para que el build falle si no se alcanzan los umbrales.

---

## 9. Criterios de Aceptación

### 9.1 Criterios TDD

- [ ] Cada clase de producción tiene al menos una prueba escrita **antes** que el código de producción
- [ ] Ninguna prueba utiliza `.block()` en tipos reactivos
- [ ] Todos los tipos reactivos (`Mono`, `Flux`) se verifican con `StepVerifier`
- [ ] El ciclo Red-Green-Refactor es verificable en el historial de commits (commit de prueba fallida, commit de código, commit de refactor)
- [ ] `mvn test` finaliza en verde sin pruebas ignoradas (`@Disabled`)
- [ ] Los umbrales de cobertura JaCoCo por capa son satisfechos; el build falla si no se alcanzan
- [ ] Las pruebas de infraestructura utilizan Testcontainers (no mocks de BD ni Kafka en pruebas de integración)

### 9.2 Criterios Funcionales

- [ ] **Saldo no negativo:** ninguna operación de débito puede resultar en `available_balance < 0`; el intento es rechazado con `InsufficientFundsException` antes de persistir
- [ ] **Idempotencia de transacciones:** dos solicitudes con el mismo `Idempotency-Key` no crean dos registros en `wallet_transactions`; la segunda retorna el estado de la primera
- [ ] **Creación por KYC:** al consumir `KYCApproved`, la billetera es creada con `available_balance = 0`, `reserved_balance = 0` y estado `ACTIVE`
- [ ] **Idempotencia del consumer Kafka:** si el mismo evento `KYCApproved` es consumido dos veces, se crea una sola billetera; el procesamiento duplicado es detectado via tabla `processed_message`
- [ ] **Compensación REVERSE_CREDIT idempotente:** aplicar REVERSE_CREDIT dos veces con el mismo `idempotency_key` produce el mismo resultado sin modificar el saldo dos veces
- [ ] **Compensación REVERSE_DEBIT idempotente:** aplicar REVERSE_DEBIT dos veces con el mismo `idempotency_key` produce el mismo resultado
- [ ] **Compensación RELEASE_RESERVATION idempotente:** aplicar RELEASE_RESERVATION dos veces con el mismo `idempotency_key` no incrementa `available_balance` dos veces
- [ ] **Límites transaccionales:** una operación que haría superar el límite acumulado del período es rechazada con `422 Unprocessable Entity`
- [ ] **Operaciones atómicas:** débito + registro de transacción son atómicos; si falla el registro, el saldo no es modificado
- [ ] **Autorización:** un usuario no puede consultar ni operar sobre la billetera de otro usuario (retorna `403`)
- [ ] **Publicación via Outbox:** todos los eventos de dominio son publicados en Kafka exclusivamente a través de la tabla `outbox`; no hay llamadas directas al productor Kafka desde los casos de uso
- [ ] **Saga DEPOSIT paso 3:** `CreditWallet` acredita el monto en `available_balance` y publica `DepositCompletedEvent`
- [ ] **Saga TRANSFER paso 3:** `DebitWallet` debita el monto de la billetera origen
- [ ] **Saga TRANSFER paso 4:** `CreditWallet` acredita el monto en la billetera destino y publica `TransferCompletedEvent`
- [ ] **Saga WITHDRAWAL paso 2:** `ReserveFunds` mueve el monto de `available_balance` a `reserved_balance`
- [ ] **Saga WITHDRAWAL paso 6:** `ConfirmWithdrawal` reduce `reserved_balance` y publica `WithdrawalCompletedEvent`
- [ ] **Health check:** el endpoint `/actuator/health` retorna `200 UP` con el servicio desplegado en K3s
- [ ] **Métricas:** el endpoint `/actuator/prometheus` expone métricas de transacciones por tipo y estado
