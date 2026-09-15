import { skywardClient } from "../skyward/client.js";
import { syncStaff } from "./staff.js";
import { syncStudents } from "./students.js";
import { syncGuardians } from "./guardians.js";
import { syncClasses } from "./classes.js";
import { audit } from "../store/db.js";
import { config } from "../config.js";

export async function runFullSync(): Promise<void> {
  console.log(`Starting sync run (allowWrites=${config.allowWrites})`);
  audit("sync_run.start", "engine", { allowWrites: config.allowWrites });

  const [staff, students, guardians, sections] = await Promise.all([
    skywardClient.listStaff(),
    skywardClient.listStudents(),
    skywardClient.listGuardians(),
    skywardClient.listSections(),
  ]);

  // Order matters: people before classes, since classes reference RC user ids.
  const staffMap = await syncStaff(staff);
  const studentMap = await syncStudents(students);
  const guardianMap = await syncGuardians(guardians);

  await syncClasses({
    sections,
    staffIdToRcUserId: staffMap,
    studentIdToRcUserId: studentMap,
    guardianIdToRcUserId: guardianMap,
    guardians,
  });

  audit("sync_run.complete", "engine", {
    staffCount: staff.length,
    studentCount: students.length,
    guardianCount: guardians.length,
    sectionCount: sections.length,
  });
  console.log("Sync run complete.");
}
