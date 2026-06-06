# Etapa 3 — Microservicio: notification-service

**Proyecto:** PagoFacil | **Bounded Context:** BC-04 Notification | **Puerto local:** 8084  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Contexto y Responsabilidad

**Bounded context:** BC-04 Notification — entrega de notificaciones transaccionales y de seguridad.

**Responsabilidad principal:**
- Consumir eventos de dominio de múltiples bounded contexts (BC-01, BC-02, BC-03).
- Seleccionar la plantilla de notificación adecuada por tipo de evento y canal.
- Enviar notificaciones por email, SMS o push según la configuración del usuario.
- Registrar el resultado de cada entrega (enviada, fallida, motivo de fallo).
- Garantizar idempotencia: un evento Kafka no genera notificaciones duplicadas.

**No expone endpoints públicos de escritura.** No tiene dependencias REST salientes hacia otros microservicios.

**Dependencias de infraestructura:**

| Recurso | Tipo | Propósito |
|---|---|---|
| `pagofacil_notification_service` | PostgreSQL R2DBC | Write side: plantillas y registro de entregas |
| Múltiples topics Kafka | Consumer | Eventos de BC-01, BC-02, BC-03 |
| SMTP / SMS / FCM | REST externo | Proveedores de canal (vía Secrets Manager) |

---

## 2. Prerrequisitos

- Etapa 2b completa.
- Secret `pagofacil/dev/notification-service` en floci.
- Migraciones Liquibase de `db/notification-service/` aplicadas.
- `wallet-service` activo (o mensajes de prueba en Kafka para `pagofacil.wallet.*`).
- Seeds de `notification_templates` aplicados (ver Paso 6 de Etapa 2 — seed opcional).

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
| `NotificationTemplate` | `templateId`, `eventType`, `channel`, `subject`, `bodyTemplate`, `isActive` | Un template activo por `(eventType, channel)`; `channel` ∈ `{EMAIL, SMS, PUSH}` |
| `Notification` | `notificationId`, `userId`, `tenantId`, `eventType`, `channel`, `recipient`, `status`, `correlationId`, `sentAt`, `failedAt`, `failureReason` | `status` transiciona: `PENDING → SENT` o `PENDING → FAILED`; no permite transición inversa |

### Value Objects

| VO | Regla de validación |
|---|---|
| `NotificationChannel` | Enum: `EMAIL`, `SMS`, `PUSH` |
| `NotificationStatus` | Enum: `PENDING`, `SENT`, `FAILED` |
| `Recipient` | Email (EMAIL), número E.164 (SMS) o device token (PUSH); validación por canal |

### Puertos secundarios

```java
// NotificationTemplateRepository
Mono<NotificationTemplate> findActiveByEventTypeAndChannel(String eventType, NotificationChannel channel);

// NotificationRepository
Mono<Notification> save(Notification notification);
Flux<Notification> findByUserId(UUID userId);

// ProcessedMessageRepository
Mono<Boolean> existsByMessageIdAndConsumer(String messageId, String consumer);
Mono<Void> save(String messageId, String consumer);

// ChannelGateway (uno por canal — interfaz de puerto)
Mono<Void> send(Notification notification);
```

### Invariantes de dominio

- Una notificación `SENT` o `FAILED` no puede retornar a `PENDING`.
- Si no existe plantilla activa para `(eventType, channel)`, se registra la notificación como `FAILED` con motivo `TEMPLATE_NOT_FOUND` (sin lanzar excepción — flujo degradado controlado).
- El `failureReason` no puede contener PII (solo código de error y mensaje técnico).

---

## 5. Capa de Aplicación (`application`) — _test-first_

### Casos de uso

| Use Case | Descripción | Puerto primario | Puertos secundarios |
|---|---|---|---|
| `SendNotificationUseCase` | Busca plantilla; renderiza el cuerpo; llama al `ChannelGateway`; persiste resultado | `SendNotificationInputPort` | `NotificationTemplateRepository`, `NotificationRepository`, `ChannelGateway` |
| `ProcessDomainEventUseCase` | Consumer Kafka: verifica idempotencia; extrae `userId`, `channel`, `eventType` del evento; invoca `SendNotificationUseCase` | `DomainEventInputPort` | `ProcessedMessageRepository`, `SendNotificationUseCase` |

### Eventos consumidos → notificaciones disparadas

| Topic Kafka | Tipo de evento | Template `eventType` | Canal |
|---|---|---|---|
| `pagofacil.wallet.deposito-confirmado` | `DepositoConfirmado` | `DEPOSITO_CONFIRMADO` | EMAIL + PUSH |
| `pagofacil.wallet.deposito-revertido` | `DepositoRevertido` | `DEPOSITO_REVERTIDO` | EMAIL |
| `pagofacil.wallet.retiro-confirmado` | `RetiroConfirmado` | `RETIRO_CONFIRMADO` | EMAIL + PUSH |
| `pagofacil.wallet.transferencia-confirmada` | `TransferenciaConfirmada` | `TRANSFERENCIA_CONFIRMADA` | EMAIL + PUSH |
| `pagofacil.identity.cuenta-activada` | `CuentaActivada` | `CUENTA_ACTIVADA` | EMAIL |
| `pagofacil.identity.cuenta-bloqueada` | `CuentaBloqueada` | `CUENTA_BLOQUEADA` | EMAIL + SMS |
| `pagofacil.identity.password-reset-solicitado` | `PasswordResetSolicitado` | `PASSWORD_RESET` | EMAIL |
| `pagofacil.fraud.transaccion-retenida` | `TransaccionRetenidaPorFraude` | `TRANSACCION_RETENIDA` | EMAIL |

---

## 6. Capa de Infraestructura (`infrastructure`) — _test-first_

### Adaptadores R2DBC

