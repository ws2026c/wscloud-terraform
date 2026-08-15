###############################################################################
# iam.tf - 최소 권한(Least Privilege) IAM Role / Policy
#   wsc2026-lambda-student-role       : Lambda(성적 처리 + 트리거) 공용
#   wsc2026-stepfunction-student-role : Step Functions State Machine
###############################################################################

locals {
  # 순환 참조 방지를 위해 State Machine ARN을 문자열로 구성
  state_machine_arn = "arn:aws:states:${local.region}:${local.account_id}:stateMachine:${var.state_machine_name}"
}

###############################################################################
# 1) Lambda Role
###############################################################################

data "aws_iam_policy_document" "lambda_assume_role" {
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
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_policy" {
  # CloudWatch Logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${var.process_function_name}:*",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${var.trigger_function_name}:*",
    ]
  }

  # 입력 CSV 읽기
  statement {
    sid       = "ReadInputObject"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.score.arn}/input/*"]
  }

  # 검증 실패 데이터 error/ 저장
  statement {
    sid       = "WriteErrorObject"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.score.arn}/error/*"]
  }

  # DynamoDB 저장
  statement {
    sid       = "PutStudentScore"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.score.arn]
  }

  # 트리거 Lambda -> Step Functions 실행
  statement {
    sid       = "StartWorkflowExecution"
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [local.state_machine_arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "wsc2026-lambda-student-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

###############################################################################
# 2) Step Functions Role
###############################################################################

data "aws_iam_policy_document" "sfn_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = var.sfn_role_name
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role.json
}

data "aws_iam_policy_document" "sfn_policy" {
  # 성적 처리 Lambda 호출
  statement {
    sid       = "InvokeProcessLambda"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.process.arn,
      "${aws_lambda_function.process.arn}:*",
    ]
  }

  # CheckS3File(HeadObject) + CopyObject 원본 읽기
  statement {
    sid       = "ReadInputObject"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.score.arn}/input/*"]
  }

  # processed/ , error/ 로 복사
  statement {
    sid       = "CopyObjectToTarget"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.score.arn}/processed/*",
      "${aws_s3_bucket.score.arn}/error/*",
    ]
  }

  # 원본 삭제
  statement {
    sid       = "DeleteInputObject"
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = ["${aws_s3_bucket.score.arn}/input/*"]
  }
}

resource "aws_iam_role_policy" "sfn" {
  name   = "wsc2026-stepfunction-student-policy"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn_policy.json
}
