import Link from "next/link";
import { ArrowUpRight, Building2, Mail, ShieldAlert, UserRound } from "lucide-react";
import type { DraftDetail } from "@/lib/queries/approvals";
import { Badge } from "@/components/ui/badge";
import { Card, CardBody, CardHeader } from "@/components/ui/card";
import { ResearchPanel, ScoreBreakdown, SignalList, SourceLink } from "@/components/evidence";
import { dateTime, humanize, offerLabel, segmentLabel } from "@/lib/format";
import { EmailReview } from "./email-review";

export function DraftPanel({ draft: d, nextId, prevId, timezone }: {
  draft: DraftDetail; nextId: string | null; prevId: string | null; timezone: string;
}) {
  const heldBy = d.autosend.find((a) => !a.approved);
  return (
    <div className="mx-auto max-w-[980px] space-y-5 px-4 py-6 md:px-8">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <h2 className="truncate text-[18px] font-semibold tracking-tight">{d.company_name}</h2>
            <Link href={`/companies/${d.company_id}`} className="inline-flex items-center gap-0.5 text-[12px] text-fg-subtle hover:text-accent">
              Company <ArrowUpRight className="size-3" />
            </Link>
          </div>
          <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-[12px] text-fg-muted">
            <span className="inline-flex items-center gap-1"><Building2 className="size-3.5" />{d.industry ?? "—"}{d.country ? ` · ${d.country}` : ""}{d.employee_count ? ` · ${d.employee_count} people` : ""}</span>
            <a href={d.website ?? `https://${d.domain}`} target="_blank" rel="noreferrer noopener" className="hover:text-accent">{d.domain}</a>
            <Badge>{segmentLabel(d.segment)}</Badge>
            {d.campaign ? <Badge tone="accent">{d.campaign}</Badge> : null}
          </div>
        </div>
      </div>

      <div className="grid gap-5 lg:grid-cols-[1fr_280px]">
        <div className="min-w-0 space-y-5">
          <Card>
            <div className="flex flex-wrap items-center gap-x-4 gap-y-1 border-b px-4 py-3 text-[12px]">
              <span className="inline-flex items-center gap-1.5 text-fg-muted">
                {d.person_kind === "role" ? <Mail className="size-3.5" /> : <UserRound className="size-3.5" />}
                <span className="text-fg-subtle">To</span>
                <span className="font-medium text-fg">{d.full_name ?? "General inbox"}</span>
                {d.title ? <span>· {d.title}</span> : null}
              </span>
              <span className="font-mono text-[12px] text-fg-muted">{d.email}</span>
              <Badge tone={d.email_status === "valid" ? "success" : d.email_status === "guessed" ? "warning" : "neutral"}>
                {humanize(d.email_status)}
              </Badge>
              {d.person_source_url ? <SourceLink href={d.person_source_url} /> : null}
            </div>
            <EmailReview id={d.outreach_id} subject={d.subject} body={d.body} nextId={nextId} prevId={prevId} />
          </Card>

          {heldBy ? (
            <div className="flex gap-3 rounded-lg border border-warning/30 bg-warning-soft/60 px-4 py-3">
              <ShieldAlert className="mt-0.5 size-4 shrink-0 text-warning" />
              <div>
                <p className="font-medium">Autosend held this draft for you</p>
                <ul className="mt-1 list-inside list-disc text-[12px] text-fg-muted">
                  {heldBy.reasons.map((r, i) => <li key={i}>{r}</li>)}
                </ul>
              </div>
            </div>
          ) : null}

          <Card>
            <CardHeader title="Why this company" description={d.lead_reason ?? d.scoring_reason ?? undefined} />
            <CardBody><SignalList signals={d.signals} /></CardBody>
          </Card>

          <Card>
            <CardHeader title="Research" description="What the research agent read, separated from what it inferred." />
            <CardBody><ResearchPanel research={d.research} /></CardBody>
          </Card>
        </div>

        <aside className="space-y-5">
          <Card>
            <CardHeader title="Score" />
            <CardBody>
              <ScoreBreakdown fit={d.fit_score} research={d.research_score} dm={d.decision_maker_score} total={d.total_score} band={d.score_band} />
            </CardBody>
          </Card>
          <Card>
            <CardHeader title="Details" />
            <CardBody className="space-y-2.5 text-[12px]">
              <Row label="Offer" value={offerLabel(d.recommended_offer)} />
              <Row label="Step" value={d.sequence_step === 1 ? "First message" : `Follow-up ${d.sequence_step - 1}`} />
              <Row label="Found via" value={humanize(d.discovery_method)} />
              <Row label="Drafted" value={dateTime(d.created_at, timezone)} />
              {d.variant && typeof d.variant === "object" && "language" in d.variant ? <Row label="Language" value={String(d.variant.language).toUpperCase()} /> : null}
            </CardBody>
          </Card>
          {d.history.length ? (
            <Card>
              <CardHeader title="History" />
              <CardBody className="space-y-2 text-[12px]">
                {d.history.map((h, i) => (
                  <div key={i} className="flex justify-between gap-2">
                    <span className="capitalize">{h.action}</span>
                    <span className="text-fg-subtle">{dateTime(h.created_at, timezone)}</span>
                  </div>
                ))}
              </CardBody>
            </Card>
          ) : null}
        </aside>
      </div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-3">
      <span className="text-fg-subtle">{label}</span>
      <span className="text-right text-fg">{value}</span>
    </div>
  );
}
