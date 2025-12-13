# AWS AppConfig Application
resource "aws_appconfig_application" "fm_assessment" {
  name        = var.application_name
  description = "Foundation Model Assessment application for model selection strategy"

  tags = {
    Name = var.application_name
  }
}

# AWS AppConfig Environment
resource "aws_appconfig_environment" "main" {
  name           = var.environment
  description    = "${var.environment} environment for AI Assistant"
  application_id = aws_appconfig_application.fm_assessment.id

  tags = {
    Name = var.environment
  }
}

# AWS AppConfig Configuration Profile
resource "aws_appconfig_configuration_profile" "model_selection" {
  application_id = aws_appconfig_application.fm_assessment.id
  name           = var.configuration_profile_name
  description    = "Model selection strategy configuration"
  location_uri   = "hosted"
  type           = "AWS.Freeform"

  tags = {
    Name = var.configuration_profile_name
  }
}

# AWS AppConfig Deployment Strategy
resource "aws_appconfig_deployment_strategy" "linear" {
  name                           = var.deployment_strategy_name
  description                    = "Linear deployment strategy for model selection"
  deployment_duration_in_minutes = var.deployment_duration_in_minutes
  final_bake_time_in_minutes     = var.final_bake_time_in_minutes
  growth_factor                  = var.growth_factor
  growth_type                    = "LINEAR"
  replicate_to                   = "NONE"

  tags = {
    Name = var.deployment_strategy_name
  }
}

# Read the model selection strategy JSON file
locals {
  model_selection_strategy = file("${path.module}/../model_selection_strategy.json")
}

# AWS AppConfig Hosted Configuration Version
resource "aws_appconfig_hosted_configuration_version" "model_selection" {
  application_id           = aws_appconfig_application.fm_assessment.id
  configuration_profile_id = aws_appconfig_configuration_profile.model_selection.configuration_profile_id
  description              = "Model selection strategy configuration"
  content_type             = "application/json"
  content                  = local.model_selection_strategy
}

# AWS AppConfig Deployment
resource "aws_appconfig_deployment" "model_selection" {
  application_id           = aws_appconfig_application.fm_assessment.id
  configuration_profile_id = aws_appconfig_configuration_profile.model_selection.configuration_profile_id
  configuration_version    = aws_appconfig_hosted_configuration_version.model_selection.version_number
  deployment_strategy_id   = aws_appconfig_deployment_strategy.linear.id
  environment_id           = aws_appconfig_environment.main.environment_id
  description              = "Deploying model selection strategy"

  tags = {
    Name = "model-selection-deployment"
  }
}
