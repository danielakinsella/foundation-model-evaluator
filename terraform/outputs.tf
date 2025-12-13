output "application_id" {
  description = "The AppConfig application ID"
  value       = aws_appconfig_application.fm_assessment.id
}

output "application_arn" {
  description = "The AppConfig application ARN"
  value       = aws_appconfig_application.fm_assessment.arn
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
    application_id = aws_appconfig_application.fm_assessment.id
    environment_id = aws_appconfig_environment.main.environment_id
  }
}
