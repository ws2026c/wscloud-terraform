###############################################################################
# variables.tf
###############################################################################

variable "region" {
  description = "과제 지정 리전"
  type        = string
  default     = "ap-northeast-1"
}

variable "azs" {
  description = "문제지 서브넷 이름이 a / d 이므로 ap-northeast-1a, ap-northeast-1d"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1d"]
}

variable "student_number" {
  description = "S3 버킷 접미사(선수 비번호). wsc2026-sensor-alert-bucket-<비번호>"
  type        = string

  validation {
    condition     = length(trimspace(var.student_number)) > 0
    error_message = "student_number(비번호)를 terraform.tfvars 에 지정하세요."
  }
}

# ---------------------------------------------------------------- 네트워크
variable "vpc_name" {
  type    = string
  default = "msk-vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "192.168.0.0/16"
}

variable "subnets" {
  type = map(object({
    cidr   = string
    public = bool
    az_idx = number
  }))
  default = {
    "msk-pub-a"  = { cidr = "192.168.0.0/24", public = true, az_idx = 0 }
    "msk-pub-d"  = { cidr = "192.168.1.0/24", public = true, az_idx = 1 }
    "msk-priv-a" = { cidr = "192.168.10.0/24", public = false, az_idx = 0 }
    "msk-priv-d" = { cidr = "192.168.11.0/24", public = false, az_idx = 1 }
  }
}

# ---------------------------------------------------------------- MSK
variable "cluster_name" {
  type    = string
  default = "wsc2026-msk-cluster"
}

variable "kafka_version" {
  type    = string
  default = "3.6.0"
}

variable "broker_instance_type" {
  type    = string
  default = "kafka.t3.small"
}

variable "allow_unauthenticated" {
  description = <<-EOT
    배포된 프로듀서(app)가 SASL 미지원이라 IAM 전용 클러스터에는 접속하지 못합니다.
    true 로 두면 IAM 과 함께 비인증(9092 PLAINTEXT) 접근도 허용해 프로듀서가 동작합니다.
    채점 4-3 은 Sasl.Iam.Enabled 만 확인하므로 영향이 없습니다.
    직접 IAM 을 지원하는 프로듀서로 교체했다면 false 로 두세요.
  EOT
  type        = bool
  default     = true
}

variable "producer_bootstrap" {
  description = "프로듀서/토픽생성이 사용할 부트스트랩 (plaintext | tls | iam)"
  type        = string
  default     = "plaintext"

  validation {
    condition     = contains(["plaintext", "tls", "iam"], var.producer_bootstrap)
    error_message = "plaintext, tls, iam 중 하나여야 합니다."
  }
}

variable "broker_count" {
  description = "고가용성: AZ 2개 x 1 = 2 (Replication Factor 2 를 만족)"
  type        = number
  default     = 2
}

variable "topic_raw" {
  type    = string
  default = "wsc2026-sensor-raw"
}

variable "topic_alert" {
  type    = string
  default = "wsc2026-sensor-alert"
}

# ---------------------------------------------------------------- EC2
variable "ec2_name" {
  type    = string
  default = "wsc2026-sensor-producer"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "ec2_role_name" {
  type    = string
  default = "wsc2026-msk-ec2-role"
}

variable "ec2_subnet_name" {
  type    = string
  default = "msk-priv-a"
}

# ---------------------------------------------------------------- Lambda
variable "lambda_role_name" {
  type    = string
  default = "wsc2026-msk-lambda-role"
}

variable "lambda_runtime" {
  description = <<-EOT
    채점 4-2 는 python3.14 를 기대합니다.
    계정/리전에서 python3.14 런타임을 아직 지원하지 않아 생성이 실패하면
    terraform.tfvars 에서 python3.13 으로 낮추세요.
  EOT
  type        = string
  default     = "python3.14"
}

variable "consumer_function_name" {
  type    = string
  default = "wsc2026-sensor-consumer"
}

variable "alert_consumer_function_name" {
  type    = string
  default = "wsc2026-sensor-alert-consumer"
}

# ---------------------------------------------------------------- 저장소
variable "table_name" {
  type    = string
  default = "wsc2026-sensor-data"
}

variable "sns_topic_name" {
  description = "이상 알림 SNS Topic (채점 대상 아님)"
  type        = string
  default     = "wsc2026-sensor-alert-topic"
}

variable "build_lambda_kafka_layer" {
  description = <<-EOT
    true 이면 EC2 가 부팅 시 kafka-python 레이어를 만들어 sensor-consumer 에 붙입니다.
    (Lambda 가 wsc2026-sensor-alert 토픽으로 produce 하려면 Kafka 클라이언트가 필요)
    실패해도 DynamoDB 저장 동작에는 영향이 없습니다.
  EOT
  type        = bool
  default     = true
}

locals {
  account_id     = data.aws_caller_identity.current.account_id
  partition      = data.aws_partition.current.partition
  alert_bucket   = "wsc2026-sensor-alert-bucket-${var.student_number}"
  artifact_bucket = "wsc2026-msk-artifacts-${var.student_number}-${data.aws_caller_identity.current.account_id}"

  public_subnets  = [for k, v in var.subnets : k if v.public]
  private_subnets = [for k, v in var.subnets : k if !v.public]
}
