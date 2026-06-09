# Etapa 3e — Microservicio: integration-service

---

## 1. Contexto y Responsabilidad

`integration-service` es el **orquestador de sagas distribuidas** y la **Anti-Corruption Layer (ACL) exclusiva** para todos los sistemas externos de PagoFacil. Ningún otro microservicio de la plataforma se comunica directamente con sistemas externos; toda integración pasa por este servicio.

**Bounded Context:** BC-05 Integration  
**Puerto local:** 8085  
**Base de datos:** PostgreSQL `pagofacil_integration_service`  
**Mensajería:** Kafka producer + consumer (`integration.events`, `saga.*`)

### Responsabilidades principales

- Orquestación de sagas distribuidas (depósito, transferencia, retiro) mediante **Apache Camel 4 Saga EIP + Narayana LRA**.
- Traducción de modelos externos al lenguaje ubicuo de PagoFacil (ACL por sistema externo).
- Gobierno centralizado de credenciales de sistemas externos vía **AWS Secrets Manager** (floci `<VPS_IP>:4566`).
- Recepción y validación de webhooks entrantes con **HMAC-SHA256** y **OAuth 2.0 client credentials**.
- Conciliación periódica con entidades financieras (`reconciliation-route`).
- Retransmisión de eventos de saga hacia Kafka mediante patrón Outbox.

### Tabla de dependencias

| Dependencia | Tipo | Dirección | Protocolo | Propósito |
|---|---|---|---|---|
| identity-service (BC-01) | Participante saga | Saliente REST | HTTP | Validar KYC activo (Transferencia paso 1) |
| wallet-service (BC-02) | Participante saga | Saliente REST + LRA | HTTP | DebitWallet, CreditWallet, ReserveFunds, compensaciones |
| fraud-compliance-service (BC-03) | Participante saga | Saliente REST + LRA | HTTP | EvaluateRisk, compensaciones |
| Proveedor KYC | Sistema externo | Saliente + webhook entrante | HTTPS | Iniciación KYC, callback webhook |
| Proveedor AML | Sistema externo | Saliente | HTTPS + API Key | Consulta listas AML |
| Entidades Financieras | Sistema externo | Saliente + webhook entrante | HTTPS | Instrucción depósito/retiro, confirmación |
| Pasarelas de Pago | Sistema externo | Saliente + webhook entrante | HTTPS + HMAC-SHA256 | Notificación de pago, confirmación |
| Proveedor SMS/Email | Sistema externo | Saliente | HTTPS | Entrega de notificaciones (delegado) |
| Kafka | Mensajería | Saliente (Outbox) | TCP | Publicación DepositCompleted, TransferCompleted, WithdrawalCompleted |
| LRA Coordinator | Infraestructura | Saliente | HTTP | Gestión del ciclo de vida LRA |

---

## 2. Prerrequisitos

### Etapas completas requeridas

- [ ] **Etapa 0** — Infraestructura VPS (K3s, PostgreSQL, Kafka, floci).
- [ ] **Etapa 0c** — Observabilidad (Prometheus, Loki, Tempo).
- [ ] **Etapa 1** — Base de datos `pagofacil_integration_service` creada con Liquibase (tablas `saga_instance`, `saga_step_log`, `external_integration_events`, `reconciliation_records`, `outbox`, `processed_message`).
- [ ] **Etapa 2** — Scaffold de `integration-service` generado con `integration_service_scaffold.py` (no `maven_hexagonal_scaffold.py`).
- [ ] **Etapa 2b** — Pipeline CI/CD Jenkins + ArgoCD operativo para `integration-service`.
- [ ] **Etapa 3a** — `identity-service` completo y exponiendo `GET /identities/{userId}/kyc-status` (consultado en Transferencia paso 1).
- [ ] **Etapa 3b** — `wallet-service` completo y exponiendo endpoints de compensación: `POST /wallets/{walletId}/compensar` (REVERSE_DEBIT, REVERSE_CREDIT, RELEASE_RESERVATION).
- [ ] **Etapa 3d** — `fraud-compliance-service` completo y exponiendo `POST /compliance/alerts/{alertId}/compensar`.

### Infraestructura de soporte

