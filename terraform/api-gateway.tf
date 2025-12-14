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

# Lambda integration - uses primary Lambda
resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.fm_evaluator.id
  resource_id             = aws_api_gateway_resource.generate.id
  http_method             = aws_api_gateway_method.generate_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.primary.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.primary.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.fm_evaluator.execution_arn}/*/*"
}

# API deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.fm_evaluator.id

  depends_on = [
    aws_api_gateway_integration.lambda
  ]

  lifecycle {
    create_before_destroy = true
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
