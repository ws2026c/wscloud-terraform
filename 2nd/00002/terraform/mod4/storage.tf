###############################################################################
# storage.tf - DynamoDB / S3 / SNS
#   채점 4-1 : wsc2026-sensor-data (PK sensorId, SK timestamp)
#              wsc2026-sensor-alert-bucket-<비번호> 존재
###############################################################################

resource "aws_dynamodb_table" "sensor" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "sensorId"
  range_key = "timestamp"

  attribute {
    name = "sensorId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }
}

# 이상 데이터 로그 저장 버킷
resource "aws_s3_bucket" "alert" {
  bucket        = local.alert_bucket
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "alert" {
  bucket = aws_s3_bucket.alert.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# app 바이너리 배포용 버킷 (채점 대상 아님)
resource "aws_s3_bucket" "artifact" {
  bucket        = local.artifact_bucket
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "app_binary" {
  bucket = aws_s3_bucket.artifact.id
  key    = "app"
  source = "${path.module}/app/app"
  etag   = filemd5("${path.module}/app/app")
}

resource "aws_sns_topic" "alert" {
  name = var.sns_topic_name
}
