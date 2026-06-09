# Etapa 3g — Microservicio: projection-service

**Proyecto:** PagoFacil — Billetera Digital
**Bounded Context:** BC-07 CQRS (Read Model)
**Puerto local:** 8087
**Base de datos:** PostgreSQL `pagofacil_readmodel` (escritura exclusiva)
**Patrón:** CQRS — único escritor del read model; consumidor Kafka puro

---

## 1. Contexto y Responsabilidad

El `projection-service` es el **único escritor** de `pagofacil_readmodel`. Consume eventos de dominio de todos los bounded contexts y proyecta tablas desnormalizadas optimizadas para consulta ETL (MS1). El lag del read model es inherente al CQRS y se espera < 30 s en condiciones nominales.

**No expone endpoints al API Gateway.** Es un servicio interno de proyección.

### Responsabilidades

- Consumo reactivo de eventos de dominio de todos los bounded contexts desde Kafka.
- Proyección del estado en tablas PostgreSQL desnormalizadas (`pagofacil_readmodel`).
- Garantía de idempotencia (tabla `processed_message`).
- Ningún otro microservicio tiene permiso de escritura sobre `pagofacil_readmodel`.

### Dependencias de infraestructura

| Recurso | Detalles |
|---|---|
| PostgreSQL | `pagofacil_readmodel` en `VPS_IP:5432` (escritura); credencial de app con permiso de escritura en esta BD |
| Kafka | `VPS_IP:29092` — consumer multi-topic |
| Secret | `pagofacil/dev/reporting-projection-service` en floci `VPS_IP:4566` |

---

## 2. Prerrequisitos

- [ ] Etapas 0, 0c, 1, 2, 2b completadas.
- [ ] Microservicios 3a–3e publicando eventos en Kafka.
- [ ] PostgreSQL `pagofacil_readmodel` disponible; tablas `report_transactions`, `report_compliance_alerts`, `report_users`, `processed_message` migradas.
- [ ] Secret `pagofacil/dev/reporting-projection-service` presente en floci `VPS_IP:4566`.

---

## 3. Ciclo de Desarrollo Incremental en K3s VPS dev

```
Implementar projector → mvn test (local) → git push → Jenkins pipeline
→ push Gitea registry → bumpImageTag → ArgoCD sync → K3s VPS → servicio disponible
```

> **TDD obligatorio — prueba FALLA (Red) antes del código (Green). StepVerifier para reactivos, NUNCA block().**

---

## 4. Capa de Dominio (`domain`) — test-first

### Puertos secundarios

```java
// Projection repositories (upsert por clave natural)
Mono<Void> ReportTransactionRepository.upsert(ReportTransaction tx);       // key: transaction_id
Mono<Void> ReportComplianceAlertRepository.upsert(ReportComplianceAlert a); // key: alert_id
Mono<Void> ReportUsersRepository.upsert(ReportUser u);                     // key: user_id
Mono<Void> ReportUsersRepository.updateKycStatus(UUID userId, String kycStatus, Instant approvedAt);
Mono<Void> ReportUsersRepository.updateUserStatus(UUID userId, String status);

// Idempotency
Mono<Boolean> ProcessedMessageRepository.checkAndInsert(String messageId, String consumer);
```

### Value Objects

`ProjectionKey` (topic + messageId — clave única para idempotencia), `TenantId`, `TransactionId`, `AlertId`, `UserId`

---

## 5. Capa de Aplicación (`application`) — test-first

### Casos de uso

