# ===================== Formato PDF =====================
data "archive_file" "pdf" {
  type        = "zip"
  source_dir  = "${path.module}/pdf"
  output_path = "${path.module}/build/pdf.zip"
}

resource "aws_lambda_function" "pdf" {
  function_name    = "${var.org}-report-pdf"
  role             = aws_iam_role.reporting_lambda.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.pdf.output_path
  source_code_hash = data.archive_file.pdf.output_base64sha256
  timeout          = 120
  memory_size      = 512

  environment {
    variables = {
      REPORT_BUCKET    = var.report_bucket
      AWS_ENDPOINT_URL = var.aws_endpoint_url
    }
  }
}

resource "aws_cloudwatch_event_rule" "pdf" {
  name           = "${var.org}-report-pdf"
  event_bus_name = aws_cloudwatch_event_bus.report_bus.name
  event_pattern = jsonencode({
    "source"      = ["${var.org}.reporting"]
    "detail-type" = ["ReportFormatRequested"]
    "detail"      = { "format" = ["PDF"] }
  })
}

resource "aws_cloudwatch_event_target" "pdf" {
  rule           = aws_cloudwatch_event_rule.pdf.name
  event_bus_name = aws_cloudwatch_event_bus.report_bus.name
  arn            = aws_lambda_function.pdf.arn
}

resource "aws_lambda_permission" "pdf" {
  statement_id  = "AllowEventBridgePDF"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pdf.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.pdf.arn
}

# ===================== Formato XLS =====================
data "archive_file" "xls" {
  type        = "zip"
  source_dir  = "${path.module}/xls"
  output_path = "${path.module}/build/xls.zip"
}

resource "aws_lambda_function" "xls" {
  function_name    = "${var.org}-report-xls"
  role             = aws_iam_role.reporting_lambda.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.xls.output_path
  source_code_hash = data.archive_file.xls.output_base64sha256
  timeout          = 120
  memory_size      = 512

  environment {
    variables = {
      REPORT_BUCKET    = var.report_bucket
      AWS_ENDPOINT_URL = var.aws_endpoint_url
    }
  }
}

resource "aws_cloudwatch_event_rule" "xls" {
  name           = "${var.org}-report-xls"
  event_bus_name = aws_cloudwatch_event_bus.report_bus.name
  event_pattern = jsonencode({
    "source"      = ["${var.org}.reporting"]
    "detail-type" = ["ReportFormatRequested"]
    "detail"      = { "format" = ["XLS"] }
  })
}

resource "aws_cloudwatch_event_target" "xls" {
  rule           = aws_cloudwatch_event_rule.xls.name
  event_bus_name = aws_cloudwatch_event_bus.report_bus.name
  arn            = aws_lambda_function.xls.arn
}

resource "aws_lambda_permission" "xls" {
  statement_id  = "AllowEventBridgeXLS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.xls.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.xls.arn
}

# ===================== Formato CSV =====================
data "archive_file" "csv" {
  type        = "zip"
  source_dir  = "${path.module}/csv"
  output_path = "${path.module}/build/csv.zip"
}

resource "aws_lambda_function" "csv" {
  function_name    = "${var.org}-report-csv"
  role             = aws_iam_role.reporting_lambda.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.csv.output_path
  source_code_hash = data.archive_file.csv.output_base64sha256
  timeout          = 120
  memory_size      = 512

  environment {
    variables = {
      REPORT_BUCKET    = var.report_bucket
      AWS_ENDPOINT_URL = var.aws_endpoint_url
    }
  }
}

resource "aws_cloudwatch_event_rule" "csv" {
  name           = "${var.org}-report-csv"
  event_bus_name = aws_cloudwatch_event_bus.report_bus.name
  event_pattern = jsonencode({
    "source"      = ["${var.org}.reporting"]
    "detail-type" = ["ReportFormatRequested"]
    "detail"      = { "format" = ["CSV"] }
  })
}

resource "aws_cloudwatch_event_target" "csv" {
  rule           = aws_cloudwatch_event_rule.csv.name
  event_bus_name = aws_cloudwatch_event_bus.report_bus.name
  arn            = aws_lambda_function.csv.arn
}

resource "aws_lambda_permission" "csv" {
  statement_id  = "AllowEventBridgeCSV"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.csv.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.csv.arn
}
