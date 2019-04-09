variable "vpc_cidr" {}

variable "private_subnet_cidrs" {
  type = "list"
}

variable "public_subnet_cidrs" {
  type = "list"
}

variable "project_name" {}
variable "eks_worker_node_key" {}
