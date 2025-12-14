# Step Functions State Machine - Foundation Model Evaluator with Circuit Breaker Pattern

# IAM Role for Step Functions
resource "aws_iam_role" "step_functions" {
  name = "${var.application_name_short}-step-functions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.application_name_short}-step-functions-role"
  }
}

# Compute Lambda ARNs - use provided values or fallback to model_abstraction Lambda
locals {
  step_function_lambda_arns = compact([
    var.primary_model_lambda_arn != "" ? var.primary_model_lambda_arn : aws_lambda_function.model_abstraction.arn,
    var.fallback_model_lambda_arn,
    var.degradation_lambda_arn
  ])
}

# IAM Policy for Step Functions to invoke Lambda
resource "aws_iam_role_policy" "step_functions_lambda" {
  name = "${var.application_name_short}-step-functions-lambda-policy"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = length(local.step_function_lambda_arns) > 0 ? local.step_function_lambda_arns : ["arn:aws:lambda:*:*:function:placeholder"]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group for Step Functions
resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/stepfunctions/${var.application_name_short}"
  retention_in_days = 30

  tags = {
    Name = "${var.application_name_short}-step-functions-logs"
  }
}

# Compute effective Lambda ARNs for Step Functions state machine
locals {
  effective_primary_lambda_arn     = var.primary_model_lambda_arn != "" ? var.primary_model_lambda_arn : aws_lambda_function.model_abstraction.arn
  effective_fallback_lambda_arn    = var.fallback_model_lambda_arn != "" ? var.fallback_model_lambda_arn : aws_lambda_function.model_abstraction.arn
  effective_degradation_lambda_arn = var.degradation_lambda_arn != "" ? var.degradation_lambda_arn : aws_lambda_function.model_abstraction.arn
}

# Step Functions State Machine
resource "aws_sfn_state_machine" "fm_evaluator" {
  name     = "${var.application_name_short}-workflow"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "Foundation Model Evaluator - Circuit Breaker Pattern"
    StartAt = "TryPrimaryModel"
    States = {
      TryPrimaryModel = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = local.effective_primary_lambda_arn
          Payload = {
            "prompt.$"   = "$.prompt"
            "use_case.$" = "$.use_case"
          }
        }
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 1
            MaxAttempts     = 2
            BackoffRate     = 2
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "TryFallbackModel"
          }
        ]
        Next = "SuccessState"
      }

      TryFallbackModel = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = local.effective_fallback_lambda_arn
          Payload = {
            "prompt.$"    = "$.prompt"
            "use_case.$"  = "$.use_case"
            "is_fallback" = true
          }
        }
        Retry = [
          {
            ErrorEquals     = ["States.TaskFailed"]
            IntervalSeconds = 1
            MaxAttempts     = 2
            BackoffRate     = 2
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "GracefulDegradation"
          }
        ]
        Next = "SuccessState"
      }

      GracefulDegradation = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = local.effective_degradation_lambda_arn
          Payload = {
            "prompt.$"   = "$.prompt"
            "use_case.$" = "$.use_case"
          }
        }
        Next = "SuccessState"
      }

      SuccessState = {
        Type = "Succeed"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = {
    Name = "${var.application_name_short}-workflow"
  }
}
