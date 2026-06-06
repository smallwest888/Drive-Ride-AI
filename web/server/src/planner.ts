import {
  createId,
  inferLanguage,
  planSchema,
  planningResponseSchema,
  tripRequestSchema,
  type Language,
  type LiveRouteMetadata,
  type LocationPoint,
  type ParkingRecord,
  type Plan,
  type PlanStep,
  type PlanningResponse,
  type RouteSegment,
  type TravelModeOption,
  type TripPreferences,
  type TripRequest
} from "@drive-ride/shared";
import { getAllActiveParkings } from "./db.js";
import { geocode, haversineKm } from "./geo.js";
import { computeDrivingRoute, computeTransitRoute } from "./routing.js";

type ParseInput = {
  message: string;
  language?: Language;
  currentLocation?: LocationPoint | null;
};

type ParsedMessage = {
  tripRequest: TripRequest;
  followUpQuestion: string | null;
};

const cityCenterParkingRate: Record<string, number> = {
  berlin: 7.5,
  hamburg: 6.8,
  munich: 8.4,
  muenchen: 8.4,
  aachen: 4.5,
  cologne: 6.2,
  koeln: 6.2,
  london: 12.5,
  default: 6
};

export async function buildPlanningResponse(input: ParseInput): Promise<PlanningResponse> {
  const { tripRequest, followUpQuestion } = await parseMessageToRequest(input);

  if (!tripRequest.destination) {
    return planningResponseSchema.parse({
      sessionId: createId("session"),
      tripRequest,
      options: [],
      plans: [],
      recommendedPlanId: null,
      reply:
        tripRequest.language === "zh"
          ? "我还缺少明确的目的地。请告诉我要去哪里，或者直接在地图上选点。"
          : "I still need a destination. Tell me where you want to go, or pick a point on the map.",
      followUpQuestion: followUpQuestion ?? (tripRequest.language === "zh" ? "你要去哪里？" : "Where would you like to go?"),
      qwenEnhanced: false
    });
  }

  const plans = await generatePlans(tripRequest, getAllActiveParkings());
  const taggedPlans = decoratePlanTags(plans);
  const options = taggedPlans.map(planToOption);
  const recommended = taggedPlans.find((plan) => plan.strategyTag === "recommended") ?? taggedPlans[0] ?? null;
  const reply = generateReply(tripRequest, taggedPlans, recommended);

  return planningResponseSchema.parse({
    sessionId: createId("session"),
    tripRequest,
    options,
    plans: taggedPlans,
    recommendedPlanId: recommended?.planId ?? null,
    reply,
    followUpQuestion,
    qwenEnhanced: false
  });
}

async function parseMessageToRequest(input: ParseInput): Promise<ParsedMessage> {
  const language = input.language ?? inferLanguage(input.message);
  const message = input.message.trim();
  const destinationText = extractDestination(message, language);
  const originText = extractOrigin(message, language);
  const budgetLimit = extractBudget(message);
  const parkingDurationHours = extractParkingDurationHours(message);
  const departureTimeIso = extractTime(message, language);
  const preferences = extractPreferences(message, language);

  const origin = originText ? await geocode(originText) : input.currentLocation ?? null;
  const destination = destinationText ? await geocode(destinationText) : null;

  const tripRequest = tripRequestSchema.parse({
    requestId: createId("trip"),
    language,
    originalMessage: message,
    origin,
    destination,
    originText: originText || input.currentLocation?.label || "",
    destinationText,
    preferences,
    constraints: {
      budgetLimit,
      parkingDurationHours,
      departureTimeIso,
      arrivalDeadlineIso: null,
      notes: message
    }
  });

  return {
    tripRequest,
    followUpQuestion: destinationText
      ? null
      : language === "zh"
        ? "你要去哪里？可以直接说目的地名称、地址，或者在地图上选点。"
        : "Where are you going? You can say the destination name, address, or pick a point on the map."
  };
}