- [ ] **LRA Coordinator** activo y accesible en `http://<VPS_IP>:50000/lra-coordinator`.
- [ ] **WireMock** activo en `http://<VPS_IP>:9999` con stubs configurados para: Proveedor KYC, Proveedor AML, Entidades Financieras, Pasarelas de Pago, Proveedor SMS/Email.
- [ ] Secret `pagofacil/dev/integration-service` disponible en floci con las credenciales de los sistemas externos.

### Spike técnico obligatorio — RT-006

> **Antes de comenzar la implementación de sagas**, validar la compatibilidad de:
> `Narayana LRA 2.x` + `Apache Camel 4` + `Spring Boot 3.3 WebFlux` (contexto reactivo Project Reactor).
>
> El riesgo técnico RT-006 del diseño identifica posibles conflictos entre el modelo de hilos del LRA coordinator client y el scheduler reactivo. El spike debe:
> - Implementar una saga mínima de 2 pasos con LRA + Camel Saga EIP en WebFlux.
> - Verificar que la compensación se invoca correctamente en contexto reactivo.
> - Confirmar que `@LRA` y `@Compensate` de Narayana funcionan con rutas Camel reactivas.
> - Documentar la configuración resultante antes de implementar las tres sagas principales.

### Secret requerido

```bash
# Crear secret en floci
awslocal secretsmanager create-secret \
  --name pagofacil/dev/integration-service \
  --secret-string '{
    "kyc.api.key": "<KYC_API_KEY>",
    "kyc.base.url": "http://<VPS_IP>:9999/kyc",
    "aml.api.key": "<AML_API_KEY>",
    "aml.base.url": "http://<VPS_IP>:9999/aml",
    "financial.entity.base.url": "http://<VPS_IP>:9999/financial",
    "payment.gateway.base.url": "http://<VPS_IP>:9999/payment",
    "payment.gateway.hmac.secret": "<HMAC_SECRET>",
    "notification.api.key": "<NOTIF_API_KEY>",
    "notification.base.url": "http://<VPS_IP>:9999/notification"
  }'
```

---

## 3. Ciclo de Desarrollo Incremental en K3s VPS dev

**TDD obligatorio — la prueba debe FALLAR (Red) antes de escribir el código de producción (Green).**

```
┌─────────────────────────────────────────────────────────────────┐
│  CICLO RED-GREEN-REFACTOR + DEPLOY EN K3s                       │
│                                                                 │
│  1. RED    Escribir test que falla                               │
│            └─ mvn test -pl integration-service                  │
│               → BUILD FAILURE esperado                          │
│                                                                 │
│  2. GREEN  Implementar código mínimo que hace pasar el test      │
│            └─ mvn test -pl integration-service                  │
│               → BUILD SUCCESS                                   │
│                                                                 │
│  3. REFACTOR  Limpiar sin romper tests                           │
│               └─ mvn test -pl integration-service               │
│                  → BUILD SUCCESS                                │
│                                                                 │
│  4. SONAR  Análisis de calidad                                   │
│            └─ mvn sonar:sonar -pl integration-service           │
│               Quality Gate: PASSED                              │
│                                                                 │
│  5. BUILD  Construir imagen Docker multi-stage                   │
│            └─ docker build -t <VPS_IP>:3000/pagofacil/          │
│               integration-service:dev .                         │
│                                                                 │
│  6. PUSH   Publicar en Gitea Registry                            │
│            └─ docker push <VPS_IP>:3000/pagofacil/              │
│               integration-service:dev                           │
│                                                                 │
│  7. DEPLOY ArgoCD sincroniza el Helm chart                       │
│            └─ kubectl rollout status deployment/                │
│               integration-service -n pagofacil-dev              │
│                                                                 │
│  8. VERIFY Health check + smoke test                             │
│            └─ curl http://<VPS_IP>:8085/actuator/health         │
│               → {"status":"UP"}                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Orden de implementación recomendado

```
Dominio → Aplicación → Infraestructura (Camel) → REST API
   │           │               │                     │
   │       Spike LRA       WireMock stubs         Webhook
   │       antes de        desde Etapa 2          HMAC-SHA256
   │       sagas
   ▼
