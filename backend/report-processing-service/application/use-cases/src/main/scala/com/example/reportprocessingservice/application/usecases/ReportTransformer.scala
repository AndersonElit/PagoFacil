package com.example.reportprocessingservice.application.usecases

import com.example.reportprocessingservice.domain.model.ReportType
import org.apache.spark.sql.DataFrame

/** Contrato común de transformación por tipo de reporte (DR-10). `DataFrame` es el detalle
 *  de la transformación Spark; cada tipo implementa su agregación/pivot/formato lógico. */
trait ReportTransformer {
  def reportType: ReportType
  def transform(raw: DataFrame): DataFrame
}

/** Se lanza cuando MS2 recibe un `reportType` no registrado en la factory. */
class UnsupportedReportTypeException(rt: ReportType)
    extends RuntimeException(s"Unsupported report type: ${rt.value}")
