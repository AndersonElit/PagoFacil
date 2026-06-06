# Etapa 5 — Pruebas de Integración, E2E, Estrés y Carga

**Proyecto:** PagoFacil | **Ambiente:** dev (floci + K3d)  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Objetivo

Verificar la corrección del sistema como un todo: flujos de integración entre microservicios, sagas distribuidas con compensaciones, contratos de sistemas externos (WireMock), E2E de los flujos de usuario completos, y los límites de capacidad del sistema bajo carga sostenida y picos.

**Riesgos que mitiga:**
- Divergencia entre contratos de API individuales (pruebas de integración).
- Sagas que quedan en estado inconsistente (prueba de saga completa y compensada).
- Regresiones de performance ante cambios (carga y estrés).
- Fallos de seguridad de autorización entre roles (E2E).

---

## 2. Prerrequisitos

- Todos los microservicios activos en K3d dev (etapas 3a-3i completas).
- Frontend `pagofacil-web` desplegado en Vercel preview.
- WireMock configurado con stubs de sistemas externos.
- Datos de prueba sembrados (ver Sección 7).
- `projection-service` proyectando con lag < 30s.

---

## 3. Pruebas de Integración

**Herramienta:** JUnit 5 + Spring WebFlux WebTestClient + Testcontainers + WireMock + Embedded Kafka

### Estrategia

Cada prueba de integración verifica el contrato entre dos o más servicios usando el ambiente real (no mocks de servicio). Los adaptadores de infraestructura (PostgreSQL, Kafka, WireMock) son reales. Solo se mockean los sistemas externos mediante WireMock.

### Escenarios de integración por flujo

| Servicio productor | Servicio consumidor | Flujo a verificar |
|---|---|---|
| `identity-service` | `notification-service` | Registro → `UsuarioRegistrado` → notificación email enviada |
| `wallet-service` | `projection-service` | Depósito confirmado → `DepositoConfirmado` → `report_transactions` actualizado en readmodel |
| `fraud-service` → `projection-service` | `audit-service` | Alerta creada → proyectada → visible en dashboard de alertas |
| `wallet-service` → `integration-service` | `notification-service` | Retiro confirmado → `RetiroConfirmado` → notificación push enviada |

### Contract tests de sistemas externos (WireMock)

| Sistema externo | Ruta Camel | Escenario | Resultado esperado |
|---|---|---|---|
| Entidad financiera | `direct:solicitar-fondeo` | Respuesta 200 con confirmación | `ExternalRequest` status=CONFIRMED, saga avanza |
| Entidad financiera | `direct:solicitar-fondeo` | Respuesta 503 (3 veces) → 200 | Retry completado en 3er intento; log de reintentos |
| Entidad financiera | `direct:solicitar-fondeo` | Respuesta 503 > threshold | Circuit breaker abierto; `fallback` retorna error controlado |
| Entidad financiera | `direct:solicitar-fondeo` | Delay > 10s (WireMock `fixedDelay`) | Timeout; saga entra en compensación |
| Proveedor KYC | `direct:validar-identidad` | Respuesta 200 APROBADO | `kyc_registrations.result=APROBADO`; `CuentaActivada` publicado |
| Proveedor KYC | `direct:validar-identidad` | Respuesta 422 RECHAZADO | `kyc_registrations.result=RECHAZADO`; `identity-service` compensado |
| Listas AML | `direct:verificar-aml` | Respuesta 200 NO_MATCH | `AmlVerification.result=NO_MATCH`; evaluación aprobada |
| Listas AML | `direct:verificar-aml` | Respuesta 200 MATCH | `AmlVerification.result=MATCH`; `TransaccionRechazadaPorAML` publicado |

### Pruebas de Saga (integración completa)

**Saga-Deposito — Happy Path:**

```
wallet-service POST /v1/wallet/deposits
    → integration-service crea SagaInstance(DEPOSITO, INICIADA)
    → Paso 1: wallet registra PENDIENTE + incrementa pendingBalance
    → Paso 2: WireMock confirma fondeo (200)
    → Paso 4: wallet confirma + mueve pendingBalance → availableBalance
    → SagaInstance(COMPLETADA)
    → projection-service proyecta report_transactions(CONFIRMADA)
    → notification-service envía notificación
```

