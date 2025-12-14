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

interface APIGatewayEvent {
  body: string | null;
  httpMethod: string;
  path: string;
}

interface APIGatewayResponse {
  statusCode: number;
  headers: Record<string, string>;
  body: string;
}

interface RequestBody {
  prompt: string;
  use_case?: string;
  max_tokens?: number;
}

interface ModelSelectionStrategy {
  primary_model: string;
  fallback_models: string[];
}

let configurationToken: string | undefined;
let cachedConfig: ModelSelectionStrategy | null = null;

/**
 * Fetches the model selection strategy from AppConfig.
 */
async function getModelConfig(): Promise<ModelSelectionStrategy> {
  const appId = process.env.APPCONFIG_APP;
  const envId = process.env.APPCONFIG_ENV;
  const configId = process.env.APPCONFIG_CONFIG;

  if (!appId || !envId || !configId) {
    throw new Error("AppConfig environment variables not configured");
  }

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
    // Return default if AppConfig fails
    console.error("Failed to get AppConfig:", error);
    return {
      primary_model: "amazon.titan-text-express-v1",
      fallback_models: [],
    };
  }
}

/**
 * Invokes a Bedrock model with the given prompt.
 */
async function invokeModel(
  modelId: string,
  prompt: string,
  maxTokens: number
): Promise<string> {
  let body: string;

  if (modelId.includes("nova")) {
    // Nova models use Messages API
    body = JSON.stringify({
      messages: [
        {
          role: "user",
          content: [{ text: prompt }],
        },
      ],
      inferenceConfig: {
        max_new_tokens: maxTokens,
        temperature: 0.7,
        top_p: 0.9,
      },
    });
  } else if (modelId.includes("titan-text")) {
    // Titan Text models
    body = JSON.stringify({
      inputText: prompt,
      textGenerationConfig: {
        maxTokenCount: maxTokens,
        temperature: 0.7,
        topP: 0.9,
      },
    });
  } else if (modelId.includes("anthropic")) {
    // Claude models
    body = JSON.stringify({
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: maxTokens,
      messages: [{ role: "user", content: prompt }],
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

  // Extract response based on model type
  if (modelId.includes("nova")) {
    return responseBody.output?.message?.content?.[0]?.text ?? "";
  } else if (modelId.includes("titan-text")) {
    return responseBody.results?.[0]?.outputText ?? "";
  } else if (modelId.includes("anthropic")) {
    return responseBody.content?.[0]?.text ?? "";
  }

  return "";
}

/**
 * Lambda handler for API Gateway requests.
 */
export async function handler(event: APIGatewayEvent): Promise<APIGatewayResponse> {
  const headers = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
  };

  try {
    // Parse request body
    if (!event.body) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: "Request body is required" }),
      };
    }

    const requestBody: RequestBody = JSON.parse(event.body);
    const { prompt, use_case = "general", max_tokens = 500 } = requestBody;

    if (!prompt) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: "Prompt is required" }),
      };
    }

    // Get model configuration from AppConfig
    const config = await getModelConfig();
    const modelsToTry = [config.primary_model, ...config.fallback_models];

    // Try models in order until one succeeds
    let lastError: Error | null = null;
    for (const modelId of modelsToTry) {
      try {
        console.log(`Trying model: ${modelId}`);
        const response = await invokeModel(modelId, prompt, max_tokens);

        return {
          statusCode: 200,
          headers,
          body: JSON.stringify({
            model_used: modelId,
            use_case,
            response,
          }),
        };
      } catch (error) {
        console.error(`Model ${modelId} failed:`, error);
        lastError = error instanceof Error ? error : new Error(String(error));
      }
    }

    // All models failed
    return {
      statusCode: 503,
      headers,
      body: JSON.stringify({
        error: "All models unavailable",
        message: lastError?.message ?? "Unknown error",
      }),
    };
  } catch (error) {
    console.error("Handler error:", error);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        error: "Internal server error",
        message: error instanceof Error ? error.message : "Unknown error",
      }),
    };
  }
}