| Use Case | Evento que dispara | Proyección |
|---|---|---|
| `ProjectUserRegisteredUseCase` | `pagofacil.identity.user-registered` | Upsert en `report_users` |
| `ProjectKycApprovedUseCase` | `pagofacil.identity.kyc-approved` | Update `report_users.kyc_status = APPROVED`, `kyc_approved_at` |
| `ProjectKycRejectedUseCase` | `pagofacil.identity.kyc-rejected` | Update `report_users.kyc_status = REJECTED` |
| `ProjectAccountSuspendedUseCase` | `pagofacil.identity.account-suspended-by-aml` | Update `report_users.user_status = SUSPENDED` |
| `ProjectDepositCompletedUseCase` | `pagofacil.wallet.deposit-completed` | Upsert en `report_transactions` (type: DEPOSIT) |
| `ProjectTransferCompletedUseCase` | `pagofacil.wallet.transfer-completed` | Dos upserts en `report_transactions` (TRANSFER_DEBIT + TRANSFER_CREDIT) |
| `ProjectWithdrawalCompletedUseCase` | `pagofacil.wallet.withdrawal-completed` | Upsert en `report_transactions` (type: WITHDRAWAL) |
| `ProjectFraudAlertCreatedUseCase` | `pagofacil.fraud.fraud-alert-created` | Upsert en `report_compliance_alerts` |
| `ProjectComplianceAlertResolvedUseCase` | `pagofacil.fraud.compliance-alert-resolved` | Update `report_compliance_alerts.status`, `resolution_actor`, `resolved_at` |

Cada use case verifica idempotencia via `ProcessedMessageRepository.checkAndInsert` antes de proyectar.

### DTOs de eventos de dominio

`UserRegisteredEvent`, `KycApprovedEvent`, `KycRejectedEvent`, `AccountSuspendedEvent`, `DepositCompletedEvent`, `TransferCompletedEvent`, `WithdrawalCompletedEvent`, `FraudAlertCreatedEvent`, `ComplianceAlertResolvedEvent`.

---

## 6. Capa de Infraestructura (`infrastructure`) — test-first

### Adaptadores R2DBC

| Adaptador | Tabla | Operaciones clave |
|---|---|---|
| `ReportTransactionR2dbcRepository` | `report_transactions` | Upsert reactivo por `transaction_id` (ON CONFLICT DO UPDATE) |
| `ReportComplianceAlertR2dbcRepository` | `report_compliance_alerts` | Upsert por `alert_id`; update parcial por `alert_id` |
| `ReportUsersR2dbcRepository` | `report_users` | Upsert por `user_id`; update parcial (kyc_status, user_status) |
| `ProcessedMessageR2dbcRepository` | `processed_message` | `checkAndInsert` — insert único; si `DataIntegrityViolationException` → devuelve `false` |

### Consumidores Kafka

Un consumer por tópico; todos usan `checkAndInsert` para idempotencia:

| Consumer | Tópico | Use Case invocado |
|---|---|---|
| `UserRegisteredConsumer` | `pagofacil.identity.user-registered` | `ProjectUserRegisteredUseCase` |
| `KycApprovedConsumer` | `pagofacil.identity.kyc-approved` | `ProjectKycApprovedUseCase` |
| `KycRejectedConsumer` | `pagofacil.identity.kyc-rejected` | `ProjectKycRejectedUseCase` |
| `AccountSuspendedConsumer` | `pagofacil.identity.account-suspended-by-aml` | `ProjectAccountSuspendedUseCase` |
| `DepositCompletedConsumer` | `pagofacil.wallet.deposit-completed` | `ProjectDepositCompletedUseCase` |
| `TransferCompletedConsumer` | `pagofacil.wallet.transfer-completed` | `ProjectTransferCompletedUseCase` |
| `WithdrawalCompletedConsumer` | `pagofacil.wallet.withdrawal-completed` | `ProjectWithdrawalCompletedUseCase` |
| `FraudAlertCreatedConsumer` | `pagofacil.fraud.fraud-alert-created` | `ProjectFraudAlertCreatedUseCase` |
| `ComplianceAlertResolvedConsumer` | `pagofacil.fraud.compliance-alert-resolved` | `ProjectComplianceAlertResolvedUseCase` |

---

## 7. API REST (`rest-api`)

