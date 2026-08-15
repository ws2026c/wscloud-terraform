data "aws_prefix_list" "vpclattice" {
  name = "com.amazonaws.ap-northeast-1.vpc-lattice"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_security_group" "client_sg" {
  name        = "skills-lattice-client-sg"
  description = "Allow SSH 22 and HTTP 80 from anywhere"
  vpc_id      = aws_vpc.client_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "skills-lattice-client-sg"
  }
}

resource "aws_instance" "client_ec2" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.client_pub_sub_1.id
  vpc_security_group_ids = [aws_security_group.client_sg.id]

  tags = {
    Name = "skills-lattice-client-ec2"
  }
}

resource "aws_iam_role" "ssm_role" {
  name = "skills-lattice-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "skills-lattice-ssm-profile"
  role = aws_iam_role.ssm_role.name
}

resource "aws_security_group" "service_sg" {
  name        = "skills-lattice-service-sg"
  description = "Allow TCP 8080 ONLY from VPC Lattice Managed Prefix List"
  vpc_id      = aws_vpc.service_vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    prefix_list_ids = [data.aws_prefix_list.vpclattice.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "skills-lattice-service-sg"
  }
}

resource "aws_instance" "service_ec2" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.service_priv_sub_1.id
  vpc_security_group_ids = [aws_security_group.service_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name

  tags = {
    Name = "skills-lattice-service-ec2"
  }
}