function extractDestination(message: string, language: Language) {
  if (language === "zh") {
    const match = message.match(/(?:\u53bb|\u524d\u5f80|\u5230\u8fbe|\u5230)\s*([^\n\uff0c\u3002\uff01\uff1f\uff1b,.;]+)/);
    return match?.[1]?.trim() ?? "";
  }

  const match = message.match(/\b(?:to|going to|head to|reach)\s+([^,.!;]+)/i);
  return (match?.[1] ?? "").replace(/^(?:go|going)\s+to\s+/i, "").trim();
}

function extractOrigin(message: string, language: Language) {
  if (language === "zh") {
    const match = message.match(/\u4ece\s*([^\n\uff0c\u3002\uff01\uff1f\uff1b,.;]+?)(?:\u53bb|\u524d\u5f80|\u5230\u8fbe|\u5230|$)/);
    return match?.[1]?.trim() ?? "";
  }

  const match = message.match(/\bfrom\s+([^,.!;]+?)(?:\bto\b|\bgoing to\b|$)/i);
  return match?.[1]?.trim() ?? "";
}

function extractBudget(message: string) {
  const match = message.match(/(?:budget|under|within|less than|max budget|\u9884\u7b97|\u4e0d\u8d85\u8fc7)\s*[€$]?\s*(\d+(?:\.\d+)?)/i);
  return match ? Number(match[1]) : null;
}

function extractParkingDurationHours(message: string) {
  const match = message.match(/(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h|\u5c0f\u65f6)/i);
  return match ? Number(match[1]) : 2;
}

function extractTime(message: string, language: Language) {
  const now = new Date();

  if (language === "zh") {
    const isoLike = message.match(/(20\d{2})[-/\u5e74](\d{1,2})[-/\u6708](\d{1,2})[\u65e5\sT]*(\d{1,2})[:\u70b9\u65f6](\d{2})?/);
    if (isoLike) {
      const date = new Date(
        Number(isoLike[1]),
        Number(isoLike[2]) - 1,
        Number(isoLike[3]),
        Number(isoLike[4]),
        Number(isoLike[5] ?? "0"),
        0,
        0
      );
      return date.toISOString();
    }

    const match = message.match(/(?:\u4eca\u5929|\u4eca\u665a|\u660e\u5929|\u4e0b\u5348|\u665a\u4e0a|\u4e0a\u5348|\u65e9\u4e0a)?\s*(\d{1,2})(?::|\u70b9|\u65f6)?(\d{2})?/);
    if (!match) return null;

    let hours = Number(match[1]);
    const minutes = Number(match[2] ?? "0");
    if ((message.includes("\u4e0b\u5348") || message.includes("\u665a\u4e0a")) && hours < 12) hours += 12;
    if ((message.includes("\u4e0a\u5348") || message.includes("\u65e9\u4e0a")) && hours === 12) hours = 0;

    const date = new Date(now);
    if (message.includes("\u660e\u5929")) date.setDate(date.getDate() + 1);
    date.setHours(hours, minutes, 0, 0);
    return date.toISOString();
  }

  const match = message.match(/(\d{1,2})(?::(\d{2}))?\s*(am|pm)/i);
  if (!match) return null;

  let hours = Number(match[1]);
  const minutes = Number(match[2] ?? "0");
  const suffix = match[3].toLowerCase();
  if (suffix === "pm" && hours < 12) hours += 12;
  if (suffix === "am" && hours === 12) hours = 0;

  const date = new Date(now);
  if (/\btomorrow\b/i.test(message)) date.setDate(date.getDate() + 1);
  date.setHours(hours, minutes, 0, 0);
  return date.toISOString();
}

