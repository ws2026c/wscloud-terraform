###############################################################################
# eventbridge.tf - 위반 감지 Rule
#   채점 3-2 : wsc2026-ec2-stop-rule      -> wsc2026-ec2-stop-remediation
#              wsc2026-ec2-terminate-rule -> wsc2026-ec2-terminate-alert
#   문제지   : wsc2026-sg-change-rule / wsc2026-role-change-rule /
#              wsc2026-ec2-terminate-rule / wsc2026-ec2-type-change-rule
###############################################################################

locals {
  event_rules = {
    # --- Security Group 인바운드 규칙 추가 (CloudTrail API 이벤트)
    "wsc2026-sg-change-rule" = {
      function    = "wsc2026-sg-remediation"
      description = "EC2 Security Group 인바운드 규칙 추가 감지"
      pattern = jsonencode({
        source        = ["aws.ec2"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["ec2.amazonaws.com"]
          eventName   = ["AuthorizeSecurityGroupIngress"]
        }
      })
    }

    # --- EC2 IAM Role 변경
    "wsc2026-role-change-rule" = {
      function    = "wsc2026-role-remediation"
      description = "EC2 IAM Role(Instance Profile) 변경 감지"
      pattern = jsonencode({
        source        = ["aws.ec2"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["ec2.amazonaws.com"]
          eventName = [
            "AssociateIamInstanceProfile",
            "ReplaceIamInstanceProfileAssociation",
          ]
        }
      })
    }

    # --- EC2 인스턴스 종료
    "wsc2026-ec2-terminate-rule" = {
      function    = "wsc2026-ec2-terminate-alert"
      description = "EC2 인스턴스 종료 감지"
      pattern = jsonencode({
        source        = ["aws.ec2"]
        "detail-type" = ["EC2 Instance State-change Notification"]
        detail = {
          state = ["terminated", "shutting-down"]
        }
      })
    }

    # --- EC2 인스턴스 타입 변경
    "wsc2026-ec2-type-change-rule" = {
      function    = "wsc2026-ec2-type-remediation"
      description = "EC2 인스턴스 타입 변경 감지"
      pattern = jsonencode({
        source        = ["aws.ec2"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["ec2.amazonaws.com"]
          eventName   = ["ModifyInstanceAttribute"]
        }
      })
    }

    # --- EC2 인스턴스 중지 (채점 3-2 / 3-4)
    "wsc2026-ec2-stop-rule" = {
      function    = "wsc2026-ec2-stop-remediation"
      description = "EC2 인스턴스 중지 감지 -> 자동 재시작"
      pattern = jsonencode({
        source        = ["aws.ec2"]
        "detail-type" = ["EC2 Instance State-change Notification"]
        detail = {
          state = ["stopping", "stopped"]
        }
      })
    }

    # --- 필수 태그 변경 (채점 3-1 의 wsc2026-tag-alert 용)
    "wsc2026-tag-change-rule" = {
      function    = "wsc2026-tag-alert"
      description = "EC2 인스턴스 태그 변경 감지"
      pattern = jsonencode({
        source        = ["aws.tag"]
        "detail-type" = ["Tag Change on Resource"]
        detail = {
          service         = ["ec2"]
          "resource-type" = ["instance"]
        }
      })
    }
  }
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.event_rules

  name          = each.key
  description   = each.value.description
  event_pattern = each.value.pattern
  # state 인자는 provider 5.26+ 에서만 지원되므로 생략 (기본값 ENABLED)
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.event_rules

  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = each.value.function
  arn       = aws_lambda_function.fn[each.value.function].arn
}

resource "aws_lambda_permission" "events" {
  for_each = local.event_rules

  statement_id  = "AllowExecutionFromEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn[each.value.function].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this[each.key].arn
}
