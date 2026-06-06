"use client";

import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { Language, LocationPoint, Plan, PlanningResponse, RouteSegment } from "@drive-ride/shared";
import { formatCurrency } from "@drive-ride/shared";
import {
  CarFront,
  ChevronRight,
  Globe2,
  Languages,
  LoaderCircle,
  LocateFixed,
  MapPinned,
  Menu,
  Mic,
  Route,
  Settings2,
  SlidersHorizontal,
  Sparkles,
  Square,
  TrainFront,
  Volume2,
  Waves,
  X
} from "lucide-react";
import { fetchPlanning, requestSpeech, transcribeAudio } from "@/lib/api";
import {
  cleanPlanSummary,
  cleanPlanTitle,
  cleanSegmentDescription,
  cleanSegmentTitle,
  dictionaries,
  packageLabel,
  summarizePlans
} from "@/lib/i18n";
import { PlanetMap } from "./planet-map";

type MenuSection = "tripRequest" | "origin" | "destination" | "requirements" | "settings" | "language";
type VoiceMode = "idle" | "listening" | "review" | "processing";
type Priority = "balanced" | "cheapest" | "fastest" | "comfortable" | "lowCarbon";

export function PlannerApp() {
  const [language, setLanguage] = useState<Language>("en");
  const [menuOpen, setMenuOpen] = useState(false);
  const [routeDrawerOpen, setRouteDrawerOpen] = useState(false);
  const [activeSection, setActiveSection] = useState<MenuSection>("tripRequest");
  const [tripRequestInput, setTripRequestInput] = useState("");
  const [originInput, setOriginInput] = useState("");
  const [destinationInput, setDestinationInput] = useState("");
  const [requirementsInput, setRequirementsInput] = useState("");
  const [budgetInput, setBudgetInput] = useState("");
  const [departureInput, setDepartureInput] = useState("");
  const [parkingDurationInput, setParkingDurationInput] = useState("2");
  const [priority, setPriority] = useState<Priority>("balanced");
  const [useDeviceLocation, setUseDeviceLocation] = useState(true);
  const [autoSpeakReply, setAutoSpeakReply] = useState(true);
  const [loading, setLoading] = useState(false);
  const [currentLocation, setCurrentLocation] = useState<LocationPoint | null>(null);
  const [locationStatus, setLocationStatus] = useState("");
  const [voiceMode, setVoiceMode] = useState<VoiceMode>("idle");
  const [voiceTranscript, setVoiceTranscript] = useState("");
  const [voiceStatus, setVoiceStatus] = useState("");
  const [response, setResponse] = useState<PlanningResponse | null>(null);
  const [activePlan, setActivePlan] = useState<Plan | null>(null);
  const [subtitle, setSubtitle] = useState("");
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const chunksRef = useRef<Blob[]>([]);

  const t = dictionaries[language];
  const plans = response ? summarizePlans(response).packageCards : [];

  useEffect(() => {
    requestCurrentLocation(true).catch(() => undefined);
  }, []);

  useEffect(() => {
    if (!response) return;

    const recommendation = summarizePlans(response).recommendation;
    setActivePlan(recommendation);
    setRouteDrawerOpen(true);

    const nextSubtitle = buildSubtitle(language, recommendation);
    setSubtitle(nextSubtitle);

    if (autoSpeakReply) {
      speakText(nextSubtitle).catch(() => undefined);
    }
  }, [response, language, autoSpeakReply]);

  useEffect(() => {
    if (!currentLocation) return;

    const nextLabel = getCurrentLocationLabel(language);
    if (currentLocation.label === nextLabel) return;

    setCurrentLocation({
      ...currentLocation,
      label: nextLabel
    });

    if (useDeviceLocation) {
      setOriginInput(nextLabel);
    }
  }, [language, currentLocation, useDeviceLocation]);

  useEffect(() => {
    return () => {
      stopMediaTracks();
      audioRef.current?.pause();
    };
  }, []);

  const drawerSummary = useMemo(() => {
    if (!activePlan) return null;
    return {
      title: cleanPlanTitle(language, activePlan),
      summary: cleanPlanSummary(language, activePlan)
    };
  }, [activePlan, language]);

  async function requestCurrentLocation(silent = false) {
    if (!navigator.geolocation) {
      if (!silent) setLocationStatus(t.status.locationUnavailable);
      return;
    }

    setLocationStatus(t.status.locating);

    return new Promise<void>((resolve) => {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          const nextLocation = {
            label: getCurrentLocationLabel(language),
            latitude: position.coords.latitude,
            longitude: position.coords.longitude
          };

          setCurrentLocation(nextLocation);
          setLocationStatus(t.status.locationReady);

          if (useDeviceLocation && !originInput.trim()) {
            setOriginInput(nextLocation.label);
          }

          resolve();
        },
        () => {
          if (!silent) setLocationStatus(t.status.locationUnavailable);
          resolve();
        }
      );
    });
  }

  async function submitTypedTripRequest() {
    if (!tripRequestInput.trim()) {
      setVoiceStatus(t.status.emptyTripRequest);
      setMenuOpen(true);
      setActiveSection("tripRequest");
      return;
    }

    await submitPlanning(tripRequestInput);
  }

  async function submitManualPrompt() {
    if (!destinationInput.trim()) {
      setVoiceStatus(t.status.noDestination);
      setMenuOpen(true);
      setActiveSection("destination");
      return;
    }

    const message = buildPrompt({
      language,
      destination: destinationInput,
      origin: useDeviceLocation ? "" : originInput,
      requirements: requirementsInput,
      priority,
      budget: budgetInput,
      departure: departureInput,
      parkingDuration: parkingDurationInput,
      useDeviceLocation
    });

    await submitPlanning(message);
  }

  async function submitPlanning(message: string) {
    if (!message.trim()) return;

    setLoading(true);
    setVoiceStatus("");
    setSubtitle("");

    try {
      const result = await fetchPlanning(message, language, useDeviceLocation ? currentLocation : null);
      setResponse(result);
      setMenuOpen(false);
      setVoiceMode("idle");
      setVoiceTranscript("");
    } catch {
      setVoiceStatus(t.status.planningFailed);
      setVoiceMode("idle");
    } finally {
      setLoading(false);
    }
  }

  async function startVoiceCapture() {
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") {
      setVoiceStatus(t.status.transcriptionUnavailable);
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new MediaRecorder(stream);

      chunksRef.current = [];
      mediaRecorderRef.current = recorder;
      mediaStreamRef.current = stream;

      recorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          chunksRef.current.push(event.data);
        }
      };

      recorder.onstop = async () => {
        try {
          const blob = new Blob(chunksRef.current, { type: "audio/webm" });
          const transcriptResult = await transcribeAudio(blob, language);

          if (transcriptResult.text) {
            setVoiceTranscript(transcriptResult.text);
            setVoiceMode("review");
            setVoiceStatus("");
          } else {
            setVoiceMode("idle");
            setVoiceStatus(t.status.transcriptionUnavailable);
          }
        } catch {
          setVoiceMode("idle");
          setVoiceStatus(t.status.transcriptionUnavailable);
        } finally {
          stopMediaTracks();
        }
      };

      recorder.start();
      setVoiceTranscript("");
      setVoiceStatus("");
      setVoiceMode("listening");
    } catch {
      setVoiceStatus(t.voice.speechFailed);
    }
  }

  function stopVoiceCapture() {
    mediaRecorderRef.current?.stop();
  }

  async function processVoiceTranscript() {
    if (!voiceTranscript.trim()) {
      setVoiceStatus(t.status.transcriptionUnavailable);
      return;
    }

    setVoiceMode("processing");
    await submitPlanning(voiceTranscript);
  }

  async function speakText(text: string) {
    try {
      const result = await requestSpeech(text, language);
      const url = result?.audio?.url;

      if (!url) {
        setVoiceStatus(t.voice.speechFailed);
        return;
      }

      audioRef.current?.pause();
      const audio = new Audio(url);
      audioRef.current = audio;
      await audio.play();
    } catch {
      setVoiceStatus(t.voice.speechFailed);
    }
  }

  function stopMediaTracks() {
    mediaRecorderRef.current = null;
    if (mediaStreamRef.current) {
      mediaStreamRef.current.getTracks().forEach((track) => track.stop());
      mediaStreamRef.current = null;
    }
  }

  const sectionItems: ReadonlyArray<{ key: MenuSection; label: string; icon: ReactNode }> = [
    { key: "tripRequest", label: t.menu.tripRequest, icon: <Sparkles size={16} /> },
    { key: "origin", label: t.menu.origin, icon: <LocateFixed size={16} /> },
    { key: "destination", label: t.menu.destination, icon: <MapPinned size={16} /> },
    { key: "requirements", label: t.menu.requirements, icon: <SlidersHorizontal size={16} /> },
    { key: "settings", label: t.menu.settings, icon: <Settings2 size={16} /> },
    { key: "language", label: t.menu.language, icon: <Languages size={16} /> }
  ];

  return (
    <div className="planner-shell">
      <div className="planner-stage">
        <PlanetMap plan={activePlan} currentLocation={currentLocation} language={language} />

        <div className="overlay-fade" />

        <header className="planner-header">
          <div className="brand-pill">
            <button
              type="button"
              className="menu-toggle"
              onClick={() => setMenuOpen((prev) => !prev)}
              aria-label={t.menu.title}
            >
              {menuOpen ? <X size={18} /> : <Menu size={18} />}
            </button>

            <div className="brand-mark">D&amp;R</div>

            <div className="brand-copy">
              <strong>{t.brand}</strong>
              <span>{t.tag}</span>
            </div>
          </div>

          <div className="header-actions">
            <button type="button" className="floating-chip" onClick={() => setRouteDrawerOpen((prev) => !prev)}>
              <Route size={15} />
              {routeDrawerOpen ? t.route.closeDrawer : t.route.openDrawer}
            </button>

            <button type="button" className="floating-chip" onClick={() => setLanguage((prev) => (prev === "zh" ? "en" : "zh"))}>
              <Globe2 size={15} />
              {t.menu.language}
            </button>
          </div>
        </header>

        <aside className={`side-drawer ${menuOpen ? "open" : ""}`}>
          <div className="drawer-nav">
            <div className="drawer-title">{t.menu.title}</div>
            {sectionItems.map((item) => (
              <button
                key={item.key}
                type="button"
                className={`drawer-link ${activeSection === item.key ? "active" : ""}`}
                onClick={() => setActiveSection(item.key)}
              >
                {item.icon}
                {item.label}
              </button>
            ))}
          </div>

          <div className="drawer-panel">
            {activeSection === "tripRequest" ? (
              <div className="drawer-section">
                <label className="field-label">{t.fields.tripRequestLabel}</label>
                <textarea
                  className="glass-input"
                  value={tripRequestInput}
                  onChange={(event) => setTripRequestInput(event.target.value)}
                  placeholder={t.fields.tripRequestPlaceholder}
                  rows={8}
                />
                <button type="button" className="primary-drawer-button" onClick={submitTypedTripRequest} disabled={loading}>
                  {loading ? <LoaderCircle className="spin" size={18} /> : <Sparkles size={18} />}
                  {loading ? t.voice.processing : t.fields.tripRequestSubmit}
                </button>
              </div>
            ) : null}

            {activeSection === "origin" ? (
              <div className="drawer-section">
                <label className="field-label">{t.fields.originLabel}</label>
                <textarea
                  className="glass-input"
                  value={originInput}
                  onChange={(event) => setOriginInput(event.target.value)}
                  placeholder={t.fields.originPlaceholder}
                  disabled={useDeviceLocation}
                  rows={4}
                />
                <label className="toggle-line">
                  <input type="checkbox" checked={useDeviceLocation} onChange={(event) => setUseDeviceLocation(event.target.checked)} />
                  <span>{t.fields.useDeviceLocation}</span>
                </label>
                <button type="button" className="soft-button" onClick={() => requestCurrentLocation(false)}>
                  <LocateFixed size={14} />
                  {t.fields.refreshLocation}
                </button>
                <div className="drawer-hint">{locationStatus}</div>
              </div>
            ) : null}

            {activeSection === "destination" ? (
              <div className="drawer-section">
                <label className="field-label">{t.fields.destinationLabel}</label>
                <textarea
                  className="glass-input"
                  value={destinationInput}
                  onChange={(event) => setDestinationInput(event.target.value)}
                  placeholder={t.fields.destinationPlaceholder}
                  rows={5}
                />
              </div>
            ) : null}

            {activeSection === "requirements" ? (
              <div className="drawer-section">
                <label className="field-label">{t.fields.requirementsLabel}</label>
                <textarea
                  className="glass-input"
                  value={requirementsInput}
                  onChange={(event) => setRequirementsInput(event.target.value)}
                  placeholder={t.fields.requirementsPlaceholder}
                  rows={8}
                />
              </div>
            ) : null}

            {activeSection === "settings" ? (
              <div className="drawer-section">
                <label className="field-label">{t.fields.priorityLabel}</label>
                <select className="glass-select" value={priority} onChange={(event) => setPriority(event.target.value as Priority)}>
                  {Object.entries(t.priorities).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>

                <label className="field-label">{t.fields.budgetLabel}</label>
                <input className="glass-input single-line" value={budgetInput} onChange={(event) => setBudgetInput(event.target.value)} />

                <label className="field-label">{t.fields.departureLabel}</label>
                <input
                  className="glass-input single-line"
                  type="text"
                  value={departureInput}
                  onChange={(event) => setDepartureInput(event.target.value)}
                  placeholder={t.fields.departurePlaceholder}
                  inputMode="text"
                />

                <label className="field-label">{t.fields.parkingLabel}</label>
                <input
                  className="glass-input single-line"
                  type="number"
                  min="0"
                  step="0.5"
                  value={parkingDurationInput}
                  onChange={(event) => setParkingDurationInput(event.target.value)}
                />

                <label className="toggle-line">
                  <input type="checkbox" checked={autoSpeakReply} onChange={(event) => setAutoSpeakReply(event.target.checked)} />
                  <span>{language === "zh" ? "规划完成后自动播放 AI 语音回复" : "Auto-play the AI voice reply after planning"}</span>
                </label>

                <div className="drawer-hint">{t.fields.settingsHint}</div>
              </div>
            ) : null}

            {activeSection === "language" ? (
              <div className="drawer-section">
                <label className="field-label">{t.fields.languageLabel}</label>
                <div className="language-switcher">
                  <button
                    type="button"
                    className={`language-button ${language === "zh" ? "active" : ""}`}
                    onClick={() => setLanguage("zh")}
                  >
                    中文
                  </button>
                  <button
                    type="button"
                    className={`language-button ${language === "en" ? "active" : ""}`}
                    onClick={() => setLanguage("en")}
                  >
                    English
                  </button>
                </div>
              </div>
            ) : null}

            {activeSection !== "tripRequest" ? (
              <button type="button" className="primary-drawer-button" onClick={submitManualPrompt} disabled={loading}>
                {loading ? <LoaderCircle className="spin" size={18} /> : <ChevronRight size={18} />}
                {loading ? t.voice.processing : t.fields.generate}
              </button>
            ) : null}
          </div>
        </aside>

        <aside className={`route-drawer ${routeDrawerOpen ? "open" : ""}`}>
          <div className="route-drawer-header">
            <div>
              <div className="drawer-title">{t.menu.routeOptions}</div>
              <div className="drawer-subtle">{plans.length > 0 ? t.route.candidateCount(plans.length) : t.route.noResult}</div>
            </div>
            <button type="button" className="panel-close" onClick={() => setRouteDrawerOpen(false)}>
              <X size={18} />
            </button>
          </div>

          {activePlan && drawerSummary ? (
            <>
              <div className="route-hero">
                <div className="route-pill">{packageLabel(language, activePlan.strategyTag)}</div>
                <h3>{drawerSummary.title}</h3>
                <p>{drawerSummary.summary}</p>

                <div className="metric-strip">
                  <div>
                    <span>{t.metrics.totalCost}</span>
                    <strong>{formatCurrency(activePlan.totalCost, language)}</strong>
                  </div>
                  <div>
                    <span>{t.metrics.duration}</span>
                    <strong>{formatDurationLocal(activePlan.totalDuration, language)}</strong>
                  </div>
                  <div>
                    <span>{t.metrics.comfort}</span>
                    <strong>{activePlan.comfortScore.toFixed(0)} / 100</strong>
                  </div>
                  <div>
                    <span>{t.metrics.carbon}</span>
                    <strong>{activePlan.carbonEstimate.toFixed(2)} kg</strong>
                  </div>
                </div>

                <div className="chip-line">
                  {activePlan.liveRoute.usesRealtimeTraffic ? <span className="floating-chip tiny">{t.route.liveTraffic}</span> : null}
                  {activePlan.liveRoute.usesRealtimeTransitFare ? <span className="floating-chip tiny">{t.route.liveFare}</span> : null}
                </div>

                <div className="google-link-group">
                  {buildRouteGoogleLink(activePlan, "drive") ? (
                    <a className="soft-button link-button" href={buildRouteGoogleLink(activePlan, "drive") ?? "#"} target="_blank" rel="noreferrer">
                      <CarFront size={14} />
                      {t.route.openDriving}
                    </a>
                  ) : null}

                  {buildRouteGoogleLink(activePlan, "transit") ? (
                    <a
                      className="soft-button link-button"
                      href={buildRouteGoogleLink(activePlan, "transit") ?? "#"}
                      target="_blank"
                      rel="noreferrer"
                    >
                      <TrainFront size={14} />
                      {t.route.openTransit}
                    </a>
                  ) : null}
                </div>
              </div>

              <div className="route-card-stack">
                <div className="drawer-title small">{t.route.alternatives}</div>
                {plans.map((plan) => (
                  <button
                    key={plan.planId}
                    type="button"
                    className={`route-card ${plan.planId === activePlan.planId ? "active" : ""}`}
                    onClick={() => setActivePlan(plan)}
                  >
                    <div className="route-card-top">
                      <div>
                        <div className="route-pill">{packageLabel(language, plan.strategyTag)}</div>
                        <div className="route-card-title">{cleanPlanTitle(language, plan)}</div>
                      </div>
                      <strong>{formatCurrency(plan.totalCost, language)}</strong>
                    </div>
                    <p>{cleanPlanSummary(language, plan)}</p>
                    <div className="route-card-metrics">
                      <span>{formatDurationLocal(plan.totalDuration, language)}</span>
                      <span>
                        {plan.transferCount} {t.metrics.transfers}
                      </span>
                      <span>{formatDurationLocal(plan.walkingDuration, language)}</span>
                    </div>
                  </button>
                ))}
              </div>

              <div className="route-card-stack">
                <div className="drawer-title small">{t.route.steps}</div>
                {activePlan.routeSegments.map((segment, index) => {
                  const segmentLink = buildSegmentGoogleLink(segment);
                  return (
                    <div key={segment.segmentId} className="segment-card">
                      <div className="segment-top">
                        <div>
                          <div className="segment-kind">{cleanSegmentTitle(language, segment, index)}</div>
                          <div className="segment-desc">{cleanSegmentDescription(language, segment)}</div>
                        </div>
                        <div className="segment-meta">
                          <strong>{formatDurationLocal(segment.durationMinutes, language)}</strong>
                          <span>{segment.distanceKm.toFixed(1)} km</span>
                        </div>
                      </div>

                      <div className="chip-line">
                        {segment.trafficAware ? <span className="floating-chip tiny">{t.route.liveTraffic}</span> : null}
                        {segment.fareIncluded ? <span className="floating-chip tiny">{t.route.liveFare}</span> : null}
                      </div>

                      {segmentLink ? (
                        <a className="soft-button link-button" href={segmentLink} target="_blank" rel="noreferrer">
                          <MapPinned size={14} />
                          {t.route.openSegment}
                        </a>
                      ) : null}
                    </div>
                  );
                })}
              </div>
            </>
          ) : (
            <div className="route-empty">{t.route.noResult}</div>
          )}
        </aside>

        <div className={`voice-dock ${voiceMode}`}>
          {voiceMode === "idle" ? (
            <button type="button" className="voice-orb siri-idle" onClick={startVoiceCapture} disabled={loading}>
              <div className="voice-orb-halo" />
              <div className="voice-orb-core">
                <Mic size={20} />
              </div>
              <div className="voice-orb-text">
                <strong>{t.voice.idle}</strong>
                <span>{t.voice.listeningHint}</span>
              </div>
              <div className="voice-orb-tail">
                <Sparkles size={16} />
              </div>
            </button>
          ) : null}

          {voiceMode === "listening" ? (
            <div className="voice-console siri-sheet">
              <div className="voice-console-header">
                <div>
                  <strong>{t.voice.listening}</strong>
                  <span>{t.voice.listeningHint}</span>
                </div>
                <button type="button" className="panel-close" onClick={stopVoiceCapture} aria-label={t.voice.stop}>
                  <Square size={16} />
                </button>
              </div>

              <div className="siri-wave-core">
                <div className="siri-orb-mini">
                  <Mic size={18} />
                </div>
                <div className="wave-strip" aria-hidden="true">
                  {Array.from({ length: 20 }).map((_, index) => (
                    <span key={index} style={{ animationDelay: `${index * 0.06}s` }} />
                  ))}
                </div>
              </div>
            </div>
          ) : null}

          {voiceMode === "review" ? (
            <div className="voice-console siri-sheet">
              <div className="voice-console-header">
                <div>
                  <strong>{t.voice.transcriptTitle}</strong>
                  <span>{t.voice.transcriptHint}</span>
                </div>
                <button type="button" className="panel-close" onClick={() => setVoiceMode("idle")}>
                  <X size={16} />
                </button>
              </div>

              <div className="voice-transcript siri-transcript">{voiceTranscript || t.status.transcriptionUnavailable}</div>

              <div className="voice-actions">
                <button type="button" className="soft-button" onClick={startVoiceCapture}>
                  <Waves size={14} />
                  {t.voice.retry}
                </button>
                <button type="button" className="primary-drawer-button compact siri-process-button" onClick={processVoiceTranscript}>
                  <ChevronRight size={16} />
                  {t.voice.process}
                </button>
              </div>
            </div>
          ) : null}

          {voiceMode === "processing" ? (
            <div className="voice-console siri-sheet">
              <div className="voice-console-header">
                <div>
                  <strong>{t.voice.processing}</strong>
                  <span>{voiceTranscript}</span>
                </div>
                <LoaderCircle className="spin" size={18} />
              </div>

              <div className="wave-strip processing-strip" aria-hidden="true">
                {Array.from({ length: 20 }).map((_, index) => (
                  <span key={index} style={{ animationDelay: `${index * 0.05}s` }} />
                ))}
              </div>
            </div>
          ) : null}

          {voiceStatus ? <div className="voice-status">{voiceStatus}</div> : null}
        </div>

        <div className="subtitle-bar">
          <div className="subtitle-label">
            <Volume2 size={14} />
            {t.voice.subtitle}
          </div>
          <div className="subtitle-text">{subtitle || t.voice.waitingSubtitle}</div>
          {subtitle ? (
            <button type="button" className="floating-chip" onClick={() => speakText(subtitle)}>
              <Volume2 size={14} />
              {t.voice.replay}
            </button>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function getCurrentLocationLabel(language: Language) {
  return language === "zh" ? "当前位置" : "Current location";
}

function buildPrompt(input: {
  language: Language;
  destination: string;
  origin: string;
  requirements: string;
  priority: Priority;
  budget: string;
  departure: string;
  parkingDuration: string;
  useDeviceLocation: boolean;
}) {
  if (input.language === "zh") {
    const parts = [
      input.useDeviceLocation ? "我从当前设备位置出发" : input.origin ? `我从${input.origin}出发` : "",
      `我要去${input.destination}`,
      `优先策略是${dictionaries.zh.priorities[input.priority]}`,
      input.budget ? `预算不超过${input.budget}欧元` : "",
      input.departure ? `出发时间是${formatDateTimeForPrompt(input.departure, "zh")}` : "",
      input.parkingDuration ? `预计停车${input.parkingDuration}小时` : "",
      input.requirements ? `其他要求：${input.requirements}` : ""
    ].filter(Boolean);

    return `${parts.join("，")}。请比较费用、时长、舒适度和碳排放，并给出推荐路线。`;
  }

  const parts = [
    input.useDeviceLocation ? "I am starting from my current device location" : input.origin ? `I am starting from ${input.origin}` : "",
    `I need to go to ${input.destination}`,
    `my priority is ${dictionaries.en.priorities[input.priority]}`,
    input.budget ? `my budget is under EUR ${input.budget}` : "",
    input.departure ? `I want to leave at ${formatDateTimeForPrompt(input.departure, "en")}` : "",
    input.parkingDuration ? `I expect to park for ${input.parkingDuration} hour(s)` : "",
    input.requirements ? `other requirements: ${input.requirements}` : ""
  ].filter(Boolean);

  return `${parts.join(", ")}. Please compare cost, duration, comfort, and carbon output, then recommend the best route.`;
}

function buildSubtitle(language: Language, plan: Plan | null) {
  if (!plan) {
    return language === "zh"
      ? "我还没有拿到可用路线，请再说一次目的地和你的要求。"
      : "I do not have a usable route yet. Please repeat the destination and constraints.";
  }

  const title = cleanPlanTitle(language, plan);
  const duration = formatDurationLocal(plan.totalDuration, language);
  const cost = formatCurrency(plan.totalCost, language);

  if (language === "zh") {
    return `我建议你选择${title}。这条路线预计总时长约为${duration}，总费用约为${cost}。完整路线和 Google Maps 入口已经放在右侧。`;
  }

  return `I recommend ${title}. This route should take about ${duration} in total with an overall cost near ${cost}. The full path and Google Maps links are now available on the right.`;
}

function formatDateTimeForPrompt(value: string, language: Language) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  if (language === "zh") {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")} ${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
  }

  return date.toLocaleString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  });
}

function buildRouteGoogleLink(plan: Plan, mode: "drive" | "transit") {
  const kinds = mode === "drive" ? ["drive"] : ["transit", "walk"];
  const matchingSegments = plan.routeSegments.filter((segment) => kinds.includes(segment.kind) && segment.path.length > 1);
  const firstPoint = matchingSegments.at(0)?.path.at(0);
  const lastPoint = matchingSegments.at(-1)?.path.at(-1);

  if (!firstPoint || !lastPoint) {
    return null;
  }

  return buildGoogleMapsUrl(firstPoint, lastPoint, mode === "drive" ? "driving" : "transit");
}

function buildSegmentGoogleLink(segment: RouteSegment) {
  if (segment.path.length < 2) {
    return null;
  }

  const start = segment.path[0];
  const end = segment.path[segment.path.length - 1];
  const travelMode = segment.kind === "drive" ? "driving" : segment.kind === "walk" ? "walking" : "transit";

  return buildGoogleMapsUrl(start, end, travelMode);
}

function buildGoogleMapsUrl(origin: LocationPoint, destination: LocationPoint, travelMode: "driving" | "walking" | "transit") {
  const url = new URL("https://www.google.com/maps/dir/");
  url.searchParams.set("api", "1");
  url.searchParams.set("origin", `${origin.latitude},${origin.longitude}`);
  url.searchParams.set("destination", `${destination.latitude},${destination.longitude}`);
  url.searchParams.set("travelmode", travelMode);
  return url.toString();
}

function formatDurationLocal(minutes: number, language: Language) {
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;

  if (language === "zh") {
    return hours > 0 ? `${hours}小时${mins}分钟` : `${mins}分钟`;
  }

  return hours > 0 ? `${hours}h ${mins}m` : `${mins} min`;
}
