data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "reporting_lambda" {
  name               = "${var.org}-reporting-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "reporting_lambda" {
  # Lee processed/, escribe output/ (DR-6) y publica a EventBridge (consumer).
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.report_bucket}", "arn:aws:s3:::${var.report_bucket}/processed/*"]
  }
  statement {
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.report_bucket}/output/*"]
  }
  statement {
    actions   = ["events:PutEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "reporting_lambda" {
  name   = "${var.org}-reporting-lambda"
  role   = aws_iam_role.reporting_lambda.id
  policy = data.aws_iam_policy_document.reporting_lambda.json
}
