import {
  BedrockRuntimeClient,
  InvokeModelCommand,
} from "@aws-sdk/client-bedrock-runtime";

const client = new BedrockRuntimeClient({});

interface LambdaEvent {
  prompt: string;
  use_case?: string;
}

interface LambdaResponse {
  statusCode: number;
  body: string;
}

/**
 * Fallback model handler that uses a simpler, more reliable model.
 * Called by Step Functions when the primary model fails.
 */
export async function handler(event: LambdaEvent): Promise<LambdaResponse> {
  const prompt = event.prompt ?? "";
  const useCase = event.use_case ?? "general";

  // Use a simpler, more reliable model
  const modelId = "amazon.titan-text-express-v1";

  try {
    const command = new InvokeModelCommand({
      modelId,
      contentType: "application/json",
      accept: "application/json",
      body: JSON.stringify({
        inputText: prompt,
        textGenerationConfig: {
          maxTokenCount: 300, // Reduced for reliability
          temperature: 0.5,
          topP: 0.9,
        },
      }),
    });

    const response = await client.send(command);
    const responseBody = JSON.parse(new TextDecoder().decode(response.body));
    const output = responseBody.results?.[0]?.outputText ?? "";

    return {
      statusCode: 200,
      body: JSON.stringify({
        model_used: `FALLBACK:${modelId}`,
        use_case: useCase,
        response: output,
      }),
    };
  } catch (error) {
    // Let Step Functions catch this and move to graceful degradation
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Fallback model failed: ${message}`);
  }
}
