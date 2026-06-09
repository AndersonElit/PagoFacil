package com.example.reportprocessingservice.application.usecases.transformers

import com.example.reportprocessingservice.application.usecases.ReportTransformer
import com.example.reportprocessingservice.domain.model.ReportType
import org.apache.spark.sql.DataFrame

/** Transformer del reporte `COMPLIANCE_ALERTS` (DR-10). */
class ComplianceAlertsTransformer extends ReportTransformer {
  override val reportType: ReportType = ReportType("COMPLIANCE_ALERTS")

  override def transform(raw: DataFrame): DataFrame = {
    // TODO: implementar la agregación/pivot/formato lógico de `COMPLIANCE_ALERTS`.
    // Una fila del resultado debe aproximarse a una celda lógica del formato final (DR-2).
    raw
  }
}
