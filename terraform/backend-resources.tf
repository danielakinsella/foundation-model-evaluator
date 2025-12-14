# Backend Infrastructure Resources
# These resources are created by the GitHub Actions workflow bootstrap step
# and then managed by Terraform after initial creation

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# S3 Bucket for Terraform State (created by bootstrap, managed by TF after)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.application_name_short}-terraform-state-${local.account_id}"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.application_name_short}-terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB Table for State Locking (created by bootstrap, managed by TF after)
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.application_name_short}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "${var.application_name_short}-terraform-locks"
  }
}

# IAM Policy for GitHub Actions Deploy Role
resource "aws_iam_policy" "github_deploy" {
  name        = "${var.application_name_short}-github-deploy-policy"
  description = "Policy for GitHub Actions to deploy Foundation Model Evaluator infrastructure"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Terraform State Management (S3)
      {
        Sid    = "TerraformStateS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy",
          "s3:PutBucketVersioning",
          "s3:PutBucketAcl",
          "s3:PutBucketPolicy",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock"
        ]
        Resource = [
          "arn:aws:s3:::${var.application_name_short}-terraform-state-${local.account_id}",
          "arn:aws:s3:::${var.application_name_short}-terraform-state-${local.account_id}/*"
        ]
      },

      # Terraform State Locking (DynamoDB)
      {
        Sid    = "TerraformStateLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
          "dynamodb:CreateTable",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:ListTagsOfResource",
          "dynamodb:TagResource"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/${var.application_name_short}-terraform-locks"
      },

      # AppConfig
      {
        Sid    = "AppConfig"
        Effect = "Allow"
        Action = [
          "appconfig:*"
        ]
        Resource = "*"
      },

      # Lambda
      {
        Sid    = "Lambda"
        Effect = "Allow"
        Action = [
          "lambda:*"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${var.application_name_short}-*"
      },

      # IAM Roles and Policies
      {
        Sid    = "IAMRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListRoleTags",
          "iam:ListInstanceProfilesForRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies"
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.application_name_short}-*"
      },
      {
        Sid    = "IAMPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:TagPolicy",
          "iam:ListPolicyTags"
        ]
        Resource = "arn:aws:iam::${local.account_id}:policy/${var.application_name_short}-*"
      },

      # API Gateway
      {
        Sid    = "APIGateway"
        Effect = "Allow"
        Action = [
          "apigateway:*"
        ]
        Resource = [
          "arn:aws:apigateway:${var.aws_region}::/restapis",
          "arn:aws:apigateway:${var.aws_region}::/restapis/*",
          "arn:aws:apigateway:${var.aws_region}::/tags/*"
        ]
      },

      # CloudWatch Logs
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource",
          "logs:ListTagsForResource",
          "logs:TagLogGroup",
          "logs:UntagLogGroup",
          "logs:ListTagsLogGroup"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/apigateway/${var.application_name_short}-*",
          "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/stepfunctions/${var.application_name_short}*",
          "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.application_name_short}-*"
        ]
      },
      {
        Sid    = "CloudWatchLogsDescribe"
        Effect = "Allow"
        Action = ["logs:DescribeLogGroups"]
        Resource = "*"
      },

      # Step Functions
      {
        Sid    = "StepFunctions"
        Effect = "Allow"
        Action = [
          "states:CreateStateMachine",
          "states:DeleteStateMachine",
          "states:DescribeStateMachine",
          "states:UpdateStateMachine",
          "states:TagResource",
          "states:UntagResource",
          "states:ListTagsForResource"
        ]
        Resource = "arn:aws:states:${var.aws_region}:${local.account_id}:stateMachine:${var.application_name_short}-*"
      },

      # STS for getting caller identity
      {
        Sid      = "STS"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.application_name_short}-github-deploy-policy"
  }
}

# Output the policy ARN
output "github_deploy_policy_arn" {
  description = "ARN of the IAM policy for GitHub Actions deployment"
  value       = aws_iam_policy.github_deploy.arn
}
