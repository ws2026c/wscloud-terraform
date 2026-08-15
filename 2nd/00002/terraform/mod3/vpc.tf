###############################################################################
# vpc.tf
#   event-vpc      172.16.0.0/16
#   event-pub-a    172.16.0.0/24   event-pub-rtb -> event-igw
#   event-pub-b    172.16.1.0/24   event-pub-rtb -> event-igw
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
  map_public_ip_on_launch = true

  tags = { Name = each.key }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "event-igw" }
}

resource "aws_route_table" "pub" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "event-pub-rtb" }
}

resource "aws_route" "pub_default" {
  route_table_id         = aws_route_table.pub.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "pub" {
  for_each = var.subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.pub.id
}
