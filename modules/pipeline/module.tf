resource "aws_s3_bucket" "voting_artifact_store" {
  bucket        = "voting-pipeline"
  acl           = "private"
  force_destroy = true
}

resource "aws_iam_role" "codepipeline" {
  name = "voting-codepipeline"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = "${aws_iam_role.codepipeline.id}"

  policy = <<EOF
{
    "Statement": [
        {
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:GetBucketVersioning"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": [
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::codepipeline*",
                "arn:aws:s3:::elasticbeanstalk*"
            ],
            "Effect": "Allow"
        },
        {
            "Action": [
                "s3:*",
                "iam:PassRole"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": [
                "lambda:InvokeFunction",
                "lambda:ListFunctions"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": [
                "codebuild:BatchGetBuilds",
                "codebuild:StartBuild"
            ],
            "Resource": "*",
            "Effect": "Allow"
        },
        {
            "Action": [
                "codedeploy:*"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ],
    "Version": "2012-10-17"
}
EOF
}

locals {
  webhook_secret = "super-secret-to-use-webhook"
}

resource "null_resource" "eks_endpoint" {
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

resource "aws_codepipeline" "voting_pipeline" {
  depends_on = ["null_resource.eks_endpoint"]

  name     = "voting-pipeline"
  role_arn = "${aws_iam_role.codepipeline.arn}"

  artifact_store {
    location = "${aws_s3_bucket.voting_artifact_store.bucket}"
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["code"]

      configuration = {
        Owner                = "kloia"
        Repo                 = "example-voting-app"
        Branch               = "master"
        PollForSourceChanges = "false"
        OAuthToken           = "${var.github_token}"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["code"]
      version          = "1"
      output_artifacts = ["codeBuild"]

      configuration = {
        ProjectName = "voting-app"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name             = "Deploy"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["code"]
      version          = "1"
      output_artifacts = ["manifest"]

      configuration = {
        ProjectName = "voting-deployer"
      }
    }
  }
}

resource "aws_codepipeline_webhook" "pipeline_webhook" {
  name            = "github-webhook"
  authentication  = "GITHUB_HMAC"
  target_action   = "Source"
  target_pipeline = "${aws_codepipeline.voting_pipeline.name}"

  authentication_configuration {
    secret_token = "${local.webhook_secret}"
  }

  filter {
    json_path    = "$.ref"
    match_equals = "refs/heads/{Branch}"
  }
}

provider "github" {
  token        = "${var.github_token}"
  organization = "kloia"
}

resource "github_repository_webhook" "github_webhook" {
  repository = "example-voting-app"

  name = "web"

  configuration {
    url          = "${aws_codepipeline_webhook.pipeline_webhook.url}"
    content_type = "json"
    insecure_ssl = true
    secret       = "${local.webhook_secret}"
  }

  events = ["push"]
}

output "webhook_url" {
  value = "${aws_codepipeline_webhook.pipeline_webhook.url}"
}
