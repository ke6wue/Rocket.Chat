/**
 * These types define the *entire* allowed field set this connector will ever
 * read from Skyward or write to Rocket.Chat. Skyward's Integration Access
 * grant may expose far more (grades, attendance, discipline, health/IEP,
 * state/SSN IDs) — deliberately do not widen these types to pull that data
 * in just because a field happens to be available. If a future feature
 * genuinely needs more, add it here explicitly and update the FERPA notes
 * in README.md rather than reaching into a raw/untyped API response
 * elsewhere in the codebase.
 */

export interface SkywardStaff {
  staffId: string;
  firstName: string;
  lastName: string;
  districtEmail: string;
  active: boolean;
}

export interface SkywardStudent {
  studentId: string;
  firstName: string;
  lastName: string;
  districtEmail: string; // school-issued email, not a personal one
  gradeLevel: string;
  enrollmentStatus: "active" | "withdrawn" | "inactive";
}

export interface SkywardGuardian {
  guardianId: string;
  firstName: string;
  lastName: string;
  email: string;
  studentIds: string[]; // linked students
  /** Skyward's "Restrict from Family Access" / no-contact flag. When true,
   * this connector must never create an account or channel membership for
   * this guardian. Treat as a hard legal control (custody/protective order
   * situations), not a UX preference. */
  restricted: boolean;
}

export interface SkywardSection {
  sectionId: string;
  courseName: string;
  schoolYearId: string;
  teacherStaffId: string;
  studentIds: string[];
}

export type RCRole = "staff" | "student" | "parent";

export interface RCUserSpec {
  sourceSystem: "skyward";
  sourceId: string;
  username: string;
  name: string;
  email: string;
  role: RCRole;
  active: boolean;
}
