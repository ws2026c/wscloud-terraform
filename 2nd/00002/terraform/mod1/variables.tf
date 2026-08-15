###############################################################################
# variables.tf
###############################################################################

variable "region" {
  description = "과제 지정 리전"
  type        = string
  default     = "ap-southeast-1"
}

variable "student_number" {
  description = "S3 버킷명 접미사(선수 비번호). 예) 103 -> wsc2026-student-score-bucket-103"
  type        = string
  # 채점 시 버킷명이 정확히 일치해야 하므로 기본값을 두지 않음 (terraform.tfvars 에 반드시 지정)

  validation {
    condition     = length(trimspace(var.student_number)) > 0
    error_message = "student_number(비번호)를 terraform.tfvars 에 반드시 지정하세요."
  }
}

variable "bucket_name" {
  description = "S3 버킷 이름 (비우면 wsc2026-student-score-bucket-<student_number> 사용)"
  type        = string
  default     = ""
}

variable "table_name" {
  description = "DynamoDB 테이블 이름"
  type        = string
  default     = "wsc2026-student-score"
}

variable "state_machine_name" {
  description = "Step Functions State Machine 이름"
  type        = string
  default     = "wsc2026-student-score-workflow"
}

variable "lambda_role_name" {
  description = "Lambda 실행 IAM Role 이름"
  type        = string
  default     = "wsc2026-lambda-student-role"
}

variable "sfn_role_name" {
  description = "Step Functions 실행 IAM Role 이름"
  type        = string
  default     = "wsc2026-stepfunction-student-role"
}

variable "process_function_name" {
  description = "성적 처리 Lambda 함수 이름 (채점 기준 1-3 에서 정확히 이 이름으로 조회됨)"
  type        = string
  default     = "wsc2026-student-score-function"
}

variable "trigger_function_name" {
  description = "S3 업로드 감지 트리거 Lambda 함수 이름"
  type        = string
  default     = "wsc2026-student-score-trigger"
}

variable "folder_placeholders" {
  description = <<-EOT
    0-byte 폴더 마커를 생성할 prefix 목록.
    기본값은 input/ 뿐입니다.
      - input/     : 워크플로우가 원본 csv를 지운 뒤에도 `aws s3 ls s3://bucket/` 에 PRE input/ 이 남아야 하므로 필요 (채점 1-1)
      - processed/ : 채점 1-5-A 에서 `test.csv` 한 줄만 출력되어야 하므로 마커를 만들지 않음
      - error/     : 채점 1-5-B 에서 error json 4개만 출력되어야 하므로 마커를 만들지 않음
                     (두 폴더는 워크플로우 실행 결과물로 생성되므로 1-1 의 PRE 출력도 충족됨)
  EOT
  type        = list(string)
  default     = ["input/"]
}

locals {
  bucket_name = var.bucket_name != "" ? var.bucket_name : "wsc2026-student-score-bucket-${var.student_number}"
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name
}
