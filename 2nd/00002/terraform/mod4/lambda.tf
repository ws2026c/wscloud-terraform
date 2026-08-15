###############################################################################
# lambda.tf - MSK Consumer Lambda 2종
#   채점 4-2 : wsc2026-sensor-consumer / wsc2026-sensor-alert-consumer (python3.14)
#   채점 4-4 : 두 함수 모두 Event Source Mapping State = Enabled
###############################################################################

data "archive_file" "consumer" {
  type        = "zip"
  source_file = "${path.module}/src/consumer/index.py"
  output_path = "${path.module}/build/consumer.zip"
}

data "archive_file" "alert_consumer" {
  type        = "zip"
  source_file = "${path.module}/src/alert_consumer/index.py"
  output_path = "${path.module}/build/alert_consumer.zip"
}

resource "aws_cloudwatch_log_group" "consumer" {
  name              = "/aws/lambda/${var.consumer_function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "alert_consumer" {
  name              = "/aws/lambda/${var.alert_consumer_function_name}"
  retention_in_days = 7
}

###############################################################################
# 1) sensor-consumer  (raw 토픽 -> DynamoDB / alert 토픽)
#    alert 토픽으로 produce 하려면 VPC 안에서 브로커에 접근해야 하므로 VPC 연결
###############################################################################

resource "aws_lambda_function" "consumer" {
  function_name = var.consumer_function_name
  description   = "MSK raw topic consumer - anomaly detection"
  role          = aws_iam_role.lambda.arn
  runtime       = var.lambda_runtime
  handler       = "index.handler"
  timeout       = 60
  memory_size   = 512

  filename         = data.archive_file.consumer.output_path
  source_code_hash = data.archive_file.consumer.output_base64sha256

  vpc_config {
    subnet_ids         = [for n in local.private_subnets : aws_subnet.this[n].id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DDB_TABLE        = aws_dynamodb_table.sensor.name
      ALERT_TOPIC      = var.topic_alert
      BOOTSTRAP_SERVER = aws_msk_cluster.main.bootstrap_brokers_sasl_iam
    }
  }

  # layers  : EC2 user_data 가 kafka 레이어를 붙이므로 Terraform 이 다시 떼지 않도록 무시
  # runtime : Provider 가 python3.14 를 모르는 경우 scripts/set-runtime.sh 로
  #           CLI 에서 런타임을 바꾸는데, Terraform 이 되돌리지 않도록 무시
  lifecycle {
    ignore_changes = [layers, runtime]
  }

  depends_on = [
    aws_cloudwatch_log_group.consumer,
    aws_iam_role_policy.lambda,
    aws_iam_role_policy_attachment.lambda_msk,
  ]
}

###############################################################################
# 2) sensor-alert-consumer  (alert 토픽 -> SNS + S3)
###############################################################################

resource "aws_lambda_function" "alert_consumer" {
  function_name = var.alert_consumer_function_name
  description   = "MSK alert topic consumer - SNS + S3 log"
  role          = aws_iam_role.lambda.arn
  runtime       = var.lambda_runtime
  handler       = "index.handler"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.alert_consumer.output_path
  source_code_hash = data.archive_file.alert_consumer.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alert.arn
      S3_BUCKET     = aws_s3_bucket.alert.id
    }
  }

  # scripts/set-runtime.sh 로 런타임을 바꾼 경우 Terraform 이 되돌리지 않도록 무시
  lifecycle {
    ignore_changes = [runtime]
  }

  depends_on = [
    aws_cloudwatch_log_group.alert_consumer,
    aws_iam_role_policy.lambda,
    aws_iam_role_policy_attachment.lambda_msk,
  ]
}

###############################################################################
# Event Source Mapping (MSK Trigger)
#   ※ 토픽이 존재해야 매핑이 만들어진다. 토픽은 EC2 user_data 가 생성하므로
#     EC2 부팅 이후에 매핑을 만든다.
###############################################################################

# EC2 인스턴스 생성 완료 != user_data 완료.
# 토픽 생성(카프카 CLI 다운로드 포함)까지 여유를 두고 기다린다.
resource "time_sleep" "wait_for_topics" {
  create_duration = "420s"

  depends_on = [aws_instance.producer]
}

resource "aws_lambda_event_source_mapping" "raw" {
  event_source_arn  = aws_msk_cluster.main.arn
  function_name     = aws_lambda_function.consumer.arn
  topics            = [var.topic_raw]
  starting_position = "LATEST"
  batch_size        = 100
  enabled           = true

  amazon_managed_kafka_event_source_config {
    consumer_group_id = "wsc2026-sensor-consumer-group"
  }

  depends_on = [time_sleep.wait_for_topics]
}

resource "aws_lambda_event_source_mapping" "alert" {
  event_source_arn  = aws_msk_cluster.main.arn
  function_name     = aws_lambda_function.alert_consumer.arn
  topics            = [var.topic_alert]
  starting_position = "LATEST"
  batch_size        = 10
  enabled           = true

  amazon_managed_kafka_event_source_config {
    consumer_group_id = "wsc2026-sensor-alert-consumer-group"
  }

  depends_on = [time_sleep.wait_for_topics]
}
