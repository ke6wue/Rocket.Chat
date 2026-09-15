import { config } from "../config.js";
import type { SkywardStaff, SkywardStudent, SkywardGuardian, SkywardSection } from "../types.js";

/**
 * Thin, read-only client for Skyward Qmlativ's Integration Access API.
 *
 * IMPORTANT: the exact resource paths below (e.g. `/v1/staff`) are
 * placeholders. Qmlativ's Integration Access API surface is granted
 * per-district and per-vendor — your district's Skyward admin (or Skyward's
 * Partner Portal docs, once your Integration is approved) will give you the
 * real paths and field names for the tables you were granted:
 * Student, Staff, Guardian, Section, StudentSectionEnrollment,
 * GuardianStudentRelationship. Update `RESOURCE_PATHS` below to match once
 * you have that confirmation — do not guess and point this at production.
 *
 * This client never issues a POST/PUT/DELETE against Skyward.
 */

const RESOURCE_PATHS = {
  staff: "/v1/staff",
  students: "/v1/students",
  guardians: "/v1/guardians",
  sections: "/v1/sections",
};

let cachedToken: { value: string; expiresAt: number } | null = null;

async function getAccessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 30_000) {
    return cachedToken.value;
  }

  const res = await fetch(config.skyward.tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: config.skyward.clientId,
      client_secret: config.skyward.clientSecret,
      scope: "read",
    }),
  });

  if (!res.ok) {
    throw new Error(`Skyward OAuth2 token request failed: ${res.status} ${await res.text()}`);
  }

  const body = (await res.json()) as { access_token: string; expires_in: number };
  cachedToken = {
    value: body.access_token,
    expiresAt: Date.now() + body.expires_in * 1000,
  };
  return cachedToken.value;
}

async function getPaginated<T>(path: string, params: Record<string, string> = {}): Promise<T[]> {
  const token = await getAccessToken();
  const results: T[] = [];
  let page = 1;
  const pageSize = 200;

  while (true) {
    const url = new URL(config.skyward.baseUrl + path);
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
    url.searchParams.set("page", String(page));
    url.searchParams.set("pageSize", String(pageSize));
    if (config.skyward.entityId) url.searchParams.set("entityId", config.skyward.entityId);

    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
    });
    if (!res.ok) {
      throw new Error(`Skyward GET ${path} failed: ${res.status} ${await res.text()}`);
    }
    const body = (await res.json()) as { items: T[]; hasMore: boolean };
    results.push(...body.items);
    if (!body.hasMore || body.items.length === 0) break;
    page += 1;
  }

  return results;
}

export const skywardClient = {
  async listStaff(): Promise<SkywardStaff[]> {
    return getPaginated<SkywardStaff>(RESOURCE_PATHS.staff);
  },

  async listStudents(): Promise<SkywardStudent[]> {
    return getPaginated<SkywardStudent>(RESOURCE_PATHS.students, {
      schoolYearId: config.skyward.schoolYearId,
    });
  },

  async listGuardians(): Promise<SkywardGuardian[]> {
    return getPaginated<SkywardGuardian>(RESOURCE_PATHS.guardians);
  },

  async listSections(): Promise<SkywardSection[]> {
    return getPaginated<SkywardSection>(RESOURCE_PATHS.sections, {
      schoolYearId: config.skyward.schoolYearId,
    });
  },
};
