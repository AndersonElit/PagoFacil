# Etapa 3 — Microservicio: integration-service

**Proyecto:** PagoFacil | **Bounded Context:** BC-06 Integration | **Puerto local:** 8086  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Contexto y Responsabilidad

**Bounded context:** BC-06 Integration — capa de integración centralizada y orquestador de sagas.

**Responsabilidad principal:**
- Centralizar toda la comunicación saliente con sistemas externos (ACL — ADR-003).
- Orquestar las sagas: Saga-Deposito, Saga-Retiro, Saga-Transferencia y Conciliacion mediante Apache Camel Saga EIP + Narayana LRA (ADR-004).
- Recepción y validación de webhooks de confirmación de entidades financieras (HMAC).
- Sincronización periódica de listas de sanciones AML.
- Traducción de modelos externos al lenguaje ubicuo interno.
- Exposición de endpoint de compensación de saga.

**Dependencias de otros microservicios:**

| Dirección | Servicio | Protocolo | Propósito |
|---|---|---|---|
| Saliente (REST mTLS) | `wallet-service` | mTLS | Pasos y compensaciones de saga (Deposito, Retiro, Transferencia) |
| Saliente (REST mTLS) | `fraud-service` | mTLS | Evaluación de fraude en saga Retiro y Transferencia |
| Saliente (REST mTLS) | `identity-service` | mTLS | Coordinación KYC en saga de onboarding |

**Sistemas externos (solo accesibles desde `integration-service`):**

| Sistema | Protocolo | Simulación en dev |
|---|---|---|
| Entidades financieras | HTTPS + HMAC | WireMock (`http://wiremock:8888`) |
| Proveedor KYC | HTTPS | WireMock |
| Listas AML | HTTPS | WireMock |

**Dependencias de infraestructura:**

| Recurso | Tipo | Propósito |
|---|---|---|
| `pagofacil_integration_service` | PostgreSQL R2DBC | Estado de sagas, outbox, external requests |
| `pagofacil.integration.*` | Kafka Producer (Outbox relay) | Eventos de saga |
| Narayana LRA Coordinator | HTTP | Registro y coordinación de sagas LRA |

---

## 2. Prerrequisitos

- Etapa 2b completa.
- Secret `pagofacil/dev/integration-service` en floci.
- Migraciones Liquibase de `db/integration-service/` aplicadas.
- `wallet-service`, `fraud-service` e `identity-service` activos (o WireMock como stubs).
- Narayana LRA Coordinator disponible en `http://localhost:8180`.
- WireMock con stubs configurados para los sistemas externos (ver Etapa 5 para configuración).

---

## 3. Ciclo de Desarrollo Incremental en K3d dev

```
Implementar saga/ruta Camel → mvn test (Red → Green) → git push
    → Jenkins pipeline → bumpImageTag → ArgoCD sync → K3d dev
```

> **Regla TDD:** la prueba de cada adaptador Camel y cada saga se escribe y se ve **fallar (Red)** ANTES de implementar el código. Para el adaptador Camel se usa WireMock + `camel-test-spring-junit5` + StepVerifier.

---

## 4. Capa de Dominio (`domain`) — _test-first_

### Entidades

| Entidad | Campos clave | Reglas de negocio |
|---|---|---|
| `SagaInstance` | `sagaId`, `sagaType`, `state`, `currentStep`, `payload`, `correlationId` | `state` solo avanza por métodos; `COMPENSANDO` solo se alcanza desde `EN_PROGRESO` |
| `SagaStepLog` | `id`, `sagaId`, `stepName`, `status`, `compensationPayload`, `executedAt` | Inmutable tras creación; `compensationPayload` se persiste al completar cada paso exitosamente |
| `ExternalRequest` | `requestId`, `sagaId`, `systemName`, `operation`, `requestPayload`, `responsePayload`, `status` | `status` transiciona: `SENT → CONFIRMED / REJECTED / TIMEOUT` |

### Puertos secundarios (interfaces de dominio — reactivos, sin tipos de Camel)

