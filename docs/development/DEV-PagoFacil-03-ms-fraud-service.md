# Etapa 3 — Microservicio: fraud-service

**Proyecto:** PagoFacil | **Bounded Context:** BC-03 Fraud | **Puerto local:** 8083  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Contexto y Responsabilidad

**Bounded context:** BC-03 Fraud — evaluación de fraude y AML en tiempo real.

**Responsabilidad principal:**
- Evaluación de transacciones contra reglas de fraude configurables por tenant.
- Verificación AML contra listas de sanciones activas (cache local sincronizado por `integration-service`).
- Clasificación, bloqueo y retención de transacciones sospechosas.
- Generación de alertas con severidad clasificada.
- Exposición de endpoint de compensación idempotente para sagas RETIRO y TRANSFERENCIA.

**Dependencias de otros microservicios:**

| Dirección | Servicio | Protocolo | Propósito |
|---|---|---|---|
| Entrante (REST mTLS) | `integration-service` | mTLS | Invocado para evaluación de fraude en saga |

**Dependencias de infraestructura:**

| Recurso | Tipo | Propósito |
|---|---|---|
| `pagofacil_fraud_service` | PostgreSQL R2DBC | Write side: reglas, alertas, verificaciones AML |
| `pagofacil.wallet.transaccion-iniciada` | Kafka Consumer | Evaluación reactiva de transacciones |
| `pagofacil.fraud.*` | Kafka Producer (Outbox relay) | Eventos de decisión de fraude |

---

## 2. Prerrequisitos

- Etapa 2b completa.
- Secret `pagofacil/dev/fraud-service` en floci.
- Migraciones Liquibase de `db/fraud-service/` aplicadas.
- `wallet-service` disponible para recibir eventos `TransaccionIniciada` (o Kafka con mensajes de prueba).

---

## 3. Ciclo de Desarrollo Incremental en K3d dev

```
Implementar caso de uso → mvn test (Red → Green) → git push
    → Jenkins pipeline → bumpImageTag → ArgoCD sync → K3d dev
```

> **Regla TDD:** la prueba de cada capa se escribe y se ve **fallar (Red)** ANTES de implementar el código de producción.

---

## 4. Capa de Dominio (`domain`) — _test-first_

### Entidades

| Entidad | Campos clave | Reglas de negocio |
|---|---|---|
| `FraudRule` | `ruleId`, `tenantId`, `name`, `ruleType`, `threshold`, `action`, `config (JsonNode)`, `isActive` | `ruleType` ∈ `{MONTO, FRECUENCIA, PATRON, DESTINATARIO}`; `action` ∈ `{BLOQUEAR, RETENER}`; solo reglas `isActive=true` participan en la evaluación |
| `FraudAlert` | `alertId`, `transactionId`, `userId`, `tenantId`, `severity`, `status`, `alertType`, `evaluationData` | `status` solo transiciona por métodos explícitos; inmutable una vez `APROBADA` o `RECHAZADA`; `resolvedAt` y `auditorDecision` se asignan juntos |
| `AmlVerification` | `verificationId`, `transactionId`, `userId`, `counterpartId`, `listsChecked`, `result`, `matchDetails` | Inmutable — no permite UPDATE; `result` ∈ `{NO_MATCH, MATCH, INCIERTO}` |

### Value Objects

| VO | Regla de validación |
|---|---|
| `AlertSeverity` | Enum: `BAJA`, `MEDIA`, `ALTA`, `CRITICA` |
| `AlertType` | Enum: `FRAUDE`, `AML` |
| `EvaluationDecision` | Enum: `APROBADA`, `RETENIDA`, `RECHAZADA` |
| `FraudRuleType` | Enum: `MONTO`, `FRECUENCIA`, `PATRON`, `DESTINATARIO` |

### Eventos de dominio

| Evento | Payload mínimo | Topic Kafka |
|---|---|---|
| `EvaluacionAprobada` | `transactionId`, `correlationId`, `decision: APROBADA` | `pagofacil.fraud.evaluacion-aprobada` |
| `TransaccionRechazadaPorAML` | `transactionId`, `correlationId`, `verificationId`, `decision: RECHAZADA` | `pagofacil.fraud.transaccion-rechazada-aml` |
| `TransaccionRetenidaPorFraude` | `transactionId`, `alertId`, `severity`, `decision: RETENIDA` | `pagofacil.fraud.transaccion-retenida` |

### Puertos secundarios

```java
// FraudRuleRepository
Flux<FraudRule> findActiveByTenantId(UUID tenantId);
Mono<FraudRule> findById(UUID ruleId);
Mono<FraudRule> save(FraudRule rule);

// FraudAlertRepository
Mono<FraudAlert> findById(UUID alertId);
Flux<FraudAlert> findByTenantIdAndStatusPaginated(UUID tenantId, String status, int page, int size);
Mono<FraudAlert> save(FraudAlert alert);

// AmlVerificationRepository
Mono<AmlVerification> save(AmlVerification verification);
Mono<AmlVerification> findByTransactionId(UUID transactionId);

// OutboxRepository
Mono<Void> save(OutboxEvent event);

// ProcessedMessageRepository
Mono<Boolean> existsByMessageIdAndConsumer(String messageId, String consumer);
Mono<Void> save(String messageId, String consumer);
```

