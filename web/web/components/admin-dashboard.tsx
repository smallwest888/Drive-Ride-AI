"use client";

import { useEffect, useState } from "react";
import type { ParkingRecord } from "@drive-ride/shared";
import { fetchParkings, fetchStats, removeParking, saveParking } from "@/lib/api";

const emptyParking: Partial<ParkingRecord> = {
  name: "",
  address: "",
  city: "",
  latitude: 52.52,
  longitude: 13.404,
  totalSpaces: 100,
  pricePerHour: 0,
  publicTransport: "",
  facilities: "",
  notes: "",
  isActive: true
};

export function AdminDashboard() {
  const [parkings, setParkings] = useState<ParkingRecord[]>([]);
  const [stats, setStats] = useState<{ total: number; totalSpaces: number } | null>(null);
  const [form, setForm] = useState<Partial<ParkingRecord>>(emptyParking);

  async function refresh() {
    const [parkingRows, statRows] = await Promise.all([fetchParkings(), fetchStats()]);
    setParkings(parkingRows);
    setStats(statRows);
  }

  useEffect(() => {
    refresh().catch(() => undefined);
  }, []);

  return (
    <div className="page-shell">
      <div className="glass" style={{ padding: 20, borderRadius: 28 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 16, flexWrap: "wrap" }}>
          <div>
            <div className="section-title">Drive&Ride Admin</div>
            <div className="subtle">Parking inventory, sync-friendly CRUD, and bilingual-ready content.</div>
          </div>
          <a href="/" className="pill">
            Return to planner
          </a>
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "360px minmax(0, 1fr)", gap: 20, marginTop: 20 }}>
        <section className="glass panel" style={{ padding: 20, minHeight: "auto" }}>
          <div className="section-title">Create or edit parking</div>
          <div className="stack" style={{ marginTop: 16 }}>
            {[
              ["name", "Name"],
              ["address", "Address"],
              ["city", "City"],
              ["latitude", "Latitude"],
              ["longitude", "Longitude"],
              ["totalSpaces", "Total spaces"],
              ["pricePerHour", "Price per hour"],
              ["publicTransport", "Transit"],
              ["facilities", "Facilities"],
              ["notes", "Notes"]
            ].map(([key, label]) => (
              <label key={key} className="stack" style={{ gap: 8 }}>
                <span className="subtle">{label}</span>
                <input
                  value={String((form as Record<string, unknown>)[key] ?? "")}
                  onChange={(event) =>
                    setForm((prev) => ({
                      ...prev,
                      [key]:
                        ["latitude", "longitude", "totalSpaces", "pricePerHour"].includes(key)
                          ? Number(event.target.value)
                          : event.target.value
                    }))
                  }
                  style={{
                    borderRadius: 14,
                    border: "1px solid rgba(24,50,43,0.12)",
                    padding: "12px 14px",
                    background: "rgba(255,255,255,0.9)"
                  }}
                />
              </label>
            ))}

            <button
              type="button"
              onClick={async () => {
                await saveParking(form);
                setForm(emptyParking);
                await refresh();
              }}
              style={{
                border: "none",
                borderRadius: 18,
                background: "linear-gradient(135deg, var(--accent), var(--accent-strong))",
                color: "white",
                padding: "14px 18px",
                cursor: "pointer"
              }}
            >
              Save parking
            </button>
          </div>
        </section>

        <section className="glass panel" style={{ padding: 20, minHeight: "auto" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 16, flexWrap: "wrap" }}>
            <div className="section-title">Active parking list</div>
            <div className="pill">{stats ? `${stats.total} parkings / ${stats.totalSpaces} spaces` : "Loading stats..."}</div>
          </div>

          <div className="stack" style={{ marginTop: 16, maxHeight: "75vh", overflow: "auto" }}>
            {parkings.map((parking) => (
              <div key={parking.id} className="card" style={{ padding: 16 }}>
                <div style={{ display: "flex", justifyContent: "space-between", gap: 16, alignItems: "start" }}>
                  <div>
                    <div style={{ fontWeight: 800 }}>{parking.name}</div>
                    <div className="subtle" style={{ marginTop: 6 }}>
                      {parking.address}
                    </div>
                    <div className="subtle" style={{ marginTop: 6 }}>
                      {parking.city} | {parking.totalSpaces} spaces | €{(parking.pricePerHour ?? 0).toFixed(2)}/h
                    </div>
                  </div>
                  <div style={{ display: "flex", gap: 8 }}>
                    <button
                      type="button"
                      className="pill"
                      style={{ border: "none", cursor: "pointer" }}
                      onClick={() => setForm(parking)}
                    >
                      Edit
                    </button>
                    <button
                      type="button"
                      className="pill"
                      style={{ border: "none", cursor: "pointer", background: "rgba(219,80,74,0.12)", color: "#a33228" }}
                      onClick={async () => {
                        await removeParking(parking.id);
                        await refresh();
                      }}
                    >
                      Delete
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
