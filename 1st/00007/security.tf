variable "candidate_number" {
  type        = string
  description = "Candidate Number"
  default     = "101"
}

data "aws_region" "current" {}

resource "aws_iam_role" "unicorn_audit_role" {
  name                 = "unicorn-audit-role"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "unicorn-audit-2026${var.candidate_number}"
          }
        }
      }
    ]
  })

  inline_policy {
    name = "unicorn-audit-inline-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "DynamoDBReadAccess"
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:Query",
            "dynamodb:DescribeTable"
          ]
          Resource = [
            "arn:aws:dynamodb:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:table/unicorn-concert-db",
            "arn:aws:dynamodb:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:table/unicorn-concert-db/index/client-id-created-at-index"
          ]
        },
        {
          Sid    = "VPCDescribeAccess"
          Effect = "Allow"
          Action = [
            "ec2:DescribeVpcs",
            "ec2:DescribeSubnets",
            "ec2:DescribeRouteTables",
            "ec2:DescribeInternetGateways",
            "ec2:DescribeNatGateways"
          ]
          Resource = "*"
        },
        {
          Sid    = "EKSDescribeAccess"
          Effect = "Allow"
          Action = [
            "eks:DescribeCluster",
            "eks:DescribeNodegroup"
          ]
          Resource = "arn:aws:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:cluster/unicorn-eks-cluster"
        }
      ]
    })
  }

  tags = {
    Name = "unicorn-audit-role"
  }
}
