import { z } from "zod";

export const languageSchema = z.enum(["zh", "en"]);
export type Language = z.infer<typeof languageSchema>;

export const locationPointSchema = z.object({
  label: z.string(),
  latitude: z.number(),
  longitude: z.number()
});
export type LocationPoint = z.infer<typeof locationPointSchema>;

export const tripPreferencesSchema = z.object({
  priority: z.enum(["balanced", "cheapest", "fastest", "comfortable", "lowCarbon"]).default("balanced"),
  maxWalkingMinutes: z.number().min(0).max(120).default(20),
  maxTransfers: z.number().min(0).max(10).default(2),
  comfortBias: z.number().min(0).max(1).default(0.5),
  carbonBias: z.number().min(0).max(1).default(0.4),
  avoidTransit: z.boolean().default(false),
  avoidDriving: z.boolean().default(false)
});
export type TripPreferences = z.infer<typeof tripPreferencesSchema>;

export const tripConstraintsSchema = z.object({
  budgetLimit: z.number().nullable().default(null),
  parkingDurationHours: z.number().min(0).max(48).default(2),
  departureTimeIso: z.string().nullable().default(null),
  arrivalDeadlineIso: z.string().nullable().default(null),
  notes: z.string().default("")
});
export type TripConstraints = z.infer<typeof tripConstraintsSchema>;

export const tripRequestSchema = z.object({
  requestId: z.string(),
  language: languageSchema,
  originalMessage: z.string(),
  origin: locationPointSchema.nullable(),
  destination: locationPointSchema.nullable(),
  originText: z.string().default(""),
  destinationText: z.string().default(""),
  preferences: tripPreferencesSchema,
  constraints: tripConstraintsSchema
});
export type TripRequest = z.infer<typeof tripRequestSchema>;

export const modeTypeSchema = z.enum(["direct-drive", "park-and-ride", "transit-only"]);
export type ModeType = z.infer<typeof modeTypeSchema>;

export const travelModeOptionSchema = z.object({
  modeId: z.string(),
  requestId: z.string(),
  modeType: modeTypeSchema,
  parkingRequired: z.boolean(),
  estimatedCost: z.number(),
  estimatedDuration: z.number(),
  comfortScore: z.number(),
  carbonScore: z.number(),
  rawMetrics: z.record(z.union([z.number(), z.string(), z.boolean()]))
});
export type TravelModeOption = z.infer<typeof travelModeOptionSchema>;

export const planTagSchema = z.enum(["recommended", "cheapest", "fastest", "comfortable", "lowCarbon", "balanced"]);
export type PlanTag = z.infer<typeof planTagSchema>;

export const planStepSchema = z.object({
  kind: z.enum(["drive", "park", "transit", "walk", "summary"]),
  title: z.string(),
  description: z.string(),
  durationMinutes: z.number(),
  cost: z.number(),
  carbonKg: z.number()
});
export type PlanStep = z.infer<typeof planStepSchema>;

export const routeSegmentSchema = z.object({
  segmentId: z.string(),
  kind: z.enum(["drive", "park", "transit", "walk", "summary"]),
  title: z.string(),
  description: z.string(),
  provider: z.string(),
  durationMinutes: z.number(),
  distanceKm: z.number(),
  trafficAware: z.boolean().default(false),
  fareIncluded: z.boolean().default(false),
  path: z.array(locationPointSchema).default([]),
  metadata: z.record(z.union([z.string(), z.number(), z.boolean()])).default({})
});
export type RouteSegment = z.infer<typeof routeSegmentSchema>;

export const liveRouteMetadataSchema = z.object({
  routeProvider: z.string(),
  usesRealtimeTraffic: z.boolean().default(false),
  usesRealtimeTransitFare: z.boolean().default(false),
  generatedAtIso: z.string(),
  warnings: z.array(z.string()).default([])
});
export type LiveRouteMetadata = z.infer<typeof liveRouteMetadataSchema>;

export const parkingSummarySchema = z.object({
  id: z.number(),
  name: z.string(),
  address: z.string(),
  city: z.string(),
  latitude: z.number(),
  longitude: z.number(),
  totalSpaces: z.number(),
  pricePerHour: z.number().nullable(),
  publicTransport: z.string(),
  facilities: z.string(),
  notes: z.string()
});
export type ParkingSummary = z.infer<typeof parkingSummarySchema>;

export const parkingRecordSchema = parkingSummarySchema.extend({
  isActive: z.boolean(),
  createdAt: z.string().nullable().default(null),
  updatedAt: z.string().nullable().default(null)
});
export type ParkingRecord = z.infer<typeof parkingRecordSchema>;

export const parkingWriteSchema = parkingRecordSchema
  .omit({ createdAt: true, updatedAt: true })
  .extend({
    id: z.number().optional().default(0)
  });
export type ParkingWriteInput = z.infer<typeof parkingWriteSchema>;

export const planSchema = z.object({
  planId: z.string(),
  requestId: z.string(),
  modeId: z.string(),
  title: z.string(),
  strategyTag: planTagSchema,
  parking: parkingSummarySchema.nullable(),
  totalCost: z.number(),
  parkingCost: z.number(),
  transitCost: z.number(),
  totalDuration: z.number(),
  drivingDuration: z.number(),
  transitDuration: z.number(),
  walkingDuration: z.number(),
  transferCount: z.number(),
  comfortScore: z.number(),
  carbonEstimate: z.number(),
  score: z.number(),
  explanation: z.string(),
  steps: z.array(planStepSchema),
  routePoints: z.array(locationPointSchema),
  routePath: z.array(locationPointSchema).default([]),
  routeSegments: z.array(routeSegmentSchema).default([]),
  liveRoute: liveRouteMetadataSchema
});
export type Plan = z.infer<typeof planSchema>;

export const planningResponseSchema = z.object({
  sessionId: z.string(),
  tripRequest: tripRequestSchema,
  options: z.array(travelModeOptionSchema),
  plans: z.array(planSchema),
  recommendedPlanId: z.string().nullable(),
  reply: z.string(),
  followUpQuestion: z.string().nullable(),
  qwenEnhanced: z.boolean().default(false)
});
export type PlanningResponse = z.infer<typeof planningResponseSchema>;

export function formatCurrency(value: number, language: Language) {
  return new Intl.NumberFormat(language === "zh" ? "zh-CN" : "en-US", {
    style: "currency",
    currency: "EUR",
    maximumFractionDigits: 2
  }).format(value);
}

export function formatDuration(minutes: number, language: Language) {
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;

  if (language === "zh") {
    if (hours > 0) return `${hours}小时${mins}分钟`;
    return `${mins}分钟`;
  }

  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins} min`;
}

export function inferLanguage(input: string): Language {
  return /[\u4e00-\u9fff]/.test(input) ? "zh" : "en";
}

export function createId(prefix: string) {
  return `${prefix}_${Math.random().toString(36).slice(2, 10)}`;
}