Iterar por flujo: Deposit → Transfer → Withdrawal
```

---

## 4. Capa de Dominio (`domain`)

Implementar con ciclo Red-Green-Refactor. **Los tests se escriben antes que las clases.**

### 4.1 Puertos (interfaces reactivas)

Todos los puertos son interfaces puras del dominio. **No deben importar ningún tipo de Camel, Narayana LRA ni Spring.**

```java
// KycProviderGateway.java
public interface KycProviderGateway {
    Mono<KycResult> initiateKyc(KycRequest request);
    Mono<KycResult> getKycResult(String kycReferenceId);
}

// AmlProviderGateway.java
public interface AmlProviderGateway {
    Mono<AmlResult> evaluate(AmlEvaluationRequest request);
}

// FinancialEntityGateway.java
public interface FinancialEntityGateway {
    Mono<FinancialConfirmation> instructDeposit(DepositInstruction instruction);
    Mono<FinancialConfirmation> instructWithdrawal(WithdrawalInstruction instruction);
    Mono<Void> requestReversal(String externalReference);
}

// PaymentGatewayPort.java
public interface PaymentGatewayPort {
    Mono<Void> validateHmacSignature(String payload, String signature, String secret);
    Mono<PaymentNotification> parseNotification(String rawPayload);
}

// NotificationDeliveryGateway.java
public interface NotificationDeliveryGateway {
    Mono<Void> sendSms(SmsRequest request);
    Mono<Void> sendEmail(EmailRequest request);
}

// SagaCoordinatorPort.java
public interface SagaCoordinatorPort {
    Mono<SagaId> startSaga(SagaType type, String tenantId, String payload);
    Mono<Void> completeSaga(SagaId sagaId);
    Mono<Void> compensateSaga(SagaId sagaId);
}
```

### 4.2 Entidades de dominio

**`SagaInstance`** — gestiona el ciclo de vida de estado de una saga:

| Estado | Transiciones válidas |
|---|---|
| `INITIATED` | → `IN_PROGRESS` |
| `IN_PROGRESS` | → `COMPLETED`, → `COMPENSATING` |
| `COMPENSATING` | → `FAILED` (compensación aplicada) |
| `COMPLETED` | (estado terminal) |
| `FAILED` | (estado terminal) |

```java
// Columnas: saga_id, tenant_id, saga_type (DEPOSIT|TRANSFER|WITHDRAWAL),
// state, current_step, payload (JSONB), created_at, updated_at
public class SagaInstance {
    public SagaInstance start();       // INITIATED → IN_PROGRESS
    public SagaInstance advance(int step);
    public SagaInstance complete();    // IN_PROGRESS → COMPLETED
    public SagaInstance beginCompensation(); // IN_PROGRESS → COMPENSATING
    public SagaInstance fail();        // COMPENSATING → FAILED
}
```

**`SagaStepLog`** — registro inmutable de cada paso ejecutado:

```
Columnas: id, saga_id, step_name, status (PENDING|COMPLETED|COMPENSATED|FAILED),
          compensation_payload (JSONB), executed_at
```

**`ExternalIntegrationEvent`** — garantiza idempotencia en eventos externos:

```
Columnas: id, saga_id, tenant_id, source_system, event_type, payload (JSONB),
          idempotency_key, processed_at
UNIQUE(idempotency_key, source_system)
```

### 4.3 Value Objects

| Value Object | Invariante |
|---|---|
| `SagaId` | UUID no nulo, inmutable |
| `CorrelationId` | UUID no nulo, trazabilidad entre servicios |
| `IdempotencyKey` | String no vacío, usado como clave de deduplicación |

### 4.4 Eventos de dominio

| Evento | Publicado en | Descripción |
|---|---|---|
| `DepositCompletedEvent` | `integration.events` | Depósito acreditado exitosamente |
| `DepositCompensatedEvent` | `integration.events` | Depósito revertido por fallo |
| `TransferCompletedEvent` | `integration.events` | Transferencia completada |
| `TransferCompensatedEvent` | `integration.events` | Transferencia revertida |
| `WithdrawalCompletedEvent` | `integration.events` | Retiro confirmado |
| `WithdrawalRevertedEvent` | `integration.events` | Retiro revertido, reserva liberada |

---

## 5. Capa de Aplicación (`application`)

### 5.1 Casos de uso — orquestadores de saga

Un caso de uso por flujo de saga. Cada uno recibe el request, invoca los puertos en el orden de pasos y delega la compensación al `SagaCoordinatorPort`.

```java
// DepositSagaOrchestratorUseCase.java
// Pasos: 1-Validar idempotencia → 2-EvaluarAML → 3-CreditarFondos
//        → 4-ConfirmarEntidad → 5-PublicarEvento
public Mono<SagaId> orchestrate(DepositSagaStartRequest request);