### Invariantes de dominio

- Una evaluación con `result = MATCH` en AML genera siempre una alerta de tipo AML con severidad `ALTA` o `CRITICA`.
- Una alerta resuelta (`APROBADA` o `RECHAZADA`) no puede volver a estado `PENDIENTE`.
- Las reglas activas se aplican en orden determinístico (por `rule_type` y luego por `created_at DESC`).
- La acción más restrictiva entre todas las reglas disparadas prevalece (`BLOQUEAR` > `RETENER`).

---

## 5. Capa de Aplicación (`application`) — _test-first_

### Casos de uso

| Use Case | Descripción | Puerto primario | Puertos secundarios |
|---|---|---|---|
| `EvaluateTransactionUseCase` | Evalúa transacción contra reglas activas del tenant; ejecuta verificación AML; retorna decisión; publica evento vía Outbox | `EvaluateTransactionInputPort` | `FraudRuleRepository`, `AmlVerificationRepository`, `FraudAlertRepository`, `OutboxRepository` |
| `CreateFraudRuleUseCase` | Crea nueva regla de fraude para el tenant | `CreateFraudRuleInputPort` | `FraudRuleRepository` |
| `UpdateFraudRuleUseCase` | Actualiza configuración de regla existente | `UpdateFraudRuleInputPort` | `FraudRuleRepository` |
| `ListFraudRulesUseCase` | Lista reglas activas del tenant | `ListFraudRulesInputPort` | `FraudRuleRepository` |
| `CompensateFraudRetentionUseCase` | Idempotente — libera la retención de fraude sobre una transacción | `CompensateFraudInputPort` | `FraudAlertRepository`, `OutboxRepository` |
| `ProcessTransactionInitiatedUseCase` | Consumer Kafka de `TransaccionIniciada` — dispara evaluación reactiva | `TransactionInitiatedInputPort` | `EvaluateTransactionUseCase`, `ProcessedMessageRepository` |

### Flujo de evaluación de fraude

1. Cargar reglas activas del tenant desde `FraudRuleRepository`.
2. Aplicar cada regla al contexto de la transacción (monto, frecuencia, patrón, destinatario).
3. Si `ruleType = DESTINATARIO`: ejecutar verificación AML → crear `AmlVerification`.
4. Determinar la decisión final (la más restrictiva de las reglas disparadas).
5. Si `RETENIDA` o `RECHAZADA`: crear `FraudAlert` con severidad calculada.
6. Publicar evento vía Outbox.
7. Retornar `EvaluationDecision` al llamador (REST) o publicar a Kafka (consumer).

---

## 6. Capa de Infraestructura (`infrastructure`) — _test-first_

### Adaptadores R2DBC

| Adaptador | Tablas | Operaciones principales |
|---|---|---|
| `FraudRuleR2dbcAdapter` | `fraud_rules` | `findActiveByTenantId`, `findById`, `save` |
| `FraudAlertR2dbcAdapter` | `fraud_alerts` | `findById`, `findByTenantIdAndStatusPaginated`, `save` |
| `AmlVerificationR2dbcAdapter` | `aml_verifications` | `save`, `findByTransactionId` |
| `OutboxR2dbcAdapter` | `outbox` | `save` (en misma transacción) |
| `ProcessedMessageR2dbcAdapter` | `processed_message` | `existsByMessageIdAndConsumer`, `save` |

### Consumidor Kafka

| Topic | Consumer Group | Lógica |
|---|---|---|
| `pagofacil.wallet.transaccion-iniciada` | `fraud-evaluator` | Deserializar evento → verificar idempotencia con `processed_message` → invocar `ProcessTransactionInitiatedUseCase` → marcar procesado |

### Productores Kafka (Outbox relay)

| Topic | Evento |
|---|---|
| `pagofacil.fraud.evaluacion-aprobada` | `EvaluacionAprobada` |
| `pagofacil.fraud.transaccion-rechazada-aml` | `TransaccionRechazadaPorAML` |
| `pagofacil.fraud.transaccion-retenida` | `TransaccionRetenidaPorFraude` |

### Configuración de seguridad

- `GET /v1/fraud/rules`: requiere JWT Bearer (administrador de plataforma).
- `POST /v1/fraud/rules`: requiere JWT Bearer (administrador).
- `PUT /v1/fraud/rules/{ruleId}`: requiere JWT Bearer (administrador).
- `POST /v1/fraud/evaluate`: requiere mTLS (solo `integration-service`).
- `POST /v1/fraud/evaluate/{id}/compensar`: requiere mTLS.

---

## 7. API REST (`rest-api`) — _test-first_

Especificación completa: `docs/design/api/SDD-PagoFacil-openapi.yaml` — tag `Fraud` y `Compensaciones`