Este servicio **no expone endpoints de negocio** al API Gateway. Solo actuator:

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/actuator/health/readiness` | Readiness probe K3s |
| GET | `/actuator/health/liveness` | Liveness probe |
| GET | `/actuator/prometheus` | Métricas Prometheus |

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> **Regla:** prueba FALLA (Red) antes del código de producción (Green). StepVerifier, nunca `block()`.

### Dominio

| Clase de test | Método | Invariante / Regla | Elemento que precede |
|---|---|---|---|
| `ProjectionKeyTest` | `shouldBeUniquePerTopicAndMessageId` | Combinación topic+messageId genera clave única | `ProjectionKey` constructor |
| `ProjectionKeyTest` | `shouldBeEqualWhenTopicAndMessageIdMatch` | Igualdad por valor | `ProjectionKey.equals()` |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case que precede |
|---|---|---|---|---|
| `ProjectUserRegisteredUseCaseTest` | `shouldUpsertReportUser_whenUserRegistered` | Happy path | `ReportUsersRepository`, `ProcessedMessageRepository` (mocks) | `ProjectUserRegisteredUseCase` |
| `ProjectUserRegisteredUseCaseTest` | `shouldSkipProjection_whenMessageAlreadyProcessed` | `checkAndInsert` devuelve `false` | `ProcessedMessageRepository` (mock) | `ProjectUserRegisteredUseCase` |
| `ProjectTransferCompletedUseCaseTest` | `shouldCreateTwoTransactionRows_onTransferCompleted` | Un TRANSFER_DEBIT + un TRANSFER_CREDIT | `ReportTransactionRepository`, `ProcessedMessageRepository` (mocks) | `ProjectTransferCompletedUseCase` |
| `ProjectComplianceAlertResolvedUseCaseTest` | `shouldUpdateAlertStatus_whenResolved` | Update parcial | `ReportComplianceAlertRepository` (mock) | `ProjectComplianceAlertResolvedUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador que precede |
|---|---|---|---|
| `ReportTransactionR2dbcRepositoryTest` | `shouldUpsertOnDuplicateTransactionId` | Upsert idempotente | `ReportTransactionR2dbcRepository` (Testcontainers PostgreSQL) |
| `ProcessedMessageRepositoryTest` | `shouldPreventDuplicateProcessing` | Inserción duplicada devuelve `false` | `ProcessedMessageR2dbcRepository` |
| `DepositCompletedConsumerTest` | `shouldProjectDeposit_whenEventReceived` | Consume Kafka → proyecta en read model | `DepositCompletedConsumer` (Testcontainers Kafka + PostgreSQL) |

### REST

| Clase de test | Método | Endpoint + status | Elemento que precede |
|---|---|---|---|
| `ActuatorTest` | `shouldReturn200_onReadinessCheck` | `GET /actuator/health/readiness` → 200 | Readiness probe |

### Umbrales de cobertura

| Capa | Umbral mínimo |
|---|---|
| `domain` | ≥ 90% |
| `application` | ≥ 85% |
| `infrastructure` | ≥ 80% |

---

## 9. Criterios de Aceptación

### TDD

- [ ] Cada projector tuvo su prueba escrita y vista fallar (Red) antes del código (Green).
- [ ] `mvn test` finaliza en verde; sin `block()` en pruebas.
- [ ] Cobertura por capa cumple los umbrales declarados.

### Funcionales

- [ ] Evento `UserRegistered` → fila insertada en `report_users`.
- [ ] Evento `KYCApproved` → fila actualizada en `report_users` con `kyc_status = APPROVED` y `kyc_approved_at`.
- [ ] Evento `DepositCompleted` → fila insertada en `report_transactions` con tipo `DEPOSIT`.
- [ ] Evento `TransferCompleted` → dos filas en `report_transactions` (TRANSFER_DEBIT + TRANSFER_CREDIT).
- [ ] Reentrega del mismo evento (mismo `message_id`) no genera fila duplicada (idempotencia).
- [ ] Lag del read model < 30 s bajo carga nominal.
- [ ] MS1 (`report-extraction-service`) puede leer `pagofacil_readmodel` con credenciales de solo lectura.
- [ ] Servicio arranca y `/actuator/health/readiness` responde `UP` en K3s VPS.
