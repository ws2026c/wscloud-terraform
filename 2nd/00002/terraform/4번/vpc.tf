###############################################################################
# vpc.tf
#   msk-pub-a   192.168.0.0/24    msk-pub-rtb     -> msk-igw
#   msk-pub-d   192.168.1.0/24    msk-pub-rtb     -> msk-igw
#   msk-priv-a  192.168.10.0/24   msk-priv-a-rtb  -> msk-ngw
#   msk-priv-d  192.168.11.0/24   msk-priv-d-rtb  -> msk-ngw
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

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "msk-igw" }
}

resource "aws_eip" "ngw" {
  domain = "vpc"

  tags = { Name = "msk-ngw-eip" }
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.ngw.id
  subnet_id     = aws_subnet.this["msk-pub-a"].id

  tags = { Name = "msk-ngw" }

  depends_on = [aws_internet_gateway.igw]
}

# Public
resource "aws_route_table" "pub" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "msk-pub-rtb" }
}

resource "aws_route" "pub_default" {
  route_table_id         = aws_route_table.pub.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "pub" {
  for_each = toset(local.public_subnets)

  subnet_id      = aws_subnet.this[each.value].id
  route_table_id = aws_route_table.pub.id
}

# Private (AZ 별 라우팅 테이블)
resource "aws_route_table" "priv" {
  for_each = toset(local.private_subnets)

  vpc_id = aws_vpc.main.id

  tags = { Name = "${each.value}-rtb" }
}

resource "aws_route" "priv_default" {
  for_each = toset(local.private_subnets)

  route_table_id         = aws_route_table.priv[each.value].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ngw.id
}

resource "aws_route_table_association" "priv" {
  for_each = toset(local.private_subnets)

  subnet_id      = aws_subnet.this[each.value].id
  route_table_id = aws_route_table.priv[each.value].id
}