function extractPreferences(message: string, _language: Language): TripPreferences {
  const normalized = message.toLowerCase();

  const priority =
    /cheapest|budget|save money|\u7701\u94b1|\u4fbf\u5b9c|\u4f4e\u6210\u672c/.test(normalized)
      ? "cheapest"
      : /fastest|quick|\u6700\u5feb|\u8d76\u65f6\u95f4|\u5c3d\u5feb/.test(normalized)
        ? "fastest"
        : /comfort|comfortable|\u8212\u9002|\u5c11\u8d70|\u5c11\u6362\u4e58/.test(normalized)
          ? "comfortable"
          : /carbon|low carbon|\u73af\u4fdd|\u4f4e\u78b3/.test(normalized)
            ? "lowCarbon"
            : "balanced";

  const maxWalkingMatch = message.match(/(\d+)\s*(?:minutes?|mins?|\u5206\u949f).{0,10}(?:walk|walking|\u6b65\u884c)/i);
  const maxTransfersMatch = message.match(/(\d+)\s*(?:transfers?|\u6362\u4e58)/i);

  return {
    priority,
    maxWalkingMinutes: maxWalkingMatch ? Number(maxWalkingMatch[1]) : 20,
    maxTransfers: maxTransfersMatch ? Number(maxTransfersMatch[1]) : 2,
    comfortBias: priority === "comfortable" ? 0.9 : 0.5,
    carbonBias: priority === "lowCarbon" ? 0.9 : 0.4,
    avoidTransit: /\u4e0d\u5750\u516c\u4ea4|\u907f\u514d\u516c\u4ea4|avoid transit|no transit/.test(normalized),
    avoidDriving: /\u4e0d\u5f00\u8f66|\u907f\u514d\u5f00\u8f66|avoid driving|no driving/.test(normalized)
  };
}

async function generatePlans(request: TripRequest, parkings: ParkingRecord[]): Promise<Plan[]> {
  if (!request.destination) return [];

  const origin = request.origin ?? buildHeuristicOrigin(request.destination);
  const destination = request.destination;
  const durationHours = request.constraints.parkingDurationHours;
  const plans: Plan[] = [];

  if (!request.preferences.avoidDriving) {
    const drivingRoute = await computeDrivingRoute(origin, destination, request.constraints.departureTimeIso, request.language);
    plans.push(makeDirectDrivePlan(request, origin, destination, durationHours, drivingRoute));
  }

  if (!request.preferences.avoidTransit) {
    const transitRoute = await computeTransitRoute(
      origin,
      destination,
      request.constraints.departureTimeIso,
      request.preferences,
      request.language
    );
    plans.push(makeTransitOnlyPlan(request, origin, destination, transitRoute));
  }

  if (!request.preferences.avoidDriving && !request.preferences.avoidTransit) {
    const nearbyParkings = parkings
      .map((parking) => ({
        parking,
        distanceToDestination: haversineKm(destination, {
          latitude: parking.latitude,
          longitude: parking.longitude
        })
      }))
      .filter(({ distanceToDestination }) => distanceToDestination <= 18)
      .sort((a, b) => a.distanceToDestination - b.distanceToDestination)
      .slice(0, 4);

    const parkRidePlans = await Promise.all(
      nearbyParkings.map(async ({ parking }) => {
        try {
          return await makeParkRidePlan(request, origin, destination, parking, durationHours);
        } catch {
          return null;
        }
      })
    );

    plans.push(...parkRidePlans.filter((plan): plan is Plan => Boolean(plan)));
  }

  const ranked = plans.sort((a, b) => b.score - a.score);
  if (ranked[0]) ranked[0] = planSchema.parse({ ...ranked[0], strategyTag: "recommended" });
  return ranked;
}

