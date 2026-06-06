"use client";

import dynamic from "next/dynamic";
import type { Plan } from "@drive-ride/shared";

const MapCanvas = dynamic(() => import("./map-panel-canvas").then((mod) => mod.MapPanelCanvas), {
  ssr: false,
  loading: () => (
    <div className="card" style={{ height: "100%", minHeight: 780, padding: 24, display: "grid", placeItems: "center" }}>
      <div className="subtle">Loading map...</div>
    </div>
  )
});

type Props = {
  plan: Plan | null;
};

export function MapPanel({ plan }: Props) {
  return <MapCanvas plan={plan} />;
}
