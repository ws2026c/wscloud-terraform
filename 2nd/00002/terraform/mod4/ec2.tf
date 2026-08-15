###############################################################################
# ec2.tf - Producer 서버 (Private Subnet)
#   부팅 시 수행:
#     1) Kafka CLI + MSK IAM Auth 설치
#     2) 토픽 생성  wsc2026-sensor-raw(3,RF2) / wsc2026-sensor-alert(1,RF2)
#     3) app 바이너리 배치 후 systemd 상시 실행 (재부팅 시 자동 시작)
#     4) (옵션) Lambda 용 kafka 레이어 빌드 및 부착
###############################################################################

resource "aws_instance" "producer" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.this[var.ec2_subnet_name].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  associate_public_ip_address = false

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    region                 = var.region
    cluster_arn            = aws_msk_cluster.main.arn
    kafka_version          = var.kafka_version
    topic_raw              = var.topic_raw
    topic_alert            = var.topic_alert
    artifact_bucket        = aws_s3_bucket.artifact.id
    build_layer            = var.build_lambda_kafka_layer ? "true" : "false"
    consumer_function_name = var.consumer_function_name
    producer_bootstrap     = var.producer_bootstrap
  })

  tags = { Name = var.ec2_name }

  depends_on = [
    aws_msk_cluster.main,
    aws_route.priv_default,
    aws_nat_gateway.ngw,
    aws_s3_object.app_binary,
    aws_iam_role_policy.ec2,
    aws_iam_role_policy_attachment.ec2_ssm,
  ]
}
