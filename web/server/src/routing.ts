import {
  createId,
  type Language,
  type LocationPoint,
  type RouteSegment,
  type TripPreferences
} from "@drive-ride/shared";
import { config } from "./config.js";

type DrivingRouteResult = {
  provider: string;
  distanceKm: number;
  durationMinutes: number;
  staticDurationMinutes: number;
  path: LocationPoint[];
  segments: RouteSegment[];
  trafficAware: boolean;
  warnings: string[];
};

type TransitRouteResult = {
  provider: string;
  distanceKm: number;
  totalDurationMinutes: number;
  transitDurationMinutes: number;
  walkingDurationMinutes: number;
  transferCount: number;
  fare: number;
  fareIncluded: boolean;
  path: LocationPoint[];
  segments: RouteSegment[];
  warnings: string[];
};

type GoogleComputeRouteResponse = {
  routes?: Array<{
    duration?: string;
    distanceMeters?: number;
    polyline?: { encodedPolyline?: string };
    localizedValues?: {
      transitFare?: { text?: string };
    };
    travelAdvisory?: {
      transitFare?: {
        currencyCode?: string;
        units?: string;
        nanos?: number;
      };
      speedReadingIntervals?: Array<{ speed?: string }>;
    };
    legs?: Array<{
      steps?: Array<{
        distanceMeters?: number;
        staticDuration?: string;
        duration?: string;
        travelMode?: string;
        polyline?: { encodedPolyline?: string };
        navigationInstruction?: { instructions?: string };
        transitDetails?: {
          headsign?: string;
          stopCount?: number;
          transitLine?: {
            name?: string;
            nameShort?: string;
            vehicle?: { type?: string; name?: { text?: string } };
            agencies?: Array<{ name?: string }>;
          };
          stopDetails?: {
            departureStop?: {
              name?: string;
              location?: { latLng?: { latitude?: number; longitude?: number } };
            };
            arrivalStop?: {
              name?: string;
              location?: { latLng?: { latitude?: number; longitude?: number } };
            };
          };
        };
      }>;
    }>;
  }>;
};

type OsrmRouteResponse = {
  routes?: Array<{
    geometry?: string;
    distance?: number;
    duration?: number;
    legs?: Array<{
      steps?: Array<{
        geometry?: string;
        distance?: number;
        duration?: number;
        name?: string;
        maneuver?: {
          type?: string;
          modifier?: string;
        };
      }>;
    }>;
  }>;
};

export async function computeDrivingRoute(
  origin: LocationPoint,
  destination: LocationPoint,
  departureTimeIso: string | null,
  language: Language
): Promise<DrivingRouteResult> {
  if (config.googleMapsApiKey) {
    try {
      return await computeGoogleDrivingRoute(origin, destination, departureTimeIso, language);
    } catch (error) {
      const fallback = await computeOsrmDrivingRoute(origin, destination, language);
      return {
        ...fallback,
        warnings: [
          formatProviderError(language, "Google Routes", error),
          ...fallback.warnings
        ]
      };
    }
  }

  return computeOsrmDrivingRoute(origin, destination, language);
}

export async function computeTransitRoute(
  origin: LocationPoint,
  destination: LocationPoint,
  departureTimeIso: string | null,
  preferences: TripPreferences,
  language: Language
): Promise<TransitRouteResult> {
  if (!config.googleMapsApiKey) {
    return buildHeuristicTransitRoute(origin, destination, preferences, language, [
      language === "zh"
        ? "暂时无法获取实时公交票价和班次，已为你提供可靠的估算方案。"
        : "Google Routes API is not configured, so transit fare and schedule data are still heuristic."
    ]);
  }

  try {
    return await computeGoogleTransitRoute(origin, destination, departureTimeIso, preferences, language);
  } catch (error) {
    return buildHeuristicTransitRoute(origin, destination, preferences, language, [
      formatProviderError(language, "Google Routes", error)
    ]);
  }
}

