import type { SkywardStaff } from "../types.js";
import { rocketChatClient } from "../rocketchat/client.js";
import { recordUserMap, getUserMap, audit } from "../store/db.js";

function usernameFor(staff: SkywardStaff): string {
  return `staff.${staff.districtEmail.split("@")[0]}`;
}

export async function syncStaff(allStaff: SkywardStaff[]): Promise<Map<string, string>> {
  const idToRcUserId = new Map<string, string>();

  for (const staff of allStaff) {
    const { userId } = await rocketChatClient.upsertUser({
      sourceSystem: "skyward",
      sourceId: staff.staffId,
      username: usernameFor(staff),
      name: `${staff.firstName} ${staff.lastName}`,
      email: staff.districtEmail,
      role: "staff",
      active: staff.active,
    });

    recordUserMap(staff.staffId, "staff", userId);
    idToRcUserId.set(staff.staffId, userId);
    audit("staff.sync", staff.staffId, { active: staff.active, rcUserId: userId });

    if (!staff.active) {
      const existing = getUserMap(staff.staffId, "staff");
      if (existing) await rocketChatClient.deactivateUser(existing);
    }
  }

  return idToRcUserId;
}
