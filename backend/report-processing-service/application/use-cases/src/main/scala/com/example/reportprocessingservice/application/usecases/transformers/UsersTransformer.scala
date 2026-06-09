package com.example.reportprocessingservice.application.usecases.transformers

import com.example.reportprocessingservice.application.usecases.ReportTransformer
import com.example.reportprocessingservice.domain.model.ReportType
import org.apache.spark.sql.DataFrame

/** Transformer del reporte `USERS` (DR-10). */
class UsersTransformer extends ReportTransformer {
  override val reportType: ReportType = ReportType("USERS")

  override def transform(raw: DataFrame): DataFrame = {
    // TODO: implementar la agregación/pivot/formato lógico de `USERS`.
    // Una fila del resultado debe aproximarse a una celda lógica del formato final (DR-2).
    raw
  }
}
