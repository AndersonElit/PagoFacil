# Etapa 3c — Microservicio: notification-service

**Proyecto:** PagoFacil — Billetera Digital
**Bounded Context:** BC-04 Notification
**Puerto local:** 8084
**Base de datos:** PostgreSQL `pagofacil_notification_service`
**Patrón:** Consumidor Kafka puro + delegación de envío físico al integration-service

---

## 1. Contexto y Responsabilidad

El `notification-service` es el servicio de notificaciones reactivo del sistema. **No expone endpoints al API Gateway** (es un servicio interno). Recibe eventos de dominio desde Kafka y delega el envío físico (SMS/email) al `integration-service` vía REST interno.

### Responsabilidades

- Envío de confirmaciones de operaciones financieras (depósito, transferencia, retiro).
- Envío de códigos MFA (OTP, TOTP) bajo solicitud del `identity-service`.
- Notificaciones de resultado KYC, alertas de seguridad y cambios de estado de cuenta.
- Gestión de preferencias de canal por usuario y tenant.
- Delegación del envío físico (SMS/email) al proveedor externo a través del `integration-service`.

### Dependencias de infraestructura

| Recurso | Detalles |
|---|---|
| PostgreSQL | `pagofacil_notification_service` en `VPS_IP:5432` |
| Kafka | `VPS_IP:29092` — consumer de múltiples tópicos |
| integration-service | REST interno `http://integration-service:8085` para envío físico |
| Secret | `pagofacil/dev/notification-service` en floci `VPS_IP:4566` |

### Dependencias REST

| Dirección | Servicio | Propósito |
|---|---|---|
| Saliente | integration-service `:8085` | Delegación de envío físico SMS/email |
| Entrante | Ninguna vía API Gateway | Servicio interno puro |

---

## 2. Prerrequisitos

- [ ] Etapas 0, 0c, 1, 2, 2b completadas.
- [ ] Etapa 3a (`identity-service`) funcional — genera eventos que se consumen aquí.
- [ ] PostgreSQL `pagofacil_notification_service` creado y migraciones aplicadas.
- [ ] Kafka activo en `VPS_IP:29092`.
- [ ] WireMock en `VPS_IP:9999` para simular `integration-service` en pruebas de integración.
- [ ] Secret `pagofacil/dev/notification-service` presente en floci `VPS_IP:4566`.

---

## 3. Ciclo de Desarrollo Incremental en K3s VPS dev

Con la Etapa 2b completada, cada commit que pasa el pipeline CI despliega automáticamente el servicio en K3s via ArgoCD.

**Condición mínima para el primer despliegue:** Spring arranca sin errores, `/actuator/health/readiness` responde `UP`, secret `pagofacil/dev/notification-service` existe en floci.

```
Implementar caso de uso → mvn test (local) → git push → Jenkins pipeline
→ push Gitea registry → bumpImageTag → ArgoCD sync → K3s VPS → servicio disponible
```

> **TDD obligatorio — cada prueba de la Sección 8 se escribe y se ve FALLAR (Red) antes de implementar el código de producción (Green), seguido de Refactor. Los tipos reactivos se verifican con StepVerifier, NUNCA con `block()`.**

---

## 4. Capa de Dominio (`domain`) — test-first

### Entidades

| Entidad | Campos clave | Reglas de negocio |
|---|---|---|
| `Notification` | id, user_id, tenant_id, channel, template_code, destination, subject, body, status (PENDING→SENT\|FAILED), correlation_id, sent_at | Transición de estado PENDING→SENT\|FAILED; body generado desde template |
| `NotificationTemplate` | id, tenant_id, template_code, channel (EMAIL\|SMS\|PUSH), subject, body_template, is_active | body_template con variables `{{nombre}}` reemplazadas; validación de variables requeridas |
| `NotificationPreference` | user_id, tenant_id, event_type, preferred_channel, is_enabled | Canal preferido por usuario y tipo de evento |

### Value Objects

`NotificationId`, `TemplateCode`, `Channel` (EMAIL\|SMS\|PUSH), `Destination` (email o número E.164), `CorrelationId`

### Puertos secundarios

```java
// Repository ports
Mono<Void> NotificationRepository.save(Notification)
Flux<Notification> NotificationRepository.findByUserId(UUID userId, UUID tenantId)
Mono<NotificationTemplate> NotificationTemplateRepository.findByCodeAndChannel(String code, Channel channel)
Mono<NotificationPreference> NotificationPreferenceRepository.findByUserAndEventType(UUID userId, String eventType)

// Sending port (delegado al integration-service)
Mono<Void> NotificationSenderPort.send(NotificationRequest)
```

