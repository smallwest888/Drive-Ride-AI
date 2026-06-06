import path from "node:path";
import fs from "node:fs";
import dotenv from "dotenv";

dotenv.config();

const rootDir = path.resolve(process.cwd(), "..");
const explicitDbPath = process.env.DB_PATH;
const dbCandidates = [
  explicitDbPath,
  path.join(rootDir, "data", "prparking.db"),
  path.join(rootDir, "CityDriveRide", "prparking.db"),
  path.join(process.cwd(), "prparking.db")
].filter(Boolean) as string[];

export const config = {
  port: Number(process.env.PORT ?? 3000),
  frontendOrigin: process.env.FRONTEND_ORIGIN ?? "http://localhost:3001",
  dbPath: dbCandidates.find((candidate) => fs.existsSync(candidate)) ?? dbCandidates[0],
  openClawBaseUrl: process.env.OPENCLAW_BASE_URL ?? "http://127.0.0.1:18789",
  openClawToken: process.env.OPENCLAW_TOKEN ?? "drive-ride-openclaw-local-token",
  qwenApiKey: process.env.QWEN_API_KEY ?? process.env.DASHSCOPE_API_KEY ?? "",
  qwenBaseUrl: process.env.QWEN_BASE_URL ?? "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
  qwenModel: process.env.QWEN_MODEL ?? "qwen-plus",
  qwenAsrUrl: process.env.QWEN_ASR_URL ?? "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/audio/transcriptions",
  qwenAsrModel: process.env.QWEN_ASR_MODEL ?? "qwen3-asr-flash",
  qwenTtsUrl:
    process.env.QWEN_TTS_URL ??
    "https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation",
  qwenTtsModel: process.env.QWEN_TTS_MODEL ?? "qwen3-tts-flash",
  qwenTtsModelZh: process.env.QWEN_TTS_MODEL_ZH ?? "qwen-tts",
  qwenTtsModelEn: process.env.QWEN_TTS_MODEL_EN ?? "qwen3-tts-flash",
  qwenTtsVoiceZh: process.env.QWEN_TTS_VOICE_ZH ?? "Cherry",
  qwenTtsVoiceEn: process.env.QWEN_TTS_VOICE_EN ?? "Serena",
  googleMapsApiKey: process.env.GOOGLE_MAPS_API_KEY ?? "",
  googleRoutesUrl: process.env.GOOGLE_ROUTES_URL ?? "https://routes.googleapis.com/directions/v2:computeRoutes",
  osrmBaseUrl: process.env.OSRM_BASE_URL ?? "https://router.project-osrm.org",
  userAgent: "DriveRidePlanner/1.0 (contact: local-dev)"
};
