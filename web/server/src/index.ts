import express from "express";
import cors from "cors";
import multer from "multer";
import { z } from "zod";
import { config } from "./config.js";
import { deleteParking, getAllActiveParkings, getParkingStats, upsertParking } from "./db.js";
import { runClawdbotTravelAgent, runDirectPlanningService } from "./agent.js";
import { searchLocations } from "./geo.js";
import { synthesizeSpeech, transcribeAudio } from "./qwen.js";
import { parkingWriteSchema, type Language } from "@drive-ride/shared";

const app = express();
const upload = multer();

app.use(
  cors({
    origin: [config.frontendOrigin, "http://localhost:3001"],
    credentials: true
  })
);
app.use(express.json({ limit: "4mb" }));
app.use(express.urlencoded({ extended: true }));

app.get("/api/health", (_req, res) => {
  res.json({
    status: "ok",
    service: "drive-ride-api",
    dbPath: config.dbPath
  });
});

app.get("/api/parkings", (_req, res) => {
  res.json(getAllActiveParkings());
});

app.get("/api/admin/stats", (_req, res) => {
  res.json(getParkingStats());
});

app.post("/api/parkings", (req, res) => {
  const parsed = parkingWriteSchema.safeParse({
    ...req.body,
    id: req.body.id ? Number(req.body.id) : 0,
    latitude: Number(req.body.latitude),
    longitude: Number(req.body.longitude),
    totalSpaces: Number(req.body.totalSpaces),
    pricePerHour: req.body.pricePerHour === "" || req.body.pricePerHour === null ? null : Number(req.body.pricePerHour),
    isActive: req.body.isActive !== false && req.body.isActive !== "false"
  });

  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  const parking = upsertParking(parsed.data);
  res.json(parking);
});

app.put("/api/parkings/:id", (req, res) => {
  const parsed = parkingWriteSchema.safeParse({
    ...req.body,
    id: Number(req.params.id),
    latitude: Number(req.body.latitude),
    longitude: Number(req.body.longitude),
    totalSpaces: Number(req.body.totalSpaces),
    pricePerHour: req.body.pricePerHour === "" || req.body.pricePerHour === null ? null : Number(req.body.pricePerHour),
    isActive: req.body.isActive !== false && req.body.isActive !== "false"
  });

  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  const parking = upsertParking(parsed.data);
  res.json(parking);
});

app.delete("/api/parkings/:id", (req, res) => {
  res.json({ success: deleteParking(Number(req.params.id)) });
});

app.get("/api/geo/search", async (req, res) => {
  const query = String(req.query.q ?? "");
  res.json(await searchLocations(query));
});

app.post("/api/planning/query", async (req, res) => {
  const requestSchema = z.object({
    message: z.string().min(1),
    language: z.enum(["zh", "en"]).optional(),
    currentLocation: z
      .object({
        label: z.string(),
        latitude: z.number(),
        longitude: z.number()
      })
      .nullable()
      .optional()
  });

  const parsed = requestSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  try {
    const response = await runClawdbotTravelAgent(parsed.data);
    res.json(response);
  } catch (error) {
    res.status(500).json({
      error: error instanceof Error ? error.message : "planning_failed"
    });
  }
});

app.post("/internal/plan-trip", async (req, res) => {
  const requestSchema = z.object({
    message: z.string().min(1),
    language: z.enum(["zh", "en"]).optional(),
    currentLocation: z
      .object({
        label: z.string(),
        latitude: z.number(),
        longitude: z.number()
      })
      .nullable()
      .optional()
  });

  if (req.headers["x-drive-ride-internal"] !== "true") {
    return res.status(403).json({ error: "forbidden" });
  }

  const parsed = requestSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  try {
    const response = await runDirectPlanningService(parsed.data);
    res.json(response);
  } catch (error) {
    res.status(500).json({
      error: error instanceof Error ? error.message : "planning_failed"
    });
  }
});

app.post("/api/voice/transcribe", upload.single("audio"), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: "audio file is required" });
  }

  try {
    const language = req.body.language === "en" || req.body.language === "zh" ? req.body.language : undefined;
    const text = await transcribeAudio(
      req.file.buffer,
      req.file.originalname || "prompt.webm",
      req.file.mimetype,
      language
    );
    res.json({ text });
  } catch (error) {
    res.status(501).json({
      error: error instanceof Error ? error.message : "ASR unavailable",
      fallback: "text"
    });
  }
});

app.post("/api/voice/speak", async (req, res) => {
  const requestSchema = z.object({
    text: z.string().min(1),
    language: z.enum(["zh", "en"]).default("zh")
  });
  const parsed = requestSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  try {
    const audio = await synthesizeSpeech(parsed.data.text, parsed.data.language as Language);
    res.json({ audio });
  } catch (error) {
    res.status(501).json({
      error: error instanceof Error ? error.message : "TTS unavailable",
      fallback: "text"
    });
  }
});

app.listen(config.port, () => {
  console.log(`Drive&Ride API listening on http://localhost:${config.port}`);
});
