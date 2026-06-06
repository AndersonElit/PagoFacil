# Etapa 3 — Microservicio: projection-service

**Proyecto:** PagoFacil | **Bounded Context:** CQRS Read Model | **Puerto local:** 8087  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Contexto y Responsabilidad

**Bounded context:** CQRS Read Model — proyección y mantenimiento del estado desnormalizado.

**Responsabilidad principal:**
- Consumir eventos de dominio publicados en Kafka por BC-01, BC-02, BC-03 y BC-06.
- Proyectar y mantener las tablas desnormalizadas del Read Model en `pagofacil_readmodel` (PostgreSQL).
- Ser el **único escritor** del Read Model. `audit-service` y MS1 solo leen.
- Garantizar idempotencia en la proyección (event key + upsert).
- Mantener el lag de proyección dentro del SLA ≤ 30 segundos.

**Dependencias de otros microservicios:** ninguna REST saliente.

**Dependencias de infraestructura:**

| Recurso | Tipo | Propósito |
|---|---|---|
| `pagofacil_readmodel` | PostgreSQL R2DBC (owner, escritura exclusiva) | Tablas desnormalizadas |
| `pagofacil.wallet.*`, `pagofacil.identity.*`, `pagofacil.fraud.*` | Kafka Consumer multi-topic | Eventos de dominio de todos los BCs |

---

## 2. Prerrequisitos

- Etapa 2b completa.
- Secret `pagofacil/dev/projection-service` en floci.
- Migraciones Liquibase de `db/projection-service/` aplicadas (Read Model schema).
- `wallet-service` activo publicando eventos a Kafka (o mensajes de prueba en el topic).

---

## 3. Ciclo de Desarrollo Incremental en K3d dev

```
Implementar proyector → mvn test (Red → Green) → git push
    → Jenkins pipeline → bumpImageTag → ArgoCD sync → K3d dev
```

> **Regla TDD:** la prueba de cada proyector se escribe y se ve **fallar (Red)** ANTES de implementar el código.

---

## 4. Capa de Dominio (`domain`) — _test-first_

### Puertos secundarios (interfaces del dominio)

```java
// TransactionProjectionRepository
Mono<Void> upsert(TransactionProjection projection);
Mono<Boolean> existsById(UUID transactionId);

// AlertProjectionRepository
Mono<Void> upsert(AlertProjection projection);
Mono<Void> updateResolution(UUID alertId, String status, String auditorDecision, Instant resolvedAt);

// WalletProjectionRepository
Mono<Void> upsert(WalletProjection projection);

// ReconciliationProjectionRepository
Mono<Void> upsert(ReconciliationProjection projection);

// ProcessedMessageRepository
Mono<Boolean> existsByMessageIdAndConsumer(String messageId, String consumer);
Mono<Void> save(String messageId, String consumer);
```

### Proyecciones (modelos del Read Model)

| Proyección | Tabla en `pagofacil_readmodel` | Campos principales |
|---|---|---|
| `TransactionProjection` | `report_transactions` | `transactionId`, `correlationId`, `userId`, `tenantId`, `walletId`, `operationType`, `amount`, `currency`, `status`, `counterpartUserId`, `externalReference`, `createdAt`, `resolvedAt`, `projectedAt` |
| `AlertProjection` | `report_alerts` | `alertId`, `transactionId`, `userId`, `tenantId`, `severity`, `status`, `alertType`, `ruleTriggered`, `createdAt`, `resolvedAt`, `auditorDecision`, `projectedAt` |
| `WalletProjection` | `report_wallets` | `walletId`, `userId`, `tenantId`, `availableBalance`, `pendingBalance`, `currency`, `lastUpdated`, `projectedAt` |
| `ReconciliationProjection` | `report_reconciliations` | `reconciliationId`, `correlationId`, `transactionId`, `tenantId`, `discrepancyType`, `internalAmount`, `externalAmount`, `status`, `detectedAt`, `projectedAt` |

### Invariante de idempotencia

- Cada proyección usa UPSERT (`INSERT ... ON CONFLICT DO UPDATE`): una reentrega del mismo evento actualiza la fila en lugar de duplicarla.
- La idempotencia de alto nivel se gestiona con `processed_message` (verifica `messageId` + `consumer` antes de procesar).

