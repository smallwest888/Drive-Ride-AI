import { planningResponseSchema, type Language, type LocationPoint, type PlanningResponse } from "@drive-ride/shared";
import { config } from "./config.js";
import { buildPlanningResponse } from "./planner.js";
import { polishReply } from "./qwen.js";

type AgentInput = {
  message: string;
  language?: Language;
  currentLocation?: LocationPoint | null;
};

type OpenClawToolInvokeResponse = {
  ok?: boolean;
  result?: {
    content?: Array<{ type?: string; text?: string }>;
    details?: unknown;
  };
};

export async function runClawdbotTravelAgent(input: AgentInput): Promise<PlanningResponse> {
  try {
    const response = await runOpenClawToolPlan(input);
    return await polishPlanningResponse(response);
  } catch {
    return runDirectPlanningService(input);
  }
}

export async function runDirectPlanningService(input: AgentInput): Promise<PlanningResponse> {
  const baseResponse = await buildPlanningResponse(input);
  return polishPlanningResponse(baseResponse);
}

async function polishPlanningResponse(baseResponse: PlanningResponse) {
  if (!baseResponse.plans.length) return baseResponse;

  const topPlans = baseResponse.plans.slice(0, 3);
  const contextSummary = topPlans
    .map(
      (plan) =>
        `${plan.title}: EUR ${plan.totalCost.toFixed(2)}, ${plan.totalDuration} min, comfort ${plan.comfortScore.toFixed(0)}, carbon ${plan.carbonEstimate.toFixed(2)}kg`
    )
    .join("\n");

  try {
    const polished = await polishReply(baseResponse.tripRequest.language, baseResponse.reply, contextSummary);
    return {
      ...baseResponse,
      reply: polished.text,
      qwenEnhanced: polished.enhanced
    };
  } catch {
    return baseResponse;
  }
}

async function runOpenClawToolPlan(input: AgentInput): Promise<PlanningResponse> {
  const response = await fetch(`${config.openClawBaseUrl}/tools/invoke`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.openClawToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      tool: "drive_ride_plan_trip",
      args: {
        message: input.message,
        language: input.language,
        currentLocation: input.currentLocation ?? null
      }
    })
  });

  if (!response.ok) {
    throw new Error(`OpenClaw tool invoke failed: ${response.status} ${await response.text()}`);
  }

  const payload = (await response.json()) as OpenClawToolInvokeResponse;
  const direct = planningResponseSchema.safeParse(payload.result?.details);
  if (direct.success) {
    return direct.data;
  }

  const content = payload.result?.content?.map((item) => item.text ?? "").join("").trim() ?? "";
  const parsed = tryParsePlanningResponse(content);
  if (!parsed) {
    throw new Error("OpenClaw tool invoke returned a non-parseable planning payload.");
  }
  return parsed;
}

function tryParsePlanningResponse(content: string) {
  const direct = safeParse(content);
  if (direct) return direct;

  const objectMatch = content.match(/\{[\s\S]*\}/);
  if (!objectMatch) return null;
  return safeParse(objectMatch[0]);
}

function safeParse(input: string) {
  try {
    return planningResponseSchema.parse(JSON.parse(input));
  } catch {
    return null;
  }
}
