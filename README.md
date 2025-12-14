# Foundation Model Evaluator

A production-ready framework for evaluating, selecting, and deploying AI foundation models on AWS Bedrock with built-in resilience patterns.

## Overview

This project provides:

1. **Model Evaluation Framework** - Benchmark multiple AI models against test cases
2. **Dynamic Model Selection** - Use AWS AppConfig to switch models without redeployment
3. **Circuit Breaker Pattern** - Automatic fallback when primary models fail
4. **Infrastructure as Code** - Fully automated deployment via Terraform and GitHub Actions

## Architecture

```
                         POST /generate
                              │
                              ▼
                        ┌───────────┐
                        │    API    │
                        │  Gateway  │
                        └───────────┘
                              │
                              ▼ (StartSyncExecution)
                   ┌─────────────────────┐
                   │   Step Functions    │
                   │     (EXPRESS)       │
                   │                     │
                   │  Circuit Breaker    │
                   │      Pattern        │
                   └─────────────────────┘
                              │
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
    ┌───────────────┐  ┌───────────┐  ┌───────────────┐
    │    Primary    │  │  Fallback │  │  Degradation  │
    │    Lambda     │  │  Lambda   │  │    Lambda     │
    │               │  │           │  │               │
    │ (AppConfig    │  │ (Titan    │  │ (Canned       │
    │  model)       │  │  Express) │  │  response)    │
    └───────────────┘  └───────────┘  └───────────────┘
            │                 │
            ▼                 ▼
    ┌─────────────────────────────────┐
    │         AWS Bedrock             │
    │   (Nova, Titan, Claude, etc.)   │
    └─────────────────────────────────┘
```

### How the Circuit Breaker Works

1. **TryPrimaryModel** - Invokes the model configured in AppConfig (with 2 retries)
2. **TryFallbackModel** - If primary fails, uses Amazon Titan Express (with 2 retries)
3. **GracefulDegradation** - If all models fail, returns a helpful canned response

This ensures users always get a response, even during outages.

## Project Structure

```
├── src/
│   ├── eval-framework.ts    # Model evaluation benchmarking
│   ├── selection.ts         # Analyzes results, generates selection strategy
│   ├── primary-lambda.ts    # Primary model Lambda (uses AppConfig)
│   ├── fallback-lambda.ts   # Fallback model Lambda
│   ├── degradation-lambda.ts# Returns canned responses
│   └── types.ts             # TypeScript type definitions
├── terraform/
│   ├── main.tf              # AppConfig resources
│   ├── api-gateway.tf       # API Gateway + IAM
│   ├── step-functions.tf    # Step Functions state machine
│   ├── lambdas.tf           # Lambda function deployments
│   ├── backend-resources.tf # S3/DynamoDB for Terraform state
│   ├── variables.tf         # Terraform variables
│   ├── outputs.tf           # Terraform outputs
│   └── versions.tf          # Provider versions + backend config
├── config/
│   ├── model_evaluation_results.csv    # Benchmark results
│   └── model_selection_strategy.json   # Model selection config
├── scripts/
│   └── package-lambdas.js   # Lambda packaging script
└── .github/
    └── workflows/
        └── deploy-appconfig.yml  # CI/CD pipeline
```

## Getting Started

### Prerequisites

- Node.js 20+
- AWS CLI configured
- Terraform 1.9+
- Access to AWS Bedrock models

### Local Development

```bash
# Install dependencies
npm install

# Run model evaluation (requires AWS credentials)
npm run start:eval

# Generate selection strategy from evaluation results
npm run start:selection

# Build TypeScript and package Lambdas
npm run build:lambdas
```

### Deployment

The infrastructure deploys automatically via GitHub Actions when you push to `main`.

**First-time setup:**

1. Configure GitHub secret `AWS_ROLE_ARN` with an IAM role that has the required permissions
2. Push to `main` branch
3. The workflow will:
   - Build and package Lambda functions
   - Bootstrap S3 bucket and DynamoDB table for Terraform state
   - Deploy all infrastructure via Terraform

