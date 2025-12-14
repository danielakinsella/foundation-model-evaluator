import {
  BedrockRuntimeClient,
  InvokeModelCommand,
} from "@aws-sdk/client-bedrock-runtime";
import * as fs from "fs";
import * as path from "path";
import { TestCase, InvokeResult, EvaluationResult, SummaryResult } from "./types";

// Resolve config directory path relative to this file
const CONFIG_DIR = path.resolve(__dirname, "..", "config");
// Initialize Bedrock client
const bedrockRuntime = new BedrockRuntimeClient({ region: "us-east-1" });

// Models to evaluate
const models = [
  "amazon.nova-lite-v1:0",
  "amazon.titan-text-express-v1",
];


// Test cases with ground truth answers
const testCases: TestCase[] = [
  {
    question: "What is a 401(k) retirement plan?",
    context: "Financial services",
    ground_truth:
      "A 401(k) is a tax-advantaged retirement savings plan offered by employers.",
  },
  // Add more test cases...
];

async function invokeModel(
  modelId: string,
  prompt: string,
  maxTokens: number = 500
): Promise<InvokeResult> {
  const startTime = Date.now();

  // Prepare request body based on model provider
  let body: string;

  if (modelId.includes("anthropic")) {
    body = JSON.stringify({
      anthropic_version: "bedrock-2023-05-31",
      max_tokens: maxTokens,
      messages: [{ role: "user", content: prompt }],
    });
  } else if (modelId.includes("nova")) {
    // Nova models use Messages API format
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
  } else {
    // Add more model providers as needed
    body = JSON.stringify({ prompt });
  }

  try {
    const command = new InvokeModelCommand({
      modelId,
      body: Buffer.from(body),
    });

    
    const response = await bedrockRuntime.send(command);
   
    // Parse the response
    const responseBody = JSON.parse(new TextDecoder().decode(response.body));

    let output: string;

    if (modelId.includes("anthropic")) {
      output = responseBody.content[0].text;
    } else if (modelId.includes("nova")) {
      // Nova response format
      output = responseBody.output?.message?.content?.[0]?.text || "";
    } else if (modelId.includes("titan-text")) {
      // Titan Text response format
      output = responseBody.results[0].outputText;
    } else {
      output = responseBody.output || "";
    }

    // Calculate metrics
    const latency = (Date.now() - startTime) / 1000;
    const tokenCount = output.split(/\s+/).length; // Rough estimate

    return {
      success: true,
      output,
      latency,
      token_count: tokenCount,
    };
  } catch (error) {
    console.error(`Model invocation failed:`, error);
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
      latency: (Date.now() - startTime) / 1000,
    };
  }
}

function calculateSimilarity(output: string, groundTruth: string): number {
  // Calculate similarity between model output and ground truth (simplified)
  // In a real implementation, use more sophisticated NLP techniques
  // This is a very simplified version
  const outputWords = new Set(output.toLowerCase().split(/\s+/));
  const truthWords = new Set(groundTruth.toLowerCase().split(/\s+/));

  if (truthWords.size === 0) {
    return 0.0;
  }

  const commonWords = [...outputWords].filter((word) => truthWords.has(word));
  return commonWords.length / truthWords.size;
}

async function evaluateModels(): Promise<EvaluationResult[]> {
  const results: EvaluationResult[] = [];

  for (const testCase of testCases) {
    const prompt = `Question: ${testCase.question}\nContext: ${testCase.context}`;

    for (const modelId of models) {
      console.log(`Evaluating ${modelId} on: ${testCase.question}`);
      const response = await invokeModel(modelId, prompt);

      if (response.success && response.output) {
        // Calculate similarity score with ground truth
        const similarity = calculateSimilarity(
          response.output,
          testCase.ground_truth
        );

        results.push({
          model_id: modelId,
          question: testCase.question,
          output: response.output,
          latency: response.latency,
          token_count: response.token_count,
          similarity_score: similarity,
        });
      } else {
        results.push({
          model_id: modelId,
          question: testCase.question,
          error: response.error,
          latency: response.latency,
        });
      }
    }
  }

  return results;
}

function resultsToCSV(results: EvaluationResult[]): string {
  if (results.length === 0) return "";

  const headers = Object.keys(results[0]);
  const rows = results.map((row) =>
    headers
      .map((header) => {
        const value = row[header as keyof EvaluationResult];
        if (value === undefined) return "";
        if (typeof value === "string" && value.includes(",")) {
          return `"${value.replace(/"/g, '""')}"`;
        }
        return String(value);
      })
      .join(",")
  );

  return [headers.join(","), ...rows].join("\n");
}

function calculateSummary(results: EvaluationResult[]): SummaryResult[] {
  const groupedByModel = results.reduce(
    (acc, result) => {
      if (!acc[result.model_id]) {
        acc[result.model_id] = [];
      }
      acc[result.model_id].push(result);
      return acc;
    },
    {} as Record<string, EvaluationResult[]>
  );

  return Object.entries(groupedByModel).map(([modelId, modelResults]) => {
    const validResults = modelResults.filter(
      (r) => r.similarity_score !== undefined
    );

    const avgLatency =
      modelResults.reduce((sum, r) => sum + r.latency, 0) / modelResults.length;

    const avgSimilarity =
      validResults.length > 0
        ? validResults.reduce((sum, r) => sum + (r.similarity_score || 0), 0) /
          validResults.length
        : 0;

    const resultsWithTokens = modelResults.filter(
      (r) => r.token_count !== undefined
    );
    const avgTokenCount =
      resultsWithTokens.length > 0
        ? resultsWithTokens.reduce((sum, r) => sum + (r.token_count || 0), 0) /
          resultsWithTokens.length
        : 0;

    return {
      model_id: modelId,
      avg_latency: avgLatency,
      avg_similarity_score: avgSimilarity,
      avg_token_count: avgTokenCount,
    };
  });
}

// Run evaluation
async function main() {
  const results = await evaluateModels();

  // Save results to CSV
  const csvContent = resultsToCSV(results);
  const outputPath = path.join(CONFIG_DIR, "model_evaluation_results.csv");
  fs.writeFileSync(outputPath, csvContent);

  // Print summary
  console.log("\nEvaluation Summary:");
  const summary = calculateSummary(results);

  console.table(summary);
}

main().catch(console.error);
