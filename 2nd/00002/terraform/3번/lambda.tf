###############################################################################
# lambda.tf - 자동 복구 / 알림 Lambda 6종
#   채점 3-1 : wsc2026-ec2-stop-remediation / wsc2026-ec2-terminate-alert /
#              wsc2026-sg-remediation / wsc2026-tag-alert  (모두 python3.12)
#   문제지   : wsc2026-role-remediation / wsc2026-ec2-type-remediation 추가
#
#   전 함수 Handler = index.handler, 환경변수 FUNCTION_ROLE 로 동작 분기
###############################################################################

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/src/index.py"
  output_path = "${path.module}/build/lambda.zip"
}

###############################################################################
# Lambda 실행 Role (최소 권한)
###############################################################################

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = var.lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/wsc2026-*"]
  }

  statement {
    sid       = "PublishAlert"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alert.arn]
  }

  # 조회 계열은 리소스 지정이 불가능한 API
  statement {
    sid    = "DescribeResources"
    effect = "Allow"
    actions = [
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeTags",
      "ec2:DescribeIamInstanceProfileAssociations",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "RemediateSecurityGroup"
    effect    = "Allow"
    actions   = ["ec2:RevokeSecurityGroupIngress"]
    resources = ["arn:${local.partition}:ec2:${var.region}:${local.account_id}:security-group/${aws_security_group.ec2.id}"]
  }

  statement {
    sid    = "RemediateInstance"
    effect = "Allow"
    actions = [
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:CreateTags",
    ]
    resources = ["arn:${local.partition}:ec2:${var.region}:${local.account_id}:instance/${aws_instance.monitored.id}"]
  }

  statement {
    sid    = "RemediateInstanceProfile"
    effect = "Allow"
    actions = [
      "ec2:AssociateIamInstanceProfile",
      "ec2:ReplaceIamInstanceProfileAssociation",
      "ec2:DisassociateIamInstanceProfile",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassEc2Role"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ec2.arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "wsc2026-event-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

###############################################################################
# Lambda Functions
###############################################################################

resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.lambda_functions

  name              = "/aws/lambda/${each.key}"
  retention_in_days = 7
}

resource "aws_lambda_function" "fn" {
  for_each = local.lambda_functions

  function_name = each.key
  description   = each.value.description
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = each.value.timeout
  memory_size   = 256

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      FUNCTION_ROLE       = each.value.role
      SNS_TOPIC_ARN       = aws_sns_topic.alert.arn
      SECURITY_GROUP_ID   = aws_security_group.ec2.id
      INSTANCE_ID         = aws_instance.monitored.id
      ROLE_NAME           = var.ec2_role_name
      INSTANCE_TYPE       = var.instance_type
      REQUIRED_TAG_KEY    = var.required_tag_key
      REQUIRED_TAG_VALUE  = var.ec2_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda,
  ]
}
