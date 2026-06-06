# Etapa 3 — MS2: report-processing-service (Spark)

**Proyecto:** PagoFacil | **Tipo:** Job batch Spark (CronJob K8s) | **BC:** BC-07 Reporting  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Contexto y Responsabilidad

**Tipo:** Job batch Apache Spark 3.5.1 / Scala 2.13. No es un servicio REST persistente.

**Responsabilidad principal:**
- Consumir el evento `report.extracted` de Kafka (trigger del job).
- Cargar el Parquet `raw/` desde S3 generado por MS1.
- Aplicar transformaciones por `ReportType` usando el **patrón Factory** (abierto/cerrado — ADR-006).
- Generar Parquet transformado en S3 (`pagofacil-parquet-processed/`).
- Publicar evento `report.processed` a Kafka para consumo de la capa serverless.

**Dependencias:**

| Recurso | Tipo | Propósito |
|---|---|---|
| S3 `pagofacil-parquet-raw/` | SDK (floci en dev) read-only | Parquet de entrada de MS1 |
| S3 `pagofacil-parquet-processed/` | SDK (floci en dev) write | Parquet de salida para lambdas |
| Kafka `report.extracted` | Consumer | Trigger del job |
| Kafka `report.processed` | Producer | Notifica a la capa serverless |

---

## 2. Prerrequisitos

- Etapa 3h completa (MS1 disponible y publicando `report.extracted`).
- Secret `pagofacil/dev/report-processing-service` en floci.
- Buckets S3 `pagofacil-parquet-raw` y `pagofacil-parquet-processed` en floci.

---

## 3. Ciclo de Desarrollo Incremental en K3d dev

**MS2 es un CronJob, no un Deployment.** Pipeline CI termina en `bumpImageTag`. Sin smoke tests HTTP.

```
Implementar transformer → sbt test (Red → Green) → git push
    → Jenkins pipeline (sbt) → buildScalaBatchJob → bumpImageTag
    → ArgoCD sync → K3d CronJob actualizado
    → Probar: kubectl create job --from=cronjob/report-processing-service test-run-1
```

> **Regla TDD:** la prueba de cada `ReportTransformer` se escribe y se ve **fallar (Red)** ANTES de implementar la transformación.

---

## 4. Capa de Dominio (`domain`) — _test-first_

### Patrón Factory — tipos de dominio

```scala
// Contrato del transformador
trait ReportTransformer {
  def reportType: ReportType
  def transform(raw: DataFrame): DataFrame  // aplica limpieza, agregaciones, enriquecimiento
  def validate(transformed: DataFrame): Boolean
}

// Factory — registro de transformadores
class ReportTransformerFactory(transformers: Map[ReportType, ReportTransformer]) {
  def getTransformer(reportType: ReportType): Either[UnsupportedReportTypeException, ReportTransformer] =
    transformers.get(reportType).toRight(new UnsupportedReportTypeException(reportType))
}
```

### Transformadores por tipo de reporte

| ReportType | Clase | Transformaciones aplicadas |
|---|---|---|
| `TransaccionesDiario` | `TransaccionesDiarioTransformer` | Filtrar CONFIRMADAS, agregar por día/tenant, calcular totales |
| `ReporteAml` | `ReporteAmlTransformer` | Filtrar MATCH/INCIERTO, enriquecer con tipo de alerta |
| `AlertasFraude` | `AlertasFraudeTransformer` | Agrupar por severidad, calcular tasa de retención por tenant |
| `SaldoUsuarios` | `SaldoUsuariosTransformer` | Calcular balance promedio/máximo/mínimo por tenant |
| `Conciliacion` | `ConciliacionTransformer` | Calcular discrepancias netas, clasificar por tipo |

### Puertos secundarios

```scala
// ParquetSourcePort
trait ParquetSourcePort {
  def read(s3Key: String): DataFrame
}

// ParquetSinkPort
trait ParquetSinkPort {
  def write(df: DataFrame, s3Key: String): Unit
}

// EventBusPort
trait EventBusPort {
  def publishProcessed(event: ReportProcessedEvent): Unit
  def publishFailed(event: ReportProcessingFailedEvent): Unit
}
```

### Invariantes de dominio

- Añadir un nuevo tipo de reporte = añadir la clase `ReportTransformer` correspondiente y registrarla en `ReportTransformerFactory`. **No se modifica `ProcessReportUseCase`** (Principio Abierto/Cerrado).
- Si el `ReportType` no está registrado en la factory → `UnsupportedReportTypeException` → evento de fallo publicado sin abortar el proceso.
- El Parquet `raw/` de entrada se lee en modo append (no borra el original).

---

## 5. Capa de Aplicación (`application`) — _test-first_

```scala
class ProcessReportUseCase(
  transformerFactory: ReportTransformerFactory,
  parquetSourcePort: ParquetSourcePort,
  parquetSinkPort: ParquetSinkPort,
  eventBusPort: EventBusPort
) {
  def execute(event: ReportExtractedEvent): Try[Unit] = {
    for {
      transformer <- transformerFactory.getTransformer(event.reportType).toTry
      rawDf       <- Try(parquetSourcePort.read(event.s3KeyRaw))
      processedDf <- Try(transformer.transform(rawDf))
      _           <- Try { require(transformer.validate(processedDf), "Validación post-transformación fallida") }
      s3KeyProc   =  buildProcessedKey(event)
      _           <- Try(parquetSinkPort.write(processedDf, s3KeyProc))
      _           <- Try(eventBusPort.publishProcessed(ReportProcessedEvent(event.jobId, event.reportType, s3KeyProc, event.formats)))
    } yield ()
  }
}
```

