resource "aws_iam_role" "codebuild" {
  name = "voting-codebuild"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codebuild" {
  role = "${aws_iam_role.codebuild.name}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Resource": [
        "*"
      ],
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
          "ecr:*",
          "cloudtrail:LookupEvents"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_codebuild_project" "voting" {
  name          = "voting-app"
  description   = "voting app codebuild project"
  build_timeout = "5"
  service_role  = "${aws_iam_role.codebuild.arn}"

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/docker:18.09.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = "true"

    # environment_variable {
    #   "name"  = "AWS_DEFAULT_REGION"
    #   "value" = "${var.region}"
    # }

    environment_variable {
      "name"  = "AWS_ACCOUNT_ID"
      "value" = "${var.accountId}"
    }
  }

  source {
    type = "CODEPIPELINE"
  }
}

resource "aws_codebuild_project" "voting_deployer" {
  name          = "voting-deployer"
  description   = "voting deployer codebuild project"
  build_timeout = "10"
  service_role  = "${aws_iam_role.codebuild.arn}"

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "${var.accountId}.dkr.ecr.${var.region}.amazonaws.com/votingapp_deployer:latest"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "SERVICE_ROLE"
    privileged_mode             = "true"

    environment_variable {
      "name"  = "AWS_ACCOUNT_ID"
      "value" = "${var.accountId}"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec_deploy.yml"
  }
}

# ECR Repositories
resource "aws_ecr_repository" "vote" {
  name = "votingapp_vote"
}

resource "aws_ecr_repository" "worker" {
  name = "votingapp_worker"
}

resource "aws_ecr_repository" "result" {
  name = "votingapp_result"
}
