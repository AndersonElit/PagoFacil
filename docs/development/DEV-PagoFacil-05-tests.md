# Etapa 5 — Pruebas de Integración, E2E, Estrés y Carga

**Proyecto:** PagoFacil — Billetera Digital
**Ambiente de pruebas:** VPS Ubuntu 26.04 LTS — K3s nativo + floci (`VPS_IP:4566`)

---

## 1. Objetivo

Esta etapa valida el sistema integrado completo: contratos entre microservicios, sagas distribuidas, flujos E2E del usuario final y la capacidad de la plataforma bajo carga. Los riesgos que mitiga:

- Inconsistencias de contrato entre servicios tras cambios independientes.
- Sagas que no compensan correctamente ante fallos en pasos intermedios.
- Flujos de usuario rotos tras integración de features de frontend.
- Degradación del sistema bajo carga nominal y picos.
- Stack de observabilidad no correlacionado con los eventos de la aplicación.

---

## 2. Prerrequisitos

- [ ] Todas las etapas 3a–3i completadas y servicios desplegados en K3s VPS.
- [ ] Etapa 6 (capa serverless) completada.
- [ ] Features frontend 4a–4f desplegados.
- [ ] Stack de observabilidad (Etapa 0c) activo: Prometheus, Grafana, Jaeger, Loki.
- [ ] Todos los seeders de datos de prueba ejecutados (ver Sección 8).
- [ ] Variables de entorno de test configuradas (ver Sección 8).

---

## 3. Pruebas de Integración

### 3.1 Estrategia

Spring Boot Test + Testcontainers + WireMock para aislar sistemas externos. Cada prueba de integración que valida un criterio ATDD incluye el ID en el `@DisplayName`:

```java
@Test
@DisplayName("AC-003-S1: depósito completado acredita saldo y publica DepositCompleted")
void shouldCreditWalletAndPublishDepositCompleted() { ... }
```

### 3.2 Escenarios de integración por flujo

| Servicio productor | Servicio consumidor | Flujo a verificar |
|---|---|---|
| identity-service | wallet-service | `KYCApproved` → billetera creada con saldo cero |
| identity-service | audit-service | `UserRegistered` → traza en MongoDB |
| identity-service | notification-service | `KYCApproved` → notificación de bienvenida |
| identity-service | projection-service | `UserRegistered` → fila en `report_users` |
| wallet-service | audit-service | `DepositCompleted` → traza en MongoDB |
| wallet-service | projection-service | `DepositCompleted` → fila en `report_transactions` |
| fraud-compliance-service | audit-service | `FraudAlertCreated` → traza en MongoDB |
| fraud-compliance-service | projection-service | `FraudAlertCreated` → fila en `report_compliance_alerts` |
| integration-service | todos los participantes | Saga DEPOSIT completa (pasos 1–5 exitosos) |
| integration-service | todos los participantes | Saga TRANSFER completa (pasos 1–5 exitosos) |
| integration-service | todos los participantes | Saga WITHDRAWAL completa (pasos 1–7 exitosos) |
| projection-service | report-extraction-service | Read model populado → MS1 extrae Parquet sin error |
| MS1 | MS2 | `report.extracted` → MS2 transforma y escribe `processed/` |
| MS2 | capa serverless | `report.processed` → Lambda Consumer → Lambda PDF → archivo en S3 |

### 3.3 Contract tests — sistemas externos (WireMock en `VPS_IP:9999`)

| Sistema externo | Ruta Camel | Escenario | Resultado esperado |
|---|---|---|---|
| Proveedor KYC | `kyc-route` | Respuesta KYC aprobado (200) | `KycResult.status = APPROVED` |
| Proveedor KYC | `kyc-route` | Timeout (> 5 s) | Circuit breaker Resilience4j abierto; evento de error publicado |
| Proveedor AML | `aml-route` | Sin coincidencia AML | `AmlResult.match = false` |
| Proveedor AML | `aml-route` | Coincidencia AML positiva | `AmlResult.match = true`; `ComplianceAlert` generado |
| Proveedor AML | `aml-route` | HTTP 503 del proveedor | Retry exponencial 3 veces; circuit breaker |
| Entidad Financiera | `deposit-saga-route` | Confirmación de pago válida | Saga DEPOSIT pasa al paso 3 |
| Entidad Financiera | `withdrawal-saga-route` | Rechazo de retiro | Compensación de reserva ejecutada (RELEASE_RESERVATION) |

### 3.4 Sagas — escenarios completos

