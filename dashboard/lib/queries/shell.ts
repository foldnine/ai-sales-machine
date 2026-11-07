import "server-only";
import { sql } from "@/lib/db";
import { env } from "@/lib/env";

export async function getShellCounts() {
  const [row] = await sql<{ pending: number; conversations: number; failures: number; autosend: boolean | null }[]>`
    SELECT
      (SELECT count(*) FROM outreach WHERE status = 'pending_approval')::int AS pending,
      (SELECT count(*) FROM conversations WHERE status IN ('open','awaiting_human','escalated'))::int AS conversations,
      (SELECT count(*) FROM agent_runs WHERE status IN ('error','timeout') AND started_at > now() - interval '24 hours')::int AS failures,
      autosend_enabled() AS autosend
  `;
  return { ...row, paused: env.outreach.paused, autosendMaster: env.outreach.autosendMaster };
}
