package com.example.reportextractionservice.infrastructure.driven.jdbcsource

import com.example.reportextractionservice.domain.ports.SourceDataPort
import org.apache.spark.sql.{DataFrame, SparkSession}

/** Adaptador de origen JDBC para proyectos SIN CQRS (alternativa a Mongo). */
class SparkJdbcSourceAdapter(
    spark: SparkSession,
    url: String,
    table: String,
    user: String,
    password: String
) extends SourceDataPort {

  override def read(): DataFrame =
    spark.read
      .format("jdbc")
      .option("url", url)
      .option("dbtable", table)
      .option("user", user)
      .option("password", password)
      .load()
}