// TransferSagaOrchestratorUseCase.java
// Pasos: 1-ValidarKYC → 2-EvaluarRiesgo → 3-DebitarEmisor
//        → 4-AcreditarReceptor → 5-PublicarEvento
public Mono<SagaId> orchestrate(TransferSagaStartRequest request);

// WithdrawalSagaOrchestratorUseCase.java
// Pasos: 1-ValidarSaldo → 2-ReservarFondos → 3-EvaluarAML
//        → 4-InstruirRetiro → 5-RecibirConfirmacion → 6-ConfirmarDebito → 7-PublicarEvento
public Mono<SagaId> orchestrate(WithdrawalSagaStartRequest request);
```

### 5.2 Casos de uso auxiliares

| Caso de uso | Método principal | Descripción |
|---|---|---|
| `InitiateKycUseCase` | `Mono<KycResult> initiate(KycRequest)` | Inicia verificación KYC vía ACL |
| `EvaluateAmlUseCase` | `Mono<AmlResult> evaluate(AmlEvaluationRequest)` | Consulta listas AML vía ACL |
| `ValidateWebhookUseCase` | `Mono<WebhookPayload> validate(String payload, String sig, String source)` | HMAC-SHA256 + OAuth validation |
| `GetSagaStatusUseCase` | `Mono<SagaStatusResponse> getStatus(SagaId)` | Consulta estado actual de una saga |
| `CompensateSagaUseCase` | `Mono<Void> compensate(SagaId)` | Dispara compensación manual (endpoint interno) |
| `RunReconciliationUseCase` | `Mono<ReconciliationReport> run(String tenantId, LocalDate date)` | Conciliación periódica con entidades |

### 5.3 DTOs

| DTO | Dirección | Campos clave |
|---|---|---|
| `SagaStartRequest` | Entrada | `tenantId`, `sagaType`, `payload`, `idempotencyKey` |
| `SagaStatusResponse` | Salida | `sagaId`, `state`, `currentStep`, `createdAt`, `updatedAt` |
| `WebhookPayload` | Entrada | `sourceSystem`, `eventType`, `rawPayload`, `signature` |
| `KycCallbackPayload` | Entrada | `kycReferenceId`, `status`, `rejectionReason` |
| `CompensationRequest` | Entrada | `sagaId`, `reason` |

---

## 6. Capa de Infraestructura (`infrastructure`)

### 6.1 Adaptadores Camel — implementan los puertos Gateway

Cada adaptador implementa el puerto correspondiente del dominio. La ruta Camel encapsula la lógica de integración, traducción de modelos (ACL) y resiliencia.

#### `KycProviderCamelAdapter` — ruta `kyc-route`

```
PaymentGatewayPort → from("direct:kyc-initiate")
  → removeHeaders("*")              // limpieza headers internos
  → process(KycRequestTranslator)   // traducción dominio → modelo KYC externo
  → circuitBreaker()                // Resilience4j: umbral 50%, ventana 10 llamadas
      .resilience4jConfiguration()
        .timeoutEnabled(true)
        .timeoutDuration(5000)       // timeout 5s
        .slidingWindowSize(10)
      .end()
  → to("https://{{kyc.base.url}}/verify?authMethod=header&authUsername=...")
  → process(KycResponseTranslator)  // traducción modelo externo → KycResult dominio
  → to("direct:kyc-result")
```

- Retry exponencial: 3 intentos, backoff 500ms / 1000ms / 2000ms.
- Webhook entrante: `from("servlet:/webhooks/kyc")` → validar firma → `KycCallbackPayload`.

#### `AmlProviderCamelAdapter` — ruta `aml-route`

```
AmlProviderGateway → from("direct:aml-evaluate")
  → process(AmlRequestTranslator)
  → circuitBreaker()                // Resilience4j circuit breaker
      .resilience4jConfiguration()
        .timeoutEnabled(true)
        .timeoutDuration(3000)       // timeout 3s — AML es crítico en tiempo
      .end()
  → to("https://{{aml.base.url}}/screen?apiKey={{aml.api.key}}")
  → process(AmlResponseTranslator)  // traducción → AmlResult dominio
