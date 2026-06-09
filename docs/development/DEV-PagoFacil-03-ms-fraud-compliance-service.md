# Etapa 3d — Microservicio: fraud-compliance-service

**Proyecto:** PagoFacil — Billetera Digital
**Bounded Context:** BC-03 Fraud & Compliance
**Etapa:** 3d — fraud-compliance-service
**Versión:** 1.0
**Fecha:** 2026-06-08

---

## 1. Contexto y Responsabilidad

`fraud-compliance-service` es el microservicio responsable de la detección de fraude y el cumplimiento normativo AML (Anti-Money Laundering) dentro de la plataforma PagoFacil. Actúa como guardián de todas las operaciones financieras sensibles y como proveedor de datos estructurados para reportes regulatorios (ROS/SAR).

### Responsabilidades principales

- **Evaluación AML en onboarding:** consume el evento `UserRegistered` publicado por `identity-service` y dispara una evaluación AML del nuevo usuario contra el proveedor externo (accesible vía `integration-service`).
- **Evaluación AML y antifraude en tiempo real:** responde al comando `EvaluateRisk` del `integration-service` durante la ejecución de sagas (DEPOSIT, TRANSFER, WITHDRAWAL) y devuelve el resultado de la evaluación antes de que la operación financiera continúe.
- **Gestión del ciclo de vida de alertas:** crea y gestiona alertas de cumplimiento con el ciclo `OPEN → UNDER_REVIEW → APPROVED | REJECTED | ESCALATED`.
- **Bloqueo automático:** cuando una evaluación de riesgo produce un resultado `CRITICAL`, el servicio suspende la cuenta del usuario y publica el evento `AccountSuspendedByAML`.
- **Soporte ROS/SAR:** mantiene datos estructurados de evaluaciones y alertas para la generación de reportes regulatorios por el servicio de reporting (BC-07).
- **Participante en sagas LRA:** compensa evaluaciones de riesgo mediante el endpoint `/compliance/alerts/{alertId}/compensar` cuando la saga es revertida.

### Eventos publicados

| Evento | Tópico | Descripción |
|---|---|---|
| `FraudAlertCreated` | `pagofacil.fraud.fraud-alert-created` | Nueva alerta de fraude creada tras evaluación positiva |
| `ComplianceAlertResolved` | `pagofacil.fraud.compliance-alert-resolved` | Alerta resuelta por analista u oficial de cumplimiento |
| `AccountSuspendedByAML` | `pagofacil.fraud.account-suspended-by-aml` | Cuenta suspendida automáticamente por riesgo CRITICAL |

### Puerto local

`8083`

---

## 2. Prerrequisitos

Antes de iniciar el desarrollo de esta etapa, las siguientes etapas deben estar completadas y verificadas:

| Etapa | Documento | Estado requerido |
|---|---|---|
| Etapa 0 — Infraestructura VPS | DEV-PagoFacil-00-infrastructure.md | Completada |
| Etapa 0c — Observabilidad | DEV-PagoFacil-0c-observability.md | Completada |
| Etapa 1 — Bases de datos | DEV-PagoFacil-01-databases.md | Completada |
| Etapa 2 — Scaffolding | DEV-PagoFacil-02-scaffold.md | Completada |
| Etapa 2b — CI/CD | DEV-PagoFacil-02b-cicd.md | Completada |
| Etapa 3a — identity-service | DEV-PagoFacil-03a-identity-service.md | Completada |

### Servicios VPS requeridos

| Servicio | Endpoint | Rol en esta etapa |
|---|---|---|
| PostgreSQL 16 | `<VPS_IP>:5432` | BD `pagofacil_fraud_compliance_service` |
| Apache Kafka 3 | `<VPS_IP>:29092` | Consumo de eventos y publicación vía outbox |
| LRA Coordinator (Narayana) | `<VPS_IP>:50000` | Coordinador de sagas para compensaciones |
| WireMock | `<VPS_IP>:9999` | Simulación del proveedor AML externo en pruebas |

### Secret en floci

```
pagofacil/dev/fraud-compliance-service
```

Contenido: URL de BD, credenciales, Kafka brokers, configuración del proveedor AML.

---

## 3. Ciclo de Desarrollo Incremental en K3s VPS dev

El desarrollo de `fraud-compliance-service` sigue estrictamente el ciclo TDD (Red-Green-Refactor) por cada clase de dominio, caso de uso e integración. Ninguna implementación puede existir sin un test fallido previo que la justifique.

