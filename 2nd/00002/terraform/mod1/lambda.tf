###############################################################################
# lambda.tf
#   A. 성적 처리 함수  : CSV 검증 -> 평균/등급 계산 -> DynamoDB 저장
#   B. 트리거 함수     : S3 업로드 감지 -> Step Functions 실행
###############################################################################

data "archive_file" "process" {
  type        = "zip"
  source_file = "${path.module}/src/process/index.py"
  output_path = "${path.module}/build/process.zip"
}

data "archive_file" "trigger" {
  type        = "zip"
  source_file = "${path.module}/src/trigger/index.py"
  output_path = "${path.module}/build/trigger.zip"
}

###############################################################################
# A. 성적 처리 Lambda
###############################################################################

resource "aws_cloudwatch_log_group" "process" {
  name              = "/aws/lambda/${var.process_function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "process" {
  function_name = var.process_function_name
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.process.output_path
  source_code_hash = data.archive_file.process.output_base64sha256

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.score.id
      DDB_TABLE = aws_dynamodb_table.score.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.process]
}

###############################################################################
# B. 트리거 Lambda
###############################################################################

resource "aws_cloudwatch_log_group" "trigger" {
  name              = "/aws/lambda/${var.trigger_function_name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "trigger" {
  function_name = var.trigger_function_name
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.trigger.output_path
  source_code_hash = data.archive_file.trigger.output_base64sha256

  environment {
    variables = {
      STATE_MACHINE_ARN = local.state_machine_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.trigger]
}
