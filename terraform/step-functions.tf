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

# IAM Policy for Step Functions to invoke Lambda
resource "aws_iam_role_policy" "step_functions_lambda" {
  name = "${var.application_name_short}-step-functions-lambda-policy"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          aws_lambda_function.primary.arn,
          aws_lambda_function.fallback.arn,
          aws_lambda_function.degradation.arn
        ]
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
          FunctionName = aws_lambda_function.primary.arn
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
          FunctionName = aws_lambda_function.fallback.arn
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
          FunctionName = aws_lambda_function.degradation.arn
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
