variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "Production"
}

variable "application_name" {
  description = "Name of the application"
  type        = string
  default     = "FoundationModelEvaluator"
}

variable "application_name_short" {
  description = "Short name for resource naming (kebab-case)"
  type        = string
  default     = "fm-evaluator"
}

variable "configuration_profile_name" {
  description = "Name of the configuration profile"
  type        = string
  default     = "ModelSelectionStrategy"
}

variable "deployment_strategy_name" {
  description = "Name of the deployment strategy"
  type        = string
  default     = "LinearDeployment"
}

variable "deployment_duration_in_minutes" {
  description = "Total duration of deployment in minutes"
  type        = number
  default     = 10
}

variable "growth_factor" {
  description = "Percentage of targets to receive deployment during each interval"
  type        = number
  default     = 20
}

variable "final_bake_time_in_minutes" {
  description = "Time to wait after deployment before considering it complete"
  type        = number
  default     = 5
}

# Step Functions Lambda ARNs
# Note: These can be left empty if not using Step Functions workflow
# When using Step Functions, provide the ARNs of deployed Lambda functions
variable "primary_model_lambda_arn" {
  description = "ARN of the Lambda function for primary model invocation (use model_abstraction_lambda_arn output)"
  type        = string
  default     = ""

  validation {
    condition     = var.primary_model_lambda_arn == "" || can(regex("^arn:aws:lambda:", var.primary_model_lambda_arn))
    error_message = "primary_model_lambda_arn must be empty or a valid Lambda ARN."
  }
}

variable "fallback_model_lambda_arn" {
  description = "ARN of the Lambda function for fallback model invocation"
  type        = string
  default     = ""

  validation {
    condition     = var.fallback_model_lambda_arn == "" || can(regex("^arn:aws:lambda:", var.fallback_model_lambda_arn))
    error_message = "fallback_model_lambda_arn must be empty or a valid Lambda ARN."
  }
}

variable "degradation_lambda_arn" {
  description = "ARN of the Lambda function for graceful degradation"
  type        = string
  default     = ""

  validation {
    condition     = var.degradation_lambda_arn == "" || can(regex("^arn:aws:lambda:", var.degradation_lambda_arn))
    error_message = "degradation_lambda_arn must be empty or a valid Lambda ARN."
  }
}
