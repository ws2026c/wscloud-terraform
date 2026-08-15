###############################################################################
# security.tf
#   MSK SG : Producer EC2 / Lambda ENI 로부터 9098(SASL_IAM) 허용
#            + Lambda MSK 이벤트 소스는 클러스터 SG 를 그대로 사용하므로
#              자기 자신을 참조하는 인바운드 규칙이 반드시 필요하다.
###############################################################################

resource "aws_security_group" "msk" {
  name        = "wsc2026-msk-cluster-sg"
  description = "MSK broker access (IAM SASL 9098)"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "wsc2026-msk-cluster-sg" }
}

resource "aws_security_group" "ec2" {
  name        = "wsc2026-msk-producer-sg"
  description = "Producer EC2"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "wsc2026-msk-producer-sg" }
}

resource "aws_security_group" "lambda" {
  name        = "wsc2026-msk-lambda-sg"
  description = "Lambda VPC ENI"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "wsc2026-msk-lambda-sg" }
}

# --- MSK inbound -------------------------------------------------------------
# 프로듀서는 9092(PLAINTEXT) / 9094(TLS) / 9098(SASL_IAM) 중 하나를 쓴다.
# 어느 방식이든 붙을 수 있도록 세 포트를 모두 연다.
resource "aws_vpc_security_group_ingress_rule" "msk_from_ec2" {
  for_each = toset(["9092", "9094", "9098"])

  security_group_id            = aws_security_group.msk.id
  description                  = "kafka ${each.value} from producer"
  referenced_security_group_id = aws_security_group.ec2.id
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "msk_from_lambda" {
  security_group_id            = aws_security_group.msk.id
  description                  = "SASL_SSL(IAM) from lambda vpc eni"
  referenced_security_group_id = aws_security_group.lambda.id
  from_port                    = 9098
  to_port                      = 9098
  ip_protocol                  = "tcp"
}

# Lambda MSK 이벤트 소스가 만드는 ENI 는 클러스터 SG 를 사용한다 -> self 참조 필수
resource "aws_vpc_security_group_ingress_rule" "msk_self" {
  security_group_id            = aws_security_group.msk.id
  description                  = "self reference for Lambda MSK event source ENI"
  referenced_security_group_id = aws_security_group.msk.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "msk_all" {
  security_group_id = aws_security_group.msk.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- EC2 / Lambda outbound ---------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  description       = "outbound all (NAT, MSK, AWS API)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "lambda_all" {
  security_group_id = aws_security_group.lambda.id
  description       = "outbound all"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
