import "server-only";
import { sql } from "@/lib/db";

export const OUTREACH_STATUSES = ["pending_approval", "approved", "queued", "sent", "rejected", "bounced", "failed", "cancelled"] as const;

export async function listOutreach(status: string | null, page: number, pageSize = 50) {
  const st = status && (OUTREACH_STATUSES as readonly string[]).includes(status) ? status : null;
  const rows = await sql<{
    id: string; status: string; subject: string; company_id: string; company_name: string; recipient: string | null;
    email: string | null; sequence_step: number; created_at: Date; sent_at: Date | null; reply_at: Date | null;
    approved_by: string | null; rejection_reason: string | null; segment: string | null; total: number;
  }[]>`
    SELECT o.id, o.status, o.subject, c.id AS company_id, c.name AS company_name, p.full_name AS recipient, p.email::text AS email,
           o.sequence_step, o.created_at, o.sent_at, o.reply_at, o.approved_by, o.rejection_reason, o.segment,
           count(*) OVER ()::int AS total
    FROM outreach o JOIN leads l ON l.id = o.lead_id JOIN companies c ON c.id = l.company_id JOIN people p ON p.id = l.person_id
    WHERE (${st}::text IS NULL OR o.status = ${st})
    ORDER BY COALESCE(o.sent_at, o.created_at) DESC
    LIMIT ${pageSize} OFFSET ${(page - 1) * pageSize}`;
  const counts = await sql<{ status: string; n: number }[]>`SELECT status, count(*)::int AS n FROM outreach GROUP BY 1 ORDER BY 2 DESC`;
  return { rows, total: rows[0]?.total ?? 0, counts };
}

export async function listConversations(filter: string | null) {
  return sql<{
    id: string; status: string; company_id: string; company_name: string; full_name: string | null; email: string | null;
    classification: string | null; confidence: number | null; last_body: string | null; last_message_at: Date | null;
    deal_value_eur: number | null; lead_status: string; escalation_reason: string | null;
  }[]>`
    SELECT cv.id, cv.status, c.id AS company_id, c.name AS company_name, p.full_name, p.email::text AS email,
           m.classification, m.classification_confidence::float8 AS confidence, m.body AS last_body, cv.last_message_at,
           l.deal_value_eur, l.status AS lead_status, cv.escalation_reason
    FROM conversations cv
    JOIN leads l ON l.id = cv.lead_id JOIN companies c ON c.id = l.company_id JOIN people p ON p.id = l.person_id
    LEFT JOIN LATERAL (SELECT * FROM messages mm WHERE mm.conversation_id = cv.id AND mm.direction = 'inbound'
                       ORDER BY mm.created_at DESC LIMIT 1) m ON true
    WHERE ${filter}::text IS NULL
       OR (${filter} = 'needs_you' AND cv.status IN ('open','awaiting_human','escalated'))
       OR (${filter} = 'nurture' AND cv.status = 'nurture')
       OR (${filter} = 'closed' AND cv.status IN ('closed_won','closed_lost','unsubscribed'))
    ORDER BY cv.last_message_at DESC NULLS LAST`;
}

export async function getPerformance() {
  const [segments, campaigns, variants, stages] = await Promise.all([
    sql<{ segment: string; active: boolean; min_score: number; companies: number; qualified: number; contacted: number; replied: number; conversations: number; meetings: number; won: number; bounced: number; reply_rate_pct: number | null }[]>`
      SELECT segment, active, min_score, companies, qualified, contacted, replied, conversations, meetings, won, bounced,
             reply_rate_pct::float8 AS reply_rate_pct
      FROM v_segment_results ORDER BY companies DESC`,
    sql<{ campaign: string; segment: string | null; offer: string | null; hypothesis: string | null; message_variant: string | null; active: boolean | null; started_at: Date | null; contacted: number; replied: number; conversations: number; calls: number; proposals: number; won: number; revenue_eur: number; reply_rate_pct: number | null }[]>`
      SELECT campaign, segment, offer, hypothesis, message_variant, active, started_at, contacted, replied, conversations, calls,
             proposals, won, revenue_eur, reply_rate_pct::float8 AS reply_rate_pct
      FROM v_campaign_results ORDER BY started_at DESC NULLS LAST`,
    sql<{ segment: string | null; cta: string | null; language: string | null; contacted: number; replied: number; conversations: number }[]>`
      SELECT segment, cta, language, contacted, replied, conversations FROM v_variant_results ORDER BY contacted DESC`,
    sql<{ stage: string; n: number; value: number }[]>`
      SELECT status AS stage, count(*)::int AS n, COALESCE(sum(deal_value_eur), 0)::int AS value
      FROM leads WHERE status IN ('replied','opportunity','meeting','audit','proposal','closed_won','closed_lost','nurture')
      GROUP BY 1`,
  ]);
  return { segments, campaigns, variants, stages };
}

export async function getSystem() {
  const [agents, failures, notifications, totals, migrations, actions] = await Promise.all([
    sql<{ agent_name: string; runs_24h: number; succeeded: number; failed: number; in_flight: number; avg_duration_ms: number | null; last_run_at: Date | null }[]>`
      SELECT agent_name, runs_24h::int, succeeded::int, failed::int, in_flight::int, avg_duration_ms::float8 AS avg_duration_ms, last_run_at
      FROM v_agent_health ORDER BY agent_name`,
    sql<{ id: string; agent_name: string; status: string; model: string | null; error: string | null; started_at: Date; company_id: string | null; company_name: string | null }[]>`
      SELECT r.id, r.agent_name, r.status, r.model, r.error, r.started_at, c.id AS company_id, c.name AS company_name
      FROM agent_runs r LEFT JOIN companies c ON c.id = r.company_id
      WHERE r.status IN ('error','timeout') ORDER BY r.started_at DESC LIMIT 15`,
    sql<{ id: string; kind: string; priority: string; title: string; occurrences: number; last_seen_at: Date }[]>`
      SELECT id, kind, priority, title, occurrences, last_seen_at FROM v_pending_notifications ORDER BY last_seen_at DESC LIMIT 10`,
    sql<{ suppressed: number; runs_7d: number; tokens_7d: number; queued_research: number }[]>`
      SELECT (SELECT count(*) FROM suppression_list)::int AS suppressed,
             (SELECT count(*) FROM agent_runs WHERE started_at > now() - interval '7 days')::int AS runs_7d,
             (SELECT COALESCE(sum(COALESCE(prompt_tokens,0) + COALESCE(output_tokens,0)), 0) FROM agent_runs WHERE started_at > now() - interval '7 days')::int AS tokens_7d,
             (SELECT count(*) FROM companies WHERE status = 'new')::int AS queued_research`,
    sql<{ version: string; applied_at: Date }[]>`SELECT version, applied_at FROM schema_migrations ORDER BY version DESC LIMIT 1`,
    sql<{ action: string; actor: string; created_at: Date; company_name: string | null; outreach_id: string }[]>`
      SELECT x.action, x.actor, x.created_at, c.name AS company_name, x.outreach_id
      FROM operator_actions x JOIN outreach o ON o.id = x.outreach_id JOIN leads l ON l.id = o.lead_id JOIN companies c ON c.id = l.company_id
      ORDER BY x.created_at DESC LIMIT 10`,
  ]);
  return { agents, failures, notifications, totals: totals[0], migration: migrations[0] ?? null, actions };
}

export async function getAutosend() {
  const [r] = await sql<{ enabled: boolean }[]>`SELECT autosend_enabled() AS enabled`;
  return r.enabled;
}
