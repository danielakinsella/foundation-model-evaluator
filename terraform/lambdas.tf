# Lambda Functions for Step Functions Circuit Breaker Pattern

# -----------------------------------------------------------------------------
# Primary Model Lambda
# -----------------------------------------------------------------------------

data "archive_file" "primary_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../dist/lambdas/primary-lambda"
  output_path = "${path.module}/../dist/lambdas/primary-lambda.zip"
}

resource "aws_lambda_function" "primary" {
  function_name = "${var.application_name_short}-primary-${lower(var.environment)}"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.primary_lambda.output_path
  source_code_hash = data.archive_file.primary_lambda.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT      = var.environment
      APPCONFIG_APP    = aws_appconfig_application.fm_evaluator.id
      APPCONFIG_ENV    = aws_appconfig_environment.main.environment_id
      APPCONFIG_CONFIG = aws_appconfig_configuration_profile.model_selection.configuration_profile_id
    }
  }

  tags = {
    Name = "${var.application_name_short}-primary-${lower(var.environment)}"
  }
}

# -----------------------------------------------------------------------------
# Fallback Model Lambda
# -----------------------------------------------------------------------------

data "archive_file" "fallback_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../dist/lambdas/fallback-lambda"
  output_path = "${path.module}/../dist/lambdas/fallback-lambda.zip"
}

resource "aws_lambda_function" "fallback" {
  function_name = "${var.application_name_short}-fallback-${lower(var.environment)}"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.fallback_lambda.output_path
  source_code_hash = data.archive_file.fallback_lambda.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = {
    Name = "${var.application_name_short}-fallback-${lower(var.environment)}"
  }
}

# -----------------------------------------------------------------------------
# Degradation Lambda
# -----------------------------------------------------------------------------

data "archive_file" "degradation_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../dist/lambdas/degradation-lambda"
  output_path = "${path.module}/../dist/lambdas/degradation-lambda.zip"
}

resource "aws_lambda_function" "degradation" {
  function_name = "${var.application_name_short}-degradation-${lower(var.environment)}"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.degradation_lambda.output_path
  source_code_hash = data.archive_file.degradation_lambda.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = {
    Name = "${var.application_name_short}-degradation-${lower(var.environment)}"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "primary_lambda_arn" {
  description = "ARN of the primary model Lambda function"
  value       = aws_lambda_function.primary.arn
}

output "fallback_lambda_arn" {
  description = "ARN of the fallback model Lambda function"
  value       = aws_lambda_function.fallback.arn
}

output "degradation_lambda_arn" {
  description = "ARN of the degradation Lambda function"
  value       = aws_lambda_function.degradation.arn
}
