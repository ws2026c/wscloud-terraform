###############################################################################
# kinesis.tf - 주문 로그 수집 스트림
#   채점 2-3-A : wsc2026-order-stream / ACTIVE / ON_DEMAND
###############################################################################

resource "aws_kinesis_stream" "orders" {
  name             = var.stream_name
  retention_period = 24

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }
}
