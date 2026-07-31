###############################################################################
# variables.tf
###############################################################################

variable "region" {
  description = "과제 지정 리전"
  type        = string
  default     = "eu-west-1"
}

variable "azs" {
  type    = list(string)
  default = ["eu-west-1a", "eu-west-1b"]
}

variable "student_number" {
  description = "S3 버킷 이름 충돌 방지용 접미사 (비번호). CloudTrail/Config 버킷에 사용"
  type        = string

  validation {
    condition     = length(trimspace(var.student_number)) > 0
    error_message = "student_number(비번호)를 terraform.tfvars 에 지정하세요."
  }
}

# ---------------------------------------------------------------- 네트워크
variable "vpc_name" {
  type    = string
  default = "event-vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "172.16.0.0/16"
}

variable "subnets" {
  type = map(object({
    cidr   = string
    az_idx = number
  }))
  default = {
    "event-pub-a" = { cidr = "172.16.0.0/24", az_idx = 0 }
    "event-pub-b" = { cidr = "172.16.1.0/24", az_idx = 1 }
  }
}

# ---------------------------------------------------------------- EC2
variable "ec2_name" {
  type    = string
  default = "wsc2026-event-ec2"
}

variable "instance_type" {
  description = "정상 상태 인스턴스 타입 (타입 변경 감지 시 이 값으로 원복)"
  type        = string
  default     = "t3.micro"
}

variable "ec2_role_name" {
  type    = string
  default = "wsc2026-event-ec2-role"
}

variable "ec2_subnet_name" {
  type    = string
  default = "event-pub-a"
}

variable "sg_name" {
  type    = string
  default = "wsc2026-event-sg"
}

# ---------------------------------------------------------------- 이벤트 처리
variable "sns_topic_name" {
  type    = string
  default = "wsc2026-event-alert"
}

variable "trail_name" {
  type    = string
  default = "wsc2026-event-trail"
}

variable "lambda_role_name" {
  type    = string
  default = "wsc2026-event-lambda-role"
}

# ---------------------------------------------------------------- AWS Config
variable "config_sg_rule_name" {
  type    = string
  default = "wsc2026-sg-ssh-rule"
}

variable "config_tags_rule_name" {
  type    = string
  default = "wsc2026-required-tags-rule"
}

variable "required_tag_key" {
  description = "wsc2026-required-tags-rule 이 요구하는 태그 키"
  type        = string
  default     = "Name"
}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  partition       = data.aws_partition.current.partition
  trail_bucket    = "wsc2026-event-trail-${var.student_number}-${data.aws_caller_identity.current.account_id}"
  config_bucket   = "wsc2026-event-config-${var.student_number}-${data.aws_caller_identity.current.account_id}"
  sns_topic_arn   = "arn:${data.aws_partition.current.partition}:sns:${var.region}:${data.aws_caller_identity.current.account_id}:${var.sns_topic_name}"

  # 채점기준 3-1 / 3-2 + 문제지 lambda.md 를 모두 만족하도록 6개 함수를 구성한다.
  lambda_functions = {
    "wsc2026-sg-remediation" = {
      role        = "SG_REMEDIATION"
      timeout     = 60
      description = "Security Group 인바운드 규칙 추가 감지 -> 규칙 삭제 + 알림"
    }
    "wsc2026-role-remediation" = {
      role        = "ROLE_REMEDIATION"
      timeout     = 60
      description = "EC2 IAM Role 변경 감지 -> 원복 + 알림"
    }
    "wsc2026-ec2-terminate-alert" = {
      role        = "EC2_TERMINATE_ALERT"
      timeout     = 30
      description = "EC2 종료 감지 -> 알림"
    }
    "wsc2026-ec2-type-remediation" = {
      role        = "EC2_TYPE_REMEDIATION"
      timeout     = 300
      description = "EC2 타입 변경 감지 -> 원복 + 알림"
    }
    "wsc2026-ec2-stop-remediation" = {
      role        = "EC2_STOP_REMEDIATION"
      timeout     = 300
      description = "EC2 중지 감지 -> 재시작 + 알림"
    }
    "wsc2026-tag-alert" = {
      role        = "TAG_ALERT"
      timeout     = 60
      description = "필수 태그 변경 감지 -> 태그 복구 + 알림"
    }
  }
}
