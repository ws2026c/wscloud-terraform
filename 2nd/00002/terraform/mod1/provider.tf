###############################################################################
# provider.tf - Terraform / AWS Provider 설정
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    # pipeline.tf (완전 자동 실행) 용 - 추가 후 terraform init 재실행 필요
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "wsc2026-student-score"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
