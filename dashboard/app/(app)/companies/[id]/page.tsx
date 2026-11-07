import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, ExternalLink, ShieldOff } from "lucide-react";
import { verifySession } from "@/lib/session";
import { env } from "@/lib/env";
import { getCompany } from "@/lib/queries/companies";
import { PageBody } from "@/components/page-header";
import { Card, CardBody, CardHeader } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Empty } from "@/components/ui/empty";
import { ResearchPanel, ScoreBreakdown, SignalList, SourceLink } from "@/components/evidence";
import {
  ago, classificationLabel, classificationTone, companyStatusTone, dateTime, duration, humanize, outreachLabel, outreachTone, segmentLabel,
} from "@/lib/format";
import { cn } from "@/lib/utils";

export const metadata: Metadata = { title: "Company" };

export default async function CompanyPage({ params }: { params: Promise<{ id: string }> }) {
  await verifySession();
  const { id } = await params;
  const c = await getCompany(id);
  if (!c) notFound();

  return (
    <>
      <header className="border-b">
        <div className="mx-auto max-w-[1400px] px-4 pb-5 pt-5 md:px-8">
          <Link href="/companies" className="inline-flex items-center gap-1 text-[12px] text-fg-subtle hover:text-fg">
            <ArrowLeft className="size-3" /> Companies
          </Link>
          <div className="mt-3 flex flex-wrap items-start gap-4">
            <div className="flex size-11 shrink-0 items-center justify-center rounded-lg border bg-bg-subtle text-[16px] font-semibold text-fg-muted">
              {c.name.slice(0, 1)}
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-2">
                <h1 className="page-title text-[20px] font-semibold tracking-tight">{c.name}</h1>
                <Badge tone={companyStatusTone(c.status)}>{humanize(c.status)}</Badge>
                {c.suppressed ? <Badge tone="danger"><ShieldOff className="size-3" /> Suppressed</Badge> : null}
              </div>
              <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-[12px] text-fg-muted">
                <a href={c.website ?? `https://${c.domain}`} target="_blank" rel="noreferrer noopener" className="inline-flex items-center gap-1 hover:text-accent">
                  {c.domain} <ExternalLink className="size-3" />
                </a>
                {c.industry ? <span>{c.industry}</span> : null}
                {c.country ? <span>{c.country}</span> : null}
                {c.employee_count ? <span>{c.employee_count} people</span> : null}
                <span>{segmentLabel(c.segment)}</span>
                <span>Found {ago(c.created_at)} via {humanize(c.source)}</span>
              </div>
              {c.description ? <p className="mt-2 max-w-3xl text-fg-muted">{c.description}</p> : null}
            </div>
          </div>
        </div>
      </header>

      <PageBody>
        <div className="grid gap-5 lg:grid-cols-[1fr_320px]">
          <div className="min-w-0 space-y-5">
            <Card>
              <CardHeader title="Signals" description={c.scoring_reason ?? "Public evidence of a need, each with its source."} />
              <CardBody><SignalList signals={c.signals} /></CardBody>
            </Card>
            <Card>
              <CardHeader title="Research" description="Facts with sources, kept apart from inferences and unknowns." />
              <CardBody><ResearchPanel research={c.research} /></CardBody>
            </Card>
            <Card>
              <CardHeader title="Outreach" />
              {c.outreach.length === 0 ? (
                <Empty title="No messages yet" />
              ) : (
                <ul className="divide-y">
                  {c.outreach.map((o) => (
                    <li key={o.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                      <Badge tone={outreachTone(o.status)}>{outreachLabel(o.status)}</Badge>
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-medium">{o.subject}</p>
                        <p className="text-[12px] text-fg-subtle">
                          To {o.recipient ?? "—"} · {o.sequence_step === 1 ? "first message" : `follow-up ${o.sequence_step - 1}`}
                          {o.sent_at ? ` · sent ${dateTime(o.sent_at, env.timezone)}` : ` · drafted ${ago(o.created_at)}`}
                          {o.reply_at ? " · replied" : ""}
                          {o.rejection_reason ? ` · ${o.rejection_reason}` : ""}
                        </p>
                      </div>
                      {o.status === "pending_approval" ? (
                        <Link href={`/approvals?id=${o.id}`} className="text-[12px] font-medium text-accent hover:underline">Review</Link>
                      ) : null}
                    </li>
                  ))}
                </ul>
              )}
            </Card>
            {c.messages.length ? (
              <Card>
                <CardHeader title="Conversation" />
                <ul className="divide-y">
                  {c.messages.map((m) => (
                    <li key={m.id} className="px-4 py-3">
                      <div className="flex items-center gap-2 text-[12px]">
                        <span className="font-medium">{m.direction === "inbound" ? "Reply" : "Sent"}</span>
                        {m.classification ? <Badge tone={classificationTone(m.classification)}>{classificationLabel(m.classification)}</Badge> : null}
                        <span className="ml-auto text-fg-subtle">{dateTime(m.created_at, env.timezone)}</span>
                      </div>
                      <p className="mt-1.5 whitespace-pre-wrap text-fg-muted">{m.body}</p>
                    </li>
                  ))}
                </ul>
              </Card>
            ) : null}
          </div>

          <aside className="space-y-5">
            <Card>
              <CardHeader title="Score" />
              <CardBody>
                <ScoreBreakdown fit={c.fit_score} research={c.research_score} dm={c.decision_maker_score} total={c.total_score} band={c.score_band} />
              </CardBody>
            </Card>
            <Card>
              <CardHeader title="Contacts" />
              {c.people.length === 0 ? (
                <Empty title="No contact found yet">WF-03 looks for a named decision maker on the company's own pages.</Empty>
              ) : (
                <ul className="divide-y">
                  {c.people.map((p) => (
                    <li key={p.id} className="px-4 py-3">
                      <p className="font-medium">{p.full_name ?? "General inbox"}</p>
                      {p.title ? <p className="text-[12px] text-fg-muted">{p.title}</p> : null}
                      <div className="mt-1 flex items-center gap-2">
                        <span className="truncate font-mono text-[11.5px] text-fg-muted">{p.email ?? "no address"}</span>
                        <Badge tone={p.email_status === "valid" ? "success" : p.email_status === "bounced" ? "danger" : "neutral"}>{humanize(p.email_status)}</Badge>
                      </div>
                      <SourceLink href={p.source_url} className="mt-1" />
                    </li>
                  ))}
                </ul>
              )}
            </Card>
            {c.tech_stack?.length ? (
              <Card>
                <CardHeader title="Stack" />
                <CardBody className="flex flex-wrap gap-1.5">
                  {c.tech_stack.map((t) => (
                    <span key={t} className="rounded border bg-bg-subtle px-1.5 py-0.5 font-mono text-[11px] text-fg-muted">{t}</span>
                  ))}
                </CardBody>
              </Card>
            ) : null}
            <Card>
              <CardHeader title="Agent runs" />
              {c.runs.length === 0 ? <Empty title="No runs yet" /> : (
                <ul className="divide-y">
                  {c.runs.map((r) => (
                    <li key={r.id} className="flex items-center gap-2.5 px-4 py-2.5 text-[12px]">
                      <span className={cn("size-1.5 rounded-full", r.status === "success" ? "bg-success" : r.status === "running" ? "bg-accent" : "bg-danger")} />
                      <span className="font-medium capitalize">{r.agent_name}</span>
                      <span className="text-fg-subtle">{duration(r.duration_ms)}</span>
                      <span className="ml-auto text-fg-subtle">{ago(r.started_at)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </Card>
          </aside>
        </div>
      </PageBody>
    </>
  );
}
