# State file to S3
terraform {
  backend "s3" {
    encrypt = true
    bucket = "kubernetes-presentation-state-store"
    key    = "voting-app"
    region = "eu-west-1"
    profile = "kloia"
  }
}
