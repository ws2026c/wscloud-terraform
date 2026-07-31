###############################################################################
# dynamodb.tf - 처리된 학생 성적 저장 테이블
#   PK: studentId (S) / SK: examDate (S)
###############################################################################

resource "aws_dynamodb_table" "score" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "studentId"
  range_key = "examDate"

  attribute {
    name = "studentId"
    type = "S"
  }

  attribute {
    name = "examDate"
    type = "S"
  }

  point_in_time_recovery {
    enabled = false
  }
}