function makeDirectDrivePlan(
  request: TripRequest,
  origin: LocationPoint,
  destination: LocationPoint,
  durationHours: number,
  route: Awaited<ReturnType<typeof computeDrivingRoute>>
): Plan {
  const parkingCost = estimateDowntownParkingCost(destination.label || request.destinationText, durationHours);
  const comfortScore = clamp(78 - route.distanceKm * 0.35, 25, 96);
  const carbonEstimate = route.distanceKm * 0.17;
  const totalDuration = route.durationMinutes + 8;
  const score = scorePlan({
    request,
    totalCost: parkingCost,
    totalDuration,
    comfortScore,
    carbonEstimate,
    transferCount: 0,
    walkingDuration: 6
  });

  const routeSegments = [
    ...route.segments,
    buildParkingSegment(request.language, durationHours, parkingCost, null),
    buildWalkSegment(
      request.language,
      request.language === "zh" ? "从停车位步行到目的地" : "Walk from the parking spot to the destination",
      6,
      0.35
    )
  ];

  return planSchema.parse({
    planId: createId("plan"),
    requestId: request.requestId,
    modeId: createId("mode"),
    title: request.language === "zh" ? "直接开进市区" : "Drive directly into the city",
    strategyTag: "balanced",
    parking: null,
    totalCost: parkingCost,
    parkingCost,
    transitCost: 0,
    totalDuration,
    drivingDuration: route.durationMinutes,
    transitDuration: 0,
    walkingDuration: 6,
    transferCount: 0,
    comfortScore,
    carbonEstimate,
    score,
    explanation:
      request.language === "zh"
        ? "适合短时间办事或你不想换乘的场景。现在路线使用真实道路几何，停车费用按市中心停留时长估算。"
        : "Best for short errands or when you want to avoid transfers. The route uses real road geometry, while parking is estimated from downtown dwell time.",
    steps: routeSegmentsToSteps(routeSegments),
    routePoints: [origin, destination],
    routePath: route.path,
    routeSegments,
    liveRoute: buildLiveRouteMetadata(route.provider, route.trafficAware, false, route.warnings)
  });
}

function makeTransitOnlyPlan(
  request: TripRequest,
  origin: LocationPoint,
  destination: LocationPoint,
  route: Awaited<ReturnType<typeof computeTransitRoute>>
): Plan {
  const comfortScore = clamp(88 - route.walkingDurationMinutes * 0.8 - route.transferCount * 9, 18, 90);
  const carbonEstimate = route.distanceKm * 0.05;
  const score = scorePlan({
    request,
    totalCost: route.fare,
    totalDuration: route.totalDurationMinutes,
    comfortScore,
    carbonEstimate,
    transferCount: route.transferCount,
    walkingDuration: route.walkingDurationMinutes
  });

  return planSchema.parse({
    planId: createId("plan"),
    requestId: request.requestId,
    modeId: createId("mode"),
    title: request.language === "zh" ? "全程公共交通" : "Public transit only",
    strategyTag: "balanced",
    parking: null,
    totalCost: route.fare,
    parkingCost: 0,
    transitCost: route.fare,
    totalDuration: route.totalDurationMinutes,
    drivingDuration: 0,
    transitDuration: route.transitDurationMinutes,
    walkingDuration: route.walkingDurationMinutes,
    transferCount: route.transferCount,
    comfortScore,
    carbonEstimate,
    score,
    explanation:
      request.language === "zh"
        ? route.fareIncluded
          ? "使用真实公共交通路径与票价数据。通常是最低碳方案，但步行和换乘负担可能更高。"
          : "公共交通路径可用，但当前票价或时刻数据不完整，部分结果仍带估算成分。"
        : route.fareIncluded
          ? "Uses live transit geometry and fare data. Usually the lowest-carbon option, but walking and transfers can be higher."
          : "Transit geometry is available, but fare or schedule coverage is incomplete so part of the result is still estimated.",
    steps: routeSegmentsToSteps(route.segments),
    routePoints: [origin, destination],
    routePath: route.path,
    routeSegments: route.segments,
    liveRoute: buildLiveRouteMetadata(route.provider, false, route.fareIncluded, route.warnings)
  });
}