| Método | Ruta | Request Body | Response | Códigos HTTP |
|---|---|---|---|---|
| GET | `/v1/fraud/rules` | — | `ReglaFraudeResponse[]` | 200 |
| POST | `/v1/fraud/rules` | `ReglaFraudeRequest` | `ReglaFraudeResponse` | 201, 422 |
| PUT | `/v1/fraud/rules/{ruleId}` | `ReglaFraudeRequest` | `ReglaFraudeResponse` | 200, 404 |
| POST | `/v1/fraud/evaluate` | `EvaluacionFraudeRequest` | `EvaluacionFraudeResponse` | 200 |
| POST | `/v1/fraud/evaluate/{transactionId}/compensar` | `CompensacionRequest` | — | 200, 404 |

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> Tipos reactivos verificados con `StepVerifier`, nunca `block()`.

### Dominio

| Clase de test | Método | Invariante | Elemento de Sección 4 |
|---|---|---|---|
| `FraudRuleTest` | `shouldApplyMostRestrictiveAction` | BLOQUEAR prevalece sobre RETENER | Lógica de agregación de reglas |
| `FraudAlertTest` | `shouldNotAllowStateChangeOnResolvedAlert` | Alerta resuelta es inmutable | Entidad `FraudAlert` |
| `AmlVerificationTest` | `shouldBeImmutableAfterCreation` | `AmlVerification` no tiene setters post-construcción | Entidad `AmlVerification` |
| `EvaluationDecisionTest` | `shouldReturnRechazadaOnAmlMatch` | AML MATCH → decisión RECHAZADA | Lógica de decisión |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case |
|---|---|---|---|---|
| `EvaluateTransactionUseCaseTest` | `shouldReturnApprovedWhenNoRuleTriggered` | Sin regla activa disparada | `FraudRuleRepository` (mock sin reglas), `OutboxRepository` (mock) | `EvaluateTransactionUseCase` |
| `EvaluateTransactionUseCaseTest` | `shouldReturnRetainedOnHighAmountRule` | Regla MONTO supera threshold | `FraudRuleRepository` (mock con regla RETENER) | `EvaluateTransactionUseCase` |
| `EvaluateTransactionUseCaseTest` | `shouldReturnRejectedOnAmlMatch` | AML MATCH → RECHAZADA | `AmlVerificationRepository` (mock MATCH) | `EvaluateTransactionUseCase` |
| `CompensateFraudRetentionUseCaseTest` | `shouldBeIdempotent` | Segunda compensación sin efecto | `FraudAlertRepository` (mock ya liberado) | `CompensateFraudRetentionUseCase` |
| `ProcessTransactionInitiatedUseCaseTest` | `shouldSkipOnDuplicateMessageId` | `processed_message` ya existe → sin efecto | `ProcessedMessageRepository` (mock) | `ProcessTransactionInitiatedUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador |
|---|---|---|---|
| `FraudRuleR2dbcAdapterTest` | `shouldReturnOnlyActiveRulesForTenant` | SELECT con `is_active=true` y `tenant_id` con Testcontainers | `FraudRuleR2dbcAdapter` |
| `FraudAlertR2dbcAdapterTest` | `shouldSaveAlertWithEvaluationData` | INSERT con campo JSONB | `FraudAlertR2dbcAdapter` |
| `OutboxR2dbcAdapterTest` | `shouldPersistEventAtomically` | INSERT alerta + INSERT outbox en misma transacción | `OutboxR2dbcAdapter` |
| `KafkaConsumerAdapterTest` | `shouldProcessMessageAndMarkAsProcessed` | Consumir mensaje, evaluar, marcar idempotencia | Consumer Kafka + `ProcessedMessageR2dbcAdapter` |

### REST

| Clase de test | Método | Endpoint | Status / body | Elemento |
|---|---|---|---|---|
| `FraudControllerTest` | `shouldReturn201OnValidRuleCreation` | `POST /v1/fraud/rules` | 201 + `ruleId` | POST rules |
| `FraudControllerTest` | `shouldReturn200OnFraudEvaluation` | `POST /v1/fraud/evaluate` | 200 + `decision` | POST evaluate |
| `FraudControllerTest` | `shouldReturn200IdempotentOnCompensacion` | `POST /v1/fraud/evaluate/{id}/compensar` | 200 (2da llamada) | POST compensar |

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
- [ ] La cobertura por capa cumple los umbrales.
- [ ] `POST /v1/fraud/evaluate` retorna `APROBADA`, `RETENIDA` o `RECHAZADA` según las reglas activas.
- [ ] Transacción con AML MATCH retorna `RECHAZADA` y crea `AmlVerification` inmutable.
- [ ] Transacción con regla RETENER activa crea `FraudAlert` con severidad calculada.
- [ ] Los eventos de fraude se publican vía Outbox (no dual-write).
- [ ] El consumer de `TransaccionIniciada` es idempotente: mensajes duplicados no producen doble evaluación.
- [ ] El endpoint de compensación es idempotente.
- [ ] Pipeline CI despliega en K3d: `kubectl get pods -n dev | grep fraud-service` muestra `Running`.
