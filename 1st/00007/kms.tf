data "aws_caller_identity" "current" {}

resource "aws_kms_key" "app" {
  description             = "KMS Key for DynamoDB and Secrets Manager"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  rotation_period_in_days = 90

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow DynamoDB and Secrets Manager Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "dynamodb.amazonaws.com",
            "secretsmanager.amazonaws.com"
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "unicorn-kms-app"
  }
}

resource "aws_kms_alias" "app" {
  name          = "alias/unicorn-kms-app"
  target_key_id = aws_kms_key.app.key_id
}

resource "aws_kms_key" "data" {
  description             = "KMS Key for S3 and ECR"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  rotation_period_in_days = 90

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow S3 and ECR Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "s3.amazonaws.com",
            "ecr.amazonaws.com"
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "unicorn-kms-data"
  }
}

resource "aws_kms_alias" "data" {
  name          = "alias/unicorn-kms-data"
  target_key_id = aws_kms_key.data.key_id
}

resource "aws_kms_key" "platform" {
  description             = "Multi-Region Primary KMS Key for EKS, EBS, Logs, WAF"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  rotation_period_in_days = 90
  multi_region            = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow EKS EBS Logs WAF Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "eks.amazonaws.com",
            "ec2.amazonaws.com",
            "logs.amazonaws.com",
            "wafv2.amazonaws.com"
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "unicorn-kms-platform"
  }
}

resource "aws_kms_alias" "platform" {
  name          = "alias/unicorn-kms-platform"
  target_key_id = aws_kms_key.platform.key_id
}

resource "aws_kms_replica_key" "platform_us_east_1" {
  provider                = aws.us_east_1
  description             = "Multi-Region Replica KMS Key for WAF Logs in us-east-1"
  deletion_window_in_days = 7
  primary_key_arn         = aws_kms_key.platform.arn

  tags = {
    Name = "unicorn-kms-platform"
  }
}

resource "aws_kms_alias" "platform_us_east_1" {
  provider      = aws.us_east_1
  name          = "alias/unicorn-kms-platform"
  target_key_id = aws_kms_replica_key.platform_us_east_1.key_id
}