---

## 5. Capa de Aplicación (`application`) — _test-first_

### Casos de uso (proyectores)

| Use Case | Evento consumido | Topic | Proyección actualizada |
|---|---|---|---|
| `ProjectTransactionInitiatedUseCase` | `TransaccionIniciada` | `pagofacil.wallet.transaccion-iniciada` | `report_transactions` (status: EN_PROCESO) |
| `ProjectDepositConfirmedUseCase` | `DepositoConfirmado` | `pagofacil.wallet.deposito-confirmado` | `report_transactions` (status: CONFIRMADA), `report_wallets` (saldo actualizado) |
| `ProjectWithdrawalConfirmedUseCase` | `RetiroConfirmado` | `pagofacil.wallet.retiro-confirmado` | `report_transactions` (status: CONFIRMADA), `report_wallets` |
| `ProjectTransferConfirmedUseCase` | `TransferenciaConfirmada` | `pagofacil.wallet.transferencia-confirmada` | `report_transactions` (status: CONFIRMADA), `report_wallets` x2 |
| `ProjectTransactionFailedUseCase` | `DepositoRevertido` | `pagofacil.wallet.deposito-revertido` | `report_transactions` (status: FALLIDA), `report_wallets` |
| `ProjectUserActivatedUseCase` | `CuentaActivada` | `pagofacil.identity.cuenta-activada` | Extiende `report_wallets` (billetera activada) |
| `ProjectFraudAlertCreatedUseCase` | `TransaccionRetenidaPorFraude` | `pagofacil.fraud.transaccion-retenida` | `report_alerts` (nueva alerta), `report_transactions` (status: RETENIDA) |
| `ProjectFraudAlertRejectedUseCase` | `TransaccionRechazadaPorAML` | `pagofacil.fraud.transaccion-rechazada-aml` | `report_alerts` (nueva alerta AML), `report_transactions` (status: FALLIDA) |

---

## 6. Capa de Infraestructura (`infrastructure`) — _test-first_

### Adaptadores R2DBC

| Adaptador | Tabla | Operaciones principales |
|---|---|---|
| `TransactionProjectionR2dbcAdapter` | `report_transactions` | `upsert` (INSERT ON CONFLICT DO UPDATE) |
| `AlertProjectionR2dbcAdapter` | `report_alerts` | `upsert`, `updateResolution` |
| `WalletProjectionR2dbcAdapter` | `report_wallets` | `upsert` |
| `ReconciliationProjectionR2dbcAdapter` | `report_reconciliations` | `upsert` |
| `ProcessedMessageR2dbcAdapter` | Tabla en `pagofacil_readmodel` | `existsByMessageIdAndConsumer`, `save` |

> **Nota:** la tabla `processed_message` en `projection-service` vive en `pagofacil_readmodel` (no en una BD aparte). Solo el `projection-service` escribe en `pagofacil_readmodel`.

### Consumidores Kafka (multi-topic)

| Topic | Consumer Group | Proyector invocado |
|---|---|---|
| `pagofacil.wallet.transaccion-iniciada` | `projection-wallet` | `ProjectTransactionInitiatedUseCase` |
| `pagofacil.wallet.deposito-confirmado` | `projection-wallet` | `ProjectDepositConfirmedUseCase` |
| `pagofacil.wallet.deposito-revertido` | `projection-wallet` | `ProjectTransactionFailedUseCase` |
| `pagofacil.wallet.retiro-confirmado` | `projection-wallet` | `ProjectWithdrawalConfirmedUseCase` |
| `pagofacil.wallet.transferencia-confirmada` | `projection-wallet` | `ProjectTransferConfirmedUseCase` |
| `pagofacil.identity.cuenta-activada` | `projection-identity` | `ProjectUserActivatedUseCase` |
| `pagofacil.fraud.transaccion-retenida` | `projection-fraud` | `ProjectFraudAlertCreatedUseCase` |
| `pagofacil.fraud.transaccion-rechazada-aml` | `projection-fraud` | `ProjectFraudAlertRejectedUseCase` |