---

## 5. Capa de Aplicación (`application`) — test-first

### Casos de uso

| Use Case | Descripción | Puerto primario | Puerto secundario |
|---|---|---|---|
| `ProcessNotificationEventUseCase` | Procesa cualquier evento de dominio → selecciona plantilla → construye `Notification` → delega envío | Kafka Consumer (entry-point) | `NotificationTemplateRepository`, `NotificationPreferenceRepository`, `NotificationSenderPort`, `NotificationRepository` |
| `SendDepositConfirmationUseCase` | Notifica depósito completado | Kafka (`pagofacil.wallet.deposit-completed`) | Todos los puertos |
| `SendTransferConfirmationUseCase` | Notifica transferencia completada | Kafka (`pagofacil.wallet.transfer-completed`) | Todos los puertos |
| `SendWithdrawalConfirmationUseCase` | Notifica retiro completado | Kafka (`pagofacil.wallet.withdrawal-completed`) | Todos los puertos |
| `SendKycResultUseCase` | Notifica aprobación o rechazo KYC | Kafka (`pagofacil.identity.kyc-approved`, `kyc-rejected`) | Todos los puertos |
| `SendAlertNotificationUseCase` | Notifica alerta de fraude/AML | Kafka (`pagofacil.fraud.fraud-alert-created`) | Todos los puertos |

### DTOs

`NotificationEventRequest` (userId, tenantId, eventType, correlationId, params: Map<String,String>), `NotificationRecord` (id, status, sentAt).

---

## 6. Capa de Infraestructura (`infrastructure`) — test-first

### Adaptadores R2DBC

| Adaptador | Tabla | Operaciones |
|---|---|---|
| `NotificationR2dbcRepository` | `notifications` | save, findByUserId+tenantId (paginado), updateStatus |
| `NotificationTemplateR2dbcRepository` | `notification_templates` | findByCodeAndChannel, findActiveByTenant |
| `NotificationPreferenceR2dbcRepository` | `notification_preferences` | findByUserAndEventType, upsert |
| `ProcessedMessageR2dbcRepository` | `processed_message` | checkAndInsert (idempotencia) |

### Consumidores Kafka

| Consumer | Tópico | Use Case invocado |
|---|---|---|
| `KycApprovedEventConsumer` | `pagofacil.identity.kyc-approved` | `SendKycResultUseCase` |
| `KycRejectedEventConsumer` | `pagofacil.identity.kyc-rejected` | `SendKycResultUseCase` |
| `DepositCompletedConsumer` | `pagofacil.wallet.deposit-completed` | `SendDepositConfirmationUseCase` |
| `TransferCompletedConsumer` | `pagofacil.wallet.transfer-completed` | `SendTransferConfirmationUseCase` |
| `WithdrawalCompletedConsumer` | `pagofacil.wallet.withdrawal-completed` | `SendWithdrawalConfirmationUseCase` |
| `FraudAlertCreatedConsumer` | `pagofacil.fraud.fraud-alert-created` | `SendAlertNotificationUseCase` |
| `AccountSuspendedConsumer` | `pagofacil.fraud.account-suspended-by-aml` | `SendAlertNotificationUseCase` |

Todos los consumers verifican `processed_message` antes de procesar (idempotencia).

### NotificationSenderAdapter

Implementa `NotificationSenderPort` via WebClient apuntando a `integration-service`:
- `POST http://integration-service:8085/internal/notifications/send`
- Resilience4j retry (3 intentos, backoff exponencial).

### Spring Security

JWT Bearer con scope `service:internal`; no acceso de usuarios finales al puerto HTTP del servicio.

---

## 7. API REST (`rest-api`) — test-first

