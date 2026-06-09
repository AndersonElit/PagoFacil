# Etapa 3i — report-processing-service (MS2, Spark)

**Proyecto:** PagoFacil — Billetera Digital
**Bounded Context:** BC-07 Reporting — ETL Transformación
**Tecnología:** Apache Spark 3.5.1 + Scala 3 + sbt 1.9
**Despliegue:** Kubernetes CronJob (schedule `0 3 * * *`) — NO es un Deployment HTTP
**Scaffolding:** `scala_hexagonal_scaffold.py --report-role processing`

---

## 1. Contexto y Responsabilidad

MS2 es un **job batch Spark** que transforma los Parquet `raw/` producidos por MS1 mediante el **patrón Factory (Abierto/Cerrado)**. Escribe Parquet en S3 `processed/` y publica `report.processed`. **No expone endpoints HTTP.** El pipeline CI termina en `bumpImageTag`.

### Responsabilidades

- Consumo del evento `report.extracted` y lectura del Parquet `raw/` desde S3.
- Transformación de datos por `ReportType` mediante `ReportTransformerFactory`.
- Generación de Parquet en S3 `processed/{report_type}/{execution_id}/`.
- Publicación del evento `report.processed`.

### Dependencias de infraestructura

| Recurso | Detalles |
|---|---|
| S3 / floci | `http://VPS_IP:4566` — lectura de `raw/`; escritura en `processed/` |
| Kafka | `VPS_IP:29092` — consume `report.extracted`; publica `report.processed` |
| Secret | `pagofacil/dev/report-processing-service` en floci |

---

## 2. Prerrequisitos

- [ ] Etapas 0, 0c, 1, 2, 2b completadas.
- [ ] Etapa 3h (MS1) funcional; Parquet en S3 `raw/` disponible.
- [ ] S3/floci activo `VPS_IP:4566` con bucket `pagofacil-reports`.
- [ ] Kafka activo en `VPS_IP:29092`.
- [ ] Secret `pagofacil/dev/report-processing-service` en floci.

---

## 3. Ciclo de Desarrollo Incremental en K3s VPS dev

```
sbt test (local) → git push → Jenkins CI (sin smoke tests)
→ sbt assembly → buildAndPushImage → bumpImageTag
→ ArgoCD sync → K3s CronJob actualizado
→ Ejecución a las 03:00 (1h después de MS1) o trigger manual
```

> **TDD obligatorio — ScalaTest. Prueba FALLA (Red) antes del código (Green).**

---

## 4. Capa de Dominio (`domain`) — test-first

### Patrón Factory (Abierto/Cerrado)

```scala
// Trait base — contrato de cada transformador
trait ReportTransformer:
  def transform(rawData: DataFrame): Try[DataFrame]
  def reportType: ReportType

// Factory — registro de transformadores
class ReportTransformerFactory(
  transformers: Map[ReportType, ReportTransformer]
):
  def get(reportType: ReportType): Either[UnsupportedReportTypeException, ReportTransformer] =
    transformers.get(reportType).toRight(UnsupportedReportTypeException(reportType))

case class UnsupportedReportTypeException(reportType: ReportType)
  extends RuntimeException(s"No transformer registered for report type: $reportType")
```

**Regla Abierto/Cerrado:** añadir un nuevo `ReportType` = crear nueva clase `XxxReportTransformer` + registrar en el mapa de la factory. `ProcessReportUseCase` **no se modifica**.

### Transformadores implementados

| Clase | Transformaciones |
|---|---|
| `TransactionsReportTransformer` | Filtra por tenant; calcula totales por tipo y moneda; agrega por período; enriquece con estado |
| `ComplianceAlertsReportTransformer` | Agrupa por tipo y nivel de riesgo; calcula tiempo promedio de resolución; cuenta por estado |
| `UsersReportTransformer` | Proyección de usuarios con estado KYC; cuenta por kyc_status; selecciona columnas de salida |

### Puertos secundarios

```scala
trait ParquetReaderPort:
  def read(path: String): Try[DataFrame]

trait ParquetWriterPort:
  def write(df: DataFrame, path: String): Try[String]

trait EventBusPort:
  def publish(topic: String, event: Map[String, Any]): Try[Unit]
```

---

## 5. Capa de Aplicación (`application`) — test-first

### `ProcessReportUseCase`

```scala
case class ProcessingRequest(
  executionId: UUID,
  reportType: ReportType,
  parquetRawPath: String,
  tenantId: UUID
)

class ProcessReportUseCase(
  factory: ReportTransformerFactory,
  reader: ParquetReaderPort,
  writer: ParquetWriterPort,
  eventBus: EventBusPort
):
  def execute(request: ProcessingRequest): Try[ProcessingResult] =
    for
      transformer  <- factory.get(request.reportType).toTry
      rawData      <- reader.read(request.parquetRawPath)
      processed    <- transformer.transform(rawData)
      outputPath   <- writer.write(processed, s"processed/${request.reportType}/${request.executionId}/")
      _            <- eventBus.publish("report.processed", Map(
                        "execution_id" -> request.executionId,
                        "report_type"  -> request.reportType,
                        "parquet_processed_path" -> outputPath
                      ))
    yield ProcessingResult(success = true, processedPath = Some(outputPath))
```