```
┌─────────────────────────────────────────────────────────────────┐
│           CICLO TDD + DEPLOY EN K3S VPS DEV                     │
│                                                                 │
│  1. RED        Escribir test que falla                          │
│     └─────────► mvn test (FALLA - rojo)                        │
│                                                                 │
│  2. GREEN      Implementar mínimo para pasar el test            │
│     └─────────► mvn test (PASA - verde)                        │
│                                                                 │
│  3. REFACTOR   Mejorar diseño sin romper tests                  │
│     └─────────► mvn test (PASA - verde)                        │
│                                                                 │
│  4. COMMIT     git push → Jenkins pipeline                      │
│     └─────────► mvn verify + SonarQube Quality Gate            │
│                                                                 │
│  5. DEPLOY     Jenkins → docker build + push Gitea Registry     │
│     └─────────► ArgoCD sync → K3s pod restart                  │
│                                                                 │
│  6. SMOKE      curl <VPS_IP>:8083/actuator/health → UP          │
│     └─────────► Criterio de aceptación verificado              │
└─────────────────────────────────────────────────────────────────┘
```

> **TDD es obligatorio.** Todo código de producción debe estar precedido por un test rojo. Los PRs sin tests serán rechazados en el Quality Gate de SonarQube.

---

## 4. Capa de Dominio (`domain`)

### Enfoque: test-first

Cada entidad, value object y puerto se desarrolla comenzando por el test unitario. Los tests de dominio no tienen dependencias externas (sin Spring context, sin base de datos).

### 4.1 Entidades

#### `ComplianceAlert`

Representa una alerta de cumplimiento con ciclo de vida gestionado.

| Responsabilidad | Descripción |
|---|---|
| Ciclo de vida de estados | `OPEN → UNDER_REVIEW → APPROVED \| REJECTED \| ESCALATED` |
| Bloqueo automático CRITICAL | Al crear una alerta con `risk_level = CRITICAL`, el método `create()` dispara internamente el evento `AccountSuspendedByAmlEvent` |
| Invariante de resolución | Solo actores con rol `FRAUD_ANALYST` o `COMPLIANCE_OFFICER` pueden invocar `assignReviewer()` y `resolve()` |
| Idempotencia de compensación | El método `compensate()` es idempotente: si la alerta ya está `APPROVED` o `REJECTED`, no genera efecto adicional |

Métodos principales: `ComplianceAlert.create(alertType, userId, transactionId, correlationId, riskLevel, triggeredRule)`, `assignReviewer(actor)`, `resolve(actor, resolution, reason)`, `compensate()`.

#### `RiskEvaluation`

Representa el resultado de una evaluación de riesgo para una transacción o usuario.

| Campo | Tipo | Descripción |
|---|---|---|
| `evaluationType` | `EvaluationType` | `AML` o `FRAUD` |
| `result` | `EvaluationResult` | `APPROVED`, `BLOCKED` o `ESCALATED` |
| `riskLevel` | `RiskLevel` | `LOW`, `MEDIUM`, `HIGH`, `CRITICAL` |
| `triggeredRules` | `JSONB` | Lista de reglas disparadas con sus pesos |

Método principal: `RiskEvaluation.evaluate(rules, transactionContext)` — determina `result` según las reglas activas y sus umbrales; devuelve `BLOCKED` si alguna regla de tipo `CRITICAL` es disparada.

#### `FraudRule`

Representa una regla de detección de fraude configurable por tenant.

| Campo | Tipo | Descripción |
|---|---|---|
| `ruleType` | enum | `VELOCITY`, `AMOUNT_THRESHOLD`, `GEOLOCATION`, `BEHAVIORAL` |
| `parameters` | `JSONB` | Configuración específica de la regla (umbrales, ventanas de tiempo, zonas) |
| `riskLevel` | `RiskLevel` | Nivel de riesgo asignado a la regla |
| `isActive` | `boolean` | Solo reglas activas participan en evaluaciones |

Métodos: `FraudRule.matchesContext(transactionContext)` — evalúa si los `parameters` aplican al contexto de la transacción.

### 4.2 Value Objects

| Value Object | Descripción | Invariante |
|---|---|---|
| `AlertId` | Identificador único de alerta (UUID) | No nulo, formato UUID v4 |
| `CorrelationId` | Identificador de correlación distribuida (UUID) | No nulo, propagado desde API Gateway |
| `RiskLevel` | Enum `LOW`, `MEDIUM`, `HIGH`, `CRITICAL` | Solo valores del enum |
| `EvaluationType` | Enum `AML`, `FRAUD` | Solo valores del enum |

