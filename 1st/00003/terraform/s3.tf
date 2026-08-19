resource "aws_kms_key" "bucket_kms" {
  description             = "KMS Key for S3 Bucket Encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "wsc2026-bucket-kms"
  }
}

resource "aws_kms_alias" "bucket_kms_alias" {
  name          = "alias/wsc2026-bucket-kms"
  target_key_id = aws_kms_key.bucket_kms.key_id
}

resource "aws_kms_key_policy" "bucket_kms_policy" {
  key_id = aws_kms_key.bucket_kms.id

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
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_s3_bucket" "static_bucket" {
  bucket        = "wsc2026-static-${var.random_suffix}${var.user_number}-bucket"
  force_destroy = true

  tags = {
    Name = "wsc2026-static-${var.random_suffix}${var.user_number}-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "static_bucket_pab" {
  bucket                  = aws_s3_bucket.static_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static_bucket_encryption" {
  bucket = aws_s3_bucket.static_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.bucket_kms.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}