**`ProcessReportUseCase` no conoce los transformadores concretos** — solo delega a la factory.

---

## 6. Capa de Infraestructura (`infrastructure`) — test-first

| Adaptador | Puerto | Detalles |
|---|---|---|
| `SparkS3ParquetReader` | `ParquetReaderPort` | Lee Parquet desde S3/floci vía `spark.read.parquet(path)` |
| `SparkS3ParquetWriter` | `ParquetWriterPort` | Escribe en `s3a://pagofacil-reports/processed/...` |
| `KafkaEventConsumer` | Entry-point | Consume `report.extracted`; extrae payload; dispara el job |
| `KafkaEventPublisher` | `EventBusPort` | Publica `report.processed` |

Configuración S3A igual a MS1 (endpoint floci `VPS_IP:4566`).

---

## 7. Capa de Pipeline (`entry-points`)

```scala
object ReportProcessingJob:
  def main(args: Array[String]): Unit =
    val config = Config.fromEnv()
    val spark  = SparkSession.builder().appName("pagofacil-report-processing").getOrCreate()
    
    val factory = ReportTransformerFactory(Map(
      ReportType.TRANSACTIONS      -> TransactionsReportTransformer(spark),
      ReportType.COMPLIANCE_ALERTS -> ComplianceAlertsReportTransformer(spark),
      ReportType.USERS             -> UsersReportTransformer(spark)
    ))
    
    val useCase = ProcessReportUseCase(
      factory  = factory,
      reader   = SparkS3ParquetReader(spark, config),
      writer   = SparkS3ParquetWriter(spark, config),
      eventBus = KafkaEventPublisher(config)
    )
    
    val request = ProcessingRequest(
      executionId     = UUID.fromString(config.executionId),
      reportType      = ReportType.valueOf(config.reportType),
      parquetRawPath  = config.parquetRawPath,
      tenantId        = UUID.fromString(config.tenantId)
    )
    
    useCase.execute(request).get  // lanza excepción si falla → CronJob restartPolicy: Never
```

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> ScalaTest. Prueba FALLA (Red) antes del código (Green).

### Dominio

| Clase de test | Método | Regla | Elemento que precede |
|---|---|---|---|
| `ReportTransformerFactorySpec` | `should return correct transformer for known report type` | Factory lookup exitoso | `ReportTransformerFactory.get()` |
| `ReportTransformerFactorySpec` | `should return Left for unknown report type` | `UnsupportedReportTypeException` | `ReportTransformerFactory.get()` |
| `TransactionsReportTransformerSpec` | `should aggregate transactions by currency` | Transformación correcta | `TransactionsReportTransformer.transform()` con fixture parquet |
| `ComplianceAlertsReportTransformerSpec` | `should group alerts by risk level` | Agrupación correcta | `ComplianceAlertsReportTransformer.transform()` |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case que precede |
|---|---|---|---|---|
| `ProcessReportUseCaseSpec` | `should process report when all steps succeed` | Happy path | `ReportTransformerFactory`, `ParquetReaderPort`, `ParquetWriterPort`, `EventBusPort` (mocks) | `ProcessReportUseCase` |
| `ProcessReportUseCaseSpec` | `should fail when report type is unsupported` | `UnsupportedReportTypeException` | Factory devuelve `Left` | `ProcessReportUseCase` |
| `ProcessReportUseCaseSpec` | `should not modify use case when adding new report type` | Abierto/Cerrado verificado | Añadir `FakeNewTransformer` al mapa sin tocar `ProcessReportUseCase` | `ProcessReportUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador que precede |
|---|---|---|---|
| `SparkS3ParquetReaderSpec` | `should read parquet from S3 path` | Lectura round-trip | `SparkS3ParquetReader` (SparkSession local + S3 floci) |
| `KafkaEventConsumerSpec` | `should trigger processing on extracted event` | Consume Kafka → job disparado | `KafkaEventConsumer` (Testcontainers Kafka) |
| `KafkaEventPublisherSpec` | `should publish processed event with correct payload` | Publica `report.processed` | `KafkaEventPublisher` (Testcontainers Kafka) |

### Umbrales de cobertura

| Capa | Umbral mínimo |
|---|---|
| `domain` + `application` | ≥ 85% |
| `infrastructure` | ≥ 80% |

---

## 9. Despliegue K8s (CronJob)

```yaml
spec:
  schedule: "0 3 * * *"   # 1h después de MS1
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
```

Jenkins termina en `bumpImageTag` — sin smoke tests. ArgoCD sincroniza el CronJob.

---

## 10. Criterios de Aceptación

- [ ] `sbt compile` y `sbt assembly` en verde.
- [ ] `sbt test` en verde; cobertura cumple umbrales.
- [ ] Añadir un nuevo `ReportType` = crear nueva clase transformer + registro en factory; `ProcessReportUseCase` **no se modifica** (Abierto/Cerrado verificado en prueba).
- [ ] Happy path: Parquet `raw/` → transformado → Parquet `processed/`; evento `report.processed` publicado en Kafka.
- [ ] `ReportType` desconocido → `UnsupportedReportTypeException`; evento de fallo publicado.
- [ ] CronJob K3s ejecuta a las 03:00 UTC con `concurrencyPolicy: Forbid`.
- [ ] ArgoCD muestra CronJob en estado `Synced` tras el pipeline CI.
