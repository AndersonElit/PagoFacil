# Etapa 3 — Microservicio: audit-service

**Proyecto:** PagoFacil | **Bounded Context:** BC-05 Audit + BC-07 Reporting | **Puerto local:** 8085  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Contexto y Responsabilidad

**Bounded contexts:** BC-05 Audit (dashboard y alertas) + BC-07 Reporting (gestión de jobs de reporte).

**Responsabilidad principal:**
- Dashboard de búsqueda y revisión de transacciones (solo lectura sobre `pagofacil_readmodel`).
- Gestión de alertas de fraude y AML: aprobación/rechazo con justificación inmutable.
- Registro y seguimiento de jobs de extracción de reportes (`pagofacil_reporting`).
- Disparo on-demand de jobs de reporte (escribe en `report_jobs`, lo que activa MS1).
- Generación de URLs pre-firmadas S3 para descarga de reportes completados.

**Dependencias de otros microservicios:** ninguna dependencia REST saliente hacia servicios internos.

**Dependencias de infraestructura:**

| Recurso | Tipo | Propósito |
|---|---|---|
| `pagofacil_readmodel` | PostgreSQL R2DBC (read-only) | Consulta de transacciones, alertas, billeteras proyectadas |
| `pagofacil_reporting` | PostgreSQL R2DBC (read-write, propietario) | Gestión de `report_schema_catalog` y `report_jobs` |
| AWS S3 | SDK (floci en dev) | Generar URLs pre-firmadas para descargar reportes |

> **Nota:** `audit-service` tiene dos data sources R2DBC. El primero (`pagofacil_readmodel`) es de solo lectura. El segundo (`pagofacil_reporting`) es el propietario exclusivo de las tablas de reportería.

---

## 2. Prerrequisitos

- Etapa 2b completa.
- Secret `pagofacil/dev/audit-service` en floci.
- Migraciones Liquibase de `db/audit-service/` aplicadas (incluye seed de `report_schema_catalog`).
- `projection-service` activo y habiendo proyectado al menos algunas transacciones en `pagofacil_readmodel`.

---

## 3. Ciclo de Desarrollo Incremental en K3d dev

```
Implementar caso de uso → mvn test (Red → Green) → git push
    → Jenkins pipeline → bumpImageTag → ArgoCD sync → K3d dev
```

> **Regla TDD:** la prueba se escribe y se ve **fallar (Red)** ANTES de implementar el código.

---

## 4. Capa de Dominio (`domain`) — _test-first_

### Entidades

| Entidad | Tabla fuente | BD | Reglas de negocio |
|---|---|---|---|
| `TransactionView` | `report_transactions` | `pagofacil_readmodel` | Read-only; no tiene métodos de mutación |
| `AlertView` | `report_alerts` | `pagofacil_readmodel` | Read-only para listados y detalle |
| `AlertResolution` | `report_alerts` | `pagofacil_readmodel` | `status` solo puede ir a `APROBADA` o `RECHAZADA`; inmutable una vez resuelta; `justification` longitud ≥ 10 |
| `ReportJob` | `report_jobs` | `pagofacil_reporting` | `status` transiciona: `ENCOLADO → EXTRAYENDO → PROCESANDO → COMPLETADO / FALLIDO`; `requestedBy` es el `userId` del JWT |
| `ReportSchemaCatalog` | `report_schema_catalog` | `pagofacil_reporting` | Read-only; pre-cargado por seed |

### Value Objects

| VO | Regla de validación |
|---|---|
| `ReportType` | Enum: `transacciones-diario`, `reporte-aml`, `alertas-fraude`, `saldo-usuarios`, `conciliacion` |
| `ReportFormat` | Enum: `PDF`, `XLS`, `CSV` |
| `AlertResolutionDecision` | Enum: `APROBADA`, `RECHAZADA` |
| `Justification` | Longitud ≥ 10 y ≤ 1000 |

### Puertos secundarios

```java
// TransactionViewRepository (read-only, fuente: pagofacil_readmodel)
Flux<TransactionView> searchByFilters(UUID tenantId, UUID userId, String status, LocalDate from, LocalDate to, int page, int size);
Mono<Long> countByFilters(UUID tenantId, UUID userId, String status, LocalDate from, LocalDate to);

// AlertViewRepository (read-only, fuente: pagofacil_readmodel)
Flux<AlertView> findByTenantIdAndStatus(UUID tenantId, String status, int page, int size);
Mono<AlertView> findById(UUID alertId);
Mono<AlertView> resolveAlert(UUID alertId, AlertResolution resolution);  // escribe en readmodel

// ReportJobRepository (fuente: pagofacil_reporting)
Mono<ReportJob> save(ReportJob job);
Mono<ReportJob> findById(UUID reportId);
Mono<ReportJob> updateStatus(UUID reportId, String status, String s3Key);

// ReportSchemaCatalogRepository (read-only, fuente: pagofacil_reporting)
Mono<ReportSchemaCatalog> findByReportType(String reportType);

// S3PresignedUrlPort
Mono<String> generateDownloadUrl(String s3Key, Duration ttl);
```

> **Nota sobre `resolveAlert`:** aunque `report_alerts` es parte del Read Model proyectado, la resolución de alertas es una operación administrativa inmutable que se escribe en el Read Model directamente por `audit-service`. Esta es una excepción controlada al principio de solo lectura del Read Model — las resoluciones de auditor son datos de audit, no proyecciones.

### Invariantes de dominio

- Una alerta resuelta no puede volver a `PENDIENTE`.
- Un `ReportJob` solo puede dispararse para tipos de reporte presentes en `report_schema_catalog`.
- `periodFrom` debe ser ≤ `periodTo` en un job de reporte.
- Los `formats` del job deben ser un subconjunto de `formats` definidos en `report_schema_catalog` para ese tipo.

---

## 5. Capa de Aplicación (`application`) — _test-first_

### Casos de uso

| Use Case | Descripción | Puerto primario | Puertos secundarios |
|---|---|---|---|
| `SearchTransactionsUseCase` | Búsqueda paginada de transacciones en Read Model con filtros | `SearchTransactionsInputPort` | `TransactionViewRepository` |
| `ListAlertsUseCase` | Lista alertas paginadas por tenant y estado | `ListAlertsInputPort` | `AlertViewRepository` |
| `GetAlertDetailUseCase` | Detalle completo de una alerta | `GetAlertInputPort` | `AlertViewRepository` |
| `ResolveAlertUseCase` | Resuelve alerta con decisión + justificación; valida que el usuario es auditor autorizado | `ResolveAlertInputPort` | `AlertViewRepository` |
| `TriggerReportJobUseCase` | Valida tipo de reporte contra catálogo; crea `ReportJob` con `status=ENCOLADO`; dispara el CronJob de MS1 on-demand vía anotación K8s o mensaje Kafka | `TriggerReportJobInputPort` | `ReportJobRepository`, `ReportSchemaCatalogRepository` |
| `GetReportStatusUseCase` | Consulta estado del job de reporte | `GetReportStatusInputPort` | `ReportJobRepository` |
| `DownloadReportUseCase` | Genera URL pre-firmada S3 con TTL 15 min; valida que `status=COMPLETADO` | `DownloadReportInputPort` | `ReportJobRepository`, `S3PresignedUrlPort` |

---

## 6. Capa de Infraestructura (`infrastructure`) — _test-first_

### Adaptadores R2DBC (dos data sources)

**DataSource 1 — `pagofacil_readmodel` (read-only):**

| Adaptador | Tabla | Operaciones |
|---|---|---|
| `TransactionViewR2dbcAdapter` | `report_transactions` | `searchByFilters` con paginación |
| `AlertViewR2dbcAdapter` | `report_alerts` | `findByTenantIdAndStatus`, `findById`, `resolveAlert` |

**DataSource 2 — `pagofacil_reporting` (read-write):**

| Adaptador | Tabla | Operaciones |
|---|---|---|
| `ReportJobR2dbcAdapter` | `report_jobs` | `save`, `findById`, `updateStatus` |
| `ReportSchemaCatalogR2dbcAdapter` | `report_schema_catalog` | `findByReportType` |

### Adaptador S3 (floci en dev)

```java
// S3PresignedUrlAdapter
Mono<String> generateDownloadUrl(String s3Key, Duration ttl) {
    // Usa AWS SDK v2 async; genera URL pre-firmada via S3Presigner
    // En dev: apunta a floci (LocalStack) endpoint
}
```

### Configuración de seguridad

- `GET /v1/audit/transactions`: JWT Bearer (auditor / compliance / administrador).
- `GET /v1/audit/alerts`: JWT Bearer (auditor).
- `PUT /v1/audit/alerts/{alertId}/resolve`: JWT Bearer; rol `AUDITOR` o `COMPLIANCE`; `tenantId` del JWT.
- `POST /v1/audit/reports/trigger`: JWT Bearer; rol `AUDITOR`.
- `GET /v1/audit/reports/{reportId}/status` y `/download`: JWT Bearer.

---

## 7. API REST (`rest-api`) — _test-first_

Especificación completa: `docs/design/api/SDD-PagoFacil-openapi.yaml` — tag `Audit`

| Método | Ruta | Request Body | Response | Códigos HTTP |
|---|---|---|---|---|
| GET | `/v1/audit/transactions` | — (query params) | `TransaccionPageResponse` | 200, 401, 403 |
| GET | `/v1/audit/alerts` | — (query params) | `AlertaPageResponse` | 200, 401 |
| GET | `/v1/audit/alerts/{alertId}` | — | `AlertaDetalleResponse` | 200, 404 |
| PUT | `/v1/audit/alerts/{alertId}/resolve` | `ResolucionAlertaRequest` | `AlertaDetalleResponse` | 200, 409 |
| POST | `/v1/audit/reports/trigger` | `ReporteTriggerRequest` | `ReporteJobResponse` | 202 |
| GET | `/v1/audit/reports/{reportId}/status` | — | `ReporteJobResponse` | 200, 404 |
| GET | `/v1/audit/reports/{reportId}/download` | — | — (redirect 302 a URL S3) | 302, 404 |

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> Tipos reactivos verificados con `StepVerifier`.

### Dominio

| Clase de test | Método | Invariante | Elemento de Sección 4 |
|---|---|---|---|
| `AlertResolutionTest` | `shouldNotAllowResolutionOfAlreadyResolvedAlert` | Alerta resuelta es inmutable | `AlertResolution` |
| `ReportJobTest` | `shouldRejectInvalidDateRange` | `periodFrom > periodTo` → excepción | Entidad `ReportJob` |
| `ReportJobTest` | `shouldValidateFormatsAgainstCatalog` | Formato no en catálogo → excepción | Dominio `ReportJob` + `ReportSchemaCatalog` |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case |
|---|---|---|---|---|
| `SearchTransactionsUseCaseTest` | `shouldReturnPagedResultsForTenant` | Happy path con filtros | `TransactionViewRepository` (mock) | `SearchTransactionsUseCase` |
| `ResolveAlertUseCaseTest` | `shouldResolveWithValidJustification` | Happy path | `AlertViewRepository` (mock) | `ResolveAlertUseCase` |
| `ResolveAlertUseCaseTest` | `shouldThrowOnAlreadyResolvedAlert` | Alerta ya resuelta | `AlertViewRepository` (mock ya resuelta) | `ResolveAlertUseCase` |
| `TriggerReportJobUseCaseTest` | `shouldCreateEnqueuedJobForValidType` | Happy path | `ReportJobRepository`, `ReportSchemaCatalogRepository` (mock) | `TriggerReportJobUseCase` |
| `TriggerReportJobUseCaseTest` | `shouldFailForUnknownReportType` | Tipo no en catálogo | `ReportSchemaCatalogRepository` (mock vacío) | `TriggerReportJobUseCase` |
| `DownloadReportUseCaseTest` | `shouldGeneratePresignedUrl` | Happy path: job COMPLETADO con s3_key | `ReportJobRepository`, `S3PresignedUrlPort` (mock URL) | `DownloadReportUseCase` |
| `DownloadReportUseCaseTest` | `shouldFailIfJobNotCompleted` | Job aún en proceso | `ReportJobRepository` (mock PROCESANDO) | `DownloadReportUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador |
|---|---|---|---|
| `TransactionViewR2dbcAdapterTest` | `shouldReturnFilteredTransactionsFromReadModel` | SELECT con múltiples filtros en Testcontainers (readmodel) | `TransactionViewR2dbcAdapter` |
| `AlertViewR2dbcAdapterTest` | `shouldUpdateAlertResolution` | UPDATE `fraud_alerts` con Testcontainers | `AlertViewR2dbcAdapter` |
| `ReportJobR2dbcAdapterTest` | `shouldSaveAndUpdateStatus` | INSERT + UPDATE en `report_jobs` (Testcontainers reporting) | `ReportJobR2dbcAdapter` |
| `S3PresignedUrlAdapterTest` | `shouldGenerateValidPresignedUrl` | Genera URL con SDK v2 async contra floci S3 | `S3PresignedUrlAdapter` |

### REST

| Clase de test | Método | Endpoint | Status / body | Elemento |
|---|---|---|---|---|
| `AuditControllerTest` | `shouldReturn200WithTransactionPage` | `GET /v1/audit/transactions` | 200 + `content[]` | GET transactions |
| `AuditControllerTest` | `shouldReturn200OnAlertResolve` | `PUT /v1/audit/alerts/{id}/resolve` | 200 + `auditorDecision` | PUT resolve |
| `AuditControllerTest` | `shouldReturn409OnAlreadyResolvedAlert` | `PUT /v1/audit/alerts/{id}/resolve` | 409 | PUT resolve |
| `AuditControllerTest` | `shouldReturn202OnReportTrigger` | `POST /v1/audit/reports/trigger` | 202 + `reportId`, `status: ENCOLADO` | POST trigger |
| `AuditControllerTest` | `shouldReturn302OnReportDownload` | `GET /v1/audit/reports/{id}/download` | 302 con `Location` S3 URL | GET download |

### Umbrales de cobertura mínima

| Capa | Umbral |
|---|---|
| `domain` | ≥ 85% |
| `application` | ≥ 85% |
| `infrastructure` | ≥ 80% |
| `rest-api` | ≥ 80% |

---

## 9. Criterios de Aceptación

- [ ] Cada elemento de cada capa tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] `mvn test` finaliza en verde.
- [ ] La cobertura por capa cumple los umbrales.
- [ ] `GET /v1/audit/transactions` retorna paginación con datos del Read Model.
- [ ] `PUT /v1/audit/alerts/{alertId}/resolve` con decisión válida retorna 200 e inmutabiliza la alerta.
- [ ] `POST /v1/audit/reports/trigger` crea el `report_jobs` en estado `ENCOLADO`.
- [ ] `GET /v1/audit/reports/{reportId}/download` (job COMPLETADO) retorna 302 con URL pre-firmada S3 válida.
- [ ] Pipeline CI despliega en K3d: `kubectl get pods -n dev | grep audit-service` muestra `Running`.
