# Etapa 3f — Microservicio: audit-service

**Proyecto:** PagoFacil — Billetera Digital
**Bounded Context:** BC-06 Audit
**Puerto local:** 8086
**Base de datos:** MongoDB 7 `pagofacil_audit_service` (append-only)
**Patrón:** Consumidor Kafka puro + almacenamiento inmutable

---

## 1. Contexto y Responsabilidad

El `audit-service` es el repositorio de trazabilidad del sistema. Consume pasivamente **todos** los tópicos de dominio de Kafka y almacena trazas inmutables en MongoDB. **Nunca produce eventos de dominio y no participa en sagas.** Solo los roles `ADMIN` y `COMPLIANCE_OFFICER` pueden consultar las trazas.

### Responsabilidades

- Ingesta y almacenamiento inmutable de trazas de todos los eventos de negocio.
- Registro con actor, acción, timestamp, IP de origen y correlationId.
- Dashboard de consulta filtrada (actor, eventType, correlationId, sagaId, período, tenant).
- Sin UPDATE ni DELETE en MongoDB: modo append-only estricto.

### Dependencias de infraestructura

| Recurso | Detalles |
|---|---|
| MongoDB 7 | `pagofacil_audit_service` en `VPS_IP:27017` |
| Kafka | `VPS_IP:29092` — consumer de todos los tópicos de dominio |
| Secret | `pagofacil/dev/audit-service` en floci `VPS_IP:4566` |

### Dependencias REST

| Dirección | Servicio | Propósito |
|---|---|---|
| Entrante | API Gateway | Consulta de trazas (solo ADMIN, COMPLIANCE_OFFICER) |
| Saliente | Ninguna | Servicio pasivo de ingesta |

---

## 2. Prerrequisitos

- [ ] Etapas 0, 0c, 1, 2, 2b completadas.
- [ ] Todos los microservicios de dominio (3a–3e) generando eventos en Kafka.
- [ ] MongoDB `pagofacil_audit_service` disponible en `VPS_IP:27017`.
- [ ] Colección `audit_traces` creada con validador JSON Schema (ver `SDD-PagoFacil-collections.js`).
- [ ] Secret `pagofacil/dev/audit-service` presente en floci `VPS_IP:4566`.

---

## 3. Ciclo de Desarrollo Incremental en K3s VPS dev

Con la Etapa 2b completada, cada commit despliega automáticamente en K3s via ArgoCD.

**Condición mínima para el primer despliegue:** Spring arranca, `/actuator/health/readiness` responde `UP`, MongoDB accesible.

```
Implementar caso de uso → mvn test (local) → git push → Jenkins pipeline
→ push Gitea registry → bumpImageTag → ArgoCD sync → K3s VPS → servicio disponible
```

> **TDD obligatorio — cada prueba de la Sección 8 se escribe y se ve FALLAR (Red) antes del código de producción (Green). Tipos reactivos con StepVerifier, NUNCA con `block()`.**

---

## 4. Capa de Dominio (`domain`) — test-first

### Entidad `AuditTrace`

**Campos requeridos:** `eventType`, `actor`, `action`, `tenantId`, `correlationId`, `ipAddress`, `timestamp`

**Campos opcionales:** `traceId` (UUID v4 único, generado al crear), `actorRole` (USER\|ADMIN\|FRAUD_ANALYST\|COMPLIANCE_OFFICER\|SYSTEM\|EXTERNAL_SYSTEM), `userId`, `resourceType`, `resourceId`, `sagaId`, `userAgent`, `metadata`, `sourceService`

**Invariantes críticos:**
- `AuditTrace` es INMUTABLE tras creación (sin setters después de construcción).
- `traceId` es único — garantía de idempotencia en inserción.
- Campos PII en `metadata` deben ser enmascarados antes de persistir (email → `***@domain.com`, nombre → `***`).
- `timestamp` es inmutable — no se puede modificar tras inserción.

### Value Objects

`TraceId` (UUID v4), `CorrelationId`, `SagaId`, `ActorRole` (enum), `TenantId`

### Puertos secundarios

```java
// Solo INSERT — sin update ni delete
Mono<Void> AuditTraceRepository.save(AuditTrace trace);
Flux<AuditTrace> AuditTraceRepository.findByFilter(AuditTraceFilter filter, Pageable pageable);
Mono<AuditTrace> AuditTraceRepository.findByTraceId(String traceId);
Mono<Long> AuditTraceRepository.countByFilter(AuditTraceFilter filter);
```

