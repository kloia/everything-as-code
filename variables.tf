variable "project_name" {
    description = "Project Name"
    default = "voting"
}

variable "region" {
    description = "Region that all code will be executed"
    default = "eu-west-1"
}

variable "accountId" {
    description = "AWS AccountId"
}

variable "vpc_cidr" {
    description = "CIDR for the VPC"
    default = "10.1.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets"
  type = "list"
  default = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets"
  type = "list"
  default = ["10.1.5.0/24", "10.1.6.0/24"]
}

variable "eks_worker_node_ami" {
    description = "AMI for the EKS worker nodes (current default is for Ireland)"
    default = "ami-098fb7e9b507904e7"
}

variable "eks_worker_node_instance_type" {
    description = "Instance type for the EKS worker nodes"
    default = "m5.large"
}

variable "eks_worker_node_key" {
    description = "Private key for the EKS worker nodes"
    default = "voting-app"
}

variable "eks_desired_node_count" {
  description = "Desired number of worker nodes for EKS"
  default = "1"
}

variable "eks_min_node_count" {
  description = "Min number of worker nodes for EKS"
  default = "1"
}

variable "eks_max_node_count" {
  description = "Max number of worker nodes for EKS"
  default = "3"
}

variable "github_token" {
  description = "Github OAuth Token"
}
