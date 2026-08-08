resource "aws_vpc" "main" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "wskorea26-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "book-igw"
  }
}

resource "aws_subnet" "pub_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.1.0/24"
  availability_zone       = "${var.region}c"
  map_public_ip_on_launch = true

  tags = {
    Name = "wskorea26-pub-subnet-c"
  }
}

resource "aws_subnet" "pub_d" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.2.0/24"
  availability_zone       = "${var.region}d"
  map_public_ip_on_launch = true

  tags = {
    Name = "wskorea26-pub-subnet-d"
  }
}

resource "aws_eip" "eip_c" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_eip" "eip_d" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "ngw_c" {
  allocation_id = aws_eip.eip_c.id
  subnet_id     = aws_subnet.pub_c.id

  tags = {
    Name = "book-ngw-c"
  }
}

resource "aws_nat_gateway" "ngw_d" {
  allocation_id = aws_eip.eip_d.id
  subnet_id     = aws_subnet.pub_d.id

  tags = {
    Name = "book-ngw-d"
  }
}


resource "aws_subnet" "priv_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.201.0/24"
  availability_zone = "${var.region}c"

  tags = {
    Name = "wskorea26-priv-subnet-c"
  }
}

resource "aws_subnet" "priv_d" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.202.0/24"
  availability_zone = "${var.region}d"

  tags = {
    Name = "wskorea26-priv-subnet-d"
  }
}

resource "aws_route_table" "public_rtb" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "wskorea26-public-rtb"
  }
}

resource "aws_route_table" "private_rtb_c" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw_c.id
  }

  tags = {
    Name = "wskorea26-private-rtb-c"
  }
}

resource "aws_route_table" "private_rtb_d" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw_d.id
  }

  tags = {
    Name = "wskorea26-private-rtb-d"
  }
}

resource "aws_route_table_association" "pub_c" {
  subnet_id      = aws_subnet.pub_c.id
  route_table_id = aws_route_table.public_rtb.id
}

resource "aws_route_table_association" "pub_d" {
  subnet_id      = aws_subnet.pub_d.id
  route_table_id = aws_route_table.public_rtb.id
}

resource "aws_route_table_association" "priv_c" {
  subnet_id      = aws_subnet.priv_c.id
  route_table_id = aws_route_table.private_rtb_c.id
}

resource "aws_route_table_association" "priv_d" {
  subnet_id      = aws_subnet.priv_d.id
  route_table_id = aws_route_table.private_rtb_d.id
}

resource "aws_security_group" "environment_sg" {
  name        = "wskorea26-vpc-environment-sg"
  description = "Security group for evaluation environment"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wskorea26-vpc-environment-sg"
  }
}