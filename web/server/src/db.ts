import Database from "better-sqlite3";
import { config } from "./config.js";
import type { ParkingRecord, ParkingWriteInput } from "@drive-ride/shared";

const db = new Database(config.dbPath, { readonly: false });

function rowToParking(row: Record<string, unknown>): ParkingRecord {
  return {
    id: Number(row.id),
    name: String(row.name ?? ""),
    address: String(row.address ?? ""),
    city: String(row.city ?? ""),
    latitude: Number(row.latitude ?? 0),
    longitude: Number(row.longitude ?? 0),
    totalSpaces: Number(row.totalSpaces ?? 0),
    pricePerHour: row.pricePerHour === null || row.pricePerHour === undefined ? null : Number(row.pricePerHour),
    publicTransport: String(row.publicTransport ?? ""),
    facilities: String(row.facilities ?? ""),
    notes: String(row.notes ?? ""),
    isActive: Number(row.isActive ?? 1) === 1,
    createdAt: row.createdAt ? String(row.createdAt) : null,
    updatedAt: row.updatedAt ? String(row.updatedAt) : null
  };
}

export function getAllActiveParkings() {
  return db
    .prepare(
      `SELECT id, name, address, city, latitude, longitude, totalSpaces, pricePerHour,
              publicTransport, facilities, notes, isActive, createdAt, updatedAt
       FROM PRParkings
       WHERE isActive = 1
       ORDER BY city, name`
    )
    .all()
    .map((row) => rowToParking(row as Record<string, unknown>));
}

export function getParkingById(id: number) {
  const row = db
    .prepare(
      `SELECT id, name, address, city, latitude, longitude, totalSpaces, pricePerHour,
              publicTransport, facilities, notes, isActive, createdAt, updatedAt
       FROM PRParkings
       WHERE id = ?`
    )
    .get(id);
  return row ? rowToParking(row as Record<string, unknown>) : null;
}

export function getParkingStats() {
  const totalRow = db.prepare(`SELECT COUNT(*) as count FROM PRParkings WHERE isActive = 1`).get() as { count?: number } | undefined;
  const spacesRow = db
    .prepare(`SELECT COALESCE(SUM(totalSpaces), 0) as total FROM PRParkings WHERE isActive = 1`)
    .get() as { total?: number } | undefined;
  const total = Number(totalRow?.count ?? 0);
  const totalSpaces = Number(spacesRow?.total ?? 0);
  const cities = db
    .prepare(
      `SELECT city, COUNT(*) as count
       FROM PRParkings
       WHERE isActive = 1
       GROUP BY city
       ORDER BY count DESC
       LIMIT 12`
    )
    .all();
  return { total, active: total, totalSpaces, cities };
}

export function upsertParking(input: ParkingWriteInput) {
  if (input.id) {
    const stmt = db.prepare(
      `UPDATE PRParkings
       SET name = ?, address = ?, city = ?, latitude = ?, longitude = ?, totalSpaces = ?,
           pricePerHour = ?, publicTransport = ?, facilities = ?, notes = ?, isActive = ?,
           updatedAt = CURRENT_TIMESTAMP
       WHERE id = ?`
    );
    stmt.run(
      input.name,
      input.address,
      input.city,
      input.latitude,
      input.longitude,
      input.totalSpaces,
      input.pricePerHour,
      input.publicTransport,
      input.facilities,
      input.notes,
      input.isActive ? 1 : 0,
      input.id
    );
    return getParkingById(input.id);
  }

  const stmt = db.prepare(
    `INSERT INTO PRParkings
      (name, address, city, latitude, longitude, totalSpaces, pricePerHour, publicTransport, facilities, notes, isActive, createdAt, updatedAt)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`
  );
  const result = stmt.run(
    input.name,
    input.address,
    input.city,
    input.latitude,
    input.longitude,
    input.totalSpaces,
    input.pricePerHour,
    input.publicTransport,
    input.facilities,
    input.notes,
    input.isActive ? 1 : 0
  );
  return getParkingById(Number(result.lastInsertRowid));
}

export function deleteParking(id: number) {
  const result = db.prepare(`DELETE FROM PRParkings WHERE id = ?`).run(id);
  return result.changes > 0;
}
