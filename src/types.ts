// Type definitions
export interface TestCase {
  question: string;
  context: string;
  ground_truth: string;
}

export interface InvokeResult {
  success: boolean;
  output?: string;
  error?: string;
  latency: number;
  token_count?: number;
}

export interface EvaluationResult {
  model_id: string;
  question: string;
  output?: string;
  error?: string;
  latency: number;
  token_count?: number;
  similarity_score?: number;
}

export interface SummaryResult {
  model_id: string;
  avg_latency: number;
  avg_similarity_score: number;
  avg_token_count: number;
}

/**
 * Scoring data for a single model after evaluation analysis.
 */
export interface ModelScore {
  /** The Bedrock model identifier (e.g., "amazon.nova-lite-v1:0") */
  model_id: string;
  /** Average response latency in seconds */
  latency: number;
  /** Average similarity to ground truth (0-1, higher is better) */
  similarity_score: number;
  /** Normalized latency score (0-1, higher means faster) */
  latency_score: number;
  /** Weighted overall score combining quality and performance */
  overall_score: number;
}

/**
 * The final model selection strategy output.
 * Use this to configure your application's model routing.
 */
export interface ModelSelectionStrategy {
  /** The recommended model to use as the primary choice */
  primary_model: string;
  /** Ordered list of fallback models if primary is unavailable */
  fallback_models: string[];
  /** Detailed scoring breakdown for each evaluated model */
  model_scores: ModelScore[];
}
