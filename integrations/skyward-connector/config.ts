import "dotenv/config";

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Missing required env var ${name}. Copy .env.example to .env and fill it in — ` +
        `this connector refuses to start with silent defaults for credentials.`
    );
  }
  return value;
}

export const config = {
  skyward: {
    baseUrl: required("SKYWARD_BASE_URL"),
    tokenUrl: required("SKYWARD_TOKEN_URL"),
    clientId: required("SKYWARD_CLIENT_ID"),
    clientSecret: required("SKYWARD_CLIENT_SECRET"),
    entityId: process.env.SKYWARD_ENTITY_ID ?? "",
    schoolYearId: process.env.SKYWARD_SCHOOL_YEAR_ID ?? "",
  },
  rocketchat: {
    baseUrl: required("ROCKETCHAT_BASE_URL"),
    adminUserId: required("ROCKETCHAT_ADMIN_USER_ID"),
    adminToken: required("ROCKETCHAT_ADMIN_TOKEN"),
  },
  store: {
    sqlitePath: process.env.SQLITE_PATH ?? "./data/connector.db",
  },
  cronSchedule: process.env.CRON_SCHEDULE ?? "0 2 * * *",
  // Hard safety gate: sync logic can run in dry-run (log-only) mode without
  // this being explicitly "true". Prevents an untested config from silently
  // creating/deleting real accounts on first run.
  allowWrites: (process.env.ALLOW_WRITES ?? "false").toLowerCase() === "true",
};