### Manual Deployment

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## Usage

### API Endpoint

After deployment, call the API:

```bash
curl -X POST https://<api-id>.execute-api.us-east-1.amazonaws.com/production/generate \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "What is a 401(k) retirement plan?",
    "use_case": "general"
  }'
```

**Response:**
```json
{
  "model_used": "amazon.titan-text-express-v1",
  "use_case": "general",
  "response": "A 401(k) is a tax-advantaged retirement savings plan..."
}
```

### Changing the Primary Model

Update `config/model_selection_strategy.json`:

```json
{
  "primary_model": "amazon.nova-lite-v1:0",
  "fallback_models": ["amazon.titan-text-express-v1"]
}
```

Commit and push - the new model will be deployed via AppConfig with a gradual rollout.

## Model Evaluation

The evaluation framework benchmarks models on:

- **Latency** - Response time in seconds
- **Similarity Score** - How closely output matches ground truth (0-1)
- **Token Count** - Approximate output length

### Running an Evaluation

1. Edit test cases in `src/eval-framework.ts`
2. Run `npm run start:eval`
3. Results are saved to `config/model_evaluation_results.csv`
4. Run `npm run start:selection` to generate the selection strategy

### Supported Models

- Amazon Nova (nova-lite, nova-pro)
- Amazon Titan Text (titan-text-express, titan-text-lite)
- Anthropic Claude (via Bedrock)

## Configuration

### AppConfig

The model selection strategy is managed via AWS AppConfig, enabling:

- **Dynamic model switching** without redeployment
- **Gradual rollouts** (default: 10 minutes, 20% increments)
- **Instant rollback** if issues are detected

### Environment Variables

Lambda functions use these environment variables:

| Variable | Description |
|----------|-------------|
| `APPCONFIG_APP` | AppConfig application ID |
| `APPCONFIG_ENV` | AppConfig environment ID |
| `APPCONFIG_CONFIG` | AppConfig configuration profile ID |
| `ENVIRONMENT` | Deployment environment (Production) |

## Infrastructure

### AWS Resources Created

- **API Gateway** - REST API with `/generate` endpoint
- **Step Functions** - Express workflow for circuit breaker
- **Lambda Functions** - Primary, Fallback, and Degradation handlers
- **AppConfig** - Application, Environment, Configuration Profile
- **IAM Roles** - Execution roles for Lambda, Step Functions, API Gateway
- **CloudWatch Log Groups** - Logging for all components
- **S3 Bucket** - Terraform state storage
- **DynamoDB Table** - Terraform state locking

### Costs

- **Step Functions Express** - Pay per execution and duration
- **Lambda** - Pay per invocation and duration
- **API Gateway** - Pay per request
- **Bedrock** - Pay per token (model-dependent)
- **AppConfig** - Free tier covers most usage

## Security Considerations

- API Gateway currently has `authorization = "NONE"` - add IAM auth, API keys, or Cognito for production
- Lambda roles have minimal required permissions
- Bedrock access is scoped to invoke operations only
- Terraform state is encrypted in S3 with versioning enabled

## Troubleshooting

### Common Issues

**"Model not available"**
- Ensure you have access to the Bedrock model in your AWS account
- Check the model ID format (e.g., `amazon.titan-text-express-v1`)

**"AppConfig configuration not found"**
- Verify the AppConfig IDs in Lambda environment variables
- Check that the configuration was deployed successfully

**"Step Functions execution failed"**
- Check CloudWatch logs at `/aws/stepfunctions/fm-evaluator`
- Verify Lambda functions are deployed and accessible

### Viewing Logs

```bash
# API Gateway logs
aws logs tail /aws/apigateway/fm-evaluator-production --follow

# Step Functions logs
aws logs tail /aws/stepfunctions/fm-evaluator --follow

# Lambda logs
aws logs tail /aws/lambda/fm-evaluator-primary-production --follow
```

## License

ISC

## Author

Daniela Kinsella
