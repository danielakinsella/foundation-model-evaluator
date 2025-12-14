# Import blocks for existing AWS resources
# These allow Terraform to adopt existing resources into state management
# After successful import, these blocks can be removed

# Import existing AppConfig Application
import {
  to = aws_appconfig_application.fm_evaluator
  id = "zp0tfpk"
}

# Import existing AppConfig Environment (format: environment_id:application_id)
import {
  to = aws_appconfig_environment.main
  id = "wvs4sg1:zp0tfpk"
}

# Import existing AppConfig Configuration Profile (format: profile_id:application_id)
import {
  to = aws_appconfig_configuration_profile.model_selection
  id = "od9pnlr:zp0tfpk"
}

# Import existing IAM Role for Lambda execution
import {
  to = aws_iam_role.lambda_execution
  id = "fm-evaluator-lambda-execution-production"
}

# Import existing IAM Role for Step Functions
import {
  to = aws_iam_role.step_functions
  id = "fm-evaluator-step-functions-role"
}

# Import S3 bucket (created by bootstrap step in GitHub Actions)
import {
  to = aws_s3_bucket.terraform_state
  id = "fm-evaluator-terraform-state-832787421689"
}

# Import DynamoDB table (created by bootstrap step in GitHub Actions)
import {
  to = aws_dynamodb_table.terraform_locks
  id = "fm-evaluator-terraform-locks"
}
