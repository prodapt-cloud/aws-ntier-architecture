resource "aws_route_table" "route-table" {
  vpc_id = var.vpc-id

  route {
    cidr_block           = var.cidr-block
    nat_gateway_id       = var.nat-gateway-id
    network_interface_id = var.network-interface-id
    instance_id          = var.instance-id
    gateway_id           = var.gateway-id
  }

  tags = {
    Name = "route-table-${var.project}"
  }
}

resource "aws_route_table_association" "table-association" {
  count          = length(var.subnets)
  subnet_id      = element(var.subnets, count.index)
  route_table_id = aws_route_table.route-table.id
}

