resource "aws_vpc" "client_vpc" {
  cidr_block           = "10.61.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "skills-lattice-client-vpc"
  }
}

resource "aws_internet_gateway" "client_igw" {
  vpc_id = aws_vpc.client_vpc.id

  tags = {
    Name = "skills-lattice-client-igw"
  }
}

resource "aws_subnet" "client_pub_sub_1" {
  vpc_id                  = aws_vpc.client_vpc.id
  cidr_block              = "10.61.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "skills-lattice-client-pub-sub-1"
  }
}

resource "aws_subnet" "client_pub_sub_2" {
  vpc_id                  = aws_vpc.client_vpc.id
  cidr_block              = "10.61.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true

  tags = {
    Name = "skills-lattice-client-pub-sub-2"
  }
}

resource "aws_route_table" "client_pub_rt" {
  vpc_id = aws_vpc.client_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.client_igw.id
  }

  tags = {
    Name = "skills-lattice-client-pub-rt"
  }
}

resource "aws_route_table_association" "client_pub_assoc_1" {
  subnet_id      = aws_subnet.client_pub_sub_1.id
  route_table_id = aws_route_table.client_pub_rt.id
}

resource "aws_route_table_association" "client_pub_assoc_2" {
  subnet_id      = aws_subnet.client_pub_sub_2.id
  route_table_id = aws_route_table.client_pub_rt.id
}

resource "aws_vpc" "service_vpc" {
  cidr_block           = "10.62.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "skills-lattice-service-vpc"
  }
}

resource "aws_internet_gateway" "service_igw" {
  vpc_id = aws_vpc.service_vpc.id

  tags = {
    Name = "skills-lattice-service-igw"
  }
}

resource "aws_subnet" "service_pub_sub_1" {
  vpc_id                  = aws_vpc.service_vpc.id
  cidr_block              = "10.62.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "skills-lattice-service-pub-sub-1"
  }
}

resource "aws_subnet" "service_pub_sub_2" {
  vpc_id                  = aws_vpc.service_vpc.id
  cidr_block              = "10.62.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true

  tags = {
    Name = "skills-lattice-service-pub-sub-2"
  }
}

resource "aws_subnet" "service_priv_sub_1" {
  vpc_id            = aws_vpc.service_vpc.id
  cidr_block        = "10.62.10.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "skills-lattice-service-priv-sub-1"
  }
}

resource "aws_subnet" "service_priv_sub_2" {
  vpc_id            = aws_vpc.service_vpc.id
  cidr_block        = "10.62.11.0/24"
  availability_zone = "ap-northeast-1c"

  tags = {
    Name = "skills-lattice-service-priv-sub-2"
  }
}

resource "aws_route_table" "service_pub_rt" {
  vpc_id = aws_vpc.service_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.service_igw.id
  }

  tags = {
    Name = "skills-lattice-service-pub-rt"
  }
}

resource "aws_route_table_association" "service_pub_assoc_1" {
  subnet_id      = aws_subnet.service_pub_sub_1.id
  route_table_id = aws_route_table.service_pub_rt.id
}

resource "aws_route_table_association" "service_pub_assoc_2" {
  subnet_id      = aws_subnet.service_pub_sub_2.id
  route_table_id = aws_route_table.service_pub_rt.id
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "skills-lattice-nat-eip"
  }
}

resource "aws_nat_gateway" "service_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.service_pub_sub_1.id

  tags = {
    Name = "skills-lattice-nat-gw"
  }

  depends_on = [aws_internet_gateway.service_igw]
}

resource "aws_route_table" "service_priv_rt" {
  vpc_id = aws_vpc.service_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.service_nat.id
  }

  tags = {
    Name = "skills-lattice-service-priv-rt"
  }
}

resource "aws_route_table_association" "service_priv_assoc_1" {
  subnet_id      = aws_subnet.service_priv_sub_1.id
  route_table_id = aws_route_table.service_priv_rt.id
}

resource "aws_route_table_association" "service_priv_assoc_2" {
  subnet_id      = aws_subnet.service_priv_sub_2.id
  route_table_id = aws_route_table.service_priv_rt.id
}
