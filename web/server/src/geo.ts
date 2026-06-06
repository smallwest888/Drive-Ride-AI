import { config } from "./config.js";
import type { LocationPoint } from "@drive-ride/shared";

type SearchResult = {
  display_name: string;
  lat: string;
  lon: string;
};

const cityCenters: Record<string, LocationPoint> = {
  berlin: { label: "Berlin Mitte", latitude: 52.520008, longitude: 13.404954 },
  hamburg: { label: "Hamburg", latitude: 53.551086, longitude: 9.993682 },
  munich: { label: "Munich", latitude: 48.137154, longitude: 11.576124 },
  aachen: { label: "Aachen", latitude: 50.775346, longitude: 6.083887 },
  cologne: { label: "Cologne", latitude: 50.937531, longitude: 6.960279 },
  london: { label: "London", latitude: 51.507218, longitude: -0.127586 }
};

export async function geocode(query: string): Promise<LocationPoint | null> {
  const normalized = query.trim();
  if (!normalized) return null;

  try {
    const url = new URL("https://nominatim.openstreetmap.org/search");
    url.searchParams.set("q", normalized);
    url.searchParams.set("format", "jsonv2");
    url.searchParams.set("limit", "1");

    const response = await fetch(url, {
      headers: {
        "User-Agent": config.userAgent
      }
    });

    if (response.ok) {
      const data = (await response.json()) as SearchResult[];
      const first = data[0];
      if (first) {
        return {
          label: first.display_name,
          latitude: Number(first.lat),
          longitude: Number(first.lon)
        };
      }
    }
  } catch {
    // Fall through to city-center heuristics.
  }

  const lowered = normalized.toLowerCase();
  const fallbackEntry = Object.entries(cityCenters).find(([key]) => lowered.includes(key));
  return fallbackEntry?.[1] ?? null;
}

export async function searchLocations(query: string) {
  const normalized = query.trim();
  if (!normalized) return [];

  try {
    const url = new URL("https://nominatim.openstreetmap.org/search");
    url.searchParams.set("q", normalized);
    url.searchParams.set("format", "jsonv2");
    url.searchParams.set("limit", "6");

    const response = await fetch(url, {
      headers: {
        "User-Agent": config.userAgent
      }
    });

    if (!response.ok) return [];

    const data = (await response.json()) as SearchResult[];
    return data.map((entry) => ({
      label: entry.display_name,
      latitude: Number(entry.lat),
      longitude: Number(entry.lon)
    }));
  } catch {
    return [];
  }
}

export function haversineKm(a: { latitude: number; longitude: number }, b: { latitude: number; longitude: number }) {
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
