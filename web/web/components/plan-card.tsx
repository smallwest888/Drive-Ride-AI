"use client";

import { formatCurrency, formatDuration, type Language, type Plan } from "@drive-ride/shared";
import { Car, Footprints, Leaf, Shuffle } from "lucide-react";
import { packageLabel } from "@/lib/i18n";

type Props = {
  language: Language;
  plan: Plan;
  active: boolean;
  onSelect: () => void;
};

export function PlanCard({ language, plan, active, onSelect }: Props) {
  return (
    <button
      type="button"
      onClick={onSelect}
      className="card"
      style={{
        width: "100%",
        textAlign: "left",
        padding: 18,
        cursor: "pointer",
        borderColor: active ? "rgba(88,130,243,0.44)" : undefined,
        boxShadow: active ? "0 20px 44px rgba(88, 130, 243, 0.16)" : undefined
      }}
    >
      <div style={{ display: "flex", justifyContent: "space-between", gap: 12, alignItems: "start" }}>
        <div>
          <div className="pill">{packageLabel(language, plan.strategyTag)}</div>
          <div style={{ marginTop: 10, fontWeight: 800, fontSize: 18 }}>{plan.title}</div>
          <div className="subtle" style={{ marginTop: 6, lineHeight: 1.45 }}>
            {plan.explanation}
          </div>
        </div>
        <div style={{ fontWeight: 800, fontSize: 20 }}>{formatCurrency(plan.totalCost, language)}</div>
      </div>

      <div className="metric-grid" style={{ marginTop: 16 }}>
        <div className="metric-tile">
          <div className="subtle">{language === "zh" ? "总时长" : "Total time"}</div>
          <div style={{ fontWeight: 700, marginTop: 6 }}>{formatDuration(plan.totalDuration, language)}</div>
        </div>
        <div className="metric-tile">
          <div className="subtle">{language === "zh" ? "舒适度" : "Comfort"}</div>
          <div style={{ fontWeight: 700, marginTop: 6 }}>{plan.comfortScore.toFixed(0)} / 100</div>
        </div>
      </div>

      <div style={{ display: "flex", gap: 12, marginTop: 14, flexWrap: "wrap" }}>
        <span className="pill">
          <Car size={14} />
          {formatDuration(plan.drivingDuration, language)}
        </span>
        <span className="pill">
          <Shuffle size={14} />
          {plan.transferCount}
        </span>
        <span className="pill">
          <Footprints size={14} />
          {formatDuration(plan.walkingDuration, language)}
        </span>
        <span className="pill">
          <Leaf size={14} />
          {plan.carbonEstimate.toFixed(2)} kg
        </span>
        {plan.liveRoute.usesRealtimeTraffic ? <span className="pill">{language === "zh" ? "实时路况" : "Live traffic"}</span> : null}
        {plan.liveRoute.usesRealtimeTransitFare ? <span className="pill">{language === "zh" ? "实时票价" : "Live fare"}</span> : null}
      </div>
    </button>
  );
}
