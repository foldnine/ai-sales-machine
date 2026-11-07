import "server-only";
import { sql } from "@/lib/db";

export type Kpis = {
  companies: number; companies_7d: number; qualified: number; awaiting_approval: number;
  emails_sent: number; emails_sent_7d: number; leads_contacted: number; replied: number;
  sales_conversations: number; meetings: number; proposals: number; clients: number;
  reply_rate_pct: number | null; bounce_rate_pct: number | null; pipeline_eur: number; revenue_eur: number;
  companies_24h: number; drafted_24h: number; sent_24h: number; replies_24h: number;
};

export async function getKpis() {
  const [k] = await sql<Kpis[]>`
    SELECT companies, companies_7d, qualified, awaiting_approval, emails_sent, emails_sent_7d, leads_contacted,
           replied, sales_conversations, meetings, proposals, clients,
           reply_rate_pct::float8 AS reply_rate_pct, bounce_rate_pct::float8 AS bounce_rate_pct,
           pipeline_eur, revenue_eur, companies_24h, drafted_24h, sent_24h, replies_24h
    FROM v_sales_kpis`;
  return k;
}

export async function getFunnel() {
  const [f] = await sql<{ discovered: number; researched: number; qualified: number; contacted: number; replied: number; conversations: number; won: number }[]>`
    SELECT
      (SELECT count(*) FROM companies)::int AS discovered,
      (SELECT count(*) FROM companies WHERE status NOT IN ('new','researching'))::int AS researched,
      -- Each stage counts companies that reached it at any point, so the
      -- funnel only narrows: qualified = scored at or above the outreach bar,
      -- or already given a lead.
      (SELECT count(*) FROM companies c
        WHERE c.total_score >= 60 OR EXISTS (SELECT 1 FROM leads l WHERE l.company_id = c.id))::int AS qualified,
      (SELECT leads_contacted FROM v_sales_kpis) AS contacted,
      (SELECT replied FROM v_sales_kpis) AS replied,
      (SELECT sales_conversations FROM v_sales_kpis) AS conversations,
      (SELECT clients FROM v_sales_kpis) AS won`;
  return f;
}

export type ActivityDay = { day: string; discovered: number; drafted: number; sent: number; replies: number };

export async function getActivity(days = 30, timeZone = "UTC") {
  return sql<ActivityDay[]>`
    WITH d AS (
      SELECT generate_series((now() AT TIME ZONE ${timeZone})::date - (${days - 1})::int,
                             (now() AT TIME ZONE ${timeZone})::date, interval '1 day')::date AS day
    )
    SELECT to_char(d.day, 'YYYY-MM-DD') AS day,
      (SELECT count(*) FROM companies c WHERE (c.created_at AT TIME ZONE ${timeZone})::date = d.day)::int AS discovered,
      (SELECT count(*) FROM outreach o WHERE (o.created_at AT TIME ZONE ${timeZone})::date = d.day)::int AS drafted,
      (SELECT count(*) FROM outreach o WHERE (o.sent_at AT TIME ZONE ${timeZone})::date = d.day)::int AS sent,
      (SELECT count(*) FROM messages m WHERE m.direction = 'inbound' AND (m.created_at AT TIME ZONE ${timeZone})::date = d.day)::int AS replies
    FROM d ORDER BY d.day`;
}

export async function getQueuePreview(limit = 5) {
  return sql<{ outreach_id: string; company_name: string; full_name: string | null; email: string; score: number | null; score_band: string | null; created_at: Date; subject: string }[]>`
    SELECT outreach_id, company_name, full_name, email, score, score_band, created_at, subject
    FROM v_approval_queue ORDER BY score DESC NULLS LAST, created_at LIMIT ${limit}`;
}

export async function getRecentReplies(limit = 5) {
  return sql<{ id: string; company_id: string; company_name: string; full_name: string | null; classification: string | null; body: string; created_at: Date }[]>`
    SELECT m.id, c.id AS company_id, c.name AS company_name, p.full_name, m.classification, m.body, m.created_at
    FROM messages m
    JOIN conversations cv ON cv.id = m.conversation_id
    JOIN leads l ON l.id = cv.lead_id
    JOIN companies c ON c.id = l.company_id
    JOIN people p ON p.id = l.person_id
    WHERE m.direction = 'inbound'
    ORDER BY m.created_at DESC LIMIT ${limit}`;
}

export async function getAgentHealth() {
  return sql<{ agent_name: string; runs_24h: number; succeeded: number; failed: number; in_flight: number; avg_duration_ms: number | null; last_run_at: Date | null }[]>`
    SELECT agent_name, runs_24h::int, succeeded::int, failed::int, in_flight::int,
           avg_duration_ms::float8 AS avg_duration_ms, last_run_at
    FROM v_agent_health ORDER BY agent_name`;
}
