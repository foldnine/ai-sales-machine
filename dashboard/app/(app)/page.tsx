import Link from "next/link";
import { ArrowRight, ArrowUpRight, Inbox } from "lucide-react";
import { verifySession } from "@/lib/session";
import { env } from "@/lib/env";
import { getActivity, getAgentHealth, getFunnel, getKpis, getQueuePreview, getRecentReplies } from "@/lib/queries/overview";
import { PageBody, PageHeader } from "@/components/page-header";
import { Card, CardBody, CardHeader } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Empty } from "@/components/ui/empty";
import { buttonClass } from "@/components/ui/button";
import { ActivityChart } from "@/components/charts/activity-chart";
import { ago, bandLabel, bandTone, classificationLabel, classificationTone, duration, eur, num, pct } from "@/lib/format";
import { cn } from "@/lib/utils";
import { ScorePill } from "@/components/score-pill";

export default async function OverviewPage() {
  await verifySession();
  const [kpis, funnel, activity, queue, replies, agents] = await Promise.all([
    getKpis(), getFunnel(), getActivity(30, env.timezone), getQueuePreview(), getRecentReplies(), getAgentHealth(),
  ]);

  return (
    <>
      <PageHeader
        title="Overview"
        description="What the pipeline found, what is waiting for you, and what came back."
        actions={kpis.awaiting_approval > 0 ? (
          <Link href="/approvals" className={buttonClass("primary")}>
            <Inbox className="size-4" /> Review {kpis.awaiting_approval} draft{kpis.awaiting_approval === 1 ? "" : "s"}
          </Link>
        ) : null}
      />
      <PageBody className="space-y-6">
        <section className="grid grid-cols-2 gap-px overflow-hidden rounded-lg border bg-border shadow-card lg:grid-cols-5">
          <Kpi label="Awaiting approval" value={num(kpis.awaiting_approval)} hint={`${kpis.drafted_24h} drafted in 24h`} href="/approvals" highlight={kpis.awaiting_approval > 0} />
          <Kpi label="Emails sent" value={num(kpis.emails_sent)} hint={`${kpis.emails_sent_7d} in the last 7 days`} href="/outreach" />
          <Kpi label="Reply rate" value={pct(kpis.reply_rate_pct)} hint={`${kpis.replied} of ${kpis.leads_contacted} contacted`} href="/replies" />
          <Kpi label="Open pipeline" value={eur(kpis.pipeline_eur)} hint={`${kpis.sales_conversations} sales conversations`} href="/replies" />
          <Kpi label="Revenue" value={eur(kpis.revenue_eur)} hint={`${kpis.clients} won · ${kpis.proposals} proposals`} href="/performance" />
        </section>

        <div className="grid gap-6 xl:grid-cols-3">
          <Card className="xl:col-span-2">
            <CardHeader title="Activity" description="Last 30 days, per day." />
            <CardBody><ActivityChart data={activity} /></CardBody>
          </Card>
          <Card>
            <CardHeader title="Funnel" description="Every company the pipeline has seen." />
            <CardBody className="space-y-2.5">
              <FunnelRow label="Discovered" value={funnel.discovered} max={funnel.discovered} />
              <FunnelRow label="Researched" value={funnel.researched} max={funnel.discovered} />
              <FunnelRow label="Qualified" value={funnel.qualified} max={funnel.discovered} />
              <FunnelRow label="Contacted" value={funnel.contacted} max={funnel.discovered} />
              <FunnelRow label="Replied" value={funnel.replied} max={funnel.discovered} />
              <FunnelRow label="Conversations" value={funnel.conversations} max={funnel.discovered} />
              <FunnelRow label="Won" value={funnel.won} max={funnel.discovered} accent />
            </CardBody>
          </Card>
        </div>

        <div className="grid gap-6 xl:grid-cols-3">
          <Card>
            <CardHeader title="Waiting for you" description="Highest score first."
              action={<Link href="/approvals" className="inline-flex items-center gap-1 text-[12px] text-fg-muted hover:text-fg">All <ArrowRight className="size-3" /></Link>} />
            {queue.length === 0 ? (
              <Empty title="Nothing to approve">New drafts appear here as the pipeline writes them.</Empty>
            ) : (
              <ul className="divide-y">
                {queue.map((q) => (
                  <li key={q.outreach_id}>
                    <Link href={`/approvals?id=${q.outreach_id}`} className="flex items-center gap-3 px-4 py-2.5 hover:bg-bg-subtle/60">
                      <ScorePill score={q.score} />
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-medium">{q.company_name}</p>
                        <p className="truncate text-[12px] text-fg-muted">{q.full_name ?? q.email} · {q.subject}</p>
                      </div>
                      <Badge tone={bandTone(q.score_band)}>{bandLabel(q.score_band)}</Badge>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <Card>
            <CardHeader title="Latest replies"
              action={<Link href="/replies" className="inline-flex items-center gap-1 text-[12px] text-fg-muted hover:text-fg">All <ArrowRight className="size-3" /></Link>} />
            {replies.length === 0 ? (
              <Empty title="No replies yet">Replies show up here once WF-08 reads the inbox.</Empty>
            ) : (
              <ul className="divide-y">
                {replies.map((r) => (
                  <li key={r.id}>
                    <Link href={`/companies/${r.company_id}`} className="block px-4 py-2.5 hover:bg-bg-subtle/60">
                      <div className="flex items-center gap-2">
                        <span className="truncate font-medium">{r.company_name}</span>
                        <Badge tone={classificationTone(r.classification)}>{classificationLabel(r.classification)}</Badge>
                        <span className="ml-auto shrink-0 text-[11px] text-fg-subtle">{ago(r.created_at)}</span>
                      </div>
                      <p className="mt-0.5 line-clamp-1 text-[12px] text-fg-muted">{r.body}</p>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <Card>
            <CardHeader title="Agents" description="Last 24 hours."
              action={<Link href="/system" className="inline-flex items-center gap-1 text-[12px] text-fg-muted hover:text-fg">System <ArrowRight className="size-3" /></Link>} />
            {agents.length === 0 ? (
              <Empty title="No agent runs yet" />
            ) : (
              <ul className="divide-y">
                {agents.map((a) => {
                  const rate = a.runs_24h ? (a.succeeded / a.runs_24h) * 100 : null;
                  return (
                    <li key={a.agent_name} className="flex items-center gap-3 px-4 py-2.5">
                      <span className={cn("size-2 rounded-full", a.failed === 0 ? "bg-success" : a.failed / Math.max(a.runs_24h, 1) > 0.2 ? "bg-danger" : "bg-warning")} />
                      <span className="flex-1 font-medium capitalize">{a.agent_name}</span>
                      <span className="tabular text-[12px] text-fg-muted">{a.runs_24h} runs</span>
                      <span className="tabular w-14 text-right text-[12px] text-fg-muted">{rate == null ? "—" : `${Math.round(rate)}%`}</span>
                      <span className="tabular w-16 text-right text-[12px] text-fg-subtle">{duration(a.avg_duration_ms)}</span>
                    </li>
                  );
                })}
              </ul>
            )}
          </Card>
        </div>
      </PageBody>
    </>
  );
}

function Kpi({ label, value, hint, href, highlight }: { label: string; value: string; hint: string; href: string; highlight?: boolean }) {
  return (
    <Link href={href} className="group relative bg-surface px-4 py-4 transition-colors hover:bg-bg-subtle/60">
      <p className="flex items-center gap-1 text-[12px] text-fg-muted">
        {label}
        <ArrowUpRight className="size-3 opacity-0 transition group-hover:opacity-100" />
      </p>
      <p className={cn("tabular mt-1.5 text-[24px] font-semibold tracking-tight", highlight && "text-accent")}>{value}</p>
      <p className="mt-0.5 truncate text-[12px] text-fg-subtle">{hint}</p>
    </Link>
  );
}

function FunnelRow({ label, value, max, accent }: { label: string; value: number; max: number; accent?: boolean }) {
  const w = max > 0 ? Math.max((value / max) * 100, value > 0 ? 2 : 0) : 0;
  return (
    <div>
      <div className="mb-1 flex items-baseline justify-between text-[12px]">
        <span className="text-fg-muted">{label}</span>
        <span className="tabular font-medium">{num(value)}</span>
      </div>
      <div className="h-1.5 overflow-hidden rounded-full bg-bg-subtle">
        <div className={cn("h-full rounded-full", accent ? "bg-success" : "bg-accent")} style={{ width: `${w}%`, opacity: accent ? 1 : 0.35 + 0.65 * (w / 100) }} />
      </div>
    </div>
  );
}
