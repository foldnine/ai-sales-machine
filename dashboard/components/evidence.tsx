import { ExternalLink, HelpCircle, Lightbulb, Quote } from "lucide-react";
import type { ResearchOutput } from "@/lib/queries/approvals";
import { Badge } from "@/components/ui/badge";
import { bandLabel, bandTone, humanize } from "@/lib/format";
import { cn } from "@/lib/utils";

export function SourceLink({ href, className }: { href?: string | null; className?: string }) {
  if (!href) return null;
  let label = href;
  try {
    const u = new URL(href);
    label = u.hostname.replace(/^www\./, "") + (u.pathname === "/" ? "" : u.pathname);
  } catch {}
  return (
    <a href={href} target="_blank" rel="noreferrer noopener"
      className={cn("inline-flex max-w-full items-center gap-1 truncate text-[11px] text-fg-subtle hover:text-accent", className)}>
      <ExternalLink className="size-3 shrink-0" />
      <span className="truncate">{label}</span>
    </a>
  );
}

export function ScoreBreakdown({ fit, research, dm, total, band }: {
  fit: number | null; research: number | null; dm: number | null; total: number | null; band: string | null;
}) {
  const parts = [
    { label: "Company fit", value: fit, max: 50 },
    { label: "Research evidence", value: research, max: 40 },
    { label: "Decision maker", value: dm, max: 10 },
  ];
  return (
    <div>
      <div className="mb-3 flex items-baseline gap-2">
        <span className="tabular text-[28px] font-semibold leading-none tracking-tight">{total ?? "—"}</span>
        <span className="text-fg-subtle">/ 100</span>
        <Badge tone={bandTone(band)} className="ml-auto">{bandLabel(band)}</Badge>
      </div>
      <div className="space-y-2">
        {parts.map((p) => (
          <div key={p.label}>
            <div className="mb-1 flex justify-between text-[12px]">
              <span className="text-fg-muted">{p.label}</span>
              <span className="tabular text-fg-muted">{p.value ?? "—"} <span className="text-fg-subtle">/ {p.max}</span></span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-bg-subtle">
              <div className="h-full rounded-full bg-accent" style={{ width: `${((p.value ?? 0) / p.max) * 100}%` }} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export function SignalList({ signals }: { signals: { signal_type: string; signal: string; source_url: string | null; confidence: number }[] }) {
  if (signals.length === 0) return <p className="text-[12px] text-fg-muted">No signals recorded.</p>;
  return (
    <ul className="space-y-3">
      {signals.map((s, i) => (
        <li key={i} className="flex gap-3">
          <ConfidenceDot value={s.confidence} />
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <span className="text-[11px] font-medium uppercase tracking-wide text-fg-subtle">{humanize(s.signal_type)}</span>
              <span className="tabular text-[11px] text-fg-subtle">{Math.round(s.confidence * 100)}%</span>
            </div>
            <p className="mt-0.5">{s.signal}</p>
            <SourceLink href={s.source_url} className="mt-0.5" />
          </div>
        </li>
      ))}
    </ul>
  );
}

function ConfidenceDot({ value }: { value: number }) {
  return (
    <span className={cn("mt-1.5 size-2 shrink-0 rounded-full",
      value >= 0.8 ? "bg-success" : value >= 0.6 ? "bg-accent" : "bg-warning")} title={`Confidence ${Math.round(value * 100)}%`} />
  );
}

export function ResearchPanel({ research }: { research: ResearchOutput | null }) {
  if (!research) return <p className="text-[12px] text-fg-muted">No research run recorded for this company yet.</p>;
  return (
    <div className="space-y-5">
      {research.company_summary ? <p className="text-fg">{research.company_summary}</p> : null}
      {research.why_now ? (
        <div className="rounded-md border border-accent/20 bg-accent-soft/50 px-3 py-2">
          <p className="text-[11px] font-medium uppercase tracking-wide text-accent">Why now</p>
          <p className="mt-0.5">{research.why_now}</p>
        </div>
      ) : null}
      {research.facts?.length ? (
        <Section icon={<Quote className="size-3.5" />} title="Facts" note="Each one read from a page, with its source.">
          <ul className="space-y-2.5">
            {research.facts.map((f, i) => (
              <li key={i}>
                <p>{f.fact}</p>
                <SourceLink href={f.source} />
              </li>
            ))}
          </ul>
        </Section>
      ) : null}
      {research.reasonable_inferences?.length ? (
        <Section icon={<Lightbulb className="size-3.5" />} title="Inferences" note="Reasoned, not read. Weighed lower than facts.">
          <ul className="space-y-2">
            {research.reasonable_inferences.map((f, i) => (
              <li key={i}>
                <p>{f.inference}</p>
                {f.based_on ? <p className="text-[11px] text-fg-subtle">Based on: {f.based_on}</p> : null}
              </li>
            ))}
          </ul>
        </Section>
      ) : null}
      {research.unknown?.length ? (
        <Section icon={<HelpCircle className="size-3.5" />} title="Unknown" note="What the research could not establish.">
          <ul className="list-inside list-disc space-y-1 text-fg-muted marker:text-fg-subtle">
            {research.unknown.map((u, i) => <li key={i}>{u}</li>)}
          </ul>
        </Section>
      ) : null}
      {research.technology?.length ? (
        <Section title="Technology">
          <div className="flex flex-wrap gap-1.5">
            {research.technology.map((t, i) => (
              <span key={i} title={t.evidence} className="rounded border bg-bg-subtle px-1.5 py-0.5 font-mono text-[11px] text-fg-muted">{t.name}</span>
            ))}
          </div>
        </Section>
      ) : null}
    </div>
  );
}

function Section({ title, note, icon, children }: { title: string; note?: string; icon?: React.ReactNode; children: React.ReactNode }) {
  return (
    <div>
      <div className="mb-2 flex items-center gap-1.5">
        {icon ? <span className="text-fg-subtle">{icon}</span> : null}
        <h3 className="text-[12px] font-semibold">{title}</h3>
        {note ? <span className="text-[11px] text-fg-subtle">· {note}</span> : null}
      </div>
      {children}
    </div>
  );
}
