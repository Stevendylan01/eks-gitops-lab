locals {
  vpc_cidr = "10.40.0.0/16"
  zones = {
    for index, zone in var.availability_zones : zone => {
      public_cidr  = cidrsubnet(local.vpc_cidr, 8, index)
      private_cidr = cidrsubnet(local.vpc_cidr, 8, index + 10)
    }
  }
}

resource "aws_vpc" "lab" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = local.name }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = local.name }
}

resource "aws_subnet" "public" {
  for_each = local.zones

  vpc_id            = aws_vpc.lab.id
  availability_zone = each.key
  cidr_block        = each.value.public_cidr

  tags = {
    Name                     = "${local.name}-public-${each.key}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  for_each = local.zones

  vpc_id            = aws_vpc.lab.id
  availability_zone = each.key
  cidr_block        = each.value.private_cidr

  tags = {
    Name                              = "${local.name}-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  for_each = local.zones

  domain = "vpc"
  tags   = { Name = "${local.name}-nat-${each.key}" }
}

resource "aws_nat_gateway" "lab" {
  for_each = aws_subnet.public

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id

  tags       = { Name = "${local.name}-${each.key}" }
  depends_on = [aws_route_table_association.public]
}

resource "aws_route_table" "private" {
  for_each = local.zones

  vpc_id = aws_vpc.lab.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.lab[each.key].id
  }

  tags = { Name = "${local.name}-private-${each.key}" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
