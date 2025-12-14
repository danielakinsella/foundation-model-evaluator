# -----------------------------------------------------------------------------
# AppConfig Outputs
# -----------------------------------------------------------------------------

output "application_id" {
  description = "The AppConfig application ID"
  value       = aws_appconfig_application.fm_evaluator.id
}

output "application_arn" {
  description = "The AppConfig application ARN"
  value       = aws_appconfig_application.fm_evaluator.arn
}

output "environment_id" {
  description = "The AppConfig environment ID"
  value       = aws_appconfig_environment.main.environment_id
}

output "configuration_profile_id" {
  description = "The AppConfig configuration profile ID"
  value       = aws_appconfig_configuration_profile.model_selection.configuration_profile_id
}

output "deployment_strategy_id" {
  description = "The AppConfig deployment strategy ID"
  value       = aws_appconfig_deployment_strategy.linear.id
}

output "configuration_version" {
  description = "The current configuration version number"
  value       = aws_appconfig_hosted_configuration_version.model_selection.version_number
}

output "appconfig_retrieval_info" {
  description = "Information needed to retrieve the configuration at runtime"
  value = {
    application    = var.application_name
    environment    = var.environment
    configuration  = var.configuration_profile_name
    application_id = aws_appconfig_application.fm_evaluator.id
    environment_id = aws_appconfig_environment.main.environment_id
  }
}

# -----------------------------------------------------------------------------
# Step Functions Outputs
# -----------------------------------------------------------------------------

output "state_machine_arn" {
  description = "ARN of the Foundation Model Evaluator Step Functions state machine"
  value       = aws_sfn_state_machine.fm_evaluator.arn
}

output "state_machine_name" {
  description = "Name of the Foundation Model Evaluator Step Functions state machine"
  value       = aws_sfn_state_machine.fm_evaluator.name
}

output "step_functions_role_arn" {
  description = "ARN of the IAM role used by Step Functions"
  value       = aws_iam_role.step_functions.arn
}

# -----------------------------------------------------------------------------
# API Gateway Outputs
# -----------------------------------------------------------------------------

output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = "${aws_api_gateway_stage.main.invoke_url}/generate"
}

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.fm_evaluator.id
}

output "model_abstraction_lambda_arn" {
  description = "ARN of the model abstraction Lambda function"
  value       = aws_lambda_function.model_abstraction.arn
}
