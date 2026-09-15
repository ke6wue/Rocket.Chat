import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";
import { config } from "../config.js";

fs.mkdirSync(path.dirname(config.store.sqlitePath), { recursive: true });
export const db = new Database(config.store.sqlitePath);
db.pragma("journal_mode = WAL");

db.exec(`
  CREATE TABLE IF NOT EXISTS user_map (
    source_system TEXT NOT NULL,
    source_id     TEXT NOT NULL,
    role          TEXT NOT NULL,
    rc_user_id    TEXT NOT NULL,
    updated_at    TEXT NOT NULL,
    PRIMARY KEY (source_system, source_id, role)
  );

  CREATE TABLE IF NOT EXISTS team_map (
    section_id    TEXT NOT NULL,
    kind          TEXT NOT NULL CHECK (kind IN ('class','family')),
    rc_team_id    TEXT NOT NULL,
    updated_at    TEXT NOT NULL,
    PRIMARY KEY (section_id, kind)
  );

  -- Append-only. Never UPDATE or DELETE rows here: this is the "who could
  -- message whom, since when" accounting referenced in README.md.
  CREATE TABLE IF NOT EXISTS audit_log (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    ts            TEXT NOT NULL,
    action        TEXT NOT NULL,
    subject       TEXT NOT NULL,
    detail        TEXT
  );
`);

export function recordUserMap(sourceId: string, role: string, rcUserId: string) {
  db.prepare(
    `INSERT INTO user_map (source_system, source_id, role, rc_user_id, updated_at)
     VALUES ('skyward', ?, ?, ?, datetime('now'))
     ON CONFLICT(source_system, source_id, role) DO UPDATE SET rc_user_id=excluded.rc_user_id, updated_at=excluded.updated_at`
  ).run(sourceId, role, rcUserId);
}

export function getUserMap(sourceId: string, role: string): string | undefined {
  const row = db
    .prepare(`SELECT rc_user_id FROM user_map WHERE source_system='skyward' AND source_id=? AND role=?`)
    .get(sourceId, role) as { rc_user_id: string } | undefined;
  return row?.rc_user_id;
}

export function recordTeamMap(sectionId: string, kind: "class" | "family", rcTeamId: string) {
  db.prepare(
    `INSERT INTO team_map (section_id, kind, rc_team_id, updated_at)
     VALUES (?, ?, ?, datetime('now'))
     ON CONFLICT(section_id, kind) DO UPDATE SET rc_team_id=excluded.rc_team_id, updated_at=excluded.updated_at`
  ).run(sectionId, kind, rcTeamId);
}

export function getTeamMap(sectionId: string, kind: "class" | "family"): string | undefined {
  const row = db
    .prepare(`SELECT rc_team_id FROM team_map WHERE section_id=? AND kind=?`)
    .get(sectionId, kind) as { rc_team_id: string } | undefined;
  return row?.rc_team_id;
}

export function audit(action: string, subject: string, detail?: Record<string, unknown>) {
  db.prepare(`INSERT INTO audit_log (ts, action, subject, detail) VALUES (datetime('now'), ?, ?, ?)`).run(
    action,
    subject,
    detail ? JSON.stringify(detail) : null
  );
}
