import type { SkywardStudent } from "../types.js";
import { rocketChatClient } from "../rocketchat/client.js";
import { recordUserMap, getUserMap, audit } from "../store/db.js";

function usernameFor(student: SkywardStudent): string {
  return `student.${student.districtEmail.split("@")[0]}`;
}

export async function syncStudents(allStudents: SkywardStudent[]): Promise<Map<string, string>> {
  const idToRcUserId = new Map<string, string>();

  for (const student of allStudents) {
    const active = student.enrollmentStatus === "active";

    const { userId } = await rocketChatClient.upsertUser({
      sourceSystem: "skyward",
      sourceId: student.studentId,
      username: usernameFor(student),
      name: `${student.firstName} ${student.lastName}`,
      email: student.districtEmail,
      role: "student",
      active,
    });

    recordUserMap(student.studentId, "student", userId);
    idToRcUserId.set(student.studentId, userId);
    audit("student.sync", student.studentId, {
      enrollmentStatus: student.enrollmentStatus,
      rcUserId: userId,
    });

    if (!active) {
      const existing = getUserMap(student.studentId, "student");
      if (existing) await rocketChatClient.deactivateUser(existing);
    }
  }

  return idToRcUserId;
}
