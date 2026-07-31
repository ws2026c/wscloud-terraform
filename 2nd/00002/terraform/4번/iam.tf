###############################################################################
# iam.tf - 최소 권한
#   wsc2026-msk-ec2-role     : MSK 토픽 생성/produce + app 다운로드 + SSM
#   wsc2026-msk-lambda-role  : MSK consume + DynamoDB/SNS/S3 + alert 토픽 produce
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

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ec2_policy" {
  statement {
    sid    = "MskDescribe"
    effect = "Allow"
    actions = [
      "kafka:DescribeCluster",
      "kafka:DescribeClusterV2",
      "kafka:GetBootstrapBrokers",
    ]
    resources = [local.msk_cluster_arn]
  }

  statement {
    sid    = "MskConnect"
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeCluster",
      "kafka-cluster:AlterCluster",
    ]
    resources = [local.msk_cluster_arn]
  }

  statement {
    sid    = "MskTopic"
    effect = "Allow"
    actions = [
      "kafka-cluster:CreateTopic",
      "kafka-cluster:DescribeTopic",
      "kafka-cluster:DescribeTopicDynamicConfiguration",
      "kafka-cluster:AlterTopic",
      "kafka-cluster:AlterTopicDynamicConfiguration",
      "kafka-cluster:WriteData",
      "kafka-cluster:ReadData",
    ]
    resources = [local.msk_topic_arn]
  }

  statement {
    sid    = "MskGroup"
    effect = "Allow"
    actions = [
      "kafka-cluster:AlterGroup",
      "kafka-cluster:DescribeGroup",
    ]
    resources = [local.msk_group_arn]
  }

  statement {
    sid     = "ArtifactBucketAccess"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject"]
    # PutObject 는 kafka-layer.zip 업로드용 (레이어 빌드 옵션)
    resources = ["${aws_s3_bucket.artifact.arn}/*"]
  }

  statement {
    sid       = "ArtifactBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.artifact.arn]
  }
}

resource "aws_iam_role_policy" "ec2" {
  name   = "wsc2026-msk-ec2-policy"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_policy.json
}

# Lambda 용 kafka-python 레이어를 EC2 가 빌드해서 붙이는 경우에만 필요
data "aws_iam_policy_document" "ec2_layer_build" {
  statement {
    sid    = "PublishKafkaLayer"
    effect = "Allow"
    actions = [
      "lambda:PublishLayerVersion",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:UpdateFunctionConfiguration",
    ]
    resources = [
      "arn:${local.partition}:lambda:${var.region}:${local.account_id}:layer:wsc2026-kafka-layer",
      "arn:${local.partition}:lambda:${var.region}:${local.account_id}:layer:wsc2026-kafka-layer:*",
      "arn:${local.partition}:lambda:${var.region}:${local.account_id}:function:${var.consumer_function_name}",
    ]
  }
}

resource "aws_iam_role_policy" "ec2_layer_build" {
  count = var.build_lambda_kafka_layer ? 1 : 0

  name   = "wsc2026-msk-ec2-layer-policy"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_layer_build.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = var.ec2_role_name
  role = aws_iam_role.ec2.name
}

###############################################################################
# 2) Lambda Role
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

# MSK 이벤트 소스에 필요한 kafka-cluster 읽기 + ENI 관리 + 로그
resource "aws_iam_role_policy_attachment" "lambda_msk" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaMSKExecutionRole"
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid       = "SaveSensorData"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.sensor.arn]
  }

  statement {
    sid       = "PublishAlert"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alert.arn]
  }

  statement {
    sid       = "SaveAlertLog"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alert.arn}/alert/*"]
  }

  # MSK 이벤트 소스(소비) + alert 토픽 produce 에 필요한 데이터플레인 권한.
  #
  #  ※ AWSLambdaMSKExecutionRole 관리형 정책에는 kafka:Describe*/ENI 권한만 있고
  #    kafka-cluster:* (IAM 인증 데이터플레인) 권한이 전혀 없다.
  #    ReadData / DescribeGroup / AlterGroup 이 없으면 이벤트 소스 매핑이
  #    "PROBLEM: Cluster failed to authorize Lambda" 로 소비에 실패한다.
  statement {
    sid    = "MskConnect"
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeCluster",
      "kafka-cluster:DescribeClusterDynamicConfiguration",
    ]
    resources = [local.msk_cluster_arn]
  }

  statement {
    sid    = "MskTopicReadWrite"
    effect = "Allow"
    actions = [
      "kafka-cluster:ReadData",
      "kafka-cluster:WriteData",
      "kafka-cluster:DescribeTopic",
      "kafka-cluster:DescribeTopicDynamicConfiguration",
    ]
    resources = [local.msk_topic_arn]
  }

  statement {
    sid    = "MskConsumerGroup"
    effect = "Allow"
    actions = [
      "kafka-cluster:DescribeGroup",
      "kafka-cluster:AlterGroup",
    ]
    resources = [local.msk_group_arn]
  }

  statement {
    sid       = "GetBootstrapBrokers"
    effect    = "Allow"
    actions   = ["kafka:GetBootstrapBrokers", "kafka:DescribeCluster"]
    resources = [local.msk_cluster_arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "wsc2026-msk-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}