async function makeParkRidePlan(
  request: TripRequest,
  origin: LocationPoint,
  destination: LocationPoint,
  parking: ParkingRecord,
  durationHours: number
): Promise<Plan> {
  const parkingPoint: LocationPoint = {
    label: parking.name,
    latitude: parking.latitude,
    longitude: parking.longitude
  };
  const [drivingRoute, transitRoute] = await Promise.all([
    computeDrivingRoute(origin, parkingPoint, request.constraints.departureTimeIso, request.language),
    computeTransitRoute(parkingPoint, destination, request.constraints.departureTimeIso, request.preferences, request.language)
  ]);

  const parkingCost = parking.pricePerHour ? parking.pricePerHour * durationHours : 0;
  const totalCost = parkingCost + transitRoute.fare;
  const totalDuration = drivingRoute.durationMinutes + transitRoute.totalDurationMinutes + 2;
  const comfortScore = clamp(90 - transitRoute.walkingDurationMinutes * 0.7 - transitRoute.transferCount * 7, 25, 94);
  const carbonEstimate = drivingRoute.distanceKm * 0.17 + transitRoute.distanceKm * 0.05;
  const score = scorePlan({
    request,
    totalCost,
    totalDuration,
    comfortScore,
    carbonEstimate,
    transferCount: transitRoute.transferCount,
    walkingDuration: transitRoute.walkingDurationMinutes
  });

  const routeSegments = [
    ...drivingRoute.segments,
    buildParkingSegment(request.language, durationHours, parkingCost, parking.name),
    ...transitRoute.segments
  ];
  const warnings = [...drivingRoute.warnings, ...transitRoute.warnings];
  const hasPaidParking = parking.pricePerHour !== null && parking.pricePerHour > 0;

  return planSchema.parse({
    planId: createId("plan"),
    requestId: request.requestId,
    modeId: createId("mode"),
    title: request.language === "zh" ? `停在 ${parking.name}` : `Park at ${parking.name}`,
    strategyTag: "balanced",
    parking,
    totalCost,
    parkingCost,
    transitCost: transitRoute.fare,
    totalDuration,
    drivingDuration: drivingRoute.durationMinutes,
    transitDuration: transitRoute.transitDurationMinutes,
    walkingDuration: transitRoute.walkingDurationMinutes,
    transferCount: transitRoute.transferCount,
    comfortScore,
    carbonEstimate,
    score,
    explanation:
      request.language === "zh"
        ? `适合停车换乘。${hasPaidParking ? "该停车场为收费停车。" : "该停车场停车成本较低。"}`
        : `Good park-and-ride candidate. ${hasPaidParking ? "This parking option is paid." : "Parking cost is relatively low here."}`,
    steps: routeSegmentsToSteps(routeSegments),
    routePoints: [origin, parkingPoint, destination],
    routePath: mergePaths(drivingRoute.path, transitRoute.path),
    routeSegments,
    liveRoute: buildLiveRouteMetadata(
      `${drivingRoute.provider}+${transitRoute.provider}`,
      drivingRoute.trafficAware,
      transitRoute.fareIncluded,
      warnings
    )
  });
}

function decoratePlanTags(plans: Plan[]): Plan[] {
  const copy: Plan[] = plans.map((plan) => ({ ...plan }));
  const cheapest = [...copy].sort((a, b) => a.totalCost - b.totalCost)[0];
  const fastest = [...copy].sort((a, b) => a.totalDuration - b.totalDuration)[0];
  const comfortable = [...copy].sort((a, b) => b.comfortScore - a.comfortScore)[0];
  const lowCarbon = [...copy].sort((a, b) => a.carbonEstimate - b.carbonEstimate)[0];

  return copy.map((plan) => {
    if (cheapest && plan.planId === cheapest.planId && plan.strategyTag !== "recommended") {
      return planSchema.parse({ ...plan, strategyTag: "cheapest" });
    }
    if (fastest && plan.planId === fastest.planId && plan.strategyTag !== "recommended") {
      return planSchema.parse({ ...plan, strategyTag: "fastest" });
    }
    if (comfortable && plan.planId === comfortable.planId && plan.strategyTag !== "recommended") {
      return planSchema.parse({ ...plan, strategyTag: "comfortable" });
    }
    if (lowCarbon && plan.planId === lowCarbon.planId && plan.strategyTag !== "recommended") {
      return planSchema.parse({ ...plan, strategyTag: "lowCarbon" });
    }
    return plan;
  });
}

