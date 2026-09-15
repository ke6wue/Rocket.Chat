import cron from "node-cron";
import { runFullSync } from "./sync/engine.js";
import { config } from "./config.js";

const mode = process.argv.includes("--cron") ? "cron" : "once";

async function main() {
  if (mode === "once") {
    await runFullSync();
    process.exit(0);
  }

  console.log(`Scheduling sync with cron expression "${config.cronSchedule}"`);
  cron.schedule(config.cronSchedule, () => {
    runFullSync().catch((err) => {
      console.error("Scheduled sync run failed:", err);
    });
  });
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