```java
// EntidadFinancieraGateway
Mono<ConfirmacionFondeo> solicitarFondeo(SolicitudFondeo solicitud);
Mono<Void> cancelarSolicitud(String externalRequestId);
Mono<ConfirmacionPago> enviarInstruccionPago(InstruccionPago instruccion);

// ProveedorKycGateway
Mono<ResultadoKyc> validarIdentidad(DatosKyc datos);

// ListasAmlGateway
Mono<ResultadoAml> verificarContraListas(DatosAml datos);

// SagaCoordinatorPort
Mono<SagaInstance> iniciar(SagaType sagaType, UUID correlationId, Object payload);
Mono<SagaInstance> completarPaso(UUID sagaId, String stepName, Object compensationPayload);
Mono<Void> compensar(UUID sagaId, String reason);
Mono<SagaInstance> getEstado(UUID sagaId);

// SagaInstanceRepository
Mono<SagaInstance> save(SagaInstance instance);
Mono<SagaInstance> findById(UUID sagaId);
Mono<SagaInstance> findByCorrelationId(UUID correlationId);
Mono<Void> updateState(UUID sagaId, SagaState state, String currentStep);

// SagaStepLogRepository
Mono<Void> save(SagaStepLog log);
Flux<SagaStepLog> findBySagaId(UUID sagaId);

// OutboxRepository, ProcessedMessageRepository (igual que otros servicios)
```

### Invariantes de dominio

- Ningún sistema externo es accesible directamente desde otro microservicio. El `integration-service` es el único punto de acceso.
- Cada llamada a un sistema externo crea un `ExternalRequest` con `idempotency_key` en `external_requests` antes de ejecutar la llamada HTTP.
- Una saga en estado `COMPENSADA` o `COMPLETADA` no puede volver a `EN_PROGRESO`.
- `SagaStepLog` conserva el `compensationPayload` de cada paso exitoso para poder revertir en orden inverso.

---

## 5. Capa de Aplicación (`application`) — _test-first_

### Casos de uso de orquestación (uno por saga)

| Use Case | Pasos orquestados | Puerto primario | Sistemas externos |
|---|---|---|---|
| `OrquestarSagaDepositoUseCase` | 1. wallet registra PENDIENTE; 2. integration envía solicitud fondeo; 3. recibe confirmación webhook; 4. wallet confirma depósito | `IniciarSagaInputPort` | Entidad financiera |
| `OrquestarSagaRetiroUseCase` | 1. wallet reserva fondos; 2. fraud evalúa; 3a. instrucción pago (aprobado) o 3b. retención (retenido); 4. confirmación webhook; 5. wallet confirma retiro | `IniciarSagaInputPort` | Entidad financiera, fraud-service |
| `OrquestarSagaTransferenciaUseCase` | 1. wallet débito+crédito ACID; 2. fraud evalúa; 3a. confirmar (aprobado) o 3b. compensar ACID (retenido tardío) | `IniciarSagaInputPort` | fraud-service |
| `OrquestarConciliacionUseCase` | 1. obtener transacciones pendientes; 2. contrastar contra extracto externo; 3. registrar discrepancias | `IniciarSagaInputPort` | Entidad financiera |
| `CompensarSagaUseCase` | Ejecuta compensaciones en orden inverso, usando `compensationPayload` de cada paso | `CompensarSagaInputPort` | wallet-service, fraud-service |

### Flujo de Saga-Deposito (happy path)

```
wallet → POST /v1/integration/sagas (DEPOSITO)
    → integration crea SagaInstance (INICIADA)
    → Paso 1: POST /v1/wallet/deposits (wallet registra PENDIENTE) → SagaStepLog
    → Paso 2: Camel route → POST entidad-financiera/fondeo → SagaStepLog
    → Paso 3: webhook recibido CONFIRMED → validar HMAC → SagaStepLog
    → Paso 4: POST /v1/wallet/deposits/{id}/confirmar → SagaStepLog
    → SagaInstance(COMPLETADA)
```

**Fallo en paso 2/3:** disparar `CompensarSagaUseCase` → `POST /v1/wallet/deposits/{id}/compensar` → SagaInstance(COMPENSADA).

---

## 6. Capa de Infraestructura (`infrastructure`) — _test-first_

### Adaptadores Camel (implementan los `*Gateway`)

| Adaptador | Sistema externo | Ruta Camel | Resiliencia |
|---|---|---|---|
| `EntidadFinancieraCamelAdapter` | Entidad financiera | `from("direct:solicitar-fondeo").to("https4://...")` | Retry 3x backoff exponencial (Resilience4j) + CircuitBreaker |
| `ProveedorKycCamelAdapter` | Proveedor KYC | `from("direct:validar-identidad").to("https4://...")` | Retry 2x + CircuitBreaker |
| `ListasAmlCamelAdapter` | Listas AML | `from("direct:verificar-aml").to("https4://...")` | Retry 3x + timeout 10s |
| `WebhookCamelAdapter` | Webhook entrante | `from("servlet:/webhook/entidad-financiera")` | Validación HMAC antes de procesar |

