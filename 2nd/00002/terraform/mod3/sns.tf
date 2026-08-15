###############################################################################
# sns.tf - 위반 알림 Topic
#   채점 3-1 : arn:aws:sns:eu-west-1:<ACCOUNT_ID>:wsc2026-event-alert
###############################################################################

resource "aws_sns_topic" "alert" {
  name         = var.sns_topic_name
  display_name = "WSC2026 Event Alert"
}

# 이메일로 실제 알림을 받고 싶으면 아래 주석을 풀고 주소를 넣은 뒤 확인 메일을 승인하세요.
# resource "aws_sns_topic_subscription" "email" {
#   topic_arn = aws_sns_topic.alert.arn
#   protocol  = "email"
#   endpoint  = "you@example.com"
# }
