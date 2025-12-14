import {
  BedrockRuntimeClient,
  InvokeModelCommand,
} from "@aws-sdk/client-bedrock-runtime";
import {
  AppConfigDataClient,
  StartConfigurationSessionCommand,
  GetLatestConfigurationCommand,
} from "@aws-sdk/client-appconfigdata";

const bedrockClient = new BedrockRuntimeClient({});
const appConfigClient = new AppConfigDataClient({});

interface LambdaEvent {
  body?: string;
  prompt?: string;
  use_case?: string;
}

interface LambdaResponse {
  statusCode: number;
  body: string;
}

interface ModelSelectionConfig {
  primary_model: string;
  fallback_models?: string[];
  use_case_models?: Record<string, string>;
}

let configurationToken: string | undefined;
let cachedConfig: ModelSelectionConfig | null = null;

/**
 * Fetches the model selection configuration from AppConfig.
 */
async function getAppConfig(): Promise<ModelSelectionConfig> {
  const appId = process.env.APPCONFIG_APP ?? "AIAssistantApp";
  const envId = process.env.APPCONFIG_ENV ?? "Production";
  const configId = process.env.APPCONFIG_CONFIG ?? "ModelSelectionStrategy";

  try {
    // Start a new session if we don't have a token
    if (!configurationToken) {
      const sessionResponse = await appConfigClient.send(
        new StartConfigurationSessionCommand({
          ApplicationIdentifier: appId,
          EnvironmentIdentifier: envId,
          ConfigurationProfileIdentifier: configId,
        })
      );
      configurationToken = sessionResponse.InitialConfigurationToken;
    }

    // Get the latest configuration
    const configResponse = await appConfigClient.send(
      new GetLatestConfigurationCommand({
        ConfigurationToken: configurationToken,
      })
    );

    // Update token for next call
    configurationToken = configResponse.NextPollConfigurationToken;

    // If configuration is returned, parse and cache it
    if (configResponse.Configuration && configResponse.Configuration.length > 0) {
      const configString = new TextDecoder().decode(configResponse.Configuration);
      cachedConfig = JSON.parse(configString);
    }

    if (!cachedConfig) {
      throw new Error("No configuration available");
    }

    return cachedConfig;
  } catch (error) {
    console.error("Failed to get AppConfig:", error);
    // Return default configuration if AppConfig fails
    return {
      primary_model: "amazon.titan-text-express-v1",
      fallback_models: [],
    };
  }
}

/**
 * Select appropriate model based on configuration and use case.
 */
function selectModel(config: ModelSelectionConfig, useCase: string): string {
  // Check if there's a use case specific model
  const useCaseModels = config.use_case_models ?? {};
  if (useCase in useCaseModels) {
    return useCaseModels[useCase];
  }

  // Default to primary model
  return config.primary_model;
}

/**
 * Invoke the selected model with the given prompt.
 */
async function invokeModel(modelId: string, prompt: string): Promise<string> {
  let body: string;

  // Prepare request body based on model provider
  if (modelId.includes("anthropic")) {
    body = JSON.stringify({
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: 500,
      messages: [{ role: "user", content: prompt }],
    });
  } else if (modelId.includes("nova")) {
    // Nova models use Messages API
    body = JSON.stringify({
      messages: [
        {
          role: "user",
          content: [{ text: prompt }],
        },
      ],
      inferenceConfig: {
        max_new_tokens: 500,
        temperature: 0.7,
        top_p: 0.9,
      },
    });
  } else if (modelId.includes("titan-text")) {
    // Titan Text models
    body = JSON.stringify({
      inputText: prompt,
      textGenerationConfig: {
        maxTokenCount: 500,
        temperature: 0.7,
        topP: 0.9,
      },
    });
  } else {
    throw new Error(`Unsupported model: ${modelId}`);
  }

  const command = new InvokeModelCommand({
    modelId,
    contentType: "application/json",
    accept: "application/json",
    body,
  });

  const response = await bedrockClient.send(command);
  const responseBody = JSON.parse(new TextDecoder().decode(response.body));

  // Parse response based on model provider
  if (modelId.includes("anthropic")) {
    return responseBody.content?.[0]?.text ?? "";
  } else if (modelId.includes("nova")) {
    return responseBody.output?.message?.content?.[0]?.text ?? "";
  } else if (modelId.includes("titan-text")) {
    return responseBody.results?.[0]?.outputText ?? "";
  }

  return "";
}

/**
 * Primary Lambda handler - invokes the primary model based on AppConfig.
 */
export async function handler(event: LambdaEvent): Promise<LambdaResponse> {
  try {
    // Extract request details - support both API Gateway and direct invocation
    let prompt: string;
    let useCase: string;

    if (event.body) {
      // API Gateway event
      const body = JSON.parse(event.body);
      prompt = body.prompt ?? "";
      useCase = body.use_case ?? "general";
    } else {
      // Direct invocation (e.g., from Step Functions)
      prompt = event.prompt ?? "";
      useCase = event.use_case ?? "general";
    }

    if (!prompt) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Prompt is required" }),
      };
    }

    // Get AppConfig configuration
    const config = await getAppConfig();

    // Select model based on use case and configuration
    const modelId = selectModel(config, useCase);

    // Invoke selected model
    const response = await invokeModel(modelId, prompt);

    return {
      statusCode: 200,
      body: JSON.stringify({
        model_used: modelId,
        use_case: useCase,
        response,
      }),
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`Error in primary lambda: ${message}`);

    // Throw error to let Step Functions handle fallback
    throw new Error(`Primary model failed: ${message}`);
  }
}