**Saga DEPOSIT — happy path (AC-003-S1):**

```
Precondición: usuario con KYC ACTIVE, billetera creada
  1. integration-service recibe PaymentNotification (webhook WireMock)
  2. fraud-compliance-service evalúa AML → APPROVED
  3. wallet-service acredita saldo → balance += amount
  4. integration-service confirma con entidad financiera (WireMock)
  5. DepositCompleted publicado en Kafka
  
Verificación: available_balance incrementado; DepositCompleted en topic; saga_instance.state = COMPLETED
```

**Saga DEPOSIT — compensación (AC-003-E3):**

```
Precondición: AML retorna BLOCKED (WireMock)
  1. integration-service recibe PaymentNotification
  2. fraud-compliance-service retorna BLOCKED
  3. Orquestador LRA dispara compensación: ComplianceAlert compensado
  4. saga_instance.state = COMPENSATED
  
Verificación: wallet_service.available_balance sin cambio; ComplianceAlert.status = BLOCKED
```

**Saga TRANSFER — fallo en crédito receptor (AC-004-E1 análogo):**

```
  1. Valida KYC emisor y receptor → OK
  2. Evaluación riesgo → APPROVED
  3. Débito emisor → OK (wallet_service.balance -= amount)
  4. Crédito receptor → FALLA (WireMock devuelve error)
  5. Compensación: REVERSE_DEBIT en wallet_service del emisor
  
Verificación: saldo emisor restaurado; saldo receptor sin cambio; TransferReverted en Kafka
```

**Saga WITHDRAWAL — fallo en entidad financiera (AC-005-E1):**

```
  1. Valida saldo → OK
  2. Reserva fondos → reserved_balance += amount
  3. Evaluación AML → APPROVED
  4. Instrucción retiro → entidad financiera RECHAZA (WireMock)
  5. Compensación: RELEASE_RESERVATION en wallet_service
  
Verificación: reserved_balance restaurado; WithdrawalReverted en Kafka; saga COMPENSATED
```

**Compensaciones idempotentes (AC-006-S1):**

Cada compensación se invoca dos veces con el mismo `Idempotency-Key`. La segunda invocación debe retornar el mismo resultado sin producir doble efecto.

**Outbox — no dual-write:**

Verificar que todos los eventos de saga son publicados via tabla `outbox` (no directamente a Kafka). Simular fallo entre BD commit y Kafka publish: los eventos pendientes deben publicarse tras recuperación del relay.

---

## 4. Pruebas E2E

**Herramienta:** Playwright (frontend) + REST Assured / Supertest (backend directo)

### 4.1 Flujos mínimos obligatorios

| Flujo | Actores | Pasos | Resultado esperado |
|---|---|---|---|
| Registro y autenticación completa | Usuario Final | Registro → KYC simulado → MFA → login → access token | JWT con `role=USER`, `tenant_id` válidos; sesión NextAuth.js activa |
| Solicitud de crédito completa (depósito) | Usuario Final | Login → `/transactions/deposit` → submit → polling PENDING → CONFIRMED | `WalletBalanceCard` muestra saldo incrementado |
| Transferencia entre usuarios | Usuario A, Usuario B | Login A → `/transactions/transfer` → recipientId=B → submit → CONFIRMED | Saldo A decrementado; saldo B incrementado |
| Registro de retiro | Usuario Final | Login → `/transactions/withdrawal` → cuenta bancaria → submit → CONFIRMED | Reserva liberada; saldo decrementado permanente |
| Resolución de alerta de compliance | Oficial de Cumplimiento | Login COMPLIANCE_OFFICER → `/compliance/alerts` → resolver APPROVED | Alerta status = APPROVED; traza en MongoDB |
| Generación de reporte de cartera | Administrador | Login ADMIN → `/reports` → solicitar TRANSACTIONS PDF → polling → COMPLETED → descargar | Archivo PDF descargado desde S3 output/ |
| Dashboard de auditoría | Administrador | Login ADMIN → `/audit/traces` → filtrar por correlationId → ver detalle | Traza con todos los campos visible |

### 4.2 Tabla completa de tests E2E

