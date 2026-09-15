import crypto from "node:crypto";
import { config } from "../config.js";
import type { RCUserSpec } from "../types.js";

/**
 * Wraps Rocket.Chat's REST Admin API. Assumes your fork keeps the stock
 * `/api/v1/users.*` and `/api/v1/teams.*` surface — if your fork has
 * renamed/replaced these, this is the only file that should need edits.
 */

function authHeaders() {
  return {
    "X-Auth-Token": config.rocketchat.adminToken,
    "X-User-Id": config.rocketchat.adminUserId,
    "Content-Type": "application/json",
  };
}

async function rc<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${config.rocketchat.baseUrl}/api/v1/${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers: authHeaders(),
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = await res.json();
  if (!res.ok || json.success === false) {
    throw new Error(`Rocket.Chat ${path} failed: ${res.status} ${JSON.stringify(json)}`);
  }
  return json as T;
}

function guard(action: string) {
  if (!config.allowWrites) {
    console.log(`[dry-run] would ${action}`);
    return false;
  }
  return true;
}

export const rocketChatClient = {
  /**
   * Creates or reactivates a user. Deliberately does NOT set a usable
   * password: staff/student/parent accounts should come up requiring SSO
   * login (if your fork has district SSO configured) or an out-of-band,
   * district-email-delivered "set your password" flow. Generating and
   * emailing plaintext temp passwords from this connector is exactly the
   * kind of shortcut that turns into a FERPA incident — don't add it back
   * without deliberately deciding how reset emails get delivered securely.
   */
  async upsertUser(spec: RCUserSpec): Promise<{ userId: string }> {
    const existing = await rc<{ users: Array<{ _id: string }> }>(
      `users.list?query=${encodeURIComponent(JSON.stringify({ username: spec.username }))}`
    ).catch(() => ({ users: [] }));

    if (existing.users.length > 0) {
      const userId = existing.users[0]!._id;
      if (guard(`update user ${spec.username} (active=${spec.active}, role=${spec.role})`)) {
        await rc("users.update", {
          userId,
          data: {
            name: spec.name,
            email: spec.email,
            active: spec.active,
            roles: [spec.role],
          },
        });
      }
      return { userId };
    }

    if (!guard(`create user ${spec.username} (role=${spec.role})`)) {
      return { userId: `dry-run-${spec.username}` };
    }

    // requirePasswordChange + a random unusable password forces the account
    // through SSO or an explicit reset flow rather than ever having a known
    // password in this process's memory/logs.
    const placeholder = crypto.randomBytes(32).toString("hex");
    const created = await rc<{ user: { _id: string } }>("users.create", {
      name: spec.name,
      email: spec.email,
      username: spec.username,
      password: placeholder,
      requirePasswordChange: true,
      active: spec.active,
      roles: [spec.role],
      sendWelcomeEmail: true,
      verified: false,
    });
    return { userId: created.user._id };
  },

  async deactivateUser(userId: string): Promise<void> {
    if (!guard(`deactivate user ${userId}`)) return;
    await rc("users.update", { userId, data: { active: false } });
  },

  async ensureTeam(name: string, ownerUserId: string): Promise<{ teamId: string }> {
    const found = await rc<{ team?: { _id: string } }>(
      `teams.info?teamName=${encodeURIComponent(name)}`
    ).catch(() => ({ team: undefined }));

    if (found.team) return { teamId: found.team._id };

    if (!guard(`create team ${name}`)) return { teamId: `dry-run-${name}` };

    const created = await rc<{ team: { _id: string } }>("teams.create", {
      name,
      type: 1, // private
      members: [ownerUserId],
    });
    return { teamId: created.team._id };
  },

  async setTeamMembers(teamId: string, teamName: string, desiredUserIds: string[]): Promise<void> {
    const current = await rc<{ members: Array<{ userId: string }> }>(
      `teams.members?teamId=${teamId}`
    ).catch(() => ({ members: [] }));
    const currentIds = new Set(current.members.map((m) => m.userId));
    const desiredSet = new Set(desiredUserIds);

    const toAdd = desiredUserIds.filter((id) => !currentIds.has(id));
    const toRemove = [...currentIds].filter((id) => !desiredSet.has(id));

    if (toAdd.length > 0 && guard(`add ${toAdd.length} member(s) to ${teamName}`)) {
      await rc("teams.addMembers", { teamId, members: toAdd.map((userId) => ({ userId })) });
    }
    for (const userId of toRemove) {
      if (guard(`remove member ${userId} from ${teamName}`)) {
        await rc("teams.removeMember", { teamId, userId });
      }
    }
  },
};
