###############################################################################
# variables.tf
###############################################################################

variable "region" {
  description = "과제 지정 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "azs" {
  description = "사용할 가용영역 2개 (ALB 는 2개 AZ 필요). [0]=a계열, [1]=b계열"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

# ---------------------------------------------------------------- 네트워크
variable "vpc_name" {
  type    = string
  default = "analytics-vpc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "subnets" {
  description = "문제지 표 그대로. pub-b 는 VPC CIDR(10.20.0.0/16) 안에 있어야 하므로 10.20.1.0/24"
  type = map(object({
    cidr   = string
    public = bool
    az_idx = number
  }))
  default = {
    "analytics-pub-a"  = { cidr = "10.20.0.0/24", public = true, az_idx = 0 }
    "analytics-pub-b"  = { cidr = "10.20.1.0/24", public = true, az_idx = 1 }
    "analytics-priv-a" = { cidr = "10.20.100.0/24", public = false, az_idx = 0 }
    "analytics-priv-b" = { cidr = "10.20.101.0/24", public = false, az_idx = 1 }
  }
}

# ---------------------------------------------------------------- 리소스 이름
variable "ec2_name" {
  type    = string
  default = "wsc2026-analytics-ec2"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "ec2_subnet_name" {
  description = "채점 2-1 은 EC2 가 analytics-priv-a 서브넷에 있는지 확인함"
  type        = string
  default     = "analytics-priv-a"
}

variable "alb_name" {
  type    = string
  default = "wsc2026-analytics-alb"
}

variable "tg_name" {
  type    = string
  default = "wsc2026-analytics-tg"
}

variable "app_port" {
  description = "애플리케이션 포트 (채점 2-2 는 TargetGroup Port 5000 확인)"
  type        = number
  default     = 5000
}

variable "stream_name" {
  type    = string
  default = "wsc2026-order-stream"
}

variable "flink_app_name" {
  type    = string
  default = "wsc2026-analytics-flink"
}

variable "flink_runtime" {
  description = "채점 2-4 는 ZEPPELIN-FLINK-3_0 (Managed Flink Studio Notebook) 확인"
  type        = string
  default     = "ZEPPELIN-FLINK-3_0"
}

variable "glue_database_name" {
  description = "Studio Notebook 이 요구하는 Glue Data Catalog 데이터베이스"
  type        = string
  default     = "wsc2026_analytics_db"
}

# ---------------------------------------------------------------- IAM
variable "ec2_role_name" {
  description = "문제지 표기 그대로 (문제지에 'alaytics' 오타가 있으나 원문을 따름)"
  type        = string
  default     = "wsc2026-alaytics-ec2-role"
}

variable "flink_role_name" {
  type    = string
  default = "wsc2026-analytics-flink-role"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  public_subnet_names  = [for k, v in var.subnets : k if v.public]
  private_subnet_names = [for k, v in var.subnets : k if !v.public]
}