| Test E2E | Flujo | Precondición | Herramienta |
|---|---|---|---|
| `e2e-onboarding.spec.ts` | Registro completo + KYC aprobado | WireMock KYC stub → aprobado | Playwright |
| `e2e-login-mfa.spec.ts` | Login + MFA + redirect | Usuario activo en BD | Playwright |
| `e2e-deposit-full.spec.ts` | Depósito completo saga | Billetera activa | Playwright + REST Assured |
| `e2e-transfer-full.spec.ts` | Transferencia entre cuentas | Dos usuarios activos con saldo | Playwright |
| `e2e-withdrawal-full.spec.ts` | Retiro con confirmación | Cuenta bancaria VERIFIED | Playwright |
| `e2e-compliance-resolve.spec.ts` | Resolución de alerta | Alerta OPEN en BD | Playwright |
| `e2e-report-pipeline.spec.ts` | Reporte completo PDF | Read model populado; pipeline ETL activo | Playwright |
| `e2e-audit-trace.spec.ts` | Trazas de operación | DepositCompleted en MongoDB | Playwright |

---

## 5. Pruebas de Estrés

**Herramienta:** k6 (script en `tests/stress/`)

### 5.1 Servicios a estresar

| Servicio | Endpoint | Métrica objetivo |
|---|---|---|
| identity-service | `POST /auth/login` | Punto de quiebre (tasa error > 5%) |
| wallet-service | `GET /wallets/{id}` | Latencia P95 < 500 ms bajo 500 VUs |
| integration-service | `POST /transactions/deposits` | Latencia saga P95 < 2 s bajo 200 VUs |
| fraud-compliance-service | `GET /compliance/alerts` | Throughput sostenido |

### 5.2 Escenario de ramp-up

```javascript
// tests/stress/ramp-up.js
export const options = {
  stages: [
    { duration: "2m", target: 100 },   // ramp-up a 100 VUs
    { duration: "5m", target: 500 },   // ramp-up a 500 VUs
    { duration: "2m", target: 1000 },  // ramp-up a 1000 VUs (punto de quiebre)
    { duration: "2m", target: 0 },     // cool-down
  ],
  thresholds: {
    http_req_failed: ["rate < 0.05"],
    http_req_duration: ["p(95) < 500"],
  },
};
```

### 5.3 Métricas a capturar

| Métrica | Herramienta | Umbral de alerta |
|---|---|---|
| Latencia P95 — lectura | k6 + Grafana | > 500 ms |
| Latencia P95 — saga | k6 + Grafana | > 2 s |
| Tasa de error HTTP | k6 | > 5% |
| Throughput (req/s) | k6 | < 100 req/s bajo 200 VUs (alerta) |
| CPU pods | Prometheus + Grafana | > 80% durante > 2 min |
| Memory usage | Prometheus | Crecimiento sostenido (posible memory leak) |

---

## 6. Pruebas de Carga

**Herramienta:** k6

### 6.1 Escenarios de carga sostenida

| Escenario | VUs | Duración | P95 objetivo | Tasa error máx |
|---|---|---|---|---|
| Carga nominal — lectura de wallets | 200 | 30 min | < 300 ms | < 1% |
| Carga nominal — depósitos concurrentes | 50 | 30 min | < 2 s (saga) | < 2% |
| Carga sostenida — autenticación | 100 | 30 min | < 500 ms | < 1% |
| Carga pico — transferencias | 100 | 10 min | < 2 s | < 3% |
| Carga nominal — consulta auditoría | 50 | 30 min | < 500 ms | < 1% |

```javascript
// tests/load/nominal-wallets.js
export const options = {
  scenarios: {
    wallet_reads: {
      executor: "constant-vus",
      vus: 200,
      duration: "30m",
    },
  },
  thresholds: {
    http_req_duration: ["p(95) < 300"],
    http_req_failed: ["rate < 0.01"],
  },
};
```

---

## 7. Verificación E2E de Observabilidad

Verifica que el stack instalado en Etapa 0c está integrado correctamente con los microservicios desplegados.

| Escenario | Herramienta | Precondición | Resultado esperado |
|---|---|---|---|
| Traza end-to-end de depósito | Jaeger UI `http://VPS_IP:16686` | Request `POST /transactions/deposits` ejecutada | Traza visible con spans de integration-service, wallet-service, fraud-compliance-service; `traceId` correlacionado entre servicios |
| Métrica de endpoint scrapeada | Prometheus `http://VPS_IP:9090` | Microservicio en `Running` | `http_server_requests_seconds_count{application="identity-service"}` visible en Prometheus |
| Log estructurado con traceId | Grafana/Loki `http://VPS_IP:3001` | Request HTTP ejecutada | Log en JSON con campos `traceId`, `spanId`, `level`, `service`; `traceId` coincide con la traza en Jaeger |
| Todos los targets Prometheus UP | Prometheus → Status → Targets | Todos los servicios en `Running` | Todos los targets en estado `UP`; ninguno en `DOWN` |
| Métricas JVM en Grafana | Dashboard ID 4701 | Prometheus scrapeando | Heap usage, GC time, thread count visibles por microservicio |

