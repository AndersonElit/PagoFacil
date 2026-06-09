resource "aws_cloudwatch_event_bus" "report_bus" {
  name = "${var.org}-report-bus"
}

# --- Lambda Kafka Consumer: report.processed -> EventBridge PutEvents (DR-5) ---
data "archive_file" "kafka_consumer" {
  type        = "zip"
  source_dir  = "${path.module}/kafka-consumer"
  output_path = "${path.module}/build/kafka-consumer.zip"
}

resource "aws_lambda_function" "kafka_consumer" {
  function_name    = "${var.org}-report-kafka-consumer"
  role             = aws_iam_role.reporting_lambda.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.kafka_consumer.output_path
  source_code_hash = data.archive_file.kafka_consumer.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      EVENTBRIDGE_BUS  = aws_cloudwatch_event_bus.report_bus.name
      AWS_ENDPOINT_URL = var.aws_endpoint_url
      REPORT_BUCKET    = var.report_bucket
    }
  }
}

# Trigger Kafka self-managed (floci/MSK) sobre el topic report.processed (DR-9).
resource "aws_lambda_event_source_mapping" "kafka_consumer" {
  function_name     = aws_lambda_function.kafka_consumer.arn
  topics            = [var.kafka_topic]
  starting_position = "TRIM_HORIZON"

  self_managed_event_source {
    endpoints = {
      KAFKA_BOOTSTRAP_SERVERS = var.kafka_bootstrap_servers
    }
  }
}
