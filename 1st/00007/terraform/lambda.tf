data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = <<EOF
import json
import os
import boto3

TABLE_NAME = os.environ.get("TABLE_NAME")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    try:
        query_params = event.get("queryStringParameters") or {}
        
        booking_id = query_params.get("booking_id")
        email = query_params.get("email")
        concert_name = query_params.get("concert_name")

        if not booking_id:
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Missing required parameter: booking_id"})
            }

        response = table.get_item(Key={"booking_id": booking_id})
        item = response.get("Item")

        if not item:
            return {
                "statusCode": 404,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Booking not found"})
            }

        if email and item.get("email") != email:
            return {
                "statusCode": 404,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Booking not found with specified email"})
            }

        if concert_name and item.get("concert_name") != concert_name:
            return {
                "statusCode": 404,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Booking not found with specified concert_name"})
            }

        result = {
            "booking_id": item.get("booking_id"),
            "client_id": item.get("client_id"),
            "username": item.get("username"),
            "email": item.get("email"),
            "concert_name": item.get("concert_name"),
            "created_at": item.get("created_at")
        }

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(result)
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)})
        }
EOF
    filename = "lambda_function.py"
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/unicorn/lambda/get-booking"
  kms_key_id        = aws_kms_key.platform.arn
  retention_in_days = 30

  tags = {
    Name = "unicorn-lambda-log-group"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "unicorn-lambda-execution-role"

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
  name        = "unicorn-lambda-execution-policy"
  description = "IAM policy for unicorn-get-booking-func Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.concert.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.app.arn,
          aws_kms_key.platform.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda_log_group.arn}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "get_booking" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "unicorn-get-booking-func"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.14"

  kms_key_arn = aws_kms_key.platform.arn

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda_log_group.name
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.concert.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_log_group,
    aws_iam_role_policy_attachment.lambda_policy_attach
  ]

  tags = {
    Name = "unicorn-get-booking-func"
  }
}
