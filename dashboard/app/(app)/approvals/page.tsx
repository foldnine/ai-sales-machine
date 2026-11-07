import type { Metadata } from "next";
import Link from "next/link";
import { CheckCircle2, PauseCircle, ShieldCheck } from "lucide-react";
import { verifySession } from "@/lib/session";
import { env } from "@/lib/env";
import { getDraft, getQueue } from "@/lib/queries/approvals";
import { PageHeader } from "@/components/page-header";
import { Empty } from "@/components/ui/empty";
import { Badge } from "@/components/ui/badge";
import { ScorePill } from "@/components/score-pill";
import { ago, segmentLabel } from "@/lib/format";
import { cn, isUuid } from "@/lib/utils";
import { DraftPanel } from "./draft-panel";

export const metadata: Metadata = { title: "Approvals" };

export default async function ApprovalsPage({ searchParams }: { searchParams: Promise<{ id?: string }> }) {
  await verifySession();
  const { id } = await searchParams;
  const queue = await getQueue();
  const selectedId = id && isUuid(id) ? id : queue[0]?.outreach_id;
  const draft = selectedId ? await getDraft(selectedId) : null;
  const index = queue.findIndex((q) => q.outreach_id === selectedId);
  const nextId = queue[index + 1]?.outreach_id ?? queue[index - 1]?.outreach_id ?? null;
  const prevId = index > 0 ? queue[index - 1].outreach_id : null;

  return (
    <div className="flex h-dvh flex-col">
      <PageHeader
        title="Approvals"
        description={queue.length
          ? `${queue.length} draft${queue.length === 1 ? "" : "s"} waiting. Nothing is sent until you approve it.`
          : "Nothing is waiting. New drafts appear here as the pipeline writes them."}
        actions={
          env.outreach.paused ? (
            <span className="inline-flex items-center gap-1.5 rounded-md border border-warning/30 bg-warning-soft px-2.5 py-1 text-[12px] text-warning">
              <PauseCircle className="size-3.5" /> Sending paused - approved drafts wait until OUTREACH_PAUSED=false
            </span>
          ) : (
            <span className="inline-flex items-center gap-1.5 rounded-md border bg-surface px-2.5 py-1 text-[12px] text-fg-muted">
              <ShieldCheck className="size-3.5 text-success" /> Approved drafts go out in the next send window, up to {env.outreach.dailyLimit} a day
            </span>
          )
        }
      />
      {queue.length === 0 ? (
        <div className="flex flex-1 items-center justify-center">
          <Empty title="You're all caught up" icon={<CheckCircle2 className="size-8" />}>
            WF-05 drafts new messages on its schedule. They will wait here for you.
          </Empty>
        </div>
      ) : (
        <div className="flex min-h-0 flex-1">
          <ul className={cn("scroll-thin w-full shrink-0 overflow-y-auto border-r bg-bg-subtle/40 md:block md:w-[340px] xl:w-[380px]", id ? "hidden" : "block")}>
            {queue.map((q) => {
              const active = q.outreach_id === selectedId;
              return (
                <li key={q.outreach_id}>
                  <Link
                    href={`/approvals?id=${q.outreach_id}`}
                    scroll={false}
                    className={cn(
                      "flex gap-3 border-b border-l-2 px-4 py-3 transition-colors",
                      active ? "border-l-accent bg-surface" : "border-l-transparent hover:bg-surface/70",
                    )}
                  >
                    <ScorePill score={q.score} />
                    <div className="min-w-0 flex-1">
                      <div className="flex items-baseline gap-2">
                        <p className="truncate font-medium">{q.company_name}</p>
                        <span className="ml-auto shrink-0 text-[11px] text-fg-subtle">{ago(q.created_at)}</span>
                      </div>
                      <p className="truncate text-[12px] text-fg-muted">{q.full_name ?? q.email}{q.title ? ` · ${q.title}` : ""}</p>
                      <div className="mt-1.5 flex items-center gap-1.5">
                        <span className="truncate text-[12px] text-fg-subtle">{q.subject}</span>
                        {q.sequence_step > 1 ? <Badge tone="warning">Follow-up</Badge> : null}
                        {q.person_kind === "role" ? <Badge>General inbox</Badge> : null}
                        <Badge className="ml-auto">{segmentLabel(q.segment)}</Badge>
                      </div>
                    </div>
                  </Link>
                </li>
              );
            })}
          </ul>
          <div className={cn("scroll-thin min-w-0 flex-1 overflow-y-auto md:block", id ? "block" : "hidden")}>
            {draft ? (
              <DraftPanel key={draft.outreach_id} draft={draft} nextId={nextId} prevId={prevId} timezone={env.timezone} />
            ) : (
              <Empty title="Draft not found">It may have been handled already. Pick another from the list.</Empty>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
