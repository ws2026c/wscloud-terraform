resource "aws_kms_key" "dynamodb_key" {
  description             = "KMS Key for DynamoDB Table"
  deletion_window_in_days = 7

  tags = {
    Name = "wskorea26-dynamodb-key"
  }
}

resource "aws_kms_alias" "dynamodb_key_alias" {
  name          = "alias/wskorea26-dynamodb-key"
  target_key_id = aws_kms_key.dynamodb_key.key_id
}

resource "aws_kms_key_policy" "dynamodb_key_policy" {
  key_id = aws_kms_key.dynamodb_key.id
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
        Sid    = "Allow DynamoDB Service Use of Key"
        Effect = "Allow"
        Principal = {
          Service = "dynamodb.amazonaws.com"
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

resource "aws_dynamodb_table" "data_table" {
  name                        = "wskorea26-data-table"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "client_id"
  deletion_protection_enabled = true

  attribute {
    name = "client_id"
    type = "S"
  }

  attribute {
    name = "concert_name"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "concert_name-created_at-index"
    hash_key        = "concert_name"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb_key.arn
  }

  tags = {
    Name = "wskorea26-data-table"
  }
}