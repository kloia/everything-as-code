# Subnets
data "aws_subnet_ids" "subnets" {
  vpc_id = "${var.vpc_id}"
}

# EKS Role
resource "aws_iam_role" "voting_control_panel" {
  name = "${var.project_name}-control-panel"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

# EKS Role Associations
resource "aws_iam_role_policy_attachment" "voting_control_panel_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.voting_control_panel.name}"
}

resource "aws_iam_role_policy_attachment" "voting_control_panel_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.voting_control_panel.name}"
}

# EKS Cluster
resource "aws_eks_cluster" "voting" {
  name     = "${var.project_name}"
  role_arn = "${aws_iam_role.voting_control_panel.arn}"

  vpc_config {
    security_group_ids = ["${var.security_group_id}"]
    subnet_ids         = ["${data.aws_subnet_ids.subnets.ids}"]
  }

  depends_on = [
    "aws_iam_role_policy_attachment.voting_control_panel_AmazonEKSClusterPolicy",
    "aws_iam_role_policy_attachment.voting_control_panel_AmazonEKSServicePolicy",
  ]
}

# Worker Node Role
resource "aws_iam_role" "voting_worker_node" {
  name = "${var.project_name}-worker-node"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

# External DNS Role
resource "aws_iam_policy" "external_dns" {
  name        = "external_dns_policy"
  path        = "/"
  description = "Policy to use for external DNS of kubernetes services"

  policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Effect": "Allow",
     "Action": [
       "route53:ChangeResourceRecordSets"
     ],
     "Resource": [
       "arn:aws:route53:::hostedzone/*"
     ]
   },
   {
     "Effect": "Allow",
     "Action": [
       "route53:ListHostedZones",
       "route53:ListResourceRecordSets"
     ],
     "Resource": [
       "*"
     ]
   }
 ]
}
EOF
}

# Worker Node Role Associations
resource "aws_iam_role_policy_attachment" "voting_worker_node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.voting_worker_node.name}"
}

resource "aws_iam_role_policy_attachment" "voting_worker_node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.voting_worker_node.name}"
}

resource "aws_iam_role_policy_attachment" "voting_worker_node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.voting_worker_node.name}"
}

resource "aws_iam_role_policy_attachment" "voting_worker_node_external_dns" {
  depends_on = ["aws_iam_policy.external_dns"]

  policy_arn = "arn:aws:iam::${var.account_id}:policy/external_dns_policy"
  role       = "${aws_iam_role.voting_worker_node.name}"
}

# Worker Node Instance Profile
resource "aws_iam_instance_profile" "voting_worker_node" {
  name = "${var.project_name}-worker-node"
  role = "${aws_iam_role.voting_worker_node.name}"
}

resource "null_resource" "kube_config" {
  depends_on = ["aws_eks_cluster.voting"]

  triggers {
    build_number = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "rm -rf ~/.kube/kloia && aws eks --region ${var.region} update-kubeconfig --name ${var.project_name} --kubeconfig ~/.kube/kloia --profile kloia && export KUBECONFIG=~/.kube/kloia"
  }
}

data "aws_eks_cluster_auth" "voting" {
  name = "${var.project_name}"
}

provider "kubernetes" {
  host                   = "${aws_eks_cluster.voting.endpoint}"
  cluster_ca_certificate = "${base64decode(aws_eks_cluster.voting.certificate_authority.0.data)}"
  token                  = "${data.aws_eks_cluster_auth.voting.token}"
  load_config_file       = false
}

resource "null_resource" "eks_endpoint" {
  depends_on = ["aws_eks_cluster.voting"]

  triggers {
    build_number = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/../../scripts/wait_eks.sh"

    environment {
      REGION_NAME  = "${var.region}"
      PROFILE_NAME = "kloia"
      PROJECT_NAME = "${var.project_name}"
    }
  }
}

resource "kubernetes_config_map" "aws_auth" {
  depends_on = ["null_resource.kube_config", "null_resource.eks_endpoint"]

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data {
    mapRoles = <<YAML
- rolearn: ${aws_iam_role.voting_worker_node.arn}
  username: system:node:{{EC2PrivateDNSName}}
  groups:
    - system:bootstrappers
    - system:nodes
    - system:masters
YAML
  }
}

# Install Helm Tiller
resource "null_resource" "helm_init" {
  depends_on = ["kubernetes_config_map.aws_auth"]

  triggers {
    build_number = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/../../scripts/post-creation.sh"

    environment {
      REGION      = "${var.region}"
      CLUSTER     = "${var.project_name}"
      AWS_ACCOUNT = "${var.account_id}"
    }
  }
}

# Bootsrap Script for Worker Nodes
locals {
  worker_node_userdata = <<USERDATA
#!/bin/bash

set -o xtrace
/etc/eks/bootstrap.sh ${var.project_name}
USERDATA
}

# Launch Configuration
resource "aws_launch_configuration" "voting_worker_node" {
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.voting_worker_node.name}"
  image_id                    = "${var.eks_worker_node_ami}"
  instance_type               = "${var.eks_worker_node_instance_type}"
  name_prefix                 = "${var.project_name}-worker-node"
  security_groups             = ["${var.worker_node_security_group_id}"]
  user_data_base64            = "${base64encode(local.worker_node_userdata)}"
  key_name                    = "${var.eks_worker_node_key}"

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "voting" {
  depends_on = ["aws_eks_cluster.voting"]

  # desired_capacity     = "${var.eks_desired_node_count}"
  launch_configuration = "${aws_launch_configuration.voting_worker_node.id}"
  max_size             = "${var.eks_max_node_count}"
  min_size             = "${var.eks_min_node_count}"
  name                 = "${var.project_name}"
  vpc_zone_identifier  = ["${var.private_subnet_ids}"]

  tag {
    key                 = "Name"
    value               = "${var.project_name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.project_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "auto-discovery"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.project_name}"
    value               = "auto-discovery"
    propagate_at_launch = true
  }
}

# EFS
resource "aws_efs_file_system" "voting" {
  creation_token = "${var.project_name}"

  tags {
    Name = "${var.project_name}"
  }
}

# EFS Mount Targets
resource "aws_efs_mount_target" "voting" {
  count = 2

  file_system_id = "${aws_efs_file_system.voting.id}"
  subnet_id      = "${element(var.private_subnet_ids, count.index)}"
}

# Cluster AutoScaler Role
resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "cluster_autoscaler_policy"
  path        = "/"
  description = "Policy to use for autoscaling of EKS worker nodes"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
              "autoscaling:DescribeAutoScalingGroups",
              "autoscaling:DescribeAutoScalingInstances",
              "autoscaling:SetDesiredCapacity",
              "autoscaling:DescribeLaunchConfigurations",
              "autoscaling:DescribeTags",
              "autoscaling:TerminateInstanceInAutoScalingGroup"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_policy_attachment" "auto_scaling_attachment" {
  name       = "auto-scaling-attachment"
  roles      = ["${aws_iam_role.voting_worker_node.name}"]
  policy_arn = "${aws_iam_policy.cluster_autoscaler.arn}"
}