**En staging/prod:** CloudWatch Logs recibe registros JSON; CloudWatch X-Ray muestra trazas distribuidas; alarmas en estado `OK`.

---

## 8. Configuración del Ambiente de Pruebas

### Variables de entorno para tests

```bash
# tests/.env.test
VPS_IP=<VPS_IP>
API_BASE_URL=http://<VPS_IP>:8080
KAFKA_BOOTSTRAP_SERVERS=<VPS_IP>:29092
POSTGRES_HOST=<VPS_IP>
POSTGRES_PORT=5432
MONGO_URI=mongodb://pagofacil_app:<CLAVE_APP>@<VPS_IP>:27017
S3_ENDPOINT=http://<VPS_IP>:4566
WIREMOCK_URL=http://<VPS_IP>:9999
JAEGER_URL=http://<VPS_IP>:16686
PROMETHEUS_URL=http://<VPS_IP>:9090
```

### Seeders de datos de prueba

```bash
# Ejecutar antes de las pruebas E2E y de carga
bash tests/fixtures/seed-test-data.sh --vps-ip <VPS_IP>
```

El script crea:
- 5 tenants de prueba con UUID fijos.
- 10 usuarios activos (KYC APPROVED) con billeteras creadas.
- 2 usuarios con estado SUSPENDED (para pruebas de compliance).
- 3 cuentas bancarias VERIFIED por usuario.
- `report_schema_catalog` con los 3 tipos de reporte y sus `integrity_rules`.
- Reglas de fraude activas en `fraud_rules`.
- Datos de prueba en `pagofacil_readmodel` para trigger de MS1.

### Levantar el ambiente completo para pruebas manuales

```bash
# Verificar que todos los pods están Running en K3s
kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3s \
  get pods -A | grep -E "(identity|wallet|fraud|notification|integration|audit|projection)"

# Verificar stack de observabilidad
kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3s \
  get pods -n monitoring -n tracing

# Ejecutar seeders
bash tests/fixtures/seed-test-data.sh --vps-ip <VPS_IP>

# Ejecutar suite de integración backend
mvn -pl integration-tests test -Pintegration

# Ejecutar pruebas E2E frontend
cd frontend/pagofacil-web && npx playwright test
```

---

## 9. Criterios de Aceptación

### Integración

- [ ] Saga DEPOSIT happy path completa: `DepositCompleted` en Kafka; `saga_instance.state = COMPLETED`.
- [ ] Saga DEPOSIT compensación: fallo AML → `ComplianceAlert` compensado; saldo intacto.
- [ ] Saga TRANSFER con fallo en crédito receptor: `REVERSE_DEBIT` ejecutado; saldo emisor restaurado.
- [ ] Saga WITHDRAWAL con fallo en entidad financiera: `RELEASE_RESERVATION` ejecutado; `WithdrawalReverted` en Kafka.
- [ ] Compensaciones idempotentes: segunda invocación con mismo `Idempotency-Key` no produce doble efecto.
- [ ] Outbox: eventos publicados solo si la transacción de BD se confirma; relay publica pendientes tras recuperación.
- [ ] Contract tests de rutas Camel contra WireMock: timeout → circuit breaker Resilience4j activo.

### E2E

- [ ] Todos los flujos mínimos de la Sección 4.1 pasan en Playwright.
- [ ] Pipeline ETL completo: read model → MS1 → MS2 → Lambda → PDF en S3 → `report_executions.status = COMPLETED`.

### Performance

- [ ] Latencia P95 de endpoints de lectura < 500 ms bajo 200 VUs (carga nominal).
- [ ] Latencia P95 de sagas < 2 s end-to-end bajo 50 VUs concurrentes.
- [ ] Tasa de error < 1% bajo carga nominal.

### Observabilidad

- [ ] Traza E2E de depósito visible en Jaeger con spans de todos los servicios involucrados.
- [ ] `http_server_requests_seconds_count` visible en Prometheus para cada microservicio.
- [ ] Logs en Grafana/Loki con campos `traceId`, `spanId`, `level`, `service` en JSON.
- [ ] Todos los Prometheus targets en estado `UP`.
