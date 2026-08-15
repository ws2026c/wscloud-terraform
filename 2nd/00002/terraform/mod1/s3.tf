###############################################################################
# s3.tf - 학생 성적 원본 데이터 버킷
#   input/     : 원본 학생 성적 csv 파일 저장
#   processed/ : 처리 완료된 파일 저장
#   error/     : 검증 실패 데이터 및 워크플로우 오류 로그 저장
###############################################################################

resource "aws_s3_bucket" "score" {
  bucket        = local.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "score" {
  bucket = aws_s3_bucket.score.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "score" {
  bucket = aws_s3_bucket.score.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 폴더(prefix) 마커
#   input/ 만 0-byte 마커를 생성한다.
#   - 워크플로우가 input/test.csv 를 processed/ 로 옮기면 input/ prefix 가 사라지므로
#     채점 1-1 (`aws s3 ls s3://bucket/` -> PRE error/ input/ processed/) 를 위해 마커가 필요하다.
#   - processed/ , error/ 에 마커를 만들면 채점 1-5-A / 1-5-B 의
#     `aws s3 ls s3://bucket/processed/` 출력에 0-byte 빈 줄이 추가되어 오답 처리된다.
#     두 폴더는 워크플로우 실행 결과(test.csv, error json)로 자동 생성된다.
resource "aws_s3_object" "folders" {
  for_each = toset(var.folder_placeholders)

  bucket       = aws_s3_bucket.score.id
  key          = each.value
  content_type = "application/x-directory"
  content      = ""
}

###############################################################################
# S3 Event Notification -> 트리거 Lambda
#   Prefix: input/ , Suffix: .csv , Event: s3:ObjectCreated:*
###############################################################################

resource "aws_s3_bucket_notification" "score" {
  bucket = aws_s3_bucket.score.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id   = "AllowExecutionFromS3Bucket"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.trigger.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.score.arn
  source_account = local.account_id
}