| Adaptador | Tablas | Operaciones |
|---|---|---|
| `NotificationTemplateR2dbcAdapter` | `notification_templates` | `findActiveByEventTypeAndChannel` |
| `NotificationR2dbcAdapter` | `notifications` | `save` |
| `ProcessedMessageR2dbcAdapter` | `processed_message` | `existsByMessageIdAndConsumer`, `save` |

### Consumidores Kafka

| Topic | Consumer Group | Lógica |
|---|---|---|
| `pagofacil.wallet.deposito-confirmado` | `notification-sender` | Idempotencia → `ProcessDomainEventUseCase` |
| `pagofacil.wallet.deposito-revertido` | `notification-sender` | Ídem |
| `pagofacil.wallet.retiro-confirmado` | `notification-sender` | Ídem |
| `pagofacil.wallet.transferencia-confirmada` | `notification-sender` | Ídem |
| `pagofacil.identity.cuenta-activada` | `notification-sender` | Ídem |
| `pagofacil.identity.cuenta-bloqueada` | `notification-sender` | Ídem |
| `pagofacil.identity.password-reset-solicitado` | `notification-sender` | Ídem |
| `pagofacil.fraud.transaccion-retenida` | `notification-sender` | Ídem |

### Gateways de canal (adaptadores secundarios)

| Gateway | Protocolo | Configuración |
|---|---|---|
| `SmtpEmailGateway` | SMTP (JavaMail reactive) | Credenciales desde Secrets Manager |
| `SmsGateway` | REST (proveedor SMS) | API key desde Secrets Manager |
| `PushGateway` | REST (FCM) | Service Account JSON desde Secrets Manager |

En dev, los tres gateways apuntan a endpoints mock (WireMock o MailHog para SMTP).

### Configuración de seguridad

`notification-service` no expone endpoints públicos REST (solo `/actuator/**`). Toda la interacción es Kafka consumer.

---

## 7. API REST (`rest-api`)

`notification-service` no expone endpoints de negocio públicos. Solo expone los endpoints del Spring Boot Actuator:

| Endpoint | Propósito |
|---|---|
| `GET /actuator/health` | Estado del servicio |
| `GET /actuator/health/readiness` | Readiness probe K8s |
| `GET /actuator/health/liveness` | Liveness probe K8s |
| `GET /actuator/metrics` | Métricas Prometheus |

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> Tipos reactivos verificados con `StepVerifier`.

### Dominio

| Clase de test | Método | Invariante | Elemento de Sección 4 |
|---|---|---|---|
| `NotificationTest` | `shouldNotTransitionFromSentToPending` | Estado SENT es terminal | Entidad `Notification` |
| `NotificationTest` | `shouldSetFailureReasonOnFailed` | FAILED requiere `failureReason` | Entidad `Notification` |
| `NotificationTemplateTest` | `shouldReturnDegradedOnMissingTemplate` | Sin plantilla → FAILED controlado | Invariante de flujo degradado |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case |
|---|---|---|---|---|
| `SendNotificationUseCaseTest` | `shouldSendAndMarkSent` | Happy path: template encontrada, canal responde OK | `NotificationTemplateRepository`, `NotificationRepository`, `ChannelGateway` (Mockito) | `SendNotificationUseCase` |
| `SendNotificationUseCaseTest` | `shouldMarkFailedOnChannelError` | Canal retorna error | `ChannelGateway` (mock lanza excepción) | `SendNotificationUseCase` |
| `SendNotificationUseCaseTest` | `shouldMarkFailedWhenTemplateNotFound` | Sin plantilla activa | `NotificationTemplateRepository` (mock `Mono.empty()`) | `SendNotificationUseCase` |
| `ProcessDomainEventUseCaseTest` | `shouldSkipOnDuplicateMessageId` | `processed_message` ya existe → sin efecto | `ProcessedMessageRepository` (mock existe) | `ProcessDomainEventUseCase` |
| `ProcessDomainEventUseCaseTest` | `shouldInvokeSendOnNewEvent` | Mensaje nuevo | `ProcessedMessageRepository` (mock no existe) | `ProcessDomainEventUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador |
|---|---|---|---|
| `NotificationTemplateR2dbcAdapterTest` | `shouldReturnActiveTemplate` | SELECT con `is_active=true` y `event_type` con Testcontainers | `NotificationTemplateR2dbcAdapter` |
| `NotificationR2dbcAdapterTest` | `shouldPersistNotificationWithStatus` | INSERT con `status` correcto | `NotificationR2dbcAdapter` |
| `ProcessedMessageR2dbcAdapterTest` | `shouldPreventDuplicateInsert` | Second INSERT con misma PK → retorna `true` sin error | `ProcessedMessageR2dbcAdapter` |
| `SmtpEmailGatewayTest` | `shouldSendEmailViaSmtp` | Envío a MailHog (WireMock SMTP) en dev | `SmtpEmailGateway` |

### Umbrales de cobertura mínima

| Capa | Umbral |
|---|---|
| `domain` | ≥ 85% |
| `application` | ≥ 85% |
| `infrastructure` | ≥ 80% |

---

## 9. Criterios de Aceptación

- [ ] Cada elemento de cada capa tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] `mvn test` finaliza en verde.
- [ ] La cobertura por capa cumple los umbrales.
- [ ] Al recibir el evento `DepositoConfirmado` en Kafka, se crea una `Notification` con `status=SENT` y se registra en BD.
- [ ] Si la plantilla no existe para el canal, la notificación se registra como `FAILED` sin lanzar excepción.
- [ ] El consumer es idempotente: el mismo `messageId` procesado dos veces no genera dos notificaciones.
- [ ] Pipeline CI despliega en K3d: `kubectl get pods -n dev | grep notification-service` muestra `Running`.
