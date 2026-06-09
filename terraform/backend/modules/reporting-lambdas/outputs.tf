output "report_bus_name" {
  value = aws_cloudwatch_event_bus.report_bus.name
}

output "kafka_consumer_function" {
  value = aws_lambda_function.kafka_consumer.function_name
}
