###############################################################################
# security.tf
#   ALB SG  : 인터넷 -> 80
#   EC2 SG  : ALB SG 로부터만 5000 (외부 직접 접근 불가, 관리 접속은 SSM)
###############################################################################

resource "aws_security_group" "alb" {
  name        = "wsc2026-analytics-alb-sg"
  description = "ALB inbound HTTP 80"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "wsc2026-analytics-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ec2" {
  security_group_id            = aws_security_group.alb.id
  description                  = "to app port"
  referenced_security_group_id = aws_security_group.ec2.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "ec2" {
  name        = "wsc2026-analytics-ec2-sg"
  description = "App instance - only from ALB"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "wsc2026-analytics-ec2-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "ec2_from_alb" {
  security_group_id            = aws_security_group.ec2.id
  description                  = "app port from ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# 패키지 설치(NAT) 및 SSM/Kinesis 엔드포인트 통신용
resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  description       = "outbound all"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
