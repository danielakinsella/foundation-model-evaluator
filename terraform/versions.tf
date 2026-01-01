terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.27"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # S3 Backend for remote state storage
  # Before using, run the bootstrap configuration in terraform/bootstrap/
  # Then update the bucket name below with your account ID
  backend "s3" {
    bucket         = "fm-evaluator-terraform-state-832787421689"
    key            = "fm-evaluator/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "fm-evaluator-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "FoundationModelEvaluator"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
