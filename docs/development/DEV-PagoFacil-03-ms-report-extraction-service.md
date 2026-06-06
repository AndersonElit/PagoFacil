# Etapa 3 — MS1: report-extraction-service (Spark)

**Proyecto:** PagoFacil | **Tipo:** Job batch Spark (CronJob K8s) | **BC:** BC-07 Reporting  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Contexto y Responsabilidad

**Tipo:** Job batch Apache Spark 3.5.1 / Scala 2.13. No es un servicio REST persistente — no expone endpoints HTTP.

**Responsabilidad principal:**
- Leer tablas desnormalizadas del Read Model `pagofacil_readmodel` vía JDBC (`SparkJdbcSourceAdapter`).
- Validar el esquema del DataFrame extraído contra `report_schema_catalog` en `pagofacil_reporting`.
- Generar archivo Parquet en S3 (`pagofacil-parquet-raw/`) como contrato hacia MS2.
- Publicar evento `report.extracted` a Kafka.
- Ejecutado por CronJob K8s según schedule configurado (`0 2 * * *` — 2am UTC) o disparado on-demand por `audit-service` (a través de un mensaje Kafka o una anotación K8s job).

**Dependencias:**

| Recurso | Tipo | Propósito |
|---|---|---|
| `pagofacil_readmodel` | JDBC (Spark) read-only | Fuente de datos de transacciones, alertas, billeteras |
| `pagofacil_reporting` | JDBC (Spark) read-only | Consulta de `report_schema_catalog` |
| S3 `pagofacil-parquet-raw/` | SDK (floci en dev) | Escritura de Parquet `raw/` |
| Kafka `report.extracted` | Producer | Publicar evento de extracción completada |

---

## 2. Prerrequisitos

- Etapa 2b completa (pipeline CI con `bumpImageTag` que actualiza el CronJob).
- `projection-service` activo con datos proyectados en `pagofacil_readmodel`.
- `audit-service` con seed de `report_schema_catalog` aplicado.
- Secret `pagofacil/dev/report-extraction-service` en floci.
- Bucket S3 `pagofacil-parquet-raw` creado en floci.

---

## 3. Ciclo de Desarrollo Incremental en K3d dev

**MS1 es un CronJob, no un Deployment.** El pipeline CI termina en `bumpImageTag` — ArgoCD sincroniza el CronJob. No hay smoke tests HTTP.

```
Implementar case de uso → sbt test (Red → Green) → git push
    → Jenkins pipeline (sbt) → buildScalaBatchJob → bumpImageTag
    → ArgoCD sync → K3d CronJob actualizado
    → Para probar manualmente: kubectl create job --from=cronjob/report-extraction-service test-run-1
```

> **Regla TDD:** la prueba de cada componente se escribe y se ve **fallar (Red)** ANTES de implementar el código de producción.

---

## 4. Capa de Dominio (`domain`) — _test-first_

### Tipos de dominio

```scala
// ReportSchema — contrato del DataFrame esperado
case class ColumnSpec(name: String, dataType: String, nullable: Boolean)
case class ReportSchema(reportType: ReportType, schemaVersion: Int, columns: Seq[ColumnSpec], integrityRules: Seq[IntegrityRule])

// ReportType
sealed trait ReportType
object ReportType {
  case object TransaccionesDiario extends ReportType
  case object ReporteAml extends ReportType
  case object AlertasFraude extends ReportType
  case object SaldoUsuarios extends ReportType
  case object Conciliacion extends ReportType
}

// IntegrityRule — reglas de validación del DataFrame
sealed trait IntegrityRule
case class NotNullRule(column: String) extends IntegrityRule
case class UniqueRule(column: String) extends IntegrityRule
case class AmountPositiveRule(column: String) extends IntegrityRule
```

### Puertos secundarios (interfaces del dominio)

```scala
// SourceDataPort — interfaz para leer datos de la fuente
trait SourceDataPort {
  def readData(reportType: ReportType, periodFrom: LocalDate, periodTo: LocalDate): DataFrame
}

// ParquetStorePort — interfaz para escribir Parquet en S3
trait ParquetStorePort {
  def write(df: DataFrame, s3Key: String): Unit
}

// SchemaRegistryPort — interfaz para obtener el schema del catálogo
trait SchemaRegistryPort {
  def getSchema(reportType: ReportType): Option[ReportSchema]
}

// EventBusPort — interfaz para publicar el evento Kafka
trait EventBusPort {
  def publish(event: ReportExtractedEvent): Unit
}
```