function buildHeuristicTransitRoute(
  origin: LocationPoint,
  destination: LocationPoint,
  preferences: TripPreferences,
  language: Language,
  warnings: string[]
): TransitRouteResult {
  const directDistanceKm = haversineKm(origin, destination);
  const transitDurationMinutes = Math.round((directDistanceKm / 23) * 60 + 12);
  const walkingDurationMinutes = Math.round(Math.max(8, directDistanceKm * 0.45));
  const transferCount = directDistanceKm > 15 ? 2 : directDistanceKm > 7 ? 1 : 0;
  const fare = clamp(2.8 + directDistanceKm * 0.22, 2.5, 14);
  const path = [origin, destination];
  const segments: RouteSegment[] = [
    {
      segmentId: createId("segment"),
      kind: "transit",
      title: language === "zh" ? "公共交通（估算）" : "Public transit (estimated)",
      description:
        language === "zh"
          ? `按当前偏好估算，预计需要换乘 ${transferCount} 次。`
          : `Estimated for priority ${preferences.priority}, with about ${transferCount} transfer(s).`,
      provider: "heuristic-transit",
      durationMinutes: transitDurationMinutes,
      distanceKm: directDistanceKm,
      trafficAware: false,
      fareIncluded: false,
      path,
      metadata: {
        transferCount,
        fare
      }
    }
  ];

  return {
    provider: "heuristic-transit",
    distanceKm: directDistanceKm,
    totalDurationMinutes: transitDurationMinutes + walkingDurationMinutes,
    transitDurationMinutes,
    walkingDurationMinutes,
    transferCount,
    fare,
    fareIncluded: false,
    path,
    segments,
    warnings
  };
}

async function computeGoogleDrivingRoute(
  origin: LocationPoint,
  destination: LocationPoint,
  departureTimeIso: string | null,
  language: Language
): Promise<DrivingRouteResult> {
  const data = await fetchGoogleRoute(
    {
      origin: toWaypoint(origin),
      destination: toWaypoint(destination),
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_AWARE_OPTIMAL",
      departureTime: departureTimeIso ?? new Date().toISOString(),
      extraComputations: ["TRAFFIC_ON_POLYLINE"]
    },
    [
      "routes.duration",
      "routes.distanceMeters",
      "routes.polyline.encodedPolyline",
      "routes.legs.steps.distanceMeters",
      "routes.legs.steps.duration",
      "routes.legs.steps.staticDuration",
      "routes.legs.steps.polyline.encodedPolyline",
      "routes.legs.steps.navigationInstruction.instructions",
      "routes.travelAdvisory.speedReadingIntervals"
    ]
  );

  const route = data.routes?.[0];
  if (!route) {
    throw new Error("No driving route returned.");
  }

  const steps = route.legs?.flatMap((leg) => leg.steps ?? []) ?? [];
  const path = decodePolylineToPoints(route.polyline?.encodedPolyline, language);
  const segments = steps.map((step, index) => ({
    segmentId: createId("segment"),
    kind: "drive" as const,
    title: language === "zh" ? `驾车路段 ${index + 1}` : `Driving step ${index + 1}`,
    description: step.navigationInstruction?.instructions || (language === "zh" ? "请沿导航继续前进。" : "Follow the road guidance."),
    provider: "google-routes",
    durationMinutes: secondsToMinutes(step.duration ?? step.staticDuration),
    distanceKm: metersToKm(step.distanceMeters),
    trafficAware: true,
    fareIncluded: false,
    path: decodePolylineToPoints(step.polyline?.encodedPolyline, language),
    metadata: {}
  }));

  return {
    provider: "google-routes",
    distanceKm: metersToKm(route.distanceMeters),
    durationMinutes: secondsToMinutes(route.duration),
    staticDurationMinutes: sumBy(steps, (step) => secondsToMinutes(step.staticDuration)),
    path,
    segments,
    trafficAware: true,
    warnings: []
  };
}