### 4.3 Eventos de Dominio

| Evento | Datos principales | Publicado cuando |
|---|---|---|
| `FraudAlertCreatedEvent` | `alertId`, `tenantId`, `userId`, `transactionId`, `riskLevel`, `correlationId` | Nueva alerta creada con cualquier `riskLevel` |
| `ComplianceAlertResolvedEvent` | `alertId`, `tenantId`, `resolution`, `resolvedBy`, `correlationId` | Alerta resuelta por analista u oficial |
| `AccountSuspendedByAmlEvent` | `userId`, `tenantId`, `alertId`, `correlationId`, `suspendedAt` | Alerta creada con `riskLevel = CRITICAL` |

### 4.4 Puertos (interfaces)

| Puerto | Método principal | Descripción |
|---|---|---|
| `ComplianceAlertRepository` | `save(alert)`, `findById(id)`, `findByCorrelationId(correlationId)`, `findAll(filters, pageable)` | Persistencia de alertas |
| `RiskEvaluationRepository` | `save(evaluation)`, `findByCorrelationId(correlationId)` | Persistencia de evaluaciones |
| `FraudRuleRepository` | `findActiveByTenant(tenantId)`, `findByRuleCode(code, tenantId)` | Acceso a reglas activas |
| `OutboxRepository` | `save(outboxMessage)` | Patrón Transactional Outbox |
| `AmlProviderPort` | `Mono<AmlResult> evaluate(AmlRequest request)` | Evaluación AML contra proveedor externo (vía integration-service o WireMock en pruebas) |

---

## 5. Capa de Aplicación (`application`)

### Enfoque: test-first

Cada caso de uso se prueba con mocks de todos sus puertos. Los tests verifican el comportamiento del orquestador, no la implementación concreta de infraestructura.

### 5.1 Casos de Uso

| Caso de Uso | Trigger | Descripción |
|---|---|---|
| `EvaluateOnboardingAmlUseCase` | Evento `UserRegistered` | Evalúa AML del nuevo usuario al completar el registro |
| `EvaluateTransactionRiskUseCase` | Comando `EvaluateRisk` (REST/Kafka desde integration-service) | Evalúa riesgo de fraude y AML para una transacción en curso |
| `GetComplianceAlertsUseCase` | `GET /compliance/alerts` | Retorna lista paginada de alertas con filtros |
| `GetAlertDetailUseCase` | `GET /compliance/alerts/{alertId}` | Retorna detalle de una alerta específica |
| `ResolveComplianceAlertUseCase` | `PUT /compliance/alerts/{alertId}/resolve` | Resuelve una alerta con decisión del analista u oficial |
| `CompensateRiskEvaluationUseCase` | `POST /compliance/alerts/{alertId}/compensar` | Compensación idempotente de una evaluación de riesgo en saga revertida |
| `ProcessUserRegisteredEventUseCase` | Consumidor Kafka `pagofacil.identity.user-registered` | Idempotencia y orquestación del flujo AML de onboarding |

### 5.2 DTOs

| DTO | Campos | Dirección |
|---|---|---|
| `RiskEvaluationRequest` | `tenantId`, `userId`, `transactionId`, `correlationId`, `evaluationType`, `amount`, `currency` | Entrada (desde integration-service) |
| `RiskEvaluationResponse` | `result`, `riskLevel`, `correlationId`, `triggeredRules`, `evaluatedAt` | Salida |
| `AlertResponse` | `alertId`, `alertType`, `userId`, `riskLevel`, `status`, `triggeredRule`, `correlationId`, `createdAt`, `updatedAt` | Salida |
| `ResolveAlertRequest` | `resolution` (`APPROVED`\|`REJECTED`\|`ESCALATED`), `reason`, `actor` | Entrada |
| `CompensationRequest` | `correlationId`, `alertId`, `requestedBy` | Entrada (saga compensación) |

---

## 6. Capa de Infraestructura (`infrastructure`)

### Enfoque: test-first con Testcontainers

Los tests de infraestructura levantan contenedores reales (PostgreSQL, Kafka) usando Testcontainers. No se usan mocks para persistencia en esta capa.

### 6.1 Repositorios R2DBC

#### `ComplianceAlertR2dbcRepository`

Implementación de `ComplianceAlertRepository` con Spring Data R2DBC.

