"use client";

import { CircleMarker, MapContainer, Polyline, Popup, TileLayer } from "react-leaflet";
import type { Plan } from "@drive-ride/shared";

type Props = {
  plan: Plan | null;
};

export function MapPanelCanvas({ plan }: Props) {
  const route = plan?.routePoints ?? [];
  const routePath = plan?.routePath ?? [];
  const routeSegments = plan?.routeSegments ?? [];
  const center =
    routePath.length > 0
      ? [routePath[Math.floor(routePath.length / 2)].latitude, routePath[Math.floor(routePath.length / 2)].longitude]
      : route.length > 0
        ? [route[Math.floor(route.length / 2)].latitude, route[Math.floor(route.length / 2)].longitude]
      : [52.52, 13.404];

  return (
    <div className="card" style={{ height: "100%", minHeight: 780, padding: 14 }}>
      <MapContainer center={center as [number, number]} zoom={11} scrollWheelZoom style={{ height: "100%", width: "100%" }}>
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        {route.map((point, index) => (
          <CircleMarker
            key={`${point.label}-${index}`}
            center={[point.latitude, point.longitude]}
            pathOptions={{
              color: index === 0 ? "#145dff" : index === route.length - 1 ? "#ff7a1a" : "#00b894",
              fillColor: index === 0 ? "#145dff" : index === route.length - 1 ? "#ff7a1a" : "#00b894",
              fillOpacity: 0.95,
              weight: 3
            }}
            radius={index === 0 || index === route.length - 1 ? 11 : 8}
          >
            <Popup>{point.label}</Popup>
          </CircleMarker>
        ))}
        {routeSegments.length > 0
          ? routeSegments
              .filter((segment) => segment.path.length > 1)
              .map((segment) => (
                <Polyline
                  key={segment.segmentId}
                  positions={segment.path.map((point) => [point.latitude, point.longitude])}
                  pathOptions={{
                    color: segment.kind === "drive" ? "#145dff" : segment.kind === "transit" ? "#b100ff" : "#ff8a1f",
                    weight: segment.kind === "walk" ? 5 : segment.kind === "transit" ? 7 : 8,
                    dashArray: segment.kind === "walk" ? "8 10" : undefined
                  }}
                />
              ))
          : routePath.length > 1
            ? (
                <Polyline
                  positions={routePath.map((point) => [point.latitude, point.longitude])}
                  pathOptions={{ color: "#145dff", weight: 8 }}
                />
              )
            : route.length > 1
              ? <Polyline positions={route.map((point) => [point.latitude, point.longitude])} pathOptions={{ color: "#145dff", weight: 8 }} />
              : null}
      </MapContainer>
    </div>
  );
}