```

#### `FinancialEntityCamelAdapter` — `FinancialEntityGateway`

- Rutas: `direct:financial-deposit`, `direct:financial-withdrawal`, `direct:financial-reversal`.
- Webhook entrante de confirmación: `from("servlet:/webhooks/payment")`.
- Timeout HTTP: 10s (entidades financieras tienen mayor latencia).

#### `PaymentGatewayCamelAdapter` — `PaymentGatewayPort`

- Validación HMAC-SHA256 en Java (no delegar a Camel): `HmacUtils.hmacSha256Hex(secret, payload)`.
- Webhook: `from("servlet:/webhooks/payment")` → extraer header `X-Signature` → validar → parsear payload.

#### `NotificationDeliveryCamelAdapter` — `NotificationDeliveryGateway`

- Ruta: `notification-route` — `from("direct:send-sms")`, `from("direct:send-email")`.
- Retry 3 intentos. Fallo no crítico: loguear y continuar saga.

#### `ReconciliationCamelAdapter` — `ReconciliationCamelRoute`

- Ruta: `from("timer:reconciliation?period=86400000")` (diario) o vía `RunReconciliationUseCase`.
- Consulta `reconciliation_records` con `status=UNMATCHED`, reconcilia con entidad financiera, actualiza estado.

### 6.2 Adaptador Narayana LRA — `NarayanaLraSagaAdapter`

Implementa `SagaCoordinatorPort`. Combina **Camel Saga EIP** para la secuencia de pasos con el cliente HTTP del **LRA Coordinator** para el ciclo de vida de la transacción distribuida.

```java
// NarayanaLraSagaAdapter.java
// @LRA(value = LRA.Type.REQUIRED, end = false)
public Mono<SagaId> startSaga(SagaType type, String tenantId, String payload) {
    // 1. POST http://<VPS_IP>:50000/lra-coordinator/start
    // 2. Persistir SagaInstance en INITIATED
    // 3. Retornar SagaId con lraUrl embebida
}

// @Complete
public Mono<Void> completeSaga(SagaId sagaId) { ... }

