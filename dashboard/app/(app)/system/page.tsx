import type { Metadata } from "next";
import Link from "next/link";
import { CircleCheck, CirclePause, Lock, ShieldCheck } from "lucide-react";
import { verifySession } from "@/lib/session";
import { env } from "@/lib/env";
import { getAutosend, getSystem } from "@/lib/queries/activity";
import { PageBody, PageHeader } from "@/components/page-header";
import { Card, CardBody, CardHeader } from "@/components/ui/card";
import { Table, THead, Th, Tr, Td } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Empty } from "@/components/ui/empty";
import { ago, dateTime, duration, num } from "@/lib/format";
import { cn } from "@/lib/utils";

export const metadata: Metadata = { title: "System" };

const DAYS = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

export default async function SystemPage() {
  await verifySession();
  const [s, autosend] = await Promise.all([getSystem(), getAutosend()]);
  const o = env.outreach;
  const days = o.workingDays.split(",").map((d) => DAYS[Number(d)] ?? d).join(", ");

  return (
    <>
      <PageHeader title="System" description="The switches that decide what is sent, and whether the agents are healthy." />
      <PageBody className="space-y-6">
        <Card>
          <CardHeader title="Sending" description="Read-only here, on purpose: these belong to the operator, in .env and on Telegram."
            action={<span className="inline-flex items-center gap-1 text-[11px] text-fg-subtle"><Lock className="size-3" /> Not editable from the dashboard</span>} />
          <div className="grid gap-px bg-border sm:grid-cols-2 xl:grid-cols-4">
            <Switch
              label="Outbound"
              on={!o.paused}
              onText="Sending"
              offText="Paused"
              detail={o.paused ? "OUTREACH_PAUSED=true. Approved drafts wait. Set it to false in .env to start." : "WF-06 sends approved drafts inside the window below."}
            />
            <Switch
              label="Guarded autosend"
              on={o.autosendMaster && autosend}
              onText="On"
              offText="Off"
              detail={!o.autosendMaster ? "Master switch OUTREACH_AUTOSEND_ENABLED is off. Every message needs a human." : autosend ? "First messages that pass every blocker are approved automatically. /stop on Telegram ends it." : "Master switch is on; /autosend on in Telegram would enable it."}
            />
            <Fact label="Daily limit" value={`${o.dailyLimit} emails`} detail={`Minimum score ${o.minScore} to draft.`} />
            <Fact label="Send window" value={`${String(o.hourStart).padStart(2, "0")}:00–${String(o.hourEnd).padStart(2, "0")}:00`} detail={`${days} · ${env.timezone}`} />
          </div>
        </Card>

        <section className="grid grid-cols-2 gap-px overflow-hidden rounded-lg border bg-border shadow-card lg:grid-cols-4">
          <Stat label="Agent runs, 7 days" value={num(s.totals.runs_7d)} />
          <Stat label="Tokens, 7 days" value={num(s.totals.tokens_7d)} hint="All local - no API bill" />
          <Stat label="Waiting for research" value={num(s.totals.queued_research)} />
          <Stat label="Suppressed addresses" value={num(s.totals.suppressed)} hint="Enforced by a database trigger" />
        </section>

        <div className="grid gap-6 xl:grid-cols-2">
          <Card>
            <CardHeader title="Agents" description="Last 24 hours." />
            {s.agents.length === 0 ? <Empty title="No runs yet" /> : (
              <Table>
                <THead><tr><Th>Agent</Th><Th className="text-right">Runs</Th><Th className="text-right">Success</Th><Th className="text-right">Failed</Th><Th className="text-right">Avg time</Th><Th className="text-right">Last run</Th></tr></THead>
                <tbody>
                  {s.agents.map((a) => (
                    <Tr key={a.agent_name}>
                      <Td>
                        <span className="inline-flex items-center gap-2 font-medium capitalize">
                          <span className={cn("size-2 rounded-full", a.failed === 0 ? "bg-success" : a.failed / Math.max(a.runs_24h, 1) > 0.2 ? "bg-danger" : "bg-warning")} />
                          {a.agent_name}
                        </span>
                      </Td>
                      <Td className="tabular text-right">{num(a.runs_24h)}</Td>
                      <Td className="tabular text-right">{a.runs_24h ? `${Math.round((a.succeeded / a.runs_24h) * 100)}%` : "—"}</Td>
                      <Td className={cn("tabular text-right", a.failed ? "text-danger" : "text-fg-muted")}>{num(a.failed)}</Td>
                      <Td className="tabular text-right text-fg-muted">{duration(a.avg_duration_ms)}</Td>
                      <Td className="text-right text-fg-subtle">{ago(a.last_run_at)}</Td>
                    </Tr>
                  ))}
                </tbody>
              </Table>
            )}
          </Card>

          <Card>
            <CardHeader title="Recent failures" description="Every failed run also reaches Telegram through WF-99." />
            {s.failures.length === 0 ? (
              <Empty title="No failures" icon={<CircleCheck className="size-6 text-success" />} />
            ) : (
              <ul className="divide-y">
                {s.failures.map((f) => (
                  <li key={f.id} className="px-4 py-2.5">
                    <div className="flex items-center gap-2 text-[12px]">
                      <Badge tone="danger">{f.status}</Badge>
                      <span className="font-medium capitalize">{f.agent_name}</span>
                      {f.company_name && f.company_id ? <Link href={`/companies/${f.company_id}`} className="text-fg-muted hover:text-accent">{f.company_name}</Link> : null}
                      <span className="ml-auto text-fg-subtle">{ago(f.started_at)}</span>
                    </div>
                    {f.error ? <p className="mt-1 truncate font-mono text-[11.5px] text-fg-muted" title={f.error}>{f.error}</p> : null}
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>

        <div className="grid gap-6 xl:grid-cols-2">
          <Card>
            <CardHeader title="Dashboard audit log" description="Every approve, edit and reject made here, written in the same transaction as the change." />
            {s.actions.length === 0 ? <Empty title="Nothing done from the dashboard yet" icon={<ShieldCheck className="size-6" />} /> : (
              <ul className="divide-y">
                {s.actions.map((a, i) => (
                  <li key={i} className="flex items-center gap-3 px-4 py-2.5 text-[12px]">
                    <Badge tone={a.action === "approve" ? "success" : a.action === "reject" ? "neutral" : "accent"}>{a.action}</Badge>
                    <span className="font-medium">{a.company_name}</span>
                    <span className="text-fg-subtle">{a.actor}</span>
                    <span className="ml-auto text-fg-subtle" title={dateTime(a.created_at, env.timezone)}>{ago(a.created_at)}</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
          <Card>
            <CardHeader title="Pending notifications" description="Queued for Telegram by WF-10." />
            {s.notifications.length === 0 ? <Empty title="Outbox is empty" /> : (
              <ul className="divide-y">
                {s.notifications.map((n) => (
                  <li key={n.id} className="flex items-center gap-3 px-4 py-2.5 text-[12px]">
                    <Badge tone={n.priority === "high" ? "danger" : "neutral"}>{n.kind}</Badge>
                    <span className="truncate">{n.title}</span>
                    {n.occurrences > 1 ? <span className="text-fg-subtle">×{n.occurrences}</span> : null}
                    <span className="ml-auto shrink-0 text-fg-subtle">{ago(n.last_seen_at)}</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>

        <p className="text-[12px] text-fg-subtle">
          Schema {s.migration ? `${s.migration.version}, applied ${dateTime(s.migration.applied_at, env.timezone)}` : "not migrated"}.
          The dashboard connects as <code className="font-mono">aisales_dashboard</code>: it can read, and it can call three logged functions. It cannot write a table.
        </p>
      </PageBody>
    </>
  );
}

function Switch({ label, on, onText, offText, detail }: { label: string; on: boolean; onText: string; offText: string; detail: string }) {
  return (
    <div className="bg-surface px-4 py-4">
      <p className="text-[12px] text-fg-muted">{label}</p>
      <p className={cn("mt-1.5 inline-flex items-center gap-1.5 text-[16px] font-semibold", on ? "text-success" : "text-warning")}>
        {on ? <CircleCheck className="size-4" /> : <CirclePause className="size-4" />} {on ? onText : offText}
      </p>
      <p className="mt-1 text-[12px] text-fg-subtle">{detail}</p>
    </div>
  );
}

function Fact({ label, value, detail }: { label: string; value: string; detail: string }) {
  return (
    <div className="bg-surface px-4 py-4">
      <p className="text-[12px] text-fg-muted">{label}</p>
      <p className="tabular mt-1.5 text-[16px] font-semibold">{value}</p>
      <p className="mt-1 text-[12px] text-fg-subtle">{detail}</p>
    </div>
  );
}

function Stat({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="bg-surface px-4 py-4">
      <p className="text-[12px] text-fg-muted">{label}</p>
      <p className="tabular mt-1 text-[22px] font-semibold tracking-tight">{value}</p>
      {hint ? <p className="text-[11px] text-fg-subtle">{hint}</p> : null}
    </div>
  );
}
