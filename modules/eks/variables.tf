variable "project_name" {}
variable "security_group_id" {}
variable "vpc_id" {}
variable "region" {}
variable "account_id" {}
variable "eks_worker_node_ami" {}
variable "eks_worker_node_instance_type" {}
variable "worker_node_security_group_id" {}
variable "eks_worker_node_key" {}
variable "eks_desired_node_count" {}
variable "eks_min_node_count" {}
variable "eks_max_node_count" {}

variable "private_subnet_ids" {
  type = "list"
}
