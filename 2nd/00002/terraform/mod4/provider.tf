###############################################################################
# provider.tf - 제2과제 4) MSK
#   Region: ap-northeast-1
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # python3.14 런타임은 Provider 가 내부 화이트리스트로 검증한다.
    # 5.x 구버전에는 python3.14 가 없어 아래 오류가 난다.
    #   Error: expected runtime to be one of [... "python3.13" ...], got python3.14
    # 최신 Provider 로 올려야 하므로 하한을 6.0 으로 둔다.
    #   반드시  terraform init -upgrade  로 재초기화할 것
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    # EC2 user_data 가 토픽을 만들 때까지 기다리는 용도
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
      Project = "wsc2026-msk"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}
