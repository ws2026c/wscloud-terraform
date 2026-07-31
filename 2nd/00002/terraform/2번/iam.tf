###############################################################################
# iam.tf - 최소 권한
#   EC2   : Kinesis PutRecord + SSM(Session Manager)
#   Flink : Kinesis 읽기 + Glue Data Catalog + CloudWatch Logs
###############################################################################

###############################################################################
# 1) EC2 Role
###############################################################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = var.ec2_role_name
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# SSM Session Manager / RunCommand (채점 2-6 이 SSM 으로 접속)
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ec2_policy" {
  statement {
    sid    = "PutOrderRecords"
    effect = "Allow"
    actions = [
      "kinesis:PutRecord",
      "kinesis:PutRecords",
      "kinesis:DescribeStreamSummary",
    ]
    resources = [aws_kinesis_stream.orders.arn]
  }
}

resource "aws_iam_role_policy" "ec2" {
  name   = "wsc2026-analytics-ec2-policy"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_policy.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = var.ec2_role_name
  role = aws_iam_role.ec2.name
}

###############################################################################
# 2) Managed Flink (Studio Notebook) Role
###############################################################################

data "aws_iam_policy_document" "flink_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["kinesisanalytics.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flink" {
  name               = var.flink_role_name
  assume_role_policy = data.aws_iam_policy_document.flink_assume.json
}

data "aws_iam_policy_document" "flink_policy" {
  # Kinesis Data Stream 읽기
  statement {
    sid    = "ReadOrderStream"
    effect = "Allow"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards",
      "kinesis:SubscribeToShard",
      "kinesis:RegisterStreamConsumer",
      "kinesis:DeregisterStreamConsumer",
      "kinesis:DescribeStreamConsumer",
    ]
    resources = [
      aws_kinesis_stream.orders.arn,
      "${aws_kinesis_stream.orders.arn}/*",
    ]
  }

  # Studio Notebook 이 사용하는 Glue Data Catalog
  #
  #  ※ 애플리케이션 생성 시 KinesisAnalyticsV2 가 ServiceExecutionRole 로
  #    glue:GetDatabase 를 검증 호출한다. 이때 지정 DB 뿐 아니라
  #    default / hive 데이터베이스와 connection 리소스까지 접근 대상이 되므로
  #    AWS 공식 Studio Notebook 정책과 동일한 리소스 목록을 부여한다.
  #    (그렇지 않으면 "insufficient permission to perform glue:GetDatabase" 로 생성 실패)
  statement {
    sid    = "GlueCatalog"
    effect = "Allow"
    actions = [
      "glue:GetConnection",
      "glue:GetConnections",
      "glue:GetTable",
      "glue:GetTables",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:CreateDatabase",
      "glue:UpdateDatabase",
      "glue:GetUserDefinedFunction",
      "glue:GetUserDefinedFunctions",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:CreatePartition",
      "glue:BatchCreatePartition",
    ]
    resources = [
      "arn:aws:glue:${var.region}:${local.account_id}:catalog",
      "arn:aws:glue:${var.region}:${local.account_id}:database/${var.glue_database_name}",
      "arn:aws:glue:${var.region}:${local.account_id}:database/default",
      "arn:aws:glue:${var.region}:${local.account_id}:database/hive",
      "arn:aws:glue:${var.region}:${local.account_id}:database/global_temp",
      "arn:aws:glue:${var.region}:${local.account_id}:table/${var.glue_database_name}/*",
      "arn:aws:glue:${var.region}:${local.account_id}:table/default/*",
      "arn:aws:glue:${var.region}:${local.account_id}:table/hive/*",
      "arn:aws:glue:${var.region}:${local.account_id}:userDefinedFunction/${var.glue_database_name}/*",
      "arn:aws:glue:${var.region}:${local.account_id}:userDefinedFunction/default/*",
      "arn:aws:glue:${var.region}:${local.account_id}:userDefinedFunction/hive/*",
      "arn:aws:glue:${var.region}:${local.account_id}:connection/*",
    ]
  }

  # CloudWatch Logs
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
      "logs:CreateLogStream",
    ]
    resources = [
      "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/kinesis-analytics/${var.flink_app_name}",
      "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/kinesis-analytics/${var.flink_app_name}:*",
    ]
  }
}

resource "aws_iam_role_policy" "flink" {
  name   = "wsc2026-analytics-flink-policy"
  role   = aws_iam_role.flink.id
  policy = data.aws_iam_policy_document.flink_policy.json
}