async function computeGoogleTransitRoute(
  origin: LocationPoint,
  destination: LocationPoint,
  departureTimeIso: string | null,
  preferences: TripPreferences,
  language: Language
): Promise<TransitRouteResult> {
  const requestBody = {
    origin: toWaypoint(origin),
    destination: toWaypoint(destination),
    travelMode: "TRANSIT",
    computeAlternativeRoutes: true,
    departureTime: departureTimeIso ?? new Date().toISOString(),
    transitPreferences: {
      routingPreference: preferences.maxTransfers <= 1 ? "FEWER_TRANSFERS" : "LESS_WALKING",
      allowedTravelModes: ["BUS", "SUBWAY", "TRAIN", "LIGHT_RAIL", "RAIL"]
    }
  };

  const data = await fetchGoogleRoute(requestBody, [
    "routes.duration",
    "routes.distanceMeters",
    "routes.polyline.encodedPolyline",
    "routes.localizedValues.transitFare",
    "routes.travelAdvisory.transitFare",
    "routes.legs.steps.distanceMeters",
    "routes.legs.steps.staticDuration",
    "routes.legs.steps.travelMode",
    "routes.legs.steps.polyline.encodedPolyline",
    "routes.legs.steps.navigationInstruction.instructions",
    "routes.legs.steps.transitDetails"
  ]);

  const route = data.routes?.[0];
  if (!route) {
    throw new Error("No transit route returned.");
  }

  const steps = route.legs?.flatMap((leg) => leg.steps ?? []) ?? [];
  const path = decodePolylineToPoints(route.polyline?.encodedPolyline, language);
  const segments: RouteSegment[] = [];
  let transitDurationMinutes = 0;
  let walkingDurationMinutes = 0;
  let transitLegCount = 0;

  for (const [index, step] of steps.entries()) {
    const durationMinutes = secondsToMinutes(step.staticDuration ?? step.duration);
    const distanceKm = metersToKm(step.distanceMeters);
    const travelMode = step.travelMode ?? "WALK";
    const stepPath = decodePolylineToPoints(step.polyline?.encodedPolyline, language);

    if (travelMode === "TRANSIT") {
      transitLegCount += 1;
      transitDurationMinutes += durationMinutes;
      const line =
        step.transitDetails?.transitLine?.nameShort ||
        step.transitDetails?.transitLine?.name ||
        step.transitDetails?.transitLine?.vehicle?.name?.text ||
        "Transit";
      const headsign = step.transitDetails?.headsign || "";
      const agency = step.transitDetails?.transitLine?.agencies?.[0]?.name || "";
      const departureStop = step.transitDetails?.stopDetails?.departureStop?.name || "";
      const arrivalStop = step.transitDetails?.stopDetails?.arrivalStop?.name || "";

      segments.push({
        segmentId: createId("segment"),
        kind: "transit",
        title: language === "zh" ? `乘坐 ${line}` : `Take ${line}`,
        description:
          language === "zh"
            ? [headsign, departureStop && arrivalStop ? `${departureStop} -> ${arrivalStop}` : "", agency]
                .filter(Boolean)
                .join(" | ")
            : [headsign, departureStop && arrivalStop ? `${departureStop} -> ${arrivalStop}` : "", agency]
                .filter(Boolean)
                .join(" | "),
        provider: "google-routes",
        durationMinutes,
        distanceKm,
        trafficAware: false,
        fareIncluded: true,
        path: stepPath,
        metadata: {
          stopCount: step.transitDetails?.stopCount ?? 0
        }
      });
      continue;
    }

    walkingDurationMinutes += durationMinutes;
    segments.push({
      segmentId: createId("segment"),
      kind: "walk",
      title: language === "zh" ? `步行路段 ${index + 1}` : `Walking step ${index + 1}`,
      description: step.navigationInstruction?.instructions || (language === "zh" ? "请步行前往下一段接驳点。" : "Walk to the next connection."),
      provider: "google-routes",
      durationMinutes,
      distanceKm,
      trafficAware: false,
      fareIncluded: false,
      path: stepPath,
      metadata: {}
    });
  }

  const fare = parseGoogleFare(route.travelAdvisory?.transitFare);

  return {
    provider: "google-routes",
    distanceKm: metersToKm(route.distanceMeters),
    totalDurationMinutes: secondsToMinutes(route.duration),
    transitDurationMinutes,
    walkingDurationMinutes,
    transferCount: Math.max(0, transitLegCount - 1),
    fare,
    fareIncluded: fare > 0,
    path,
    segments,
    warnings: fare > 0 ? [] : [language === "zh" ? "票价信息暂未完整返回，实际支付金额可能会有细微差异。" : "Complete fare data was not returned, so the final amount may vary slightly."]
  };
}

async function computeOsrmDrivingRoute(
  origin: LocationPoint,
  destination: LocationPoint,
  language: Language
): Promise<DrivingRouteResult> {
  const coordinates = `${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}`;
  const url = `${config.osrmBaseUrl}/route/v1/driving/${coordinates}?overview=full&geometries=polyline&steps=true`;
  const response = await fetch(url, {
    headers: {
      "User-Agent": config.userAgent
    }
  });

  if (!response.ok) {
    throw new Error(`OSRM returned ${response.status}.`);
  }

  const data = (await response.json()) as OsrmRouteResponse;
  const route = data.routes?.[0];
  if (!route) {
    throw new Error("No OSRM route returned.");
  }

  const steps = route.legs?.flatMap((leg) => leg.steps ?? []) ?? [];
  const path = decodePolylineToPoints(route.geometry, language);
  const segments = steps.map((step, index) => ({
    segmentId: createId("segment"),
    kind: "drive" as const,
    title: language === "zh" ? `驾车路段 ${index + 1}` : `Driving step ${index + 1}`,
    description: formatOsrmInstruction(step, language),
    provider: "osrm",
    durationMinutes: Math.round((step.duration ?? 0) / 60),
    distanceKm: metersToKm(step.distance),
    trafficAware: false,
    fareIncluded: false,
    path: decodePolylineToPoints(step.geometry, language),
    metadata: {}
  }));

  return {
    provider: "osrm",
    distanceKm: metersToKm(route.distance),
    durationMinutes: Math.round((route.duration ?? 0) / 60),
    staticDurationMinutes: Math.round((route.duration ?? 0) / 60),
    path,
    segments,
    trafficAware: false,
    warnings: [
      language === "zh"
        ? "当前时长为常规估算，实际通行时间可能会随着路况变化。"
        : "A realtime traffic provider is not configured, so the driving path is real road geometry but the duration is not traffic-aware."
    ]
  };
}

