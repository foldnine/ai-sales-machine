import "server-only";
import { sql } from "@/lib/db";
import { isUuid } from "@/lib/utils";

export type QueueItem = {
  outreach_id: string; company_id: string; company_name: string; domain: string; full_name: string | null;
  title: string | null; email: string; person_kind: string | null; score: number | null; score_band: string | null;
  subject: string; created_at: Date; sequence_step: number; segment: string | null;
};

export async function getQueue() {
  return sql<QueueItem[]>`
    SELECT q.outreach_id, q.company_id, q.company_name, q.domain::text AS domain, q.full_name, q.title, q.email::text AS email,
           q.person_kind, q.score, q.score_band, q.subject, q.created_at, q.sequence_step, o.segment
    FROM v_approval_queue q JOIN outreach o ON o.id = q.outreach_id
    ORDER BY q.score DESC NULLS LAST, q.created_at`;
}

export type ResearchOutput = {
  company_summary?: string;
  why_now?: string;
  facts?: { fact: string; source?: string; observed_at?: string }[];
  reasonable_inferences?: { inference: string; based_on?: string; confidence?: number }[];
  unknown?: string[];
  technology?: { name: string; evidence?: string; source?: string }[];
  recommended_service?: string;
  confidence?: number;
};

export type DraftDetail = {
  outreach_id: string; status: string; subject: string; body: string; created_at: Date; sequence_step: number;
  campaign: string | null; segment: string | null; variant: Record<string, unknown> | null;
  lead_id: string; lead_reason: string | null; recommended_offer: string | null; lead_score: number | null;
  company_id: string; company_name: string; domain: string; website: string | null; country: string | null;
  industry: string | null; employee_count: number | null; description: string | null;
  fit_score: number | null; research_score: number | null; decision_maker_score: number | null;
  total_score: number | null; score_band: string | null;
  full_name: string | null; title: string | null; email: string | null; email_status: string | null;
  person_kind: string | null; person_source_url: string | null; discovery_method: string | null;
  research: ResearchOutput | null; scoring_reason: string | null;
  signals: { signal_type: string; signal: string; source_url: string | null; confidence: number }[];
  autosend: { approved: boolean; reasons: string[]; created_at: Date }[];
  history: { action: string; actor: string; created_at: Date; detail: Record<string, unknown> }[];
};

export async function getDraft(id: string) {
  if (!isUuid(id)) return null;
  const [d] = await sql<DraftDetail[]>`
    SELECT o.id AS outreach_id, o.status, o.subject, o.body, o.created_at, o.sequence_step, o.campaign, o.segment, o.variant,
           l.id AS lead_id, l.reason AS lead_reason, l.recommended_offer, l.score AS lead_score,
           c.id AS company_id, c.name AS company_name, c.domain::text AS domain, c.website, c.country, c.industry,
           c.employee_count, c.description, c.fit_score, c.research_score, c.decision_maker_score, c.total_score, c.score_band,
           p.full_name, p.title, p.email::text AS email, p.email_status, p.kind AS person_kind, p.source_url AS person_source_url,
           p.discovery_method,
           (SELECT r.output FROM agent_runs r WHERE r.company_id = c.id AND r.agent_name = 'research' AND r.status = 'success'
             ORDER BY r.started_at DESC LIMIT 1) AS research,
           (SELECT r.output ->> 'reason' FROM agent_runs r WHERE r.company_id = c.id AND r.agent_name = 'scoring' AND r.status = 'success'
             ORDER BY r.started_at DESC LIMIT 1) AS scoring_reason,
           COALESCE((SELECT json_agg(json_build_object('signal_type', s.signal_type, 'signal', s.signal, 'source_url', s.source_url,
                                                       'confidence', s.confidence::float8) ORDER BY s.confidence DESC)
                     FROM signals s WHERE s.company_id = c.id), '[]') AS signals,
           COALESCE((SELECT json_agg(json_build_object('approved', a.approved, 'reasons', a.reasons, 'created_at', a.created_at)
                                     ORDER BY a.created_at DESC)
                     FROM autosend_decisions a WHERE a.outreach_id = o.id), '[]') AS autosend,
           COALESCE((SELECT json_agg(json_build_object('action', x.action, 'actor', x.actor, 'created_at', x.created_at, 'detail', x.detail)
                                     ORDER BY x.created_at DESC)
                     FROM operator_actions x WHERE x.outreach_id = o.id), '[]') AS history
    FROM outreach o
    JOIN leads l ON l.id = o.lead_id
    JOIN companies c ON c.id = l.company_id
    JOIN people p ON p.id = l.person_id
    WHERE o.id = ${id}`;
  return d ?? null;
}
