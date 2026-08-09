resource "aws_kms_key" "db_kms" {
  description             = "KMS Key for DynamoDB Table Encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "wsc2026-db-kms"
  }
}

resource "aws_kms_alias" "db_kms_alias" {
  name          = "alias/wsc2026-db-kms"
  target_key_id = aws_kms_key.db_kms.key_id
}

resource "aws_kms_key_policy" "db_kms_policy" {
  key_id = aws_kms_key.db_kms.id

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
        Sid    = "AllowDynamoDBAndRolesUse"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.book_pod_role.arn,
            aws_iam_role.book_function_role.arn
          ]
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

  depends_on = [
    aws_iam_role.book_pod_role,
    aws_iam_role.book_function_role
  ]
}

resource "aws_dynamodb_table" "book_table" {
  name                        = "wsc2026-book-table"
  billing_mode                = "PAY_PER_REQUEST"
  deletion_protection_enabled = true
  hash_key                    = "client_id"

  attribute {
    name = "client_id"
    type = "S"
  }

  attribute {
    name = "booking_id"
    type = "S"
  }

  global_secondary_index {
    name            = "BookingIdIndex"
    hash_key        = "booking_id"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.db_kms.arn
  }

  tags = {
    Name = "wsc2026-book-table"
  }
}

resource "aws_dynamodb_resource_policy" "book_table_policy" {
  resource_arn = aws_dynamodb_table.book_table.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPodPutItemOnly"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.book_pod_role.arn
        }
        Action = [
          "dynamodb:PutItem"
        ]
        Resource = [
          aws_dynamodb_table.book_table.arn
        ]
      },
      {
        Sid    = "AllowLambdaGetAndQueryOnly"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.book_function_role.arn
        }
        Action = [
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.book_table.arn,
          "${aws_dynamodb_table.book_table.arn}/index/*"
        ]
      }
    ]
  })
}