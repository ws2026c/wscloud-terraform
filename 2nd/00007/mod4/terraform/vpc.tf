resource "aws_vpc" "o11y_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "o11y-vpc"
  }
}

resource "aws_subnet" "pub_a" {
  vpc_id                  = aws_vpc.o11y_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true

  tags = {
    Name                                = "o11y-pub-a"
    "kubernetes.io/role/elb"            = "1"
    "kubernetes.io/cluster/o11y-cluster" = "shared"
  }
}

resource "aws_subnet" "pub_c" {
  vpc_id                  = aws_vpc.o11y_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true

  tags = {
    Name                                = "o11y-pub-c"
    "kubernetes.io/role/elb"            = "1"
    "kubernetes.io/cluster/o11y-cluster" = "shared"
  }
}

resource "aws_subnet" "priv_a" {
  vpc_id            = aws_vpc.o11y_vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name                                = "o11y-priv-a"
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/o11y-cluster" = "shared"
  }
}

resource "aws_subnet" "priv_c" {
  vpc_id            = aws_vpc.o11y_vpc.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = "ap-northeast-1c"

  tags = {
    Name                                = "o11y-priv-c"
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/o11y-cluster" = "shared"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.o11y_vpc.id

  tags = {
    Name = "o11y-igw"
  }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.pub_a.id

  tags = {
    Name = "o11y-nat"
  }
}

resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.o11y_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "o11y-pub-rt"
  }
}

resource "aws_route_table" "priv_rt" {
  vpc_id = aws_vpc.o11y_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "o11y-priv-rt"
  }
}

resource "aws_route_table_association" "pub_a_assoc" {
  subnet_id      = aws_subnet.pub_a.id
  route_table_id = aws_route_table.pub_rt.id
}

resource "aws_route_table_association" "pub_c_assoc" {
  subnet_id      = aws_subnet.pub_c.id
  route_table_id = aws_route_table.pub_rt.id
}

resource "aws_route_table_association" "priv_a_assoc" {
  subnet_id      = aws_subnet.priv_a.id
  route_table_id = aws_route_table.priv_rt.id
}

resource "aws_route_table_association" "priv_c_assoc" {
  subnet_id      = aws_subnet.priv_c.id
  route_table_id = aws_route_table.priv_rt.id
}
