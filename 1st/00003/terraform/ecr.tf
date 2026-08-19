resource "aws_kms_key" "ecr_kms" {
  description             = "KMS Key for ECR Repository Encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "wsc2026-ecr-kms"
  }
}

resource "aws_kms_alias" "ecr_kms_alias" {
  name          = "alias/wsc2026-ecr-kms"
  target_key_id = aws_kms_key.ecr_kms.key_id
}

resource "aws_kms_key_policy" "ecr_kms_policy" {
  key_id = aws_kms_key.ecr_kms.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAdminManagement"
        Effect = "Allow"
        Principal = {
          AWS = var.admin_iam_arn
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowNodeRoleDecryptForPull"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.eks_node_role.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  depends_on = [
    aws_iam_role.eks_node_role
  ]
}

resource "aws_ecr_repository" "book_ecr" {
  name                 = "wsc2026-book-ecr"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr_kms.arn
  }

  tags = {
    Name = "wsc2026-book-ecr"
  }
}

resource "aws_ecr_repository_policy" "book_ecr_policy" {
  repository = aws_ecr_repository.book_ecr.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowNodePull"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.eks_node_role.arn
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}