**Verificación:** `wallet.availableBalance == initial + amount`; `saga_instance.state == COMPLETADA`; `report_transactions.status == CONFIRMADA`; notificación en BD con `status=SENT`.

**Saga-Deposito — Compensada (rechazo entidad financiera):**

```
POST /v1/wallet/deposits
    → Paso 1: wallet registra PENDIENTE + incrementa pendingBalance
    → Paso 2: WireMock rechaza fondeo (422)
    → integration-service dispara compensación: POST /v1/wallet/deposits/{id}/compensar
    → wallet revierte pendingBalance; transacción FALLIDA
    → SagaInstance(COMPENSADA)
```

**Verificación:** `wallet.pendingBalance == initial`; `wallet.availableBalance == initial`; `saga_instance.state == COMPENSADA`; `transactions.status == FALLIDA`.

**Verificación de idempotencia de compensaciones:** enviar `POST /v1/wallet/deposits/{id}/compensar` dos veces → la segunda llamada retorna 200 sin efectos adicionales (saldo no cambia).

**Saga-Retiro con Fraude:**

```
POST /v1/wallet/withdrawals
    → Paso 1: wallet reserva fondos
    → Paso 2: fraud evalúa → RETENIDA (WireMock AML MATCH)
    → wallet en estado RETENIDA; audit puede resolver alerta
    → Si auditor aprueba: instrucción pago → confirmación
    → Si auditor rechaza: compensación Paso 1 (fondos liberados)
```

**Verificación de outbox (no dual-write):** verificar que `outbox.status=PENDING` existe en `pagofacil_wallet_service` ANTES de que el evento llegue a Kafka (confirma que la escritura fue atómica).

---

## 4. Pruebas E2E

**Herramientas:** Playwright (flujos de usuario frontend) + REST Assured o WebTestClient (flujos backend directo)

### Flujos E2E obligatorios

| Nombre | Descripción | Actores | Precondiciones | Pasos | Resultado |
|---|---|---|---|---|---|
| `e2e-registro-y-login` | Registro completo con KYC y primer login | Usuario nuevo | Sistema vacío | 1. Registro con datos válidos; 2. KYC aprobado (WireMock); 3. Login + MFA; 4. Dashboard visible | Sesión activa; `accountStatus=ACTIVA`; balance visible |
| `e2e-deposito-y-historial` | Depositar fondos y verificar en historial | Usuario activo | Account activa; fuente de fondos registrada | 1. POST /deposits; 2. WireMock confirma; 3. GET /transactions; 4. Verificar status CONFIRMADA | Historial muestra depósito CONFIRMADA; balance actualizado |
| `e2e-transferencia-entre-usuarios` | Transferencia interna entre dos billeteras | Usuario remitente; usuario destinatario | Ambas cuentas activas; remitente con saldo | 1. POST /transfers; 2. Fraude aprueba; 3. Ambas billeteras actualizadas | Remitente: balance -amount; destinatario: balance +amount; ambos con notificación |
| `e2e-reporte-cartera` | Generación completa del pipeline de reportería | Auditor | MS1, MS2 activos; datos proyectados | 1. POST /audit/reports/trigger; 2. Polling hasta COMPLETADO; 3. GET /download → S3 URL | Archivo PDF/XLS/CSV descargable desde S3 |
| `e2e-alerta-fraude-y-resolucion` | Transacción retenida por fraude + resolución de auditor | Usuario + Auditor | Regla de fraude activa (RETENER para monto > 5000) | 1. POST /withdrawals con amount > 5000; 2. Fraud retiene; 3. Auditor resuelve RECHAZADA; 4. Fondos liberados | Fondos devueltos al remitente; notificación enviada |

### E2E de reportería (pipeline completo)

| Test | Descripción | Resultado esperado |
|---|---|---|
| `e2e-reporting-happy-path` | Parquet `raw/` → `processed/` → 3 formatos en `output/` | 3 archivos en S3 `pagofacil-reports/` (PDF + XLS + CSV) |
| `e2e-reporting-schema-failure` | Columna faltante en DataFrame de MS1 | `report.extraction.failed` en Kafka; sin parquet en `raw/`; job status FALLIDO |

---

## 5. Pruebas de Estrés

**Herramienta:** k6

**Objetivo:** determinar el punto de quiebre de cada servicio crítico bajo carga creciente.

### Escenarios de estrés

