###############################################################################
# outputs.tf
###############################################################################

output "s3_bucket_name" {
  description = "학생 성적 데이터 버킷"
  value       = aws_s3_bucket.score.id
}

output "dynamodb_table_name" {
  description = "학생 성적 저장 테이블"
  value       = aws_dynamodb_table.score.name
}

output "process_lambda_name" {
  description = "성적 처리 Lambda"
  value       = aws_lambda_function.process.function_name
}

output "trigger_lambda_name" {
  description = "S3 트리거 Lambda"
  value       = aws_lambda_function.trigger.function_name
}

output "state_machine_arn" {
  description = "Step Functions State Machine ARN"
  value       = aws_sfn_state_machine.workflow.arn
}

output "upload_test_command" {
  description = "테스트 CSV 업로드 명령"
  value       = "aws s3 cp test.csv s3://${aws_s3_bucket.score.id}/input/test.csv --region ${var.region}"
}