function planToOption(plan: Plan): TravelModeOption {
  return {
    modeId: plan.modeId,
    requestId: plan.requestId,
    modeType: plan.parking ? "park-and-ride" : plan.transitDuration === 0 ? "direct-drive" : "transit-only",
    parkingRequired: Boolean(plan.parking),
    estimatedCost: plan.totalCost,
    estimatedDuration: plan.totalDuration,
    comfortScore: plan.comfortScore,
    carbonScore: plan.carbonEstimate,
    rawMetrics: {
      transfers: plan.transferCount,
      walking: plan.walkingDuration,
      score: plan.score,
      realtimeTraffic: plan.liveRoute.usesRealtimeTraffic,
      realtimeFare: plan.liveRoute.usesRealtimeTransitFare
    }
  };
}

function generateReply(request: TripRequest, plans: Plan[], recommended: Plan | null) {
  if (!recommended) {
    return request.language === "zh"
      ? "当前没有足够的数据完成规划。请尝试换一个目的地，或者放宽一些约束。"
      : "I do not have enough data to plan this trip yet. Try another destination or relax the constraints.";
  }

  const direct = plans.find((plan) => plan.title.includes("直接") || plan.title.includes("Drive directly"));
  const savings = direct ? direct.totalCost - recommended.totalCost : 0;
  const durationDelta = direct ? direct.totalDuration - recommended.totalDuration : 0;
  const realtimeNotes = recommended.liveRoute.warnings.length
    ? request.language === "zh"
      ? ` 注意：${recommended.liveRoute.warnings[0]}`
      : ` Note: ${recommended.liveRoute.warnings[0]}`
    : "";

  if (request.language === "zh") {
    return [
      `我建议你选择“${recommended.title}”。`,
      `这条方案预计总时长约 ${recommended.totalDuration} 分钟，总费用约 €${recommended.totalCost.toFixed(2)}。`,
      savings > 0
        ? `和直接开进市区相比，这条路线大约能节省 €${savings.toFixed(2)}。`
        : "和直接开进市区相比，这条路线更适合控制停车成本、步行距离或换乘压力。",
      durationDelta > 0
        ? `它还比直接开进市区快大约 ${durationDelta} 分钟。`
        : `它的舒适度评分约为 ${recommended.comfortScore.toFixed(0)}，更适合你当前的限制条件。`,
      recommended.parking
        ? "如果你只是短时间办事，也要留意停车费是否已经低于公共交通加换乘停车的总成本。"
        : "如果你只是短时间办事，直接开进市区有时反而更划算，我也把该方案保留在卡片里供你比较。",
      realtimeNotes
    ].join("");
  }

  return [
    `I recommend "${recommended.title}".`,
    `This route is estimated at about ${recommended.totalDuration} minutes in total, with an overall cost near €${recommended.totalCost.toFixed(2)}.`,
    savings > 0
      ? `Compared with driving straight into the city, it saves about €${savings.toFixed(2)}.`
      : "Compared with driving straight into the city, it better balances parking cost, walking distance, and transfer effort.",
    durationDelta > 0
      ? `It is also around ${durationDelta} minutes faster than the direct-drive option.`
      : `Its comfort score is about ${recommended.comfortScore.toFixed(0)}, which fits your current constraints.`,
    recommended.parking
      ? "If this is only a short errand, still compare the parking fee against simply driving in, because a short stay can make city-center parking cheaper than transit plus outer parking."
      : "If this is only a short errand, keep the direct-drive option in view too, because a short dwell time can sometimes beat park-and-ride on total cost.",
    realtimeNotes
  ].join(" ");
}

function buildHeuristicOrigin(destination: LocationPoint): LocationPoint {
  return {
    label: destination.label ? `${destination.label} outer approach` : "Outer approach",
    latitude: destination.latitude - 0.075,
    longitude: destination.longitude - 0.11
  };
}

function estimateDowntownParkingCost(destinationLabel: string, durationHours: number) {
  const lowered = destinationLabel.toLowerCase();
  const matchedKey = Object.keys(cityCenterParkingRate).find((key) => lowered.includes(key)) ?? "default";
  const hourlyRate = cityCenterParkingRate[matchedKey] ?? cityCenterParkingRate.default;
  return Number((hourlyRate * durationHours).toFixed(2));
}

