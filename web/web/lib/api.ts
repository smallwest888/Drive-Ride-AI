import type { Language, LocationPoint, ParkingRecord, PlanningResponse } from "@drive-ride/shared";

const configuredBasePath = process.env.NEXT_PUBLIC_BASE_PATH ?? "";
const basePath =
  configuredBasePath && configuredBasePath !== "/"
    ? configuredBasePath.startsWith("/")
      ? configuredBasePath
      : `/${configuredBasePath}`
    : "";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL ?? `${basePath || ""}/api`;

export async function fetchPlanning(message: string, language: Language, currentLocation?: LocationPoint | null) {
  const response = await fetch(`${API_BASE}/planning/query`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      message,
      language,
      currentLocation: currentLocation ?? null
    })
  });

  if (!response.ok) {
    throw new Error("Planning request failed.");
  }

  return (await response.json()) as PlanningResponse;
}

export async function transcribeAudio(blob: Blob, language: Language) {
  const formData = new FormData();
  formData.append("audio", blob, "prompt.webm");
  formData.append("language", language);
  const response = await fetch(`${API_BASE}/voice/transcribe`, {
    method: "POST",
    body: formData
  });
  return response.json();
}

export async function requestSpeech(text: string, language: Language) {
  const response = await fetch(`${API_BASE}/voice/speak`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ text, language })
  });
  return response.json();
}

export async function fetchStats() {
  const response = await fetch(`${API_BASE}/admin/stats`, { cache: "no-store" });
  return response.json();
}

export async function fetchParkings() {
  const response = await fetch(`${API_BASE}/parkings`, { cache: "no-store" });
  return (await response.json()) as ParkingRecord[];
}

export async function saveParking(parking: Partial<ParkingRecord>) {
  const response = await fetch(`${API_BASE}/parkings${parking.id ? `/${parking.id}` : ""}`, {
    method: parking.id ? "PUT" : "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(parking)
  });
  return response.json();
}

export async function removeParking(id: number) {
  const response = await fetch(`${API_BASE}/parkings/${id}`, {
    method: "DELETE"
  });
  return response.json();
}
