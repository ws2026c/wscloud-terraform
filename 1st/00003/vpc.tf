resource "aws_vpc" "main" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "wsc2026-skills-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "wsc2026-skills-igw"
  }
}

resource "aws_subnet" "hub_sub_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "192.168.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "wsc2026-skills-hub-sub-a"
  }
}

resource "aws_subnet" "hub_sub_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "192.168.10.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "wsc2026-skills-hub-sub-b"
  }
}

resource "aws_subnet" "app_sub_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "wsc2026-skills-app-sub-a"
  }
}

resource "aws_subnet" "app_sub_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.20.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "wsc2026-skills-app-sub-b"
  }
}

resource "aws_eip" "nat_a" {
  domain = "vpc"
  tags   = { Name = "wsc2026-skills-nat-a-eip" }
}

resource "aws_eip" "nat_b" {
  domain = "vpc"
  tags   = { Name = "wsc2026-skills-nat-b-eip" }
}

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.hub_sub_a.id

  tags = {
    Name = "wsc2026-skills-nat-a"
  }
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.hub_sub_b.id

  tags = {
    Name = "wsc2026-skills-nat-b"
  }
}

resource "aws_route_table" "hub_rtb" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "wsc2026-skills-hub-rtb"
  }
}

resource "aws_route_table_association" "hub_a" {
  subnet_id      = aws_subnet.hub_sub_a.id
  route_table_id = aws_route_table.hub_rtb.id
}

resource "aws_route_table_association" "hub_b" {
  subnet_id      = aws_subnet.hub_sub_b.id
  route_table_id = aws_route_table.hub_rtb.id
}

resource "aws_route_table" "app_rtb_a" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }

  tags = {
    Name = "wsc2026-skills-app-rtb-a"
  }
}

resource "aws_route_table" "app_rtb_b" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }

  tags = {
    Name = "wsc2026-skills-app-rtb-b"
  }
}

resource "aws_route_table_association" "app_a" {
  subnet_id      = aws_subnet.app_sub_a.id
  route_table_id = aws_route_table.app_rtb_a.id
}

resource "aws_route_table_association" "app_b" {
  subnet_id      = aws_subnet.app_sub_b.id
  route_table_id = aws_route_table.app_rtb_b.id
}