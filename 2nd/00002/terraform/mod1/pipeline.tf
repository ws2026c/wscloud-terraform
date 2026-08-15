###############################################################################
# pipeline.tf - 완전 자동 실행
#
#   terraform apply 한 번이 매번 수행하는 것:
#     1단계  processed/ , error/ 비우기 + test.csv 업로드
#             -> S3 이벤트가 살아 있으면 여기서 이미 자동 실행됨
#     2단계  45초 대기 (자동 실행이 끝나거나, 이벤트가 유실될 시간)
#     3단계  트리거 Lambda 직접 호출 (보증 실행)
#             - 자동 실행이 이미 처리했다면: input/test.csv 가 processed/ 로
#               이동해 없으므로 CheckS3File 에서 FAILED 로 끝남 -> 결과물 불변
#             - 자동 실행이 안 됐다면: 이 호출이 처리를 수행
#           => 어느 경우든 최종 상태는 processed/ 1개 + error/ 4개 + DDB 5건
#
#   전제: terraform 을 실행하는 PC 에 aws CLI + 자격 증명 (지금 쓰는 그 터미널)
#   끄기: terraform apply -var="auto_run=false"
###############################################################################

variable "auto_run" {
  description = "apply 마지막에 초기화 + 업로드 + 보증 실행까지 자동 수행"
  type        = bool
  default     = true
}

# 트리거 Lambda 에 넣을 가짜 S3 이벤트 (셸 종류와 무관하게 file:// 로 전달)
resource "local_file" "trigger_payload" {
  count = var.auto_run ? 1 : 0

  filename = "${path.module}/build/trigger-payload.json"
  content = jsonencode({
    Records = [{ s3 = { object = { key = "input/test.csv" } } }]
  })
}

# ---------------------------------------------------------------- 1단계
resource "terraform_data" "pipeline_reset" {
  count = var.auto_run ? 1 : 0

  triggers_replace = [timestamp()]

  provisioner "local-exec" {
    command = "aws s3 rm s3://${aws_s3_bucket.score.id}/processed/ --recursive --region ${var.region}"
  }

  provisioner "local-exec" {
    command = "aws s3 rm s3://${aws_s3_bucket.score.id}/error/ --recursive --region ${var.region}"
  }

  provisioner "local-exec" {
    command = "aws s3 cp ${path.module}/test.csv s3://${aws_s3_bucket.score.id}/input/test.csv --region ${var.region}"
  }

  depends_on = [
    aws_s3_bucket_notification.score,
    aws_lambda_permission.allow_s3_invoke,
    aws_sfn_state_machine.workflow,
    aws_lambda_function.process,
    aws_lambda_function.trigger,
    aws_iam_role_policy.lambda,
    aws_iam_role_policy.sfn,
    aws_s3_object.folders,
  ]
}

# ---------------------------------------------------------------- 2단계
resource "time_sleep" "pipeline_settle" {
  count = var.auto_run ? 1 : 0

  create_duration = "45s"

  # 매 apply 마다 다시 대기하도록 강제
  triggers = {
    run = timestamp()
  }

  depends_on = [terraform_data.pipeline_reset]
}

# ---------------------------------------------------------------- 3단계
resource "terraform_data" "pipeline_ensure" {
  count = var.auto_run ? 1 : 0

  triggers_replace = [timestamp()]

  # 자동 이벤트가 유실됐더라도 반드시 한 번은 실행되게 보증.
  # 이미 처리된 경우에는 입력 파일이 없어 워크플로우가 곧장 실패로 끝나며
  # 결과물(processed/, error/, DynamoDB)에는 아무 영향이 없다.
  provisioner "local-exec" {
    command = "aws lambda invoke --function-name ${aws_lambda_function.trigger.function_name} --cli-binary-format raw-in-base64-out --payload file://${local_file.trigger_payload[0].filename} ${path.module}/build/trigger-out.json --region ${var.region}"
  }

  depends_on = [time_sleep.pipeline_settle]
}
