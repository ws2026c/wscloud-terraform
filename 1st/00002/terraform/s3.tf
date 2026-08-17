data "aws_caller_identity" "current" {}

resource "aws_kms_key" "s3_key" {
  description             = "KMS Key for S3 Bucket"
  deletion_window_in_days = 7

  tags = {
    Name = "wskorea26-s3-key"
  }
}

resource "aws_kms_alias" "s3_key_alias" {
  name          = "alias/wskorea26-s3-key"
  target_key_id = aws_kms_key.s3_key.key_id
}

resource "aws_kms_key_policy" "s3_key_policy" {
  key_id = aws_kms_key.s3_key.id
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
        Sid    = "Allow S3 Service Use of Key"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_s3_bucket" "concert_bucket" {
  bucket        = "wskorea26-concert-bucket-${var.contestant_number}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "concert_bucket_block" {
  bucket                  = aws_s3_bucket.concert_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "concert_bucket_encryption" {
  bucket = aws_s3_bucket.concert_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}