resource "aws_kms_key" "function_kms" {
  description             = "KMS Key for Lambda Function Encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "wsc2026-function-kms"
  }
}

resource "aws_kms_alias" "function_kms_alias" {
  name          = "alias/wsc2026-function-kms"
  target_key_id = aws_kms_key.function_kms.key_id
}

resource "aws_kms_key_policy" "function_kms_policy" {
  key_id = aws_kms_key.function_kms.id

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
          "kms:CancelKeyDeletion",
          "kms:Encrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowLambdaExecutionRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.book_function_role.arn
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  depends_on = [
    aws_iam_role.book_function_role
  ]
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    filename = "lambda_function.py"
    content  = <<EOF
import json
import os
import base64
from collections import OrderedDict
import boto3
from botocore.exceptions import ClientError

REGION = 'ap-northeast-2'

def decrypt_env_var(env_name):
    raw_value = os.environ.get(env_name)
    if not raw_value:
        raise RuntimeError(f"{env_name} environment variable is not set.")
    try:
        kms = boto3.client('kms', region_name=REGION)
        decoded_data = base64.b64decode(raw_value)
        return kms.decrypt(CiphertextBlob=decoded_data)['Plaintext'].decode('utf-8')
    except Exception:
        return raw_value

TABLE_NAME = decrypt_env_var('TABLE_NAME')
dynamodb = boto3.resource('dynamodb', region_name=REGION)
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    query_params = event.get('queryStringParameters') or {}
    booking_id = query_params.get('booking_id')
    
    if not booking_id:
        return {
            'statusCode': 400,
            'body': json.dumps({'message': 'Missing required parameter: booking_id'})
        }
    
    try:
        from boto3.dynamodb.conditions import Key
        response = table.query(
            IndexName='BookingIdIndex',
            KeyConditionExpression=Key('booking_id').eq(booking_id)
        )
        
        items = response.get('Items', [])
        
        if not items:
            return {
                'statusCode': 404,
                'body': json.dumps({'message': f'Booking with id {booking_id} not found'})
            }
            
        item = items[0]
        
        ordered_body = OrderedDict([
            ("client_id", item.get("client_id")),
            ("username", item.get("username")),
            ("email", item.get("email")),
            ("concert_name", item.get("concert_name")),
            ("created_at", item.get("created_at"))
        ])
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps(ordered_body)
        }
        
    except ClientError as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'message': 'Internal Server Error', 'error': e.response['Error']['Message']})
        }
EOF
  }
}

resource "aws_lambda_function" "book_get_function" {
  function_name    = "wsc2026-book-get-function"
  role             = aws_iam_role.book_function_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  kms_key_arn = aws_kms_key.function_kms.arn

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.book_table.name
    }
  }

  tags = {
    Name = "wsc2026-book-get-function"
  }
}

resource "aws_lambda_function_url" "book_function_url" {
  function_name      = aws_lambda_function.book_get_function.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "allow_function_url" {
  statement_id           = "FunctionURLAllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.book_get_function.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}