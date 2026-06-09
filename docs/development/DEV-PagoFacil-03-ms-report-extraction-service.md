# Etapa 3h — report-extraction-service (MS1, Spark)

**Proyecto:** PagoFacil — Billetera Digital
**Bounded Context:** BC-07 Reporting — ETL Extracción
**Tecnología:** Apache Spark 3.5.1 + Scala 3 + sbt 1.9
**Despliegue:** Kubernetes CronJob (schedule `0 2 * * *`) — NO es un Deployment HTTP
**Scaffolding:** `scala_hexagonal_scaffold.py --report-role extraction --source jdbc --pg-db pagofacil --org pagofacil`

---

## 1. Contexto y Responsabilidad

MS1 es un **job batch Spark** que lee el read model CQRS (`pagofacil_readmodel`) vía JDBC, valida el esquema extraído contra el catálogo y genera archivos Parquet en S3/floci. **No expone endpoints HTTP.** El pipeline CI termina en `bumpImageTag` (sin smoke tests).

### Responsabilidades

- Extracción de datos de `pagofacil_readmodel` via `SparkJdbcSourceAdapter`.
- Validación del DataFrame extraído contra `pagofacil_reporting.report_schema_catalog`.
- Generación de archivos Parquet en S3 `raw/{report_type}/{execution_id}/`.
- Publicación de evento `report.extracted` (éxito) o `report.extraction_failed` (fallo con motivo).
- Ejecución como CronJob K8s a las 02:00 o vía trigger on-demand.

### Dependencias de infraestructura

| Recurso | Detalles |
|---|---|
| PostgreSQL `pagofacil_readmodel` | JDBC `jdbc:postgresql://VPS_IP:5432/pagofacil_readmodel` — solo lectura |
| PostgreSQL `pagofacil_reporting` | JDBC — consulta `report_schema_catalog` y actualiza `report_executions` |
| S3 / floci | `http://VPS_IP:4566` — escritura en `raw/` |
| Kafka | `VPS_IP:29092` — publicación de eventos del pipeline |
| Secret | `pagofacil/dev/report-extraction-service` en floci |

---

## 2. Prerrequisitos

- [ ] Etapas 0, 0c, 1, 2, 2b completadas.
- [ ] Etapa 3g (`projection-service`) funcional con datos en `pagofacil_readmodel`.
- [ ] `pagofacil_reporting.report_schema_catalog` populado con los 3 tipos de reporte.
- [ ] Bucket S3 `pagofacil-reports` creado en floci `VPS_IP:4566`.
- [ ] Kafka activo en `VPS_IP:29092`.
- [ ] Secret `pagofacil/dev/report-extraction-service` en floci.

---

## 3. Ciclo de Desarrollo Incremental en K3s VPS dev

MS1 es un CronJob, no un Deployment. ArgoCD sincroniza el CronJob cuando `bumpImageTag` actualiza el tag en `helm/report-extraction-service/values-dev.yaml`.

```
sbt test (local) → git push → Jenkins CI (buildScalaBatchJob, sin smoke tests)
→ sbt assembly → buildAndPushImage → bumpImageTag
→ ArgoCD sync → K3s CronJob actualizado
→ Ejecución en siguiente schedule (02:00) o trigger manual con kubectl
```

> **TDD obligatorio — prueba FALLA (Red) antes del código (Green). ScalaTest + StepVerifier donde aplique.**

---

## 4. Capa de Dominio (`domain`) — test-first

### Tipos de dominio

```scala
// ReportType — tipos de reporte soportados
enum ReportType:
  case TRANSACTIONS, COMPLIANCE_ALERTS, USERS

// ColumnSpec — especificación de columna esperada
case class ColumnSpec(name: String, dataType: String, nullable: Boolean)

// IntegrityRule — regla de validación de integridad
case class IntegrityRule(ruleType: String, params: Map[String, String])

// ReportSchema — esquema completo de un reporte
case class ReportSchema(
  reportType: ReportType,
  schemaVersion: String,
  columns: List[ColumnSpec],
  integrityRules: List[IntegrityRule],
  sourceTable: String
):
  // Invariante: debe tener al menos una columna
  require(columns.nonEmpty, "ReportSchema must have at least one column")
  // Invariante: todos los nombres de columna son únicos
  require(columns.map(_.name).distinct.size == columns.size, "Column names must be unique")

// PeriodRange
case class PeriodRange(from: LocalDate, to: LocalDate):
  require(!from.isAfter(to), "from must be before or equal to to")
```

### Puertos secundarios

```scala
trait SourceDataPort:
  def extract(reportType: ReportType, period: PeriodRange): Try[DataFrame]

trait ParquetStorePort:
  def write(df: DataFrame, path: String): Try[String]  // retorna el path escrito

trait EventBusPort:
  def publish(topic: String, event: Map[String, Any]): Try[Unit]

trait SchemaCatalogPort:
  def findByReportType(reportType: ReportType): Try[ReportSchema]

trait ReportExecutionRepository:
  def updateStatus(executionId: UUID, status: String, parquetRawPath: Option[String], error: Option[String]): Try[Unit]
```

---

## 5. Capa de Aplicación (`application`) — test-first

### `ValidateAndExtractUseCase`

Flujo del use case:

1. Lee `ReportSchema` del catálogo via `SchemaCatalogPort`.
2. Extrae datos via `SourceDataPort` (SparkJdbcSourceAdapter).
3. Valida que el DataFrame tenga exactamente las columnas del esquema (nombres + tipos).
4. Valida `integrityRules` (p. ej. `NOT_NULL` en columnas críticas, `MIN_ROWS` > 0).
5. Si validación OK → escribe Parquet via `ParquetStorePort` → actualiza `report_executions` → publica `report.extracted`.
6. Si validación FALLA → publica `report.extraction_failed` con `reason: SCHEMA_VALIDATION` → **no genera Parquet** → actualiza `report_executions` con status FAILED.

```scala
case class ExtractionRequest(
  tenantId: UUID,
  reportType: ReportType,
  period: PeriodRange,
  executionId: UUID
)

case class ExtractionResult(
  success: Boolean,
  parquetPath: Option[String],
  errorReason: Option[String]
)
```

---

## 6. Capa de Infraestructura (`infrastructure`) — test-first

### `SparkJdbcSourceAdapter`

Implementa `SourceDataPort`. Conecta a `pagofacil_readmodel` via JDBC:

```scala
val jdbcUrl = s"jdbc:postgresql://${config.pgHost}:5432/pagofacil_readmodel"

// SQL por ReportType
val sql = reportType match
  case ReportType.TRANSACTIONS =>
    s"SELECT * FROM report_transactions WHERE tenant_id='$tenantId' AND created_at BETWEEN '$from' AND '$to'"
  case ReportType.COMPLIANCE_ALERTS =>
    s"SELECT * FROM report_compliance_alerts WHERE tenant_id='$tenantId' AND created_at BETWEEN '$from' AND '$to'"
  case ReportType.USERS =>
    s"SELECT * FROM report_users WHERE tenant_id='$tenantId' AND registered_at BETWEEN '$from' AND '$to'"
```

### `SparkS3ParquetAdapter`

Implementa `ParquetStorePort`. Escribe en S3/floci:

```scala
df.write.mode("overwrite").parquet(s"s3a://pagofacil-reports/raw/$reportType/$executionId/")
```

Configuración Spark S3A para floci:
- `spark.hadoop.fs.s3a.endpoint = http://VPS_IP:4566`
- `spark.hadoop.fs.s3a.path.style.access = true`

### `KafkaEventPublisher`

Implementa `EventBusPort`. Usa `KafkaProducer` con JSON serialization.

### `SchemaCatalogJdbcAdapter`

Implementa `SchemaCatalogPort`. Consulta `pagofacil_reporting.report_schema_catalog` via JDBC.

---

## 7. Capa de Pipeline (`entry-points`)

```scala
object ReportExtractionJob:
  def main(args: Array[String]): Unit =
    val config = Config.fromEnv()
    val spark = SparkSession.builder()
      .appName("pagofacil-report-extraction")
      .getOrCreate()
    
    // Wiring de adaptadores (SparkSession confinado a infra)
    val useCase = ValidateAndExtractUseCase(
      sourceData = SparkJdbcSourceAdapter(spark, config),
      parquetStore = SparkS3ParquetAdapter(spark, config),
      eventBus = KafkaEventPublisher(config),
      schemaCatalog = SchemaCatalogJdbcAdapter(config),
      executionRepo = ReportExecutionJdbcAdapter(config)
    )
    
    val request = ExtractionRequest(
      tenantId = UUID.fromString(config.tenantId),
      reportType = ReportType.valueOf(config.reportType),
      period = PeriodRange(config.periodFrom, config.periodTo),
      executionId = UUID.fromString(config.executionId)
    )
    
    useCase.execute(request) match
      case Success(_) => sys.exit(0)
      case Failure(e) => logger.error("Extraction failed", e); sys.exit(1)
```

`SparkSession` y `DataFrame` están **confinados a la capa de infraestructura** — nunca aparecen en dominio ni aplicación.

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> ScalaTest. Prueba FALLA (Red) antes del código (Green).

### Dominio

| Clase de test | Método | Invariante / Regla | Elemento que precede |
|---|---|---|---|
| `ReportSchemaSpec` | `should reject schema with no columns` | `require(columns.nonEmpty)` | `ReportSchema` constructor |
| `ReportSchemaSpec` | `should reject schema with duplicate column names` | Unicidad de nombres | `ReportSchema` constructor |
| `PeriodRangeSpec` | `should reject from after to` | `from <= to` | `PeriodRange` constructor |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case que precede |
|---|---|---|---|---|
| `ValidateAndExtractUseCaseSpec` | `should extract and write parquet when schema is valid` | Happy path | Todos los puertos (mocks) | `ValidateAndExtractUseCase` |
| `ValidateAndExtractUseCaseSpec` | `should publish extraction_failed when column missing` | AC-008-E2 | `SourceDataPort` devuelve DF sin columna requerida | `ValidateAndExtractUseCase` |
| `ValidateAndExtractUseCaseSpec` | `should publish extraction_failed when jdbc fails` | AC-008-E1 | `SourceDataPort` lanza excepción | `ValidateAndExtractUseCase` |
| `ValidateAndExtractUseCaseSpec` | `should not generate parquet when validation fails` | AC-008-E2 | `ParquetStorePort` NO debe ser invocado | `ValidateAndExtractUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador que precede |
|---|---|---|---|
| `SparkJdbcSourceAdapterSpec` | `should read transactions from readmodel` | JDBC → DataFrame | `SparkJdbcSourceAdapter` (Testcontainers PostgreSQL con fixture) |
| `SparkS3ParquetAdapterSpec` | `should write and read parquet round-trip` | Escribe → lee → mismo schema | `SparkS3ParquetAdapter` (SparkSession local + S3 floci) |
| `KafkaEventPublisherSpec` | `should publish extracted event with correct payload` | Publica JSON | `KafkaEventPublisher` (Testcontainers Kafka) |

### Umbrales de cobertura

| Capa | Umbral mínimo |
|---|---|
| `domain` + `application` | ≥ 85% |
| `infrastructure` | ≥ 80% |

---

## 9. Despliegue K8s (CronJob)

```yaml
# helm/report-extraction-service/templates/cronjob.yaml
spec:
  schedule: "0 2 * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: report-extraction
              image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
              env:
                - name: REPORT_TYPE
                  value: "{{ .Values.job.reportType }}"
```

Jenkins termina en `bumpImageTag` — **sin smoke tests HTTP**. ArgoCD sincroniza el CronJob.

---

## 10. Criterios de Aceptación

- [ ] `sbt compile` y `sbt assembly` en verde.
- [ ] `sbt test` en verde; cobertura por capa cumple umbrales.
- [ ] Validación fallida (columna faltante) → evento `report.extraction_failed` en Kafka con `reason: SCHEMA_VALIDATION`; **sin archivo Parquet en S3**.
- [ ] Error JDBC al leer `pagofacil_readmodel` → evento `report.extraction_failed` con `reason: JDBC_ERROR`; sin Parquet.
- [ ] Happy path: datos en readmodel → Parquet escrito en S3 `raw/{reportType}/{executionId}/`; evento `report.extracted` publicado.
- [ ] `report_executions.status` actualizado a `COMPLETED` o `FAILED` según resultado.
- [ ] CronJob K3s ejecuta a las 02:00 UTC; `kubectl get cronjob report-extraction-service -n default` muestra el schedule correcto.
