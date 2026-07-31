###############################################################################
# vpc.tf - 고가용성 고려 (2 AZ), Public 2 / Private 2
#
#   analytics-pub-a  10.20.0.0/24    analytics-pub-rtb     -> analytics-igw
#   analytics-pub-b  10.20.1.0/24    analytics-pub-rtb     -> analytics-igw
#   analytics-priv-a 10.20.100.0/24  analytics-priv-a-rtb  -> analytics-ngw
#   analytics-priv-b 10.20.101.0/24  analytics-priv-b-rtb  -> analytics-ngw
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.vpc_name }
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = var.azs[each.value.az_idx]
  map_public_ip_on_launch = each.value.public

  tags = { Name = each.key }
}

###############################################################################
# Internet Gateway / NAT Gateway
###############################################################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "analytics-igw" }
}

resource "aws_eip" "ngw" {
  domain = "vpc"

  tags = { Name = "analytics-ngw-eip" }
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.ngw.id
  subnet_id     = aws_subnet.this["analytics-pub-a"].id

  tags = { Name = "analytics-ngw" }

  depends_on = [aws_internet_gateway.igw]
}

###############################################################################
# Route Tables
###############################################################################

# Public (pub-a / pub-b 공용)
resource "aws_route_table" "pub" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "analytics-pub-rtb" }
}

resource "aws_route" "pub_default" {
  route_table_id         = aws_route_table.pub.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "pub" {
  for_each = toset(local.public_subnet_names)

  subnet_id      = aws_subnet.this[each.value].id
  route_table_id = aws_route_table.pub.id
}

# Private (AZ 별로 분리 - analytics-priv-a-rtb / analytics-priv-b-rtb)
resource "aws_route_table" "priv" {
  for_each = toset(local.private_subnet_names)

  vpc_id = aws_vpc.main.id

  tags = { Name = "${each.value}-rtb" }
}

resource "aws_route" "priv_default" {
  for_each = toset(local.private_subnet_names)

  route_table_id         = aws_route_table.priv[each.value].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ngw.id
}

resource "aws_route_table_association" "priv" {
  for_each = toset(local.private_subnet_names)

  subnet_id      = aws_subnet.this[each.value].id
  route_table_id = aws_route_table.priv[each.value].id
}
