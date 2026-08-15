###############################################################################
# stepfunctions.tf - 학생 성적 처리 오케스트레이션 State Machine
###############################################################################

resource "aws_sfn_state_machine" "workflow" {
  name     = var.state_machine_name
  type     = "STANDARD"
  role_arn = aws_iam_role.sfn.arn

  definition = templatefile("${path.module}/workflow.asl.json", {
    bucket_name        = aws_s3_bucket.score.id
    process_lambda_arn = aws_lambda_function.process.arn
  })

  depends_on = [aws_iam_role_policy.sfn]
}
