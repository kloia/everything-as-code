data "aws_caller_identity" "current" {}

module "vpc" {
  source               = "./modules/vpc"
  vpc_cidr             = "${var.vpc_cidr}"
  private_subnet_cidrs = "${var.private_subnet_cidrs}"
  public_subnet_cidrs  = "${var.public_subnet_cidrs}"
  project_name         = "${var.project_name}"
  eks_worker_node_key  = "${var.eks_worker_node_key}"
}

module "eks" {
  source                        = "./modules/eks"
  project_name                  = "${var.project_name}"
  vpc_id                        = "${module.vpc.vpc_id}"
  security_group_id             = "${module.vpc.control_panel_security_group_id}"
  region                        = "${var.region}"
  account_id                    = "${data.aws_caller_identity.current.account_id}"
  eks_worker_node_ami           = "${var.eks_worker_node_ami}"
  eks_worker_node_instance_type = "${var.eks_worker_node_instance_type}"
  worker_node_security_group_id = "${module.vpc.worker_node_security_group_id}"
  eks_worker_node_key           = "${var.eks_worker_node_key}"
  eks_desired_node_count        = "${var.eks_desired_node_count}"
  eks_min_node_count            = "${var.eks_min_node_count}"
  eks_max_node_count            = "${var.eks_max_node_count}"
  private_subnet_ids            = "${module.vpc.private_subnet_ids}"
}

module "codebuild" {
  source            = "./modules/codebuild"
  vpc_id            = "${module.vpc.vpc_id}"
  security_group_id = "${module.vpc.control_panel_security_group_id}"
  subnet_ids        = "${module.vpc.private_subnet_ids}"
  region            = "${var.region}"
  accountId         = "${var.accountId}"
}

module "pipeline" {
  source       = "./modules/pipeline"
  github_token = "${var.github_token}"
  region       = "${var.region}"
  project_name = "${var.project_name}"
}
