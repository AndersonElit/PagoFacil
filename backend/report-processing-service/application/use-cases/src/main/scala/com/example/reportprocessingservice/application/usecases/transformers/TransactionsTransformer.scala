package com.example.reportprocessingservice.application.usecases.transformers

import com.example.reportprocessingservice.application.usecases.ReportTransformer
import com.example.reportprocessingservice.domain.model.ReportType
import org.apache.spark.sql.DataFrame

/** Transformer del reporte `TRANSACTIONS` (DR-10). */
class TransactionsTransformer extends ReportTransformer {
  override val reportType: ReportType = ReportType("TRANSACTIONS")

  override def transform(raw: DataFrame): DataFrame = {
    // TODO: implementar la agregación/pivot/formato lógico de `TRANSACTIONS`.
    // Una fila del resultado debe aproximarse a una celda lógica del formato final (DR-2).
    raw
  }
}