### Invariantes de dominio

- Si el DataFrame no cumple el schema declarado (columnas faltantes, tipos incorrectos, reglas de integridad fallidas), el job falla con `SchemaValidationException` sin escribir el Parquet. El evento `report.extraction.failed` se publica en lugar de `report.extracted`.
- El Parquet solo se escribe si la validación pasa completamente.

---

## 5. Capa de Aplicación (`application`) — _test-first_

```scala
class ValidateAndExtractUseCase(
  sourcePort: SourceDataPort,
  schemaRegistryPort: SchemaRegistryPort,
  parquetStorePort: ParquetStorePort,
  eventBusPort: EventBusPort
) {
  def execute(reportType: ReportType, periodFrom: LocalDate, periodTo: LocalDate, jobId: UUID): Try[Unit] = {
    for {
      schema    <- schemaRegistryPort.getSchema(reportType).toRight(new UnknownReportTypeException(reportType)).toTry
      df        <- Try(sourcePort.readData(reportType, periodFrom, periodTo))
      _         <- validateSchema(df, schema)   // lanza SchemaValidationException si falla
      s3Key     =  buildS3Key(reportType, periodFrom, periodTo, jobId)
      _         <- Try(parquetStorePort.write(df, s3Key))
      _         <- Try(eventBusPort.publish(ReportExtractedEvent(jobId, reportType, s3Key, periodFrom, periodTo)))
    } yield ()
  }
}
```

---

## 6. Capa de Infraestructura (`infrastructure`) — _test-first_

### Adaptador JDBC — `SparkJdbcSourceAdapter`

Lee el Read Model PostgreSQL (`pagofacil_readmodel`) vía JDBC de Spark. La URL JDBC se deriva como `jdbc:postgresql://pagofacil-postgres-dev:5432/pagofacil_readmodel` (en dev).

```scala
class SparkJdbcSourceAdapter(spark: SparkSession, jdbcUrl: String, dbUser: String, dbPassword: String) extends SourceDataPort {
  def readData(reportType: ReportType, periodFrom: LocalDate, periodTo: LocalDate): DataFrame = {
    val (table, filters) = resolveTableAndFilters(reportType, periodFrom, periodTo)
    spark.read
      .format("jdbc")
      .option("url", jdbcUrl)
      .option("dbtable", s"(SELECT * FROM $table WHERE ${filters}) AS t")
      .option("user", dbUser)
      .option("password", dbPassword)
      .load()
  }
}
```

**Mapeo de ReportType a tabla:**

| ReportType | Tabla fuente | Filtro de período |
|---|---|---|
| `TransaccionesDiario` | `report_transactions` | `created_at BETWEEN $from AND $to` |
| `ReporteAml` | `report_alerts` | `alert_type='AML' AND created_at BETWEEN $from AND $to` |
| `AlertasFraude` | `report_alerts` | `alert_type='FRAUDE' AND created_at BETWEEN $from AND $to` |
| `SaldoUsuarios` | `report_wallets` | `last_updated BETWEEN $from AND $to` |
| `Conciliacion` | `report_reconciliations` | `detected_at BETWEEN $from AND $to` |

### Adaptador S3 — `SparkS3ParquetAdapter`

```scala
class SparkS3ParquetAdapter(spark: SparkSession, s3Endpoint: String) extends ParquetStorePort {
  def write(df: DataFrame, s3Key: String): Unit = {
    // En dev: usa floci endpoint http://floci:4566
    spark.hadoopConf.set("fs.s3a.endpoint", s3Endpoint)
    df.write.mode("overwrite").parquet(s"s3a://pagofacil-parquet-raw/$s3Key")
  }
}
```

### Adaptador Kafka — `KafkaEventPublisher`

```scala
class KafkaEventPublisher(bootstrapServers: String) extends EventBusPort {
  def publish(event: ReportExtractedEvent): Unit = {
    // Usa KafkaProducer estándar (no reactive — job batch)
    // Topic: report.extracted
  }
}
```

### Adaptador Schema Registry — `JdbcSchemaRegistryAdapter`