```javascript
// k6 ramp-up test
export const options = {
  stages: [
    { duration: '2m', target: 50 },   // ramp-up a 50 VU
    { duration: '5m', target: 200 },  // mantener 200 VU
    { duration: '2m', target: 500 },  // pico a 500 VU
    { duration: '1m', target: 0 },    // ramp-down
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'],   // P95 < 2s
    http_req_failed: ['rate<0.05'],      // error rate < 5%
  },
};
```

| Servicio | Escenario | Métrica objetivo |
|---|---|---|
| `identity-service` | Login concurrente de 500 usuarios | P95 < 500ms; error rate < 0.1% |
| `wallet-service` | Consultas de saldo + creación de depósitos | P95 < 1000ms; error rate < 0.1% |
| `integration-service` | Inicio de sagas Deposito concurrentes | P95 < 2000ms; error rate < 0.5% |
| `audit-service` | Búsqueda de transacciones en Read Model | P95 < 500ms; error rate < 0.1% |

**Métricas a capturar:** latencia P50/P95/P99, tasa de errores HTTP, throughput (req/s), uso de CPU/memoria por pod (vía Prometheus + K3d).

---

## 6. Pruebas de Carga

**Herramienta:** k6

**Objetivo:** verificar comportamiento estable bajo carga representativa del uso normal.

| Escenario | VUs | Duración | Umbral de aceptación |
|---|---|---|---|
| `carga-consulta-saldo` | 50 VU | 10 min | P95 < 300ms; error rate < 0.1%; no memory leak |
| `carga-historial-transacciones` | 30 VU | 10 min | P95 < 500ms; error rate < 0.1% |
| `carga-operaciones-financieras` | 20 VU (mix deposit/transfer) | 15 min | P95 < 1500ms; 0 transacciones duplicadas; 0 inconsistencias de saldo |
| `carga-dashboard-auditoria` | 10 VU | 10 min | P95 < 500ms; datos del Read Model coherentes |
| `carga-sagas-concurrentes` | 10 VU | 15 min | P95 < 3000ms; 0 sagas en estado STUCK; 0 inconsistencias de saldo |

**Script de referencia:**

```javascript
// k6 sustained load test
export const options = {
  vus: 50,
  duration: '10m',
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.001'],
  },
};
```

---

## 7. Verificación E2E de Observabilidad

Verificar que el stack instalado en la Etapa 0c está integrado correctamente con todos los microservicios desplegados. Estos escenarios se ejecutan una vez que todas las etapas 3a-3i están completas y los servicios están corriendo en K3d.

| Escenario | Herramienta | Precondición | Resultado esperado |
|---|---|---|---|
| Traza end-to-end en Jaeger | Jaeger UI `http://localhost:16686` | Request HTTP a `identity-service POST /v1/auth/login` | Traza con spans de `identity-service`; `traceId` visible y correlacionable |
| Traza de saga en Jaeger | Jaeger UI | `POST /v1/wallet/deposits` ejecutado (saga Deposito happy path) | Traza distribuida con spans de `wallet-service` e `integration-service` en la misma traza |
| Métricas en Prometheus | `http://localhost:9090` | Todos los servicios en `Running` + al menos 1 request | `http_server_requests_seconds_count{application="identity-service"}` presente en Prometheus; todos los targets en `Status > Targets` en estado `UP` |
| Log JSON con traceId | Grafana/Loki | Request HTTP generada | Log con `traceId` y `spanId` coincidentes con la traza de Jaeger; campo `service` = nombre del microservicio |
| Correlación log ↔ traza | Grafana/Loki + Jaeger | Traza visible en Jaeger | Copiar `traceId` de Jaeger → buscar en Loki con `{service="identity-service"} |= "<traceId>"` → logs coinciden |
| Prometheus scrapea todos los servicios | `http://localhost:9090/targets` | Todos los servicios en `Running` | identity-service, wallet-service, fraud-service, notification-service, audit-service, projection-service en estado `UP`; ninguno en `DOWN` |
| Observabilidad en staging/prod | CloudWatch Console | Módulo Terraform `observability` aplicado | Log Group `/pagofacil/staging/identity-service` recibe logs JSON; X-Ray muestra trazas; alarmas en estado `OK` |

**Comandos de verificación rápida:**

