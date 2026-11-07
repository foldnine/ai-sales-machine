import "server-only";
import { sql } from "@/lib/db";
import { isUuid } from "@/lib/utils";
import type { ResearchOutput } from "./approvals";

export const COMPANY_STATUSES = ["new", "researching", "researched", "scored", "enriching", "ready", "contacted", "replied", "opportunity", "won", "lost", "ignored", "suppressed"] as const;
export const SORTS = { score: "c.total_score DESC NULLS LAST, c.created_at DESC", newest: "c.created_at DESC", name: "c.name ASC" } as const;

export type CompanyFilter = { q?: string; status?: string; segment?: string; band?: string; sort?: keyof typeof SORTS; page?: number };
export const PAGE_SIZE = 50;

export type CompanyRow = {
  id: string; name: string; domain: string; country: string | null; segment: string | null; status: string;
  total_score: number | null; score_band: string | null; signal_count: number; created_at: Date; last_outreach: string | null;
};

export async function listCompanies(f: CompanyFilter) {
  const q = f.q?.trim() ? `%${f.q.trim()}%` : null;
  const status = f.status && (COMPANY_STATUSES as readonly string[]).includes(f.status) ? f.status : null;
  const segment = f.segment || null;
  const band = f.band || null;
  // Only the fixed ORDER BY strings above ever reach sql.unsafe.
  const order = f.sort && Object.hasOwn(SORTS, f.sort) ? SORTS[f.sort] : SORTS.score;
  const offset = Math.max(0, ((f.page ?? 1) - 1) * PAGE_SIZE);

  const rows = await sql<(CompanyRow & { total: number })[]>`
    SELECT c.id, c.name, c.domain::text AS domain, c.country, c.segment, c.status, c.total_score, c.score_band, c.created_at,
           (SELECT count(*) FROM signals s WHERE s.company_id = c.id)::int AS signal_count,
           (SELECT o.status FROM outreach o JOIN leads l ON l.id = o.lead_id WHERE l.company_id = c.id
             ORDER BY o.created_at DESC LIMIT 1) AS last_outreach,
           count(*) OVER ()::int AS total
    FROM companies c
    WHERE (${q}::text IS NULL OR c.name ILIKE ${q} OR c.domain::text ILIKE ${q})
      AND (${status}::text IS NULL OR c.status = ${status})
      AND (${segment}::text IS NULL OR c.segment = ${segment})
      AND (${band}::text IS NULL OR c.score_band = ${band})
    ORDER BY ${sql.unsafe(order)}
    LIMIT ${PAGE_SIZE} OFFSET ${offset}`;
  return { rows, total: rows[0]?.total ?? 0 };
}

export async function getFacets() {
  const [r] = await sql<{ segments: { segment: string; n: number }[]; statuses: { status: string; n: number }[] }[]>`
    SELECT
      COALESCE((SELECT json_agg(x ORDER BY x.n DESC) FROM (SELECT segment, count(*)::int AS n FROM companies WHERE segment IS NOT NULL GROUP BY 1) x), '[]') AS segments,
      COALESCE((SELECT json_agg(x ORDER BY x.n DESC) FROM (SELECT status, count(*)::int AS n FROM companies GROUP BY 1) x), '[]') AS statuses`;
  return r;
}

export type CompanyDetail = {
  id: string; name: string; domain: string; website: string | null; country: string | null; industry: string | null;
  employee_count: number | null; description: string | null; segment: string | null; status: string; source: string;
  fit_score: number | null; research_score: number | null; decision_maker_score: number | null; total_score: number | null;
  score_band: string | null; created_at: Date; updated_at: Date; tech_stack: string[];
  research: ResearchOutput | null; scoring_reason: string | null; suppressed: boolean;
  signals: { signal_type: string; signal: string; source_url: string | null; confidence: number }[];
  people: { id: string; full_name: string | null; title: string | null; email: string | null; email_status: string; kind: string; source_url: string | null }[];
  outreach: { id: string; status: string; subject: string; created_at: Date; sent_at: Date | null; reply_at: Date | null; sequence_step: number; recipient: string | null; approved_by: string | null; rejection_reason: string | null }[];
  messages: { id: string; direction: string; classification: string | null; subject: string | null; body: string; created_at: Date }[];
  runs: { id: string; agent_name: string; status: string; model: string | null; started_at: Date; duration_ms: number | null; error: string | null }[];
};

export async function getCompany(id: string) {
  if (!isUuid(id)) return null;
  const [c] = await sql<CompanyDetail[]>`
    SELECT c.id, c.name, c.domain::text AS domain, c.website, c.country, c.industry, c.employee_count, c.description, c.segment,
           c.status, c.source, c.fit_score, c.research_score, c.decision_maker_score, c.total_score, c.score_band,
           c.created_at, c.updated_at, c.tech_stack,
           (SELECT r.output FROM agent_runs r WHERE r.company_id = c.id AND r.agent_name = 'research' AND r.status = 'success'
             ORDER BY r.started_at DESC LIMIT 1) AS research,
           (SELECT r.output ->> 'reason' FROM agent_runs r WHERE r.company_id = c.id AND r.agent_name = 'scoring' AND r.status = 'success'
             ORDER BY r.started_at DESC LIMIT 1) AS scoring_reason,
           EXISTS (SELECT 1 FROM suppression_list s WHERE s.domain = c.domain) AS suppressed,
           COALESCE((SELECT json_agg(json_build_object('signal_type', s.signal_type, 'signal', s.signal, 'source_url', s.source_url,
                       'confidence', s.confidence::float8) ORDER BY s.confidence DESC) FROM signals s WHERE s.company_id = c.id), '[]') AS signals,
           COALESCE((SELECT json_agg(json_build_object('id', p.id, 'full_name', p.full_name, 'title', p.title, 'email', p.email,
                       'email_status', p.email_status, 'kind', p.kind, 'source_url', p.source_url) ORDER BY p.kind, p.created_at)
                     FROM people p WHERE p.company_id = c.id), '[]') AS people,
           COALESCE((SELECT json_agg(json_build_object('id', o.id, 'status', o.status, 'subject', o.subject, 'created_at', o.created_at,
                       'sent_at', o.sent_at, 'reply_at', o.reply_at, 'sequence_step', o.sequence_step,
                       'recipient', COALESCE(p.full_name, p.email), 'approved_by', o.approved_by, 'rejection_reason', o.rejection_reason)
                       ORDER BY o.created_at DESC)
                     FROM outreach o JOIN leads l ON l.id = o.lead_id JOIN people p ON p.id = l.person_id WHERE l.company_id = c.id), '[]') AS outreach,
           COALESCE((SELECT json_agg(json_build_object('id', m.id, 'direction', m.direction, 'classification', m.classification,
                       'subject', m.subject, 'body', m.body, 'created_at', m.created_at) ORDER BY m.created_at DESC)
                     FROM messages m JOIN conversations cv ON cv.id = m.conversation_id JOIN leads l ON l.id = cv.lead_id
                     WHERE l.company_id = c.id), '[]') AS messages,
           COALESCE((SELECT json_agg(json_build_object('id', r.id, 'agent_name', r.agent_name, 'status', r.status, 'model', r.model,
                       'started_at', r.started_at, 'duration_ms', r.duration_ms, 'error', r.error) ORDER BY r.started_at DESC)
                     FROM agent_runs r WHERE r.company_id = c.id), '[]') AS runs
    FROM companies c WHERE c.id = ${id}`;
  return c ?? null;
}