// @Compensate
public Mono<Void> compensateSaga(SagaId sagaId) {
    // Ejecutar compensaciones en orden INVERSO al de los pasos completados
    // Leer saga_step_log para determinar qué pasos deben compensarse
}
```

**Nota del spike RT-006:** Si la integración `@LRA` + WebFlux presenta problemas, usar el cliente HTTP de Narayana explícitamente sin anotaciones, coordinando el ciclo LRA manualmente en el adaptador.

### 6.3 Persistencia R2DBC

| Repositorio | Tabla | Operaciones críticas |
|---|---|---|
| `SagaInstanceR2dbcRepository` | `saga_instance` | `findBySagaId`, `updateState`, `updateCurrentStep` |
| `SagaStepLogR2dbcRepository` | `saga_step_log` | `insertStep`, `updateStepStatus`, `findBySagaIdOrderByExecutedAtDesc` |
| `ExternalIntegrationEventR2dbcRepository` | `external_integration_events` | `insertIfNotExists` (ON CONFLICT idempotency_key, source_system DO NOTHING), `existsByIdempotencyKeyAndSourceSystem` |
| `ReconciliationRecordR2dbcRepository` | `reconciliation_records` | `findUnmatched`, `upsertStatus` |

**Outbox relay** — relay estándar: `OutboxR2dbcRepository` publica en Kafka via `OutboxRelayRoute` (Camel timer → query `outbox` → `kafka:integration.events`).

### 6.4 Seguridad

- **Webhooks entrantes** (KYC, payment, withdrawal-confirmation): validación HMAC-SHA256 en `WebhookAuthFilter` antes de llegar al handler. Retornar `401` sin procesar si firma inválida.
- **OAuth 2.0 client credentials**: para webhooks que lo soporten (configurar en `SecurityConfig` como filtro de pre-autenticación).
- **Endpoints internos** (`/sagas/**`): JWT de servicio validado por `JwtServiceAuthFilter`. Solo accesible desde la red interna K3s (NetworkPolicy).

---

## 7. API REST (`rest-api`)

### Endpoints expuestos

| Método | Endpoint | Request | Response éxito | Response error | Descripción |
|---|---|---|---|---|---|
| `POST` | `/webhooks/kyc` | KycCallbackPayload (JSON) + `X-Signature` header | `200 OK` | `401 Unauthorized` (firma inválida) | Callback webhook del Proveedor KYC |
| `POST` | `/webhooks/payment` | PaymentNotification (JSON) + `X-Signature` header | `200 OK` | `401 Unauthorized` | Notificación de pago de Pasarela |
| `POST` | `/webhooks/withdrawal-confirmation` | WithdrawalConfirmation (JSON) + `X-Signature` header | `200 OK` | `401 Unauthorized` | Confirmación de retiro de Entidad Financiera |
| `GET` | `/sagas/{sagaId}` | — | `200 OK` + SagaStatusResponse | `404 Not Found` | Consulta estado de una saga |
| `POST` | `/sagas/{sagaId}/compensar` | CompensationRequest (JSON) | `200 OK` (aceptado, compensación asíncrona) | `404 Not Found` | Inicia compensación manual (uso interno) |

### Ejemplos de respuesta

```json
// GET /sagas/{sagaId} → 200
{
  "sagaId": "550e8400-e29b-41d4-a716-446655440000",
  "sagaType": "DEPOSIT",
  "tenantId": "tenant-001",
  "state": "IN_PROGRESS",
  "currentStep": 3,
  "createdAt": "2026-06-08T10:00:00Z",
  "updatedAt": "2026-06-08T10:00:15Z"
}

// POST /webhooks/kyc → 401 (firma inválida)
{
  "error": "INVALID_SIGNATURE",
  "message": "HMAC-SHA256 signature validation failed"
}
```

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

**Usar WireMock `<VPS_IP>:9999` para simular todos los sistemas externos.**  
**Usar `StepVerifier` para assertions sobre tipos reactivos.**

### 8.1 Capa de Dominio

| Clase test | Método test | Criterio / Assertion | Clase bajo prueba |
|---|---|---|---|
| `SagaInstanceTest` | `shouldTransitionFromInitiatedToInProgress` | `saga.start()` retorna instancia con `state == IN_PROGRESS` | `SagaInstance.start()` |
| `SagaInstanceTest` | `shouldTransitionToCompensatingFromInProgress` | `saga.beginCompensation()` retorna `state == COMPENSATING` | `SagaInstance.beginCompensation()` |
| `SagaInstanceTest` | `shouldRejectTransitionCompletedToAnyState` | `saga.complete().start()` lanza `InvalidSagaStateException` | `SagaInstance` (estado terminal) |
| `ExternalIntegrationEventTest` | `shouldRejectDuplicateIdempotencyKey` | segundo `validate()` con mismo `idempotency_key` retorna error de idempotencia | `ExternalIntegrationEvent.validate()` |
| `ExternalIntegrationEventTest` | `shouldAcceptEventWithUniqueIdempotencyKey` | `validate()` con clave única retorna `ExternalIntegrationEvent` válido | `ExternalIntegrationEvent.validate()` |
| `SagaIdTest` | `shouldNotAllowNullOrEmptyId` | constructor con `null` lanza `IllegalArgumentException` | `SagaId` |

### 8.2 Capa de Aplicación

| Clase test | Método test | Criterio / Assertion | Colaboradores mockeados |
|---|---|---|---|
| `DepositSagaOrchestratorUseCaseTest` | `shouldCompleteDepositSaga_whenAllStepsSucceed` | `StepVerifier.create(useCase.orchestrate(request))` → `assertNext(id -> assertNotNull(id))` → `verifyComplete()` | `KycGateway(mock)`, `AmlGateway(mock)`, `WalletGateway(mock)`, `SagaCoordinatorPort(mock)` |
| `DepositSagaOrchestratorUseCaseTest` | `shouldCompensateInReverseOrder_whenStep3Fails` | fallo en paso 3 (CreditWallet) → `SagaCoordinatorPort.compensateSaga()` invocado; AML compensation invocada antes de wallet compensation | todos los ports mockeados; `WalletGateway.creditWallet()` lanza excepción |
| `TransferSagaOrchestratorUseCaseTest` | `shouldCompleteTransfer_whenKycActiveAndFundsAvailable` | saga completa 5 pasos → `TransferCompletedEvent` publicado | `IdentityGateway(mock)`, `AmlGateway(mock)`, `WalletGateway(mock)` |
| `TransferSagaOrchestratorUseCaseTest` | `shouldReverseDebit_whenCreditFails` | fallo paso 4 (CreditWallet receptor) → REVERSE_DEBIT en wallet emisor invocado | mocks; `creditWallet()` falla |
| `WithdrawalSagaOrchestratorUseCaseTest` | `shouldReleaseReservation_whenFinancialEntityFails` | AC-005-E1: fallo paso 4 (instrucción a entidad) → `RELEASE_RESERVATION` invocado en wallet-service | `WalletGateway(mock)`, `FinancialEntityGateway(mock)` — falla |
| `ValidateWebhookUseCaseTest` | `shouldRejectPayload_whenHmacSignatureDoesNotMatch` | `StepVerifier.create(useCase.validate(payload, invalidSig, "PAYMENT"))` → `expectError(InvalidWebhookSignatureException.class)` | `PaymentGatewayPort(mock)` |
| `GetSagaStatusUseCaseTest` | `shouldReturnSagaStatus_whenSagaExists` | `StepVerifier.create(useCase.getStatus(sagaId))` → `assertNext(r -> assertEquals(IN_PROGRESS, r.state()))` | `SagaInstanceR2dbcRepository(mock)` |

### 8.3 Capa de Infraestructura (Camel + WireMock + Testcontainers)

| Clase test | Método test | Criterio / Assertion | Infraestructura de test |
|---|---|---|---|
| `KycProviderCamelAdapterTest` | `shouldTranslateKycResponseToKycResult` | Request al stub WireMock KYC → respuesta traducida a `KycResult` con campos del dominio correctos (ACL verificado) | WireMock stub `POST /kyc/verify → 200 { "status": "APPROVED" }` |
| `KycProviderCamelAdapterTest` | `shouldRetryOnTransientError_andSucceedOnThirdAttempt` | 2 respuestas `503` + 1 respuesta `200` → `KycResult` retornado sin error | WireMock stub con `fixedDelay` y scenario states |
| `AmlProviderCamelAdapterTest` | `shouldTriggerCircuitBreaker_whenAmlProviderTimesOut` | N llamadas con timeout → `CircuitBreakerOpenException` en llamada N+1 sin llegar al proveedor | WireMock stub `POST /aml/screen` con `fixedDelay(5000)` |
| `AmlProviderCamelAdapterTest` | `shouldTranslateAmlResponseToAmlResult` | Respuesta AML con `"risk": "HIGH"` → `AmlResult.riskLevel == HIGH` (traducción ACL correcta) | WireMock stub AML |
| `SagaInstanceR2dbcRepositoryTest` | `shouldSaveAndQuerySagaInstance` | `save(saga)` + `findBySagaId(id)` → entidad recuperada con estado correcto | Testcontainers PostgreSQL 16 |
| `ExternalIntegrationEventR2dbcRepositoryTest` | `shouldEnforceIdempotencyConstraint` | Dos `insert()` con mismo `idempotency_key` + `source_system` → segundo retorna vacío (ON CONFLICT DO NOTHING) | Testcontainers PostgreSQL 16 |
| `NarayanaLraSagaAdapterTest` | `shouldStartLraAndReturnSagaId` | `startSaga(DEPOSIT, tenantId, payload)` → LRA coordinator `POST /lra-coordinator/start` invocado → `SagaId` no nulo | WireMock stub LRA Coordinator en `<VPS_IP>:9999/lra-coordinator` |

### 8.4 Capa REST

| Clase test | Método test | Criterio / Assertion | Endpoint bajo prueba |
|---|---|---|---|
| `WebhookControllerTest` | `shouldReturn401_whenHmacSignatureInvalid` | `POST /webhooks/payment` con `X-Signature: invalid` → `401` sin procesar payload | `WebhookController.handlePayment()` |
| `WebhookControllerTest` | `shouldReturn200_whenHmacSignatureValid` | `POST /webhooks/payment` con firma HMAC válida → `200 OK` | `WebhookController.handlePayment()` |
| `WebhookControllerTest` | `shouldReturn200_whenKycCallbackReceived` | `POST /webhooks/kyc` con firma válida → `200 OK` + evento procesado | `WebhookController.handleKycCallback()` |
| `SagaControllerTest` | `shouldReturn200WithSagaStatus` | `GET /sagas/{sagaId}` → `200` + body con `sagaId`, `state`, `currentStep` | `SagaController.getSagaStatus()` |
| `SagaControllerTest` | `shouldReturn404_whenSagaNotFound` | `GET /sagas/unknown-id` → `404` | `SagaController.getSagaStatus()` |
| `SagaControllerTest` | `shouldReturn200_whenCompensationInitiated` | `POST /sagas/{sagaId}/compensar` → `200 OK` (compensación asíncrona aceptada) | `SagaController.compensate()` |

### 8.5 Umbrales de cobertura por capa

| Módulo | Cobertura mínima | Herramienta |
|---|---|---|
| `domain` | ≥ 90% | JaCoCo + SonarQube |
| `application` | ≥ 85% | JaCoCo + SonarQube |
| `infrastructure` | ≥ 75% | JaCoCo + SonarQube |
| `rest-api` | ≥ 80% | JaCoCo + SonarQube |

---

## 9. Criterios de Aceptación

### TDD

- [ ] Cada clase de dominio y caso de uso tiene al menos un test unitario escrito **antes** de la implementación (evidencia: primer commit con test en rojo, segundo commit con implementación).
- [ ] Los tests de adaptadores Camel usan WireMock `<VPS_IP>:9999`; los tests de repositorios usan Testcontainers PostgreSQL 16.
- [ ] `mvn test -pl integration-service` pasa en verde sin errores.
- [ ] Cobertura por capa cumple los umbrales definidos en §8.5.
- [ ] SonarQube Quality Gate `PASSED`; sin issues `BLOCKER` ni `CRITICAL`.

### Funcionales — Saga DEPOSIT

- [ ] Happy path completo: PaymentNotification con firma HMAC válida → AML aprueba → CreditWallet exitoso → Confirmación entidad → `DepositCompletedEvent` publicado en Kafka.
- [ ] Fallo en paso 3 (CreditWallet) dispara compensación en **orden inverso**: primero `compensar` AML (paso 2), luego nada en paso 1 (solo validación sin compensación).
- [ ] Segundo webhook con el mismo `idempotency_key` retorna `200 OK` sin reejecutar la saga (idempotencia garantizada por `external_integration_events`).
- [ ] Compensaciones son idempotentes: invocar `POST /sagas/{id}/compensar` dos veces no genera estado inconsistente.

### Funcionales — Saga TRANSFER

- [ ] Fallo en paso 4 (CreditWallet receptor) → `REVERSE_DEBIT` ejecutado en wallet del emisor.
- [ ] Emisor o receptor con KYC inactivo → saga rechazada en paso 1 sin iniciar pasos siguientes.

### Funcionales — Saga WITHDRAWAL (AC-005-E1)

- [ ] Fallo al instruir retiro a entidad financiera (paso 4) → `RELEASE_RESERVATION` ejecutado en wallet-service → fondos disponibles nuevamente.
- [ ] `WithdrawalRevertedEvent` publicado en Kafka cuando la saga es compensada.

### Funcionales — Webhooks y seguridad

- [ ] `POST /webhooks/*` con firma HMAC-SHA256 inválida retorna `401` sin procesar el payload (AC-003-E2).
- [ ] Circuit breaker Resilience4j se activa ante N timeouts del Proveedor AML: llamadas posteriores fallan fast sin alcanzar el proveedor.

### Operacional

- [ ] `GET <VPS_IP>:8085/actuator/health` → `{"status":"UP"}` en K3s.
- [ ] `GET <VPS_IP>:8085/actuator/prometheus` expone métricas de sagas (saga_completed_total, saga_compensated_total, circuit_breaker_state).
- [ ] Logs estructurados JSON con `sagaId` y `correlationId` visibles en Loki.
- [ ] Migraciones Liquibase idempotentes: ejecutar dos veces no genera errores.
- [ ] ArgoCD reporta `Synced` / `Healthy` para el deployment `integration-service`.
