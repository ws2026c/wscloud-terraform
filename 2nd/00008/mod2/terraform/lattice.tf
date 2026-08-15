resource "aws_vpclattice_service_network" "sn" {
  name      = "skills-lattice-sn"
  auth_type = "NONE"

  tags = {
    Name = "skills-lattice-sn"
  }
}

resource "aws_security_group" "sn_assoc_sg" {
  name        = "skills-lattice-sn-assoc-sg"
  description = "Allow TCP 80 from Client VPC CIDR"
  vpc_id      = aws_vpc.client_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.61.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "skills-lattice-sn-assoc-sg"
  }
}

resource "aws_vpclattice_service_network_vpc_association" "client_vpc_assoc" {
  vpc_identifier             = aws_vpc.client_vpc.id
  service_network_identifier = aws_vpclattice_service_network.sn.id
  security_group_ids         = [aws_security_group.sn_assoc_sg.id]

  tags = {
    Name = "skills-lattice-client-vpc-assoc"
  }
}

resource "aws_vpclattice_target_group" "order_tg" {
  name = "skills-lattice-order-tg"
  type = "INSTANCE"

  config {
    port             = 8080
    protocol         = "HTTP"
    vpc_identifier   = aws_vpc.service_vpc.id
    protocol_version = "HTTP1"

    health_check {
      enabled = true
      matcher {
        value = "200"
      }
      path             = "/health"
      protocol         = "HTTP"
      protocol_version = "HTTP1"
    }
  }

  tags = {
    Name = "skills-lattice-order-tg"
  }
}

resource "aws_vpclattice_target_group_attachment" "order_tg_attachment" {
  target_group_identifier = aws_vpclattice_target_group.order_tg.id
  target {
    id   = aws_instance.service_ec2.id
    port = 8080
  }
}

resource "aws_vpclattice_service" "order_service" {
  name      = "skills-lattice-order-service"
  auth_type = "NONE"

  tags = {
    Name = "skills-lattice-order-service"
  }
}

resource "aws_vpclattice_listener" "http_listener" {
  name               = "skills-lattice-http-listener"
  service_identifier = aws_vpclattice_service.order_service.id
  protocol           = "HTTP"
  port               = 80

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.order_tg.id
      }
    }
  }

  tags = {
    Name = "skills-lattice-http-listener"
  }
}

resource "aws_vpclattice_service_network_service_association" "service_sn_assoc" {
  service_identifier         = aws_vpclattice_service.order_service.id
  service_network_identifier = aws_vpclattice_service_network.sn.id
}