---

## 5. Capa de Aplicación (`application`) — test-first

### Casos de uso

| Use Case | Descripción | Puerto primario | Puerto secundario |
|---|---|---|---|
| `IngestAuditTraceUseCase` | Recibe evento de dominio → construye `AuditTrace` → enmascara PII → persiste | Kafka Consumer (entry-point) | `AuditTraceRepository` |
| `GetAuditTracesUseCase` | Consulta paginada con filtros (userId, eventType, correlationId, sagaId, tenantId, from, to) | REST `GET /audit/traces` | `AuditTraceRepository` |
| `GetTraceDetailUseCase` | Consulta detalle por traceId | REST `GET /audit/traces/{traceId}` | `AuditTraceRepository` |

### DTOs

`AuditTraceResponse` (todos los campos excepto PII sin enmascarar), `AuditTraceFilter` (userId, eventType, correlationId, sagaId, tenantId, from, to), `PagedAuditTracesResponse` (content, page, size, totalElements).

---

## 6. Capa de Infraestructura (`infrastructure`) — test-first

### Adaptador MongoDB

| Adaptador | Colección | Operaciones |
|---|---|---|
| `AuditTraceMongoRepository` | `audit_traces` | insertOne (solo insert, nunca update/delete), find con filtros combinados, findOne por traceId, countDocuments |

Usa Spring Data Reactive MongoDB (`ReactiveMongoTemplate` o `@ReactiveMongoRepository`).
Índice único en `traceId` — la inserción duplicada lanza `DuplicateKeyException` (garantía de idempotencia).

### Consumidores Kafka (multi-topic)

Un consumidor genérico `DomainEventToAuditTraceConsumer` con un mapper por tipo de evento:

| Tópico | eventType en trace |
|---|---|
| `pagofacil.identity.user-registered` | `USER_REGISTERED` |
| `pagofacil.identity.kyc-approved` | `KYC_APPROVED` |
| `pagofacil.identity.kyc-rejected` | `KYC_REJECTED` |
| `pagofacil.identity.account-suspended-by-aml` | `ACCOUNT_SUSPENDED_BY_AML` |
| `pagofacil.wallet.wallet-created` | `WALLET_CREATED` |
| `pagofacil.wallet.deposit-completed` | `DEPOSIT_COMPLETED` |
| `pagofacil.wallet.transfer-completed` | `TRANSFER_COMPLETED` |
| `pagofacil.wallet.withdrawal-completed` | `WITHDRAWAL_COMPLETED` |
| `pagofacil.fraud.fraud-alert-created` | `FRAUD_ALERT_CREATED` |
| `pagofacil.fraud.compliance-alert-resolved` | `COMPLIANCE_ALERT_RESOLVED` |
| `pagofacil.fraud.account-suspended-by-aml` | `ACCOUNT_SUSPENDED_BY_AML` |

Idempotencia: el índice único en `traceId` previene la inserción duplicada. Si `DuplicateKeyException` → log warning y continúa sin error.

### Spring Security

JWT Bearer; solo `ADMIN` y `COMPLIANCE_OFFICER` pueden acceder a los endpoints REST.

---

## 7. API REST (`rest-api`) — test-first

| Método | Ruta | Query Params | Response | Códigos HTTP |
|---|---|---|---|---|
| GET | `/audit/traces` | `userId`, `eventType`, `correlationId`, `sagaId`, `tenantId`, `from` (ISO), `to` (ISO), `page`, `size` | `PagedAuditTracesResponse` | 200, 400, 403 |
| GET | `/audit/traces/{traceId}` | — | `AuditTraceResponse` | 200, 403, 404 |
| GET | `/actuator/health/readiness` | — | `{status: UP}` | 200 |
| GET | `/actuator/prometheus` | — | métricas | 200 |

Especificación completa: `docs/design/api/SDD-PagoFacil-openapi.yaml` (tag: Audit).

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> **Regla:** cada prueba se escribe y se ve **FALLAR (Red)** antes del código de producción. StepVerifier para tipos reactivos, nunca `block()`.

### Dominio

