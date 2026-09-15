import type { SkywardGuardian } from "../types.js";
import { rocketChatClient } from "../rocketchat/client.js";
import { recordUserMap, getUserMap, audit } from "../store/db.js";

function usernameFor(guardian: SkywardGuardian): string {
  return `parent.${guardian.email.split("@")[0]}.${guardian.guardianId}`;
}

/**
 * Hard legal gate, not a UX preference: Skyward's "Restrict from Family
 * Access" flag exists specifically for custody disputes and protective
 * orders. A guardian with `restricted: true` must never get an account or
 * channel membership from this connector, full stop — do not add an
 * override flag or admin bypass for this without district legal sign-off.
 */
export function shouldSyncGuardian(guardian: SkywardGuardian): boolean {
  return !guardian.restricted;
}

export async function syncGuardians(allGuardians: SkywardGuardian[]): Promise<Map<string, string>> {
  const idToRcUserId = new Map<string, string>();

  for (const guardian of allGuardians) {
    if (!shouldSyncGuardian(guardian)) {
      audit("guardian.skip_restricted", guardian.guardianId, {
        reason: "restricted flag set in Skyward",
      });
      const existing = getUserMap(guardian.guardianId, "parent");
      if (existing) await rocketChatClient.deactivateUser(existing);
      continue;
    }

    const { userId } = await rocketChatClient.upsertUser({
      sourceSystem: "skyward",
      sourceId: guardian.guardianId,
      username: usernameFor(guardian),
      name: `${guardian.firstName} ${guardian.lastName}`,
      email: guardian.email,
      role: "parent",
      active: true,
    });

    recordUserMap(guardian.guardianId, "parent", userId);
    idToRcUserId.set(guardian.guardianId, userId);
    audit("guardian.sync", guardian.guardianId, { rcUserId: userId, studentIds: guardian.studentIds });
  }

  return idToRcUserId;
}