| Operación | Descripción |
|---|---|
| `save(alert)` | Inserta o actualiza la alerta en la tabla `compliance_alerts` |
| `findById(alertId)` | Búsqueda por PK con `Mono<ComplianceAlert>` |
| `findByCorrelationId(correlationId)` | Búsqueda por `correlation_id` para idempotencia |
| `findAll(filters, pageable)` | Consulta paginada con filtros dinámicos por `status`, `risk_level`, `alert_type`, `tenant_id` |

Implementaciones análogas: `RiskEvaluationR2dbcRepository`, `FraudRuleR2dbcRepository`, `OutboxR2dbcRepository`.

### 6.2 Consumidores Kafka

#### `UserRegisteredEventConsumer`

| Propiedad | Valor |
|---|---|
| Tópico | `pagofacil.identity.user-registered` |
| Group ID | `fraud-compliance-service` |
| Idempotencia | Verifica `processed_message` antes de procesar; inserta el `messageId` en la misma transacción |
| Manejo de error | Dead Letter Topic `pagofacil.identity.user-registered.dlt` tras 3 reintentos |
| Delegación | Invoca `ProcessUserRegisteredEventUseCase` → `EvaluateOnboardingAmlUseCase` |

#### `EvaluateRiskCommandConsumer` (alternativa Kafka al endpoint REST)

| Propiedad | Valor |
|---|---|
| Tópico | `pagofacil.integration.evaluate-risk` (comando desde integration-service) |
| Group ID | `fraud-compliance-service` |
| Idempotencia | Verifica `processed_message` por `correlationId` |
| Delegación | Invoca `EvaluateTransactionRiskUseCase` y publica resultado de vuelta |

### 6.3 Productor Kafka — Outbox Relay

El servicio implementa el patrón **Transactional Outbox**. Los eventos de dominio se escriben en la tabla `outbox` en la misma transacción de negocio. Un relay (scheduler o CDC) lee la tabla `outbox` y publica los mensajes pendientes en los tópicos Kafka correspondientes.

| Tópico destino | Evento |
|---|---|
| `pagofacil.fraud.fraud-alert-created` | `FraudAlertCreatedEvent` |
| `pagofacil.fraud.compliance-alert-resolved` | `ComplianceAlertResolvedEvent` |
| `pagofacil.fraud.account-suspended-by-aml` | `AccountSuspendedByAmlEvent` |

### 6.4 Spring Security

| Aspecto | Configuración |
|---|---|
| Mecanismo de autenticación | JWT Bearer Token (emitido por identity-service / Cognito) |
| Roles permitidos — gestión de alertas | `FRAUD_ANALYST`, `COMPLIANCE_OFFICER` |
| Endpoints protegidos | `GET /compliance/alerts`, `GET /compliance/alerts/{id}`, `PUT /compliance/alerts/{id}/resolve` |
| Endpoint de compensación | Solo accesible desde `integration-service` con scope `service:internal` o rol `SYSTEM` |
| Endpoint de evaluación (REST) | Accesible desde `integration-service` con scope `service:internal` |

---

## 7. API REST (`rest-api`)

### Enfoque: test-first con WebTestClient

Los tests de la capa REST verifican códigos de estado, estructura del body y comportamiento ante roles incorrectos. Se usa `@WebFluxTest` con mocks de los casos de uso.

### Tabla de Endpoints

| Método | Ruta | Request | Response | Códigos |
|---|---|---|---|---|
| `GET` | `/compliance/alerts` | Query params: `status`, `risk_level`, `alert_type`, `page`, `size` | `Page<AlertResponse>` | `200 OK`, `403 Forbidden` |
| `GET` | `/compliance/alerts/{alertId}` | Path param: `alertId` (UUID) | `AlertResponse` | `200 OK`, `403 Forbidden`, `404 Not Found` |
| `PUT` | `/compliance/alerts/{alertId}/resolve` | Body: `ResolveAlertRequest` | `AlertResponse` actualizada | `200 OK`, `403 Forbidden`, `404 Not Found`, `422 Unprocessable Entity` |
| `POST` | `/compliance/alerts/{alertId}/compensar` | Body: `CompensationRequest` | `AlertResponse` (estado post-compensación) | `200 OK` (idempotente) |

### Notas de diseño

- `GET /compliance/alerts` requiere al menos uno de los roles `FRAUD_ANALYST` o `COMPLIANCE_OFFICER`. Sin rol adecuado retorna `403`.
- `PUT /compliance/alerts/{alertId}/resolve` retorna `422` si la alerta ya está en estado terminal (`APPROVED`, `REJECTED`) y se intenta resolver nuevamente, excepto `ESCALATED`.
- `POST /compliance/alerts/{alertId}/compensar` es idempotente: si la compensación ya fue aplicada, retorna `200` con el estado actual sin efecto secundario adicional.

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> Todos los tests reactivos usan `StepVerifier`. Está **prohibido** usar `block()` en cualquier test de producción o prueba.