Este servicio **no expone endpoints de negocio** al API Gateway. Solo expone los endpoints de actuator:

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/actuator/health/readiness` | Readiness probe para K3s |
| GET | `/actuator/health/liveness` | Liveness probe |
| GET | `/actuator/prometheus` | Métricas Prometheus (scrape automático) |
| GET | `/actuator/info` | Información del servicio |

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> **Regla:** cada prueba se escribe y se ve **FALLAR (Red)** antes de escribir el código de producción que la hace **PASAR (Green)**. Seguido de **Refactor**. Los tipos reactivos se verifican con **StepVerifier**, nunca con `block()`.

### Dominio

| Clase de test | Método | Invariante / Regla | Elemento de Sección 4 que precede |
|---|---|---|---|
| `NotificationTest` | `shouldRenderTemplateWithVariables` | Reemplazo correcto de `{{nombre}}` en body_template | `Notification.render(template, params)` |
| `NotificationTest` | `shouldTransitionToPendingOnCreation` | Estado inicial siempre `PENDING` | `Notification` constructor |
| `NotificationTest` | `shouldTransitionToSentAfterDelivery` | `PENDING → SENT` solo tras confirmación de envío | `Notification.markAsSent()` |
| `NotificationTemplateTest` | `shouldValidateRequiredVariablesPresent` | Falla si faltan variables requeridas en params | `NotificationTemplate.validate()` |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case que precede |
|---|---|---|---|---|
| `SendDepositConfirmationUseCaseTest` | `shouldSendNotification_whenDepositCompleted` | Happy path | `NotificationTemplateRepository`, `NotificationSenderPort`, `NotificationRepository` (mocks) | `SendDepositConfirmationUseCase` |
| `SendDepositConfirmationUseCaseTest` | `shouldSkipSending_whenUserPreferenceDisabled` | Preferencia deshabilitada | `NotificationPreferenceRepository` (mock devuelve `is_enabled=false`) | `SendDepositConfirmationUseCase` |
| `ProcessNotificationEventUseCaseTest` | `shouldBeIdempotent_whenSameMessageIdReceived` | Mismo `message_id` recibido dos veces | `ProcessedMessageRepository` (mock) | `ProcessNotificationEventUseCase` |
| `SendKycResultUseCaseTest` | `shouldSendApprovalNotification_whenKycApproved` | KYC aprobado | `NotificationTemplateRepository`, `NotificationSenderPort` (mocks) | `SendKycResultUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador que precede |
|---|---|---|---|
| `NotificationR2dbcRepositoryTest` | `shouldSaveAndFindNotificationByUserId` | save + findByUserId | `NotificationR2dbcRepository` (Testcontainers PostgreSQL) |
| `KycApprovedEventConsumerTest` | `shouldTriggerNotification_onKycApproved` | Consume evento Kafka → usa case invocado | `KycApprovedEventConsumer` (Testcontainers Kafka) |
| `ProcessedMessageRepositoryTest` | `shouldPreventDuplicateProcessing` | Inserción duplicada → `DataIntegrityViolationException` | `ProcessedMessageR2dbcRepository` |

### REST

| Clase de test | Método | Endpoint + status/body esperado | Elemento Sección 7 que precede |
|---|---|---|---|
| `ActuatorTest` | `shouldReturn200_onReadinessCheck` | GET `/actuator/health/readiness` → 200 `{status: UP}` | Readiness probe |
| `ActuatorTest` | `shouldReturn200_onPrometheusEndpoint` | GET `/actuator/prometheus` → 200 con métricas | Prometheus endpoint |

### Umbrales de cobertura

| Capa | Umbral mínimo |
|---|---|
| `domain` | ≥ 90% |
| `application` | ≥ 85% |
| `infrastructure` | ≥ 75% |
| `rest-api` (actuator) | ≥ 70% |

---

## 9. Criterios de Aceptación

### TDD

- [ ] Cada entidad y use case tuvo su prueba escrita y vista fallar (Red) antes del código de producción (Green).
- [ ] `mvn test` finaliza en verde sin `block()` en código de pruebas.
- [ ] Cobertura por capa cumple los umbrales declarados en la Sección 8.
- [ ] No hay consumer Kafka ni rama de procesamiento sin prueba asociada.

### Funcionales

- [ ] Evento `KYCApproved` en Kafka genera notificación de bienvenida al usuario.
- [ ] Evento `DepositCompleted` genera notificación de confirmación de depósito.
- [ ] Evento `TransferCompleted` genera notificación al emisor y receptor.
- [ ] Reentrega del mismo evento Kafka (mismo `message_id`) no genera notificación duplicada (idempotencia).
- [ ] Preferencia de canal `is_enabled=false` suprime el envío.
- [ ] La notificación se registra en `pagofacil_notification_service.notifications` con `status=SENT`.
- [ ] Servicio arranca sin errores y `/actuator/health/readiness` responde `UP` en K3s VPS.
- [ ] ArgoCD muestra el app en estado `Synced` tras el pipeline CI.
