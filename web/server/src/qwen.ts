import OpenAI from "openai";
import type { Language } from "@drive-ride/shared";
import { config } from "./config.js";

const client = config.qwenApiKey
  ? new OpenAI({
      apiKey: config.qwenApiKey,
      baseURL: config.qwenBaseUrl
    })
  : null;

export function qwenConfigured() {
  return Boolean(client);
}

export async function polishReply(language: Language, draft: string, contextSummary: string) {
  if (!client) {
    return { text: draft, enhanced: false };
  }

  const systemPrompt =
    language === "zh"
      ? "你是一个出行规划助手。请基于给定的结构化摘要，把回复润色成简洁、具体、可解释的中文，不要编造新的停车场名称、时长或费用。"
      : "You are a travel planning assistant. Rewrite the provided structured summary into concise, specific, explainable English. Do not invent any new parking names, durations, or costs.";

  const completion = await client.chat.completions.create({
    model: config.qwenModel,
    temperature: 0.35,
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: `Draft reply:\n${draft}\n\nContext summary:\n${contextSummary}` }
    ]
  });

  const text = completion.choices[0]?.message?.content?.trim();
  return {
    text: text || draft,
    enhanced: Boolean(text)
  };
}

export async function synthesizeSpeech(text: string, language: Language) {
  if (!config.qwenApiKey) {
    throw new Error("Qwen TTS is not configured.");
  }

  const candidates = buildTtsCandidates(language);
  let lastError: Error | null = null;

  for (const candidate of candidates) {
    try {
      return await requestTtsAudio(text, language, candidate.model, candidate.voice);
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
    }
  }

  throw lastError ?? new Error("Qwen TTS failed for all configured model candidates.");
}

export async function transcribeAudio(
  fileBuffer: Buffer,
  filename: string,
  mimeType: string,
  language?: Language
) {
  if (!client) {
    throw new Error("Qwen ASR is not configured.");
  }

  const audioMimeType = mimeType || inferAudioMimeType(filename) || "audio/webm";
  const dataUri = `data:${audioMimeType};base64,${fileBuffer.toString("base64")}`;

  const completion = await client.chat.completions.create(
    {
      model: config.qwenAsrModel,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "input_audio",
              input_audio: {
                data: dataUri
              }
            }
          ]
        }
      ],
      extra_body: {
        asr_options: {
          ...(language ? { language } : {}),
          enable_itn: false
        }
      }
    } as any
  );

  const text = completion.choices[0]?.message?.content;
  if (typeof text === "string") {
    return text.trim();
  }

  throw new Error("Qwen ASR returned no transcript.");
}

function inferAudioMimeType(filename: string) {
  const lowered = filename.toLowerCase();
  if (lowered.endsWith(".mp3")) return "audio/mpeg";
  if (lowered.endsWith(".wav")) return "audio/wav";
  if (lowered.endsWith(".m4a")) return "audio/mp4";
  if (lowered.endsWith(".ogg")) return "audio/ogg";
  if (lowered.endsWith(".webm")) return "audio/webm";
  return null;
}

function buildTtsCandidates(language: Language) {
  if (language === "zh") {
    return dedupeTtsCandidates([
      { model: "qwen3-tts-instruct-flash", voice: config.qwenTtsVoiceZh },
      { model: config.qwenTtsModelZh, voice: config.qwenTtsVoiceZh },
      { model: config.qwenTtsModel, voice: config.qwenTtsVoiceZh },
      { model: "qwen-tts", voice: "Cherry" }
    ]);
  }

  return dedupeTtsCandidates([
    { model: config.qwenTtsModelEn, voice: config.qwenTtsVoiceEn },
    { model: config.qwenTtsModel, voice: config.qwenTtsVoiceEn }
  ]);
}

function dedupeTtsCandidates(candidates: Array<{ model: string; voice: string }>) {
  const seen = new Set<string>();
  return candidates.filter((candidate) => {
    const key = `${candidate.model}::${candidate.voice}`;
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

async function requestTtsAudio(text: string, language: Language, model: string, voice: string) {
  const response = await fetch(config.qwenTtsUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.qwenApiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model,
      input: {
        text,
        voice,
        language_type: language === "zh" ? "Chinese" : "English"
      }
    })
  });

  if (!response.ok) {
    const failureText = await response.text();
    throw new Error(`Qwen TTS request failed for ${model}/${voice}: ${response.status} ${failureText}`);
  }

  const payload = (await response.json()) as {
    output?: { audio?: { url?: string; data?: string } };
  };

  const audio = payload.output?.audio ?? null;
  if (!audio?.url && !audio?.data) {
    throw new Error(`Qwen TTS returned no audio payload for ${model}/${voice}.`);
  }

  return audio;
}
