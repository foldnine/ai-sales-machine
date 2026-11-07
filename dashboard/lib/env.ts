import "server-only";

// Settings the dashboard reads from the stack's .env (docker-compose.yml passes
// them through). The outreach switches are shown, never changed, here: they
// belong to the operator and live in .env and on Telegram.
function bool(v: string | undefined, fallback: boolean) {
  if (v === undefined || v === "") return fallback;
  return v.toLowerCase() === "true";
}

export const env = {
  databaseUrl: process.env.DATABASE_URL ?? "",
  password: process.env.DASHBOARD_PASSWORD ?? "",
  sessionSecret: process.env.DASHBOARD_SESSION_SECRET ?? "",
  timezone: process.env.GENERIC_TIMEZONE || process.env.TZ || "UTC",
  outreach: {
    paused: bool(process.env.OUTREACH_PAUSED, true),
    autosendMaster: bool(process.env.OUTREACH_AUTOSEND_ENABLED, false),
    dailyLimit: Number(process.env.OUTREACH_DAILY_LIMIT ?? 5),
    hourStart: Number(process.env.OUTREACH_WORKING_HOUR_START ?? 9),
    hourEnd: Number(process.env.OUTREACH_WORKING_HOUR_END ?? 17),
    workingDays: process.env.OUTREACH_WORKING_DAYS ?? "1,2,3,4,5",
    minScore: Number(process.env.OUTREACH_MIN_SCORE ?? 60),
  },
};

export function assertConfigured() {
  const missing = [
    ["DATABASE_URL", env.databaseUrl],
    ["DASHBOARD_PASSWORD", env.password],
    ["DASHBOARD_SESSION_SECRET", env.sessionSecret],
  ].filter(([, v]) => !v).map(([k]) => k);
  if (missing.length) {
    throw new Error(`Dashboard is not configured: ${missing.join(", ")} missing. Run make init or ./install.sh.`);
  }
  if (env.sessionSecret.length < 32) {
    throw new Error("DASHBOARD_SESSION_SECRET must be at least 32 characters.");
  }
}
