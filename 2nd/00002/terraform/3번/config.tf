###############################################################################
# config.tf - AWS Config 규칙
#   채점 3-3 : wsc2026-sg-ssh-rule ACTIVE / wsc2026-required-tags-rule ACTIVE
#   채점 3-5 : wsc2026-required-tags-rule 의 NON_COMPLIANT 리소스가 없어야 함(None)
#
#   Config 규칙은 Configuration Recorder 가 켜져 있어야 평가된다.
###############################################################################

resource "aws_s3_bucket" "config" {
  bucket        = local.config_bucket
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "config_bucket" {
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.config.arn]
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config.arn}/AWSLogs/${local.account_id}/Config/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config_bucket.json
}

###############################################################################
# Config Service Role
###############################################################################

data "aws_iam_policy_document" "config_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  name               = "wsc2026-event-config-role"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json
}

resource "aws_iam_role_policy_attachment" "config_managed" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

data "aws_iam_policy_document" "config_delivery" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.config.arn, "${aws_s3_bucket.config.arn}/*"]
  }
}

resource "aws_iam_role_policy" "config_delivery" {
  name   = "wsc2026-event-config-delivery"
  role   = aws_iam_role.config.id
  policy = data.aws_iam_policy_document.config_delivery.json
}

###############################################################################
# Configuration Recorder / Delivery Channel
###############################################################################

resource "aws_config_configuration_recorder" "main" {
  name     = "wsc2026-event-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types = [
      "AWS::EC2::Instance",
      "AWS::EC2::SecurityGroup",
    ]
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "wsc2026-event-delivery"
  s3_bucket_name = aws_s3_bucket.config.id

  depends_on = [
    aws_config_configuration_recorder.main,
    aws_s3_bucket_policy.config,
  ]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

###############################################################################
# Config Rules
###############################################################################

# SSH(22) 무제한 인바운드 금지
resource "aws_config_config_rule" "sg_ssh" {
  name        = var.config_sg_rule_name
  description = "Security Group 에 0.0.0.0/0 SSH 인바운드가 없어야 함"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  scope {
    compliance_resource_types = ["AWS::EC2::SecurityGroup"]
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# 필수 태그 보유 (채점 3-5 : NON_COMPLIANT 리소스가 없어야 함)
resource "aws_config_config_rule" "required_tags" {
  name        = var.config_tags_rule_name
  description = "EC2 인스턴스에 필수 태그(${var.required_tag_key})가 있어야 함"

  source {
    owner             = "AWS"
    source_identifier = "REQUIRED_TAGS"
  }

  input_parameters = jsonencode({
    tag1Key = var.required_tag_key
  })

  scope {
    compliance_resource_types = ["AWS::EC2::Instance"]
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}