---

## 6. Capa de Infraestructura (`infrastructure`) — _test-first_

### Entry Point — Kafka Consumer (trigger del job)

```scala
// entry-points/kafka-consumer
object ReportProcessingEntryPoint extends App {
  val event = KafkaConsumerAdapter.consumeOne[ReportExtractedEvent]("report.extracted")
  val result = processReportUseCase.execute(event)
  result.recover { case ex => eventBusPort.publishFailed(ReportProcessingFailedEvent(...)) }
}
```

### Adaptadores S3

```scala
class SparkS3ParquetSourceAdapter(spark: SparkSession, s3Endpoint: String) extends ParquetSourcePort {
  def read(s3Key: String): DataFrame =
    spark.read.parquet(s"s3a://pagofacil-parquet-raw/$s3Key")
}

class SparkS3ParquetSinkAdapter(spark: SparkSession, s3Endpoint: String) extends ParquetSinkPort {
  def write(df: DataFrame, s3Key: String): Unit =
    df.write.mode("overwrite").parquet(s"s3a://pagofacil-parquet-processed/$s3Key")
}
```

---

## 7. API REST

MS2 es un job batch. No expone endpoints HTTP. No hay smoke tests en el pipeline CI.

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> Tests con ScalaTest FlatSpec, Spark en modo local, Parquet en `/tmp` para fixtures.

### Dominio

| Clase de test | Método | Invariante | Elemento |
|---|---|---|---|
| `ReportTransformerFactoryTest` | `shouldReturnTransformerForKnownType` | Tipo registrado → `Right(transformer)` | `ReportTransformerFactory` |
| `ReportTransformerFactoryTest` | `shouldReturnErrorForUnknownType` | Tipo no registrado → `Left(UnsupportedReportTypeException)` | `ReportTransformerFactory` |
| `TransaccionesDiarioTransformerTest` | `shouldAggregateByDayAndTenant` | Agregación correcta | `TransaccionesDiarioTransformer` |
| `TransaccionesDiarioTransformerTest` | `shouldFilterOnlyConfirmedTransactions` | Solo CONFIRMADAS en output | `TransaccionesDiarioTransformer` |
| `ReporteAmlTransformerTest` | `shouldEnrichWithAlertType` | Campo `alertType` presente en output | `ReporteAmlTransformer` |
| `AlertasFraudeTransformerTest` | `shouldGroupBySeverity` | Agrupación correcta por severidad | `AlertasFraudeTransformer` |
| `SaldoUsuariosTransformerTest` | `shouldCalculateAverageBalance` | Balance promedio calculado correctamente | `SaldoUsuariosTransformer` |
| `ConciliacionTransformerTest` | `shouldClassifyDiscrepancyByType` | Clasificación por tipo de discrepancia | `ConciliacionTransformer` |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case |
|---|---|---|---|---|
| `ProcessReportUseCaseTest` | `shouldTransformAndPublishOnSuccess` | Happy path con fixture Parquet | `ParquetSourcePort`, `ParquetSinkPort`, `EventBusPort` (mocks) | `ProcessReportUseCase` |
| `ProcessReportUseCaseTest` | `shouldPublishFailureOnUnsupportedType` | Tipo no registrado | `ReportTransformerFactory` devuelve Left | `ProcessReportUseCase` |
| `ProcessReportUseCaseTest` | `shouldPublishFailureOnTransformError` | Transformación lanza excepción | `transformer.transform` mock lanza | `ProcessReportUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador |
|---|---|---|---|
| `SparkS3ParquetSourceAdapterTest` | `shouldReadParquetFromS3` | Lee Parquet de S3 floci (fixture pre-escrito por MS1 test) | `SparkS3ParquetSourceAdapter` |
| `SparkS3ParquetSinkAdapterTest` | `shouldWriteProcessedParquetToS3` | Escribe en S3 floci bucket processed | `SparkS3ParquetSinkAdapter` |
| `KafkaConsumerAdapterTest` | `shouldConsumeReportExtractedEvent` | Consume de Kafka embebido | Entry point consumer |

### Umbrales de cobertura mínima

| Capa | Umbral |
|---|---|
| `domain` (transformadores + factory) | ≥ 85% |
| `application` (use case) | ≥ 85% |
| `infrastructure` | ≥ 80% |

---

## 9. Criterios de Aceptación

- [ ] Cada componente tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] `sbt test` finaliza en verde.
- [ ] `sbt "entryPoints/assembly"` genera el fat JAR sin errores.
- [ ] La cobertura cumple los umbrales.
- [ ] Añadir un nuevo tipo de reporte requiere solo agregar una clase `ReportTransformer` y registrarla — sin modificar `ProcessReportUseCase` (principio Abierto/Cerrado verificable por test).
- [ ] Tipo no registrado → evento `report.processing.failed` publicado, sin abortar el proceso.
- [ ] Happy path: evento `report.extracted` → Parquet `raw/` leído → transformación aplicada → Parquet `processed/` escrito → evento `report.processed` publicado.
- [ ] El CronJob está creado en K3d: `kubectl get cronjob -n dev report-processing-service`.