Lee `report_schema_catalog` de `pagofacil_reporting` vía JDBC.

---

## 7. API REST

MS1 es un job batch. No expone endpoints HTTP. No hay smoke tests en el pipeline CI.

---

## 8. Especificación TDD por Capa (Red-Green-Refactor)

> Tests escritos con ScalaTest (FlatSpec), Spark en modo local (`SparkSession.builder().master("local[*]")`), Testcontainers PostgreSQL y Kafka embebido.

### Dominio

| Clase de test | Método | Invariante | Elemento |
|---|---|---|---|
| `ReportSchemaValidationTest` | `shouldFailOnMissingColumn` | Columna faltante → `SchemaValidationException` | `ReportSchema` + regla NOT_NULL |
| `ReportSchemaValidationTest` | `shouldFailOnWrongDataType` | Tipo incorrecto en columna | `ColumnSpec` validación de tipo |
| `ReportSchemaValidationTest` | `shouldFailOnIntegrityViolation` | Amount negativo en `AmountPositiveRule` | `IntegrityRule` |
| `ReportSchemaValidationTest` | `shouldPassOnValidDataframe` | DataFrame cumple todas las reglas → sin excepción | `ReportSchema` |

### Aplicación

| Clase de test | Método | Escenario | Puertos mockeados | Use Case |
|---|---|---|---|---|
| `ValidateAndExtractUseCaseTest` | `shouldWriteParquetAndPublishEventOnSuccess` | Happy path | `SourceDataPort`, `SchemaRegistryPort`, `ParquetStorePort`, `EventBusPort` (mocks) | `ValidateAndExtractUseCase` |
| `ValidateAndExtractUseCaseTest` | `shouldPublishFailureEventOnSchemaValidationError` | Schema inválido | `SchemaRegistryPort` retorna schema, `SourceDataPort` retorna DF inválido | `ValidateAndExtractUseCase` |
| `ValidateAndExtractUseCaseTest` | `shouldFailOnUnknownReportType` | ReportType no en catálogo | `SchemaRegistryPort` retorna `None` | `ValidateAndExtractUseCase` |

### Infraestructura

| Clase de test | Método | Operación | Adaptador |
|---|---|---|---|
| `SparkJdbcSourceAdapterTest` | `shouldReadTransactionDataFromReadModel` | Spark JDBC contra Testcontainers PostgreSQL con datos de fixture | `SparkJdbcSourceAdapter` |
| `SparkJdbcSourceAdapterTest` | `shouldFilterByDateRange` | Solo registros del período especificado | `SparkJdbcSourceAdapter` |
| `SparkS3ParquetAdapterTest` | `shouldWriteParquetAndRoundTrip` | Escribe Parquet en S3 floci → lee de vuelta → mismo schema | `SparkS3ParquetAdapter` |
| `KafkaEventPublisherTest` | `shouldPublishReportExtractedEvent` | Publica a Kafka embebido → consumer lo recibe | `KafkaEventPublisher` |
| `JdbcSchemaRegistryAdapterTest` | `shouldReturnSchemaForKnownReportType` | SELECT en `report_schema_catalog` Testcontainers | `JdbcSchemaRegistryAdapter` |

### Umbrales de cobertura mínima

| Capa | Umbral |
|---|---|
| `domain` (validación) | ≥ 85% |
| `application` (use case) | ≥ 85% |
| `infrastructure` (adaptadores) | ≥ 80% |

---

## 9. Criterios de Aceptación

- [ ] Cada componente tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] `sbt test` finaliza en verde.
- [ ] `sbt "entryPoints/assembly"` genera el fat JAR sin errores.
- [ ] La cobertura cumple los umbrales.
- [ ] Schema inválido → no se escribe Parquet → se publica `report.extraction.failed` → sin archivo en S3 `raw/`.
- [ ] Schema válido → Parquet escrito en `s3://pagofacil-parquet-raw/<key>` → evento `report.extracted` en Kafka.
- [ ] El adaptador JDBC lee solo registros del período especificado.
- [ ] El CronJob está creado en K3d: `kubectl get cronjob -n dev report-extraction-service` muestra el job.
- [ ] Ejecución manual funciona: `kubectl create job --from=cronjob/report-extraction-service manual-test -n dev` completa con `Completed`.