**Prohibición explícita:** ningún adaptador puede usar `.block()`. El bridge reactivo Camel↔WebFlux usa `camel-reactive-streams`.

### Adaptador Narayana LRA (implementa `SagaCoordinatorPort`)

- Participa en el ciclo LRA: `@LRA`, `@Complete`, `@Compensate` en los métodos del orquestador.
- Estado de saga persiste en `saga_instance` (R2DBC) como fuente de verdad interna; Narayana LRA como coordinador externo.
- El relay de `outbox` publica eventos de saga a Kafka.

### Adaptadores R2DBC

| Adaptador | Tabla | Operaciones |
|---|---|---|
| `SagaInstanceR2dbcAdapter` | `saga_instance` | `save`, `findById`, `findByCorrelationId`, `updateState` |
| `SagaStepLogR2dbcAdapter` | `saga_step_log` | `save`, `findBySagaId` |
| `ExternalRequestR2dbcAdapter` | `external_requests` | `save`, `updateStatus` |
| `OutboxR2dbcAdapter` | `outbox` | `save` |
| `ProcessedMessageR2dbcAdapter` | `processed_message` | `existsByMessageIdAndConsumer`, `save` |

### Configuración de seguridad

- `POST /v1/integration/sagas`: requiere mTLS (invocado por `wallet-service`).
- `GET /v1/integration/sagas/{sagaId}`: requiere mTLS.
- `POST /v1/integration/sagas/{sagaId}/compensar`: requiere mTLS.
- Webhook entrante de entidad financiera: validado por HMAC-SHA256 antes de cualquier procesamiento.

---

## 7. API REST (`rest-api`) — _test-first_

Especificación completa: `docs/design/api/SDD-PagoFacil-openapi.yaml` — tags `Integration — Saga` y `Compensaciones`

| Método | Ruta | Request Body | Response | Códigos HTTP |
|---|---|---|---|---|
| POST | `/v1/integration/sagas` | `SagaIniciarRequest` | `SagaStatusResponse` | 202 |
| GET | `/v1/integration/sagas/{sagaId}` | — | `SagaStatusResponse` | 200, 404 |
| POST | `/v1/integration/sagas/{sagaId}/compensar` | `CompensacionRequest` | — | 202 |
| POST | `/v1/integration/webhook/entidad-financiera` | (Payload externo con HMAC) | — | 200, 400 |

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> Adaptadores Camel se prueban con **WireMock** + `camel-test-spring-junit5` + StepVerifier. Sagas con happy path y compensación completa. Tipos reactivos siempre con StepVerifier.

### Dominio

| Clase de test | Método | Invariante | Elemento de Sección 4 |
|---|---|---|---|
| `SagaInstanceTest` | `shouldNotTransitionFromCompletedToInProgress` | Estado final es inmutable | `SagaInstance` |
| `SagaInstanceTest` | `shouldTransitionToCompensandoFromEnProgreso` | Solo de EN_PROGRESO a COMPENSANDO | `SagaInstance` |
| `SagaStepLogTest` | `shouldPreserveCompensationPayload` | `compensationPayload` no nulo para pasos exitosos | `SagaStepLog` |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case |
|---|---|---|---|---|
| `OrquestarSagaDepositoUseCaseTest` | `shouldCompleteDepositSagaHappyPath` | Todos los pasos exitosos | `EntidadFinancieraGateway`, `SagaCoordinatorPort`, `SagaInstanceRepository` (Mockito) | `OrquestarSagaDepositoUseCase` |
| `OrquestarSagaDepositoUseCaseTest` | `shouldCompensateOnExternalRejection` | Entidad financiera rechaza → compensación | `EntidadFinancieraGateway` (mock lanza `RechazoFondeoException`) | `OrquestarSagaDepositoUseCase` |
| `OrquestarSagaRetiroUseCaseTest` | `shouldEvaluateFraudBeforePayment` | Flujo 3a: fraud aprueba | `ListasAmlGateway`, `SagaCoordinatorPort` (mock) | `OrquestarSagaRetiroUseCase` |
| `OrquestarSagaRetiroUseCaseTest` | `shouldRetainFundsOnFraudHold` | Flujo 3b: fraud retiene | `SagaCoordinatorPort` (mock retención) | `OrquestarSagaRetiroUseCase` |
| `CompensarSagaUseCaseTest` | `shouldCompensateInReverseOrder` | 3 pasos completados → 3 compensaciones en orden inverso | `SagaStepLogRepository` (mock 3 steps), compensaciones (mock) | `CompensarSagaUseCase` |