### 8.1 Capa de Dominio

| Clase de Test | Nombre del Test | Escenario | Método bajo prueba |
|---|---|---|---|
| `ComplianceAlertTest` | `shouldAutomaticallyBlockWhenCriticalRisk` | Crear alerta con `riskLevel = CRITICAL` debe emitir `AccountSuspendedByAmlEvent` | `ComplianceAlert.create()` |
| `ComplianceAlertTest` | `shouldTransitionFromOpenToUnderReview` | Llamar `assignReviewer()` en estado `OPEN` debe pasar a `UNDER_REVIEW` | `ComplianceAlert.assignReviewer()` |
| `ComplianceAlertTest` | `shouldRejectTransitionFromApprovedToUnderReview` | Intentar `assignReviewer()` desde estado `APPROVED` debe lanzar excepción de dominio | `ComplianceAlert.assignReviewer()` |
| `RiskEvaluationTest` | `shouldReturnBlockedForCriticalRule` | Si `triggeredRules` contiene una regla `CRITICAL`, `result` debe ser `BLOCKED` | `RiskEvaluation.evaluate()` |
| `RiskEvaluationTest` | `shouldReturnApprovedWhenNoRulesTriggered` | Sin reglas disparadas, `result` debe ser `APPROVED` y `riskLevel = LOW` | `RiskEvaluation.evaluate()` |
| `FraudRuleTest` | `shouldMatchContextWhenAmountExceedsThreshold` | Regla `AMOUNT_THRESHOLD` con umbral 1000 debe activarse para monto 1500 | `FraudRule.matchesContext()` |

### 8.2 Capa de Aplicación

| Clase de Test | Nombre del Test | Criterio de Aceptación | Dependencias mockeadas |
|---|---|---|---|
| `EvaluateTransactionRiskUseCaseTest` | `shouldReturnApproved_whenNoRulesTriggered` | Happy path: ninguna regla disparada → `result = APPROVED` | `FraudRuleRepository`, `AmlProviderPort` |
| `EvaluateTransactionRiskUseCaseTest` | `shouldReturnBlocked_whenCriticalRuleTriggered` | AC-007-E1: regla CRITICAL disparada → `result = BLOCKED`, alerta CRITICAL creada | `FraudRuleRepository`, `AmlProviderPort`, `ComplianceAlertRepository` |
| `EvaluateTransactionRiskUseCaseTest` | `shouldPublishOutboxEvent_afterAlertCreation` | Tras crear alerta, `OutboxRepository.save()` debe ser invocado exactamente una vez | `OutboxRepository` |
| `ResolveAlertUseCaseTest` | `shouldResolveAlert_whenOfficialApproves` | AC-007-S1: Oficial aprueba alerta `UNDER_REVIEW` → estado `APPROVED`, evento `ComplianceAlertResolvedEvent` en outbox | `ComplianceAlertRepository` |
| `ResolveAlertUseCaseTest` | `shouldReturn422_whenAlertAlreadyApproved` | Alerta en `APPROVED` → error de dominio propagado | `ComplianceAlertRepository` |
| `CompensateRiskEvaluationUseCaseTest` | `shouldBeIdempotent_whenCalledTwice` | Compensación aplicada dos veces → mismo estado, sin efectos duplicados, `OutboxRepository` invocado una sola vez | `ComplianceAlertRepository`, `OutboxRepository` |

### 8.3 Capa de Infraestructura

| Clase de Test | Nombre del Test | Descripción |
|---|---|---|
| `ComplianceAlertR2dbcRepositoryTest` | `shouldPersistAndFindByCorrelationId` | Testcontainers PostgreSQL: `save()` + `findByCorrelationId()` retorna la alerta guardada |
| `ComplianceAlertR2dbcRepositoryTest` | `shouldReturnEmptyWhenCorrelationIdNotFound` | `findByCorrelationId()` con ID inexistente retorna `Mono.empty()` |
| `UserRegisteredEventConsumerTest` | `shouldEvaluateAmlOnUserRegistered` | Testcontainers Kafka: mensaje en tópico `pagofacil.identity.user-registered` dispara `EvaluateOnboardingAmlUseCase` |
| `UserRegisteredEventConsumerTest` | `shouldBeIdempotent_whenSameMessageIdReceived` | Mismo `messageId` consumido dos veces → `EvaluateOnboardingAmlUseCase` invocado solo una vez |
| `OutboxRelayTest` | `shouldPublishPendingOutboxMessages` | Testcontainers PostgreSQL + Kafka: relay publica mensajes `PENDING` del outbox al tópico correcto |

