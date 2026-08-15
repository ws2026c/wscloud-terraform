###############################################################################
# ec2.tf - 보안 정책 모니터링 대상 EC2
#   채점 3-0 : tag:Name = wsc2026-event-ec2
#   채점 3-4 : SG Inbound Count 가 0 이어야 하므로 인바운드 규칙을 두지 않는다.
###############################################################################

resource "aws_security_group" "ec2" {
  name        = var.sg_name
  description = "wsc2026 event ec2 - no inbound (minimum)"
  vpc_id      = aws_vpc.main.id

  tags = { Name = var.sg_name }

  # 인바운드 규칙이 자동 복구로 지워지는 것이 정상 동작이므로
  # Terraform 이 되돌리지 않도록 rule 변경은 무시한다.
  lifecycle {
    ignore_changes = [ingress]
  }
}

# 아웃바운드만 허용 (인바운드 규칙 없음 = IpPermissions length 0)
resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  description       = "outbound all"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

###############################################################################
# EC2 IAM Role
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

# Instance Profile 이름 = Role 이름 (role-remediation 이 Name 으로 원복)
resource "aws_iam_instance_profile" "ec2" {
  name = var.ec2_role_name
  role = aws_iam_role.ec2.name
}

###############################################################################
# EC2 Instance
###############################################################################

resource "aws_instance" "monitored" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.this[var.ec2_subnet_name].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  associate_public_ip_address = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = var.ec2_name }

  # 자동 복구 대상 속성들 - Lambda 가 바꾼 상태를 Terraform 이 되돌리지 않도록 무시
  lifecycle {
    ignore_changes = [
      instance_type,
      iam_instance_profile,
      ami,
    ]
  }
}