async function fetchGoogleRoute(body: Record<string, unknown>, fieldMask: string[]) {
  const response = await fetch(config.googleRoutesUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": config.googleMapsApiKey,
      "X-Goog-FieldMask": fieldMask.join(",")
    },
    body: JSON.stringify(body)
  });

  if (!response.ok) {
    throw new Error(`Google Routes returned ${response.status}: ${await response.text()}`);
  }

  return (await response.json()) as GoogleComputeRouteResponse;
}

function toWaypoint(point: LocationPoint) {
  return {
    location: {
      latLng: {
        latitude: point.latitude,
        longitude: point.longitude
      }
    }
  };
}

function decodePolylineToPoints(encoded: string | undefined, language: Language) {
  if (!encoded) return [];
  const points: LocationPoint[] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;

  while (index < encoded.length) {
    let result = 0;
    let shift = 0;
    let byte: number;

    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length + 1);

    const deltaLat = result & 1 ? ~(result >> 1) : result >> 1;
    lat += deltaLat;

    result = 0;
    shift = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length + 1);

    const deltaLng = result & 1 ? ~(result >> 1) : result >> 1;
    lng += deltaLng;

    points.push({
      label: language === "zh" ? "路径点" : "Route point",
      latitude: lat / 1e5,
      longitude: lng / 1e5
    });
  }

  return points;
}

function parseGoogleFare(
  fare:
    | {
        units?: string;
        nanos?: number;
      }
    | undefined
) {
  if (!fare) return 0;
  return Number(((Number(fare.units ?? "0") || 0) + (fare.nanos ?? 0) / 1_000_000_000).toFixed(2));
}

function formatOsrmInstruction(
  step: {
    name?: string;
    maneuver?: { type?: string; modifier?: string };
  },
  language: Language
) {
  const name = step.name?.trim();
  const type = step.maneuver?.type ?? "continue";
  const modifier = step.maneuver?.modifier ?? "";

  if (language === "zh") {
    if (name) return `沿 ${name} 行驶${modifier ? `（${modifier}）` : ""}`;
    return `请沿道路继续行驶${modifier ? `（${modifier}）` : ""}`;
  }

  if (name) return `${type} onto ${name}${modifier ? ` (${modifier})` : ""}`;
  return `Continue driving (${type}${modifier ? `/${modifier}` : ""})`;
}

function parseDurationSeconds(value: string | undefined) {
  if (!value) return 0;
  const normalized = value.endsWith("s") ? value.slice(0, -1) : value;
  return Number(normalized) || 0;
}

function secondsToMinutes(value: string | undefined) {
  return Math.round(parseDurationSeconds(value) / 60);
}

function metersToKm(value: number | undefined) {
  return Number((((value ?? 0) / 1000) || 0).toFixed(2));
}

function sumBy<T>(values: T[], iteratee: (value: T) => number) {
  return values.reduce((total, value) => total + iteratee(value), 0);
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

function formatProviderError(language: Language, provider: string, error: unknown) {
  const detail = error instanceof Error ? error.message : String(error);
  return language === "zh" ? `${provider} 暂时无法使用：${detail}` : `${provider} failed: ${detail}`;
}

function haversineKm(a: { latitude: number; longitude: number }, b: { latitude: number; longitude: number }) {
  const toRad = (value: number) => (value * Math.PI) / 180;
  const earthRadiusKm = 6371;
  const dLat = toRad(b.latitude - a.latitude);
  const dLng = toRad(b.longitude - a.longitude);
  const lat1 = toRad(a.latitude);
  const lat2 = toRad(b.latitude);
  const sinLat = Math.sin(dLat / 2);
  const sinLng = Math.sin(dLng / 2);
  const h = sinLat * sinLat + Math.cos(lat1) * Math.cos(lat2) * sinLng * sinLng;
  return 2 * earthRadiusKm * Math.asin(Math.sqrt(h));
}

