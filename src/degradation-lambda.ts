interface LambdaEvent {
  prompt?: string; // Not used in degradation handler but included for consistency
  use_case?: string;
}

interface LambdaResponse {
  statusCode: number;
  body: string;
}

const FALLBACK_RESPONSES: Record<string, string> = {
  general:
    "I'm sorry, but I'm currently experiencing technical difficulties. Please try again later or contact customer service for immediate assistance.",
  product_question:
    "I apologize, but I can't access product information right now. Please refer to our product documentation or contact customer service at 1-800-555-1234.",
  account_inquiry:
    "I'm unable to process account inquiries at the moment. For urgent matters, please call our customer service line at 1-800-555-1234.",
};

const DEFAULT_RESPONSE =
  "I'm sorry, but I'm currently experiencing technical difficulties. Please try again later.";

/**
 * Graceful degradation handler that returns a predefined response.
 * Called by Step Functions when both primary and fallback models fail.
 * This ensures users always get a response, even during outages.
 */
export async function handler(event: LambdaEvent): Promise<LambdaResponse> {
  const useCase = event.use_case ?? "general";
  const responseText = FALLBACK_RESPONSES[useCase] ?? DEFAULT_RESPONSE;

  return {
    statusCode: 200,
    body: JSON.stringify({
      model_used: "DEGRADED_SERVICE",
      use_case: useCase,
      response: responseText,
    }),
  };
}

