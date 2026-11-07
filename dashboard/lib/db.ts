import "server-only";
import postgres from "postgres";
import { env } from "./env";

// One small pool per server process. The role behind DATABASE_URL is
// aisales_dashboard (0033_dashboard.sql): SELECT on the public schema and
// EXECUTE on dashboard_approve / dashboard_reject / dashboard_edit, nothing else.
const globalForDb = globalThis as unknown as { sql?: ReturnType<typeof postgres> };

export const sql =
  globalForDb.sql ??
  postgres(env.databaseUrl || "postgres://invalid", {
    max: 5,
    idle_timeout: 30,
    connect_timeout: 10,
    prepare: true,
    connection: { application_name: "ai-sales-dashboard", statement_timeout: 15000 },
    // numeric and bigint arrive as strings by default; every query here casts
    // counts to int and rates to float8, so they are plain numbers.
  });

if (process.env.NODE_ENV !== "production") globalForDb.sql = sql;