### Infraestructura — Rutas Camel (WireMock)

| Clase de test | Método | Escenario (WireMock stub) | Adaptador |
|---|---|---|---|
| `EntidadFinancieraCamelAdapterTest` | `shouldCallFondeoAndReturnConfirmation` | WireMock responde 200 con payload de confirmación | `EntidadFinancieraCamelAdapter` |
| `EntidadFinancieraCamelAdapterTest` | `shouldRetryOnTransientError` | WireMock responde 500 los primeros 2 intentos; 200 al tercero | Retry Resilience4j |
| `EntidadFinancieraCamelAdapterTest` | `shouldOpenCircuitBreakerAfterThreshold` | WireMock responde 500 > threshold → circuit abierto | CircuitBreaker Resilience4j |
| `EntidadFinancieraCamelAdapterTest` | `shouldTimeoutOnSlowResponse` | WireMock responde con delay > 10s → `TimeoutException` | Timeout configuration |
| `ProveedorKycCamelAdapterTest` | `shouldCallKycAndMapResponse` | WireMock responde con resultado KYC válido | `ProveedorKycCamelAdapter` |
| `WebhookCamelAdapterTest` | `shouldRejectInvalidHmac` | Petición con HMAC incorrecto → 400 | Validación HMAC |

### Infraestructura — Saga con Testcontainers

| Clase de test | Método | Operación | Adaptador |
|---|---|---|---|
| `SagaInstanceR2dbcAdapterTest` | `shouldSaveAndFindSagaInstance` | INSERT + SELECT con Testcontainers PostgreSQL | `SagaInstanceR2dbcAdapter` |
| `SagaStepLogR2dbcAdapterTest` | `shouldPersistCompensationPayload` | INSERT con JSONB compensation_payload | `SagaStepLogR2dbcAdapter` |
| `OutboxR2dbcAdapterTest` | `shouldPersistEventAtomically` | INSERT saga_instance + outbox en misma transacción | `OutboxR2dbcAdapter` |

### REST

| Clase de test | Método | Endpoint | Status / body | Elemento |
|---|---|---|---|---|
| `IntegrationControllerTest` | `shouldReturn202OnSagaStart` | `POST /v1/integration/sagas` | 202 + `sagaId`, `state: INICIADA` | POST sagas |
| `IntegrationControllerTest` | `shouldReturn200OnSagaStatus` | `GET /v1/integration/sagas/{sagaId}` | 200 + `state` actual | GET status |
| `IntegrationControllerTest` | `shouldReturn202OnCompensation` | `POST /v1/integration/sagas/{id}/compensar` | 202 | POST compensar |
| `IntegrationControllerTest` | `shouldReturn400OnInvalidHmacWebhook` | `POST /v1/integration/webhook/entidad-financiera` | 400 | Webhook HMAC |

### Umbrales de cobertura mínima

| Capa | Umbral |
|---|---|
| `domain` | ≥ 90% |
| `application` | ≥ 85% |
| `infrastructure` (Camel) | ≥ 80% |
| `rest-api` | ≥ 80% |

---

## 9. Criterios de Aceptación

- [ ] Cada elemento de cada capa tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] `mvn test` finaliza en verde.
- [ ] La cobertura por capa cumple los umbrales.
- [ ] La Saga-Deposito completa su happy path: wallet → integration → entidad financiera (WireMock) → confirmación → wallet confirmado.
- [ ] Ante rechazo de la entidad financiera (WireMock devuelve error), la saga ejecuta compensación: `POST /v1/wallet/deposits/{id}/compensar`.
- [ ] Las compensaciones de saga se ejecutan en orden inverso a los pasos completados.
- [ ] Los circuit breakers de Resilience4j abren ante umbrales de error de sistemas externos.
- [ ] Webhooks con HMAC inválido son rechazados con 400 antes de procesar el payload.
- [ ] Los eventos de saga se publican vía Outbox (no dual-write).
- [ ] Los endpoints de saga son accesibles solo con mTLS.
- [ ] Pipeline CI despliega en K3d: `kubectl get pods -n dev | grep integration-service` muestra `Running`.
