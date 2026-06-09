package com.example.reportprocessingservice.domain.model

/** Tipo de reporte (lenguaje ubicuo del bounded context de Reportería). */
final case class ReportType(value: String)

object ReportType {
  def fromString(s: String): ReportType = ReportType(s.trim.toLowerCase)
}