| Clase de test | Método | Invariante / Regla | Elemento de Sección 4 que precede |
|---|---|---|---|
| `AuditTraceTest` | `shouldBuildTraceWithAllRequiredFields` | Todos los campos requeridos presentes | `AuditTrace` constructor |
| `AuditTraceTest` | `shouldFailConstruction_whenRequiredFieldMissing` | `eventType` nulo → `IllegalArgumentException` | `AuditTrace` constructor |
| `AuditTraceTest` | `shouldMaskEmailInMetadata` | email en metadata → `***@domain.com` | `AuditTrace.maskPii()` |
| `AuditTraceTest` | `shouldGenerateUniqueTraceIdOnCreation` | `traceId` generado automáticamente (UUID v4) | `AuditTrace` factory method |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case que precede |
|---|---|---|---|---|
| `IngestAuditTraceUseCaseTest` | `shouldPersistTrace_whenValidEventReceived` | Happy path | `AuditTraceRepository` (mock) | `IngestAuditTraceUseCase` |
| `IngestAuditTraceUseCaseTest` | `shouldBeIdempotent_whenSameTraceIdReceived` | `DuplicateKeyException` → sin error | `AuditTraceRepository` lanza excepción | `IngestAuditTraceUseCase` |
| `GetAuditTracesUseCaseTest` | `shouldReturnPagedTraces_withFilters` | Happy path con filtros | `AuditTraceRepository` (mock) | `GetAuditTracesUseCase` |
| `GetTraceDetailUseCaseTest` | `shouldReturn404_whenTraceNotFound` | `traceId` inexistente | `AuditTraceRepository` devuelve `Mono.empty()` | `GetTraceDetailUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador que precede |
|---|---|---|---|
| `AuditTraceMongoRepositoryTest` | `shouldInsertAndFindByCorrelationId` | Insert + find | `AuditTraceMongoRepository` (Testcontainers MongoDB) |
| `AuditTraceMongoRepositoryTest` | `shouldPreventDuplicateTraceId` | Índice único en `traceId` | `AuditTraceMongoRepository` |
| `DomainEventConsumerTest` | `shouldMapKafkaEventToAuditTrace_forEachTopic` | Mapeo evento → trace | `DomainEventToAuditTraceConsumer` (Testcontainers Kafka) |

### REST

| Clase de test | Método | Endpoint + status | Elemento Sección 7 que precede |
|---|---|---|---|
| `AuditControllerTest` | `shouldReturn200WithPagedTraces` | `GET /audit/traces` → 200 con content | `GET /audit/traces` endpoint |
| `AuditControllerTest` | `shouldReturn403_whenUserLacksAuditRole` | `GET /audit/traces` con role USER → 403 | Autorización por rol |
| `AuditControllerTest` | `shouldReturn200_whenCorrelationIdFilterApplied` | `GET /audit/traces?correlationId=...` → 200 | Filtro por correlationId |
| `AuditControllerTest` | `shouldReturn404_whenTraceNotFound` | `GET /audit/traces/{id}` inexistente → 404 | `GET /audit/traces/{traceId}` endpoint |

### Umbrales de cobertura

| Capa | Umbral mínimo |
|---|---|
| `domain` | ≥ 90% |
| `application` | ≥ 85% |
| `infrastructure` | ≥ 75% |
| `rest-api` | ≥ 80% |

---

## 9. Criterios de Aceptación

### TDD

- [ ] Cada entidad y use case tuvo su prueba escrita y vista fallar (Red) antes del código de producción (Green).
- [ ] `mvn test` finaliza en verde; sin `block()` en código de pruebas.
- [ ] Cobertura por capa cumple los umbrales declarados.
- [ ] No hay consumer Kafka ni endpoint sin prueba asociada.

### Funcionales

- [ ] Evento Kafka de cualquier tópico de dominio → traza inmutable insertada en MongoDB `pagofacil_audit_service`.
- [ ] `traceId` único: reinserción del mismo evento (misma clave) → no genera duplicado (idempotencia).
- [ ] PII en `metadata` (email, nombre) está enmascarado antes de la inserción.
- [ ] Solo `ADMIN` y `COMPLIANCE_OFFICER` pueden acceder a `GET /audit/traces`.
- [ ] Filtros por `correlationId`, `sagaId`, `userId`, `eventType` y rango de fechas funcionan correctamente.
- [ ] MongoDB rechaza UPDATE y DELETE sobre `audit_traces` (validador `strict`).
- [ ] Servicio arranca y `/actuator/health/readiness` responde `UP` en K3s VPS.
- [ ] ArgoCD muestra el app en estado `Synced` tras el pipeline CI.