function routeSegmentsToSteps(segments: RouteSegment[]): PlanStep[] {
  return segments.map((segment) => ({
    kind: segment.kind,
    title: segment.title,
    description: segment.description,
    durationMinutes: segment.durationMinutes,
    cost: segment.fareIncluded ? Number(segment.metadata.fare ?? 0) : 0,
    carbonKg: segment.kind === "drive" ? Number((segment.distanceKm * 0.17).toFixed(2)) : Number((segment.distanceKm * 0.05).toFixed(2))
  }));
}

function buildParkingSegment(language: Language, durationHours: number, parkingCost: number, parkingName: string | null): RouteSegment {
  return {
    segmentId: createId("segment"),
    kind: "park",
    title: language === "zh" ? "停车" : "Park the car",
    description:
      language === "zh"
        ? `${parkingName ? `${parkingName}，` : ""}预计停车 ${durationHours} 小时。`
        : `${parkingName ? `${parkingName}, ` : ""}estimated parking duration: ${durationHours} hour(s).`,
    provider: "parking-engine",
    durationMinutes: 2,
    distanceKm: 0,
    trafficAware: false,
    fareIncluded: parkingCost > 0,
    path: [],
    metadata: {
      fare: parkingCost
    }
  };
}

function buildWalkSegment(language: Language, description: string, durationMinutes: number, distanceKm: number): RouteSegment {
  return {
    segmentId: createId("segment"),
    kind: "walk",
    title: language === "zh" ? "步行抵达" : "Walk to the destination",
    description,
    provider: "walking-link",
    durationMinutes,
    distanceKm,
    trafficAware: false,
    fareIncluded: false,
    path: [],
    metadata: {}
  };
}

function buildLiveRouteMetadata(
  routeProvider: string,
  usesRealtimeTraffic: boolean,
  usesRealtimeTransitFare: boolean,
  warnings: string[]
): LiveRouteMetadata {
  return {
    routeProvider,
    usesRealtimeTraffic,
    usesRealtimeTransitFare,
    generatedAtIso: new Date().toISOString(),
    warnings
  };
}

function mergePaths(...paths: LocationPoint[][]) {
  const merged: LocationPoint[] = [];
  for (const path of paths) {
    for (const point of path) {
      const previous = merged[merged.length - 1];
      if (previous && previous.latitude === point.latitude && previous.longitude === point.longitude) {
        continue;
      }
      merged.push(point);
    }
  }
  return merged;
}

function scorePlan(input: {
  request: TripRequest;
  totalCost: number;
  totalDuration: number;
  comfortScore: number;
  carbonEstimate: number;
  transferCount: number;
  walkingDuration: number;
}) {
  const { request } = input;
  const budgetPenalty =
    request.constraints.budgetLimit && input.totalCost > request.constraints.budgetLimit
      ? (input.totalCost - request.constraints.budgetLimit) * 4
      : 0;
  const walkingPenalty = input.walkingDuration > request.preferences.maxWalkingMinutes ? 22 : 0;
  const transferPenalty = input.transferCount > request.preferences.maxTransfers ? 18 : 0;

  const priorityBonus =
    request.preferences.priority === "cheapest"
      ? -input.totalCost * 1.8
      : request.preferences.priority === "fastest"
        ? -input.totalDuration * 0.95
        : request.preferences.priority === "comfortable"
          ? input.comfortScore * 0.75
          : request.preferences.priority === "lowCarbon"
            ? -input.carbonEstimate * 14
            : 0;

  return Number(
    (
      180 -
      input.totalCost * 2.4 -
      input.totalDuration * 0.7 +
      input.comfortScore * 0.45 -
      input.carbonEstimate * 11 -
      budgetPenalty -
      walkingPenalty -
      transferPenalty +
      priorityBonus
    ).toFixed(2)
  );
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}
