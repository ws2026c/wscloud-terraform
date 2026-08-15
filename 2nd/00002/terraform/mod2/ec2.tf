###############################################################################
# ec2.tf - 주문 로그 발생 애플리케이션 서버
#   채점 2-1 : InstanceType t3.small, Subnet = analytics-priv-a
#   채점 2-6 : systemctl is-active app / is-enabled app -> active / enabled
###############################################################################

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.this[var.ec2_subnet_name].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # Private Subnet 배치 - 퍼블릭 IP 없음, 외부 접근은 ALB 를 통해서만
  associate_public_ip_address = false

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    app_py_b64       = base64encode(file("${path.module}/app/app.py"))
    requirements_b64 = base64encode(file("${path.module}/app/requirements.txt"))
    stream_name      = aws_kinesis_stream.orders.name
    region           = var.region
    app_port         = var.app_port
  })

  tags = { Name = var.ec2_name }

  # pip 설치를 위해 NAT 경로가 먼저 준비되어야 함
  depends_on = [
    aws_route.priv_default,
    aws_nat_gateway.ngw,
    aws_iam_role_policy.ec2,
    aws_iam_role_policy_attachment.ec2_ssm,
  ]
}
