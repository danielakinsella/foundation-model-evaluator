# API Gateway - Foundation Model Evaluator

# -----------------------------------------------------------------------------
# IAM Role for Lambda
# -----------------------------------------------------------------------------

resource "aws_iam_role" "lambda_execution" {
  name = "${var.application_name_short}-lambda-execution-${lower(var.environment)}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.application_name_short}-lambda-execution-${lower(var.environment)}"
  }
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Bedrock access policy
resource "aws_iam_role_policy" "bedrock_access" {
  name = "BedrockAccess"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock-runtime:InvokeModel"
        ]
        Resource = "*"
      }
    ]
  })
}

# AppConfig access policy
resource "aws_iam_role_policy" "appconfig_access" {
  name = "AppConfigAccess"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "appconfig:GetConfiguration",
          "appconfig:GetLatestConfiguration",
          "appconfig:StartConfigurationSession"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Role for API Gateway to invoke Step Functions
# -----------------------------------------------------------------------------

resource "aws_iam_role" "api_gateway_sfn" {
  name = "${var.application_name_short}-apigw-sfn-${lower(var.environment)}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.application_name_short}-apigw-sfn-${lower(var.environment)}"
  }
}

resource "aws_iam_role_policy" "api_gateway_sfn" {
  name = "StepFunctionsAccess"
  role = aws_iam_role.api_gateway_sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartSyncExecution"
        ]
        Resource = aws_sfn_state_machine.fm_evaluator.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# API Gateway REST API
# -----------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "fm_evaluator" {
  name        = "${var.application_name_short}-api-${lower(var.environment)}"
  description = "API for Foundation Model Evaluator"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${var.application_name_short}-api-${lower(var.environment)}"
  }
}

# /generate resource
resource "aws_api_gateway_resource" "generate" {
  rest_api_id = aws_api_gateway_rest_api.fm_evaluator.id
  parent_id   = aws_api_gateway_rest_api.fm_evaluator.root_resource_id
  path_part   = "generate"
}

# POST method
resource "aws_api_gateway_method" "generate_post" {
  rest_api_id   = aws_api_gateway_rest_api.fm_evaluator.id
  resource_id   = aws_api_gateway_resource.generate.id
  http_method   = "POST"
  authorization = "NONE"
}

# Step Functions integration
resource "aws_api_gateway_integration" "sfn" {
  rest_api_id             = aws_api_gateway_rest_api.fm_evaluator.id
  resource_id             = aws_api_gateway_resource.generate.id
  http_method             = aws_api_gateway_method.generate_post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.aws_region}:states:action/StartSyncExecution"
  credentials             = aws_iam_role.api_gateway_sfn.arn

  request_templates = {
    "application/json" = jsonencode({
      input            = "$util.escapeJavaScript($input.body)"
      stateMachineArn  = aws_sfn_state_machine.fm_evaluator.arn
    })
  }
}

# Method response
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.fm_evaluator.id
  resource_id = aws_api_gateway_resource.generate.id
  http_method = aws_api_gateway_method.generate_post.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response - extract Lambda output from Step Functions response
resource "aws_api_gateway_integration_response" "sfn" {
  rest_api_id = aws_api_gateway_rest_api.fm_evaluator.id
  resource_id = aws_api_gateway_resource.generate.id
  http_method = aws_api_gateway_method.generate_post.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  # Extract the output from Step Functions response
  response_templates = {
    "application/json" = <<EOF
#set($output = $util.parseJson($input.json('$.output')))
#if($input.json('$.status') == "SUCCEEDED")
$output.body
#else
#set($context.responseOverride.status = 500)
{"error": "Execution failed", "cause": $input.json('$.cause')}
#end
EOF
  }

  depends_on = [aws_api_gateway_integration.sfn]
}

# API deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.fm_evaluator.id

  depends_on = [
    aws_api_gateway_integration.sfn,
    aws_api_gateway_integration_response.sfn
  ]

  lifecycle {
    create_before_destroy = true
  }

  # Force new deployment when integration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_integration.sfn,
      aws_api_gateway_integration_response.sfn
    ]))
  }
}

# API stage
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.fm_evaluator.id
  stage_name    = lower(var.environment)

  tags = {
    Name = "${var.application_name_short}-api-${lower(var.environment)}"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for API Gateway
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.application_name_short}-${lower(var.environment)}"
  retention_in_days = 30

  tags = {
    Name = "${var.application_name_short}-api-logs-${lower(var.environment)}"
  }
}