### 8.4 Capa REST

| Clase de Test | Nombre del Test | Descripción |
|---|---|---|
| `AlertControllerTest` | `shouldReturn200_whenAnalystGetsAlerts` | `FRAUD_ANALYST` llama `GET /compliance/alerts` → `200 OK` con lista paginada |
| `AlertControllerTest` | `shouldReturn403_whenUserLacksRole` | Usuario sin rol adecuado llama `GET /compliance/alerts` → `403 Forbidden` |
| `AlertControllerTest` | `shouldReturn404_whenAlertNotFound` | `GET /compliance/alerts/{unknownId}` → `404 Not Found` |
| `AlertControllerTest` | `shouldReturn422_whenAlertAlreadyResolved` | `PUT /compliance/alerts/{id}/resolve` sobre alerta ya `APPROVED` → `422 Unprocessable Entity` |
| `CompensationControllerTest` | `shouldReturn200_whenCompensationIsIdempotent` | `POST /compliance/alerts/{id}/compensar` dos veces → ambas retornan `200 OK` con mismo estado |

### 8.5 Umbrales de Cobertura

| Capa | Cobertura mínima |
|---|---|
| `domain` | ≥ 90 % |
| `application` | ≥ 85 % |
| `infrastructure` | ≥ 75 % |
| `rest-api` | ≥ 80 % |

---

## 9. Criterios de Aceptación

### TDD

- [ ] Cada clase de dominio (`ComplianceAlert`, `RiskEvaluation`, `FraudRule`) tiene al menos tres tests unitarios escritos antes de la implementación (ciclo Red-Green-Refactor documentado en commits).
- [ ] Cada caso de uso tiene al menos un test con `StepVerifier` que verifica el happy path y al menos un test que verifica el camino de error.
- [ ] `mvn test` ejecuta sin errores y todos los tests pasan en verde.
- [ ] `mvn verify` (con perfil de integración) ejecuta los tests de Testcontainers sin errores.
- [ ] SonarQube Quality Gate reporta `PASSED` con los umbrales de cobertura de la sección 8.5 cumplidos.

### Funcionales

- [ ] Una evaluación con `riskLevel = CRITICAL` genera automáticamente una alerta en estado `OPEN` y publica el evento `AccountSuspendedByAML` al tópico `pagofacil.fraud.account-suspended-by-aml` vía outbox.
- [ ] El endpoint `POST /compliance/alerts/{alertId}/compensar` es idempotente: llamado dos veces con el mismo `alertId` retorna `200` con el mismo estado y sin efectos duplicados en la base de datos ni en Kafka.
- [ ] Solo usuarios con rol `FRAUD_ANALYST` o `COMPLIANCE_OFFICER` pueden resolver alertas. Cualquier otro rol recibe `403 Forbidden`.
- [ ] El evento `UserRegistered` consumido del tópico `pagofacil.identity.user-registered` desencadena la evaluación AML del nuevo usuario. El resultado queda registrado en la tabla `risk_evaluations`.
- [ ] El consumidor Kafka de `UserRegistered` es idempotente: si el mismo `messageId` llega dos veces, la evaluación AML se ejecuta solo una vez (verificado con la tabla `processed_message`).
- [ ] Los tópicos `pagofacil.fraud.*` reciben los mensajes correctos tras cada operación relevante (verificado con Testcontainers Kafka).
- [ ] `curl http://<VPS_IP>:8083/actuator/health` retorna `{"status":"UP"}` tras el despliegue en K3s.
- [ ] ArgoCD reporta el pod de `fraud-compliance-service` en estado `Synced` y `Healthy`.
- [ ] El servicio participa correctamente en los tres flujos de saga: DEPOSIT (paso 2), TRANSFER (paso 2) y WITHDRAWAL (paso 3). Las compensaciones son invocadas por el `integration-service` sin errores cuando la saga es revertida.
- [ ] Los datos de alertas y evaluaciones están disponibles con la estructura correcta para consumo por `reporting-projection-service` (campos `tenant_id`, `correlation_id`, `risk_level`, `status` presentes y no nulos).