### Configuración de seguridad

`projection-service` no expone endpoints de negocio. Solo `GET /actuator/health/readiness` y métricas.

**Métrica de observabilidad clave:** `projection.lag.seconds` — exportada como gauge de Prometheus. Alerta si lag > 60 segundos durante 10 minutos.

---

## 7. API REST (`rest-api`)

`projection-service` no expone endpoints REST de negocio. Únicamente:

| Endpoint | Propósito |
|---|---|
| `GET /actuator/health` | Estado del servicio |
| `GET /actuator/health/readiness` | Readiness probe K8s |
| `GET /actuator/metrics` | Métricas Prometheus (incluye `projection.lag.seconds`) |

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> Tipos reactivos verificados con `StepVerifier`.

### Dominio

| Clase de test | Método | Invariante | Elemento de Sección 4 |
|---|---|---|---|
| `TransactionProjectionTest` | `shouldUpsertOnRedelivery` | Segunda entrega actualiza, no duplica | Idempotencia UPSERT |
| `WalletProjectionTest` | `shouldReflectBalanceAfterConfirmedDeposit` | Balance correcto post-depósito | `WalletProjection` |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case |
|---|---|---|---|---|
| `ProjectDepositConfirmedUseCaseTest` | `shouldUpdateTransactionAndWalletProjection` | Happy path | `TransactionProjectionRepository`, `WalletProjectionRepository`, `ProcessedMessageRepository` (Mockito) | `ProjectDepositConfirmedUseCase` |
| `ProjectDepositConfirmedUseCaseTest` | `shouldSkipOnDuplicateMessageId` | Reentrega idempotente | `ProcessedMessageRepository` (devuelve `true`) | `ProjectDepositConfirmedUseCase` |
| `ProjectFraudAlertCreatedUseCaseTest` | `shouldCreateAlertAndUpdateTransactionStatus` | Happy path | `AlertProjectionRepository`, `TransactionProjectionRepository` (mock) | `ProjectFraudAlertCreatedUseCase` |
| `ProjectTransferConfirmedUseCaseTest` | `shouldUpdateBothWallets` | Remitente y destinatario actualizados | `WalletProjectionRepository` (mock, llamado 2 veces) | `ProjectTransferConfirmedUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador |
|---|---|---|---|
| `TransactionProjectionR2dbcAdapterTest` | `shouldUpsertTransaction` | INSERT + segundo INSERT con mismo PK → UPDATE con Testcontainers (readmodel) | `TransactionProjectionR2dbcAdapter` |
| `AlertProjectionR2dbcAdapterTest` | `shouldInsertNewAlert` | INSERT en `report_alerts` | `AlertProjectionR2dbcAdapter` |
| `WalletProjectionR2dbcAdapterTest` | `shouldUpsertWalletBalance` | UPSERT con nuevo saldo | `WalletProjectionR2dbcAdapter` |
| `KafkaConsumerIntegrationTest` | `shouldProjectEventFromKafka` | Embedded Kafka → evento consumido → fila en `report_transactions` | Consumer multi-topic |

### Umbrales de cobertura mínima

| Capa | Umbral |
|---|---|
| `domain` | ≥ 85% |
| `application` | ≥ 85% |
| `infrastructure` | ≥ 80% |

---

## 9. Criterios de Aceptación

- [ ] Cada proyector tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] `mvn test` finaliza en verde.
- [ ] La cobertura por capa cumple los umbrales.
- [ ] Al recibir `DepositoConfirmado` en Kafka, `report_transactions` tiene la fila con `status=CONFIRMADA`.
- [ ] Al recibir el mismo evento dos veces, solo hay una fila en `report_transactions` (idempotencia UPSERT).
- [ ] Al recibir `TransaccionRetenidaPorFraude`, aparece una nueva fila en `report_alerts` y `report_transactions` actualiza a `RETENIDA`.
- [ ] El lag de proyección (`projection.lag.seconds`) es < 30 segundos en operación normal con K3d dev.
- [ ] Pipeline CI despliega en K3d: `kubectl get pods -n dev | grep projection-service` muestra `Running`.
