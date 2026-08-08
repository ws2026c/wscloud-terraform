data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    filename = "index.py"
    content  = <<EOF
import os
import json
import boto3
from boto3.dynamodb.conditions import Key
from datetime import datetime, timedelta, timezone

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ.get('TABLE_NAME'))

def lambda_handler(event, context):
    response_headers = {
        'Content-Type': 'application/json; charset=utf-8'
    }

    path = event.get('path', '')
    if path.rstrip('/') != '/reserv_query':
        return {
            'statusCode': 404,
            'headers': response_headers,
            'body': json.dumps({'message': 'Not Found'})
        }

    query_params = event.get('queryStringParameters') or {}
    
    if 'concert_name' not in query_params:
        return {
            'statusCode': 400,
            'headers': response_headers,
            'body': json.dumps({'error': 'Missing required parameter: concert_name'}, ensure_ascii=False)
        }
    
    concert_name = query_params['concert_name']
    
    try:
        response = table.query(
            IndexName='concert_name-created_at-index',
            KeyConditionExpression=Key('concert_name').eq(concert_name),
            ScanIndexForward=False
        )
        
        items = response.get('Items', [])
        
        formatted_items = []
        for item in items:
            if 'created_at' in item:
                try:
                    dt = datetime.fromisoformat(item['created_at'].replace('Z', '+00:00'))
                    kst_dt = dt.astimezone(timezone(timedelta(hours=9)))
                    item['created_at'] = kst_dt.isoformat(timespec='seconds')
                except Exception:
                    pass
            
            ordered_item = {
                'username': item.get('username'),
                'created_at': item.get('created_at'),
                'email': item.get('email'),
                'booking_id': item.get('booking_id'),
                'client_id': item.get('client_id'),
                'concert_name': item.get('concert_name')
            }
            formatted_items.append(ordered_item)
        
        return {
            'statusCode': 200,
            'headers': response_headers,
            'body': json.dumps(formatted_items, ensure_ascii=False)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': response_headers,
            'body': json.dumps({'error': str(e)}, ensure_ascii=False)
        }
EOF
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "wskorea26-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "wskorea26-lambda-policy"
  description = "Minimal IAM policy for wskorea26-book-lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.data_table.arn,
          "${aws_dynamodb_table.data_table.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.dynamodb_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "book_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "wskorea26-book-lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.14"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.data_table.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attach
  ]

  tags = {
    Name = "wskorea26-book-lambda"
  }
}