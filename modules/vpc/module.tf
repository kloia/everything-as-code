data "aws_availability_zones" "available" {}

# VPC
resource "aws_vpc" "voting" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_hostnames = true

  tags = "${
    map(
     "Name", "${var.project_name}",
     "kubernetes.io/cluster/${var.project_name}", "shared",
    )
  }"
}

# Private Subnets
resource "aws_subnet" "voting_private_subnet" {
  count = 2

  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "${var.private_subnet_cidrs[count.index]}"
  vpc_id            = "${aws_vpc.voting.id}"

  tags = "${
    map(
     "Name", "${var.project_name} private - ${data.aws_availability_zones.available.names[count.index]}",
     "kubernetes.io/cluster/${var.project_name}", "shared",
     "Tier", "Private",
    )
  }"
}

# Public Subnets
resource "aws_subnet" "voting_public_subnet" {
  count = 2

  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "${var.public_subnet_cidrs[count.index]}"
  vpc_id            = "${aws_vpc.voting.id}"

  tags = "${
    map(
     "Name", "${var.project_name} public - ${data.aws_availability_zones.available.names[count.index]}",
     "kubernetes.io/cluster/${var.project_name}", "shared",
     "Tier", "Public",
    )
  }"
}

# Internet Gateway
resource "aws_internet_gateway" "voting" {
  vpc_id = "${aws_vpc.voting.id}"

  tags {
    Name = "${var.project_name}"
  }
}

# Elastic IP
resource "aws_eip" "nat_ip" {
  count = 2

  vpc = true
}

# NAT Gateway
resource "aws_nat_gateway" "voting" {
  count = 2

  allocation_id = "${element(aws_eip.nat_ip.*.id, count.index)}"
  subnet_id     = "${element(aws_subnet.voting_public_subnet.*.id, count.index)}"

  tags {
    Name = "${var.project_name} - ${count.index}"
  }
}

# Route Table Public
resource "aws_route_table" "voting_public" {
  vpc_id = "${aws_vpc.voting.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.voting.id}"
  }

  tags {
    Name = "${var.project_name}_public"
  }
}

# Route Table Association
resource "aws_route_table_association" "voting_public" {
  count = 2

  subnet_id      = "${element(aws_subnet.voting_public_subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.voting_public.id}"
}

# Route Table Private
resource "aws_route_table" "voting_private" {
  count = 2

  vpc_id = "${aws_vpc.voting.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${element(aws_nat_gateway.voting.*.id, count.index)}"
  }

  tags {
    Name = "${var.project_name}_private - ${count.index}"
  }
}

# Route Table Association
resource "aws_route_table_association" "voting_private" {
  count = 2

  subnet_id      = "${element(aws_subnet.voting_private_subnet.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.voting_private.*.id, count.index)}"
}

# # Bastion Host Security Group
# resource "aws_security_group" "bastion_host" {
#   name        = "${var.project_name} bastion host"
#   description = "Bastion host access"
#   vpc_id      = "${aws_vpc.voting.id}"
#
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#
#   tags {
#     Name = "${var.project_name} bastion host"
#   }
# }

# # TODO: Only allow inbound traffic from office
# resource "aws_security_group_rule" "bastion_host" {
#   cidr_blocks       = ["5.39.180.30/32"]
#   description       = "Allow workstation to communicate with the cluster API Server"
#   from_port         = 22
#   protocol          = "tcp"
#   security_group_id = "${aws_security_group.bastion_host.id}"
#   to_port           = 22
#   type              = "ingress"
# }
#
# # Bastion Host
# resource "aws_instance" "bastion_host" {
#   ami                         = "ami-047bb4163c506cd98"
#   instance_type               = "t2.micro"
#   subnet_id                   = "${aws_subnet.voting_public_subnet.0.id}"
#   associate_public_ip_address = true
#   key_name                    = "${var.eks_worker_node_key}"
#   vpc_security_group_ids      = ["${aws_security_group.bastion_host.id}"]
#   availability_zone           = "${data.aws_availability_zones.available.names[0]}"
#
#   tags {
#     Name = "${var.project_name} bastion host"
#   }
# }

# EKS Control Panel Security Group
resource "aws_security_group" "voting_control_panel" {
  name        = "${var.project_name} control panel"
  description = "Cluster communication with worker nodes"
  vpc_id      = "${aws_vpc.voting.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.project_name} control panel"
  }
}

# TODO: Only allow inbound traffic from office, it is open Worldwide for now
resource "aws_security_group_rule" "voting_control_panel" {
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow workstation to communicate with the cluster API Server"
  from_port         = 443
  protocol          = "tcp"
  security_group_id = "${aws_security_group.voting_control_panel.id}"
  to_port           = 443
  type              = "ingress"
}

# Worker Node Security Group
resource "aws_security_group" "voting_worker_node" {
  name        = "${var.project_name} worker node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.voting.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${
    map(
     "Name", "${var.project_name} worker node",
     "kubernetes.io/cluster/${var.project_name}", "owned",
    )
  }"
}

resource "aws_security_group_rule" "voting_worker_node_self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.voting_worker_node.id}"
  source_security_group_id = "${aws_security_group.voting_worker_node.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "voting_worker_node_cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.voting_worker_node.id}"
  source_security_group_id = "${aws_security_group.voting_control_panel.id}"
  to_port                  = 65535
  type                     = "ingress"
}

# Worker Node Access to EKS Master Cluster
resource "aws_security_group_rule" "voting_worker_node_https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.voting_control_panel.id}"
  source_security_group_id = "${aws_security_group.voting_worker_node.id}"
  to_port                  = 443
  type                     = "ingress"
}

# # Bastion Host access to Worker Node
# resource "aws_security_group_rule" "voting_worker_node_bastion" {
#   description              = "Allow bastion host to communicate with the worker nodes"
#   from_port                = 22
#   protocol                 = "tcp"
#   security_group_id        = "${aws_security_group.voting_worker_node.id}"
#   source_security_group_id = "${aws_security_group.bastion_host.id}"
#   to_port                  = 22
#   type                     = "ingress"
# }

# Outputs
output "vpc_id" {
  value = "${aws_vpc.voting.id}"
}

output "control_panel_security_group_id" {
  value = "${aws_security_group.voting_control_panel.id}"
}

output "worker_node_security_group_id" {
  value = "${aws_security_group.voting_worker_node.id}"
}

output "private_subnet_ids" {
  value = "${aws_subnet.voting_private_subnet.*.id}"
}