```bash
KUBECONFIG=terraform/backend/environments/dev/.kube/config-k3d

# Verificar targets de Prometheus
kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="kubernetes-pods") | {service: .labels.app, health: .health}'

# Verificar servicios en Jaeger tras una request de prueba
kubectl port-forward svc/jaeger 16686:16686 -n tracing &
curl http://localhost:16686/api/services | jq '.data[]'

# Buscar logs con traceId en Loki (reemplazar <traceId> con un valor real de Jaeger)
curl -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="dev"} |= "<traceId>"' | jq '.data.result[].values[][1]'
```

---

## 8. Configuración del Ambiente de Pruebas

### Variables de entorno para el ambiente de test

```bash
# .env.test (no commitear)
BASE_URL_IDENTITY=http://localhost:8081
BASE_URL_WALLET=http://localhost:8082
BASE_URL_FRAUD=http://localhost:8083
BASE_URL_AUDIT=http://localhost:8085
BASE_URL_INTEGRATION=http://localhost:8086
BASE_URL_FRONTEND=https://<vercel-preview-url>
WIREMOCK_URL=http://localhost:8888
KAFKA_BOOTSTRAP_SERVERS=localhost:9092
```

### Comandos para levantar todos los servicios en modo test

```bash
# Verificar que K3d está activo y todos los servicios Running
kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3d \
  get pods -n dev --field-selector=status.phase=Running

# Port-forward de los servicios para tests locales
kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3d \
  port-forward -n dev svc/identity-service 8081:80 &
kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3d \
  port-forward -n dev svc/wallet-service 8082:80 &
# (repetir para cada servicio)
```

### Seeders de datos de prueba

Los seeders se ejecutan con el script:

```bash
bash .claude/scripts/seed-test-data.sh -P pagofacil --environment dev
```

**Datos creados por el seeder:**

| Entidad | Cantidad | Descripción |
|---|---|---|
| Usuarios | 10 | 8 usuarios activos, 1 pendiente KYC, 1 bloqueado |
| Wallets | 10 | Una por usuario activo con saldo inicial de 10000 USD |
| TransactionLimits | 2 | Límites estándar (maxPerOperation: 5000, maxDaily: 20000) y premium (maxPerOperation: 50000) |
| FraudRules | 3 | Una regla MONTO (threshold 4999, RETENER), una FRECUENCIA y una DESTINATARIO |
| NotificationTemplates | 8 | Templates para todos los eventos del sistema |
| WireMock stubs | — | Respuestas configuradas para entidad financiera, KYC y listas AML |

---

## 9. Criterios de Aceptación

- [ ] Todos los escenarios de integración de la Sección 3 pasan sin errores.
- [ ] Contract tests de WireMock validan los 8 escenarios (éxito, reintentos, circuit breaker, timeout, KYC).
- [ ] Saga-Deposito happy path completa con estado `COMPLETADA` en `saga_instance`.
- [ ] Saga-Deposito compensada con rechazo de entidad financiera: `wallet.pendingBalance` restaurado; `saga_instance.state = COMPENSADA`.
- [ ] La compensación de saga es idempotente (segunda llamada no produce efectos).
- [ ] Los eventos de dominio se publican vía Outbox (verificado antes de llegada a Kafka).
- [ ] Los 5 flujos E2E de la Sección 4 pasan en Playwright contra el ambiente dev.
- [ ] El pipeline E2E de reportería produce 3 archivos en S3 (PDF + XLS + CSV).
- [ ] E2E de fallo de validación de schema: `report.extraction.failed` en Kafka, sin Parquet.
- [ ] Pruebas de estrés: `identity-service` soporta 500 VU concurrentes con P95 < 500ms.
- [ ] Pruebas de carga sostenida de 15 minutos sobre sagas: 0 sagas en estado STUCK; 0 inconsistencias de saldo.
- [ ] `wallet-service` no produce saldos negativos ni inconsistencias bajo carga concurrente de 20 VU.
- [ ] El lag del `projection-service` se mantiene < 30s durante prueba de carga.
- [ ] Los 6 escenarios de observabilidad de la Sección 7 están verificados: trazas en Jaeger, métricas en Prometheus, logs JSON con `traceId` en Loki.
- [ ] Todos los targets de Prometheus están en estado `UP` (ningún servicio en `DOWN`).
- [ ] La correlación log ↔ traza funciona: un `traceId` de Jaeger encuentra sus logs en Loki.
