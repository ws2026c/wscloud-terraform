###############################################################################
# provider.tf - 제2과제 2) Real-time data analytics
#   Region: ap-northeast-2
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # 신규 IAM Role/Policy 전파 대기용 (Windows/Linux 공통 동작)
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "wsc2026-analytics"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Amazon Linux 2023 (SSM Agent 기본 탑재)
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}
