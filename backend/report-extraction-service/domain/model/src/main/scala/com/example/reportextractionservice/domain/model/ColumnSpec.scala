package com.example.reportextractionservice.domain.model

/** Especificación declarativa de una columna del esquema de un reporte (DR-1). */
final case class ColumnSpec(name: String, dataType: String, nullable: Boolean)
