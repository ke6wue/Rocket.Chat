import type { SkywardSection, SkywardGuardian } from "../types.js";
import { rocketChatClient } from "../rocketchat/client.js";
import { recordTeamMap, audit } from "../store/db.js";
import { shouldSyncGuardian } from "./guardians.js";

function slug(input: string): string {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

interface SyncClassesArgs {
  sections: SkywardSection[];
  staffIdToRcUserId: Map<string, string>;
  studentIdToRcUserId: Map<string, string>;
  guardianIdToRcUserId: Map<string, string>;
  guardians: SkywardGuardian[];
}

export async function syncClasses(args: SyncClassesArgs): Promise<void> {
  const { sections, staffIdToRcUserId, studentIdToRcUserId, guardianIdToRcUserId, guardians } = args;

  // studentId -> guardian RC user ids (excluding restricted guardians)
  const guardiansByStudent = new Map<string, string[]>();
  for (const guardian of guardians) {
    if (!shouldSyncGuardian(guardian)) continue;
    const rcId = guardianIdToRcUserId.get(guardian.guardianId);
    if (!rcId) continue;
    for (const studentId of guardian.studentIds) {
      const list = guardiansByStudent.get(studentId) ?? [];
      list.push(rcId);
      guardiansByStudent.set(studentId, list);
    }
  }

  for (const section of sections) {
    const teacherRcId = staffIdToRcUserId.get(section.teacherStaffId);
    if (!teacherRcId) {
      audit("section.skip", section.sectionId, { reason: "teacher not found in staff sync" });
      continue;
    }

    const baseName = `${slug(section.courseName)}-${section.sectionId}`;
    const classTeamName = `${baseName}-class`;
    const familyTeamName = `${baseName}-family`;

    // --- Class team: teacher + enrolled students ---
    const { teamId: classTeamId } = await rocketChatClient.ensureTeam(classTeamName, teacherRcId);
    recordTeamMap(section.sectionId, "class", classTeamId);

    const studentRcIds = section.studentIds
      .map((id) => studentIdToRcUserId.get(id))
      .filter((id): id is string => Boolean(id));

    await rocketChatClient.setTeamMembers(classTeamId, classTeamName, [teacherRcId, ...studentRcIds]);
    audit("section.class_team_synced", section.sectionId, {
      teamId: classTeamId,
      memberCount: studentRcIds.length + 1,
    });

    // --- Family team: teacher + guardians of enrolled students. ---
    // Students are never members here by design — see README FERPA notes.
    const { teamId: familyTeamId } = await rocketChatClient.ensureTeam(familyTeamName, teacherRcId);
    recordTeamMap(section.sectionId, "family", familyTeamId);

    const guardianRcIds = new Set<string>();
    for (const studentId of section.studentIds) {
      for (const rcId of guardiansByStudent.get(studentId) ?? []) guardianRcIds.add(rcId);
    }

    await rocketChatClient.setTeamMembers(familyTeamId, familyTeamName, [
      teacherRcId,
      ...guardianRcIds,
    ]);
    audit("section.family_team_synced", section.sectionId, {
      teamId: familyTeamId,
      memberCount: guardianRcIds.size + 1,
    });
  }
}
