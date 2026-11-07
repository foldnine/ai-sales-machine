import type { Metadata } from "next";
import Link from "next/link";
import { verifySession } from "@/lib/session";
import { listConversations } from "@/lib/queries/activity";
import { PageBody, PageHeader } from "@/components/page-header";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Empty } from "@/components/ui/empty";
import { Chip } from "@/components/filters";
import { ago, classificationLabel, classificationTone, eur, humanize } from "@/lib/format";

export const metadata: Metadata = { title: "Replies" };

const FILTERS = [
  { key: undefined, label: "All" },
  { key: "needs_you", label: "Needs you" },
  { key: "nurture", label: "Nurture" },
  { key: "closed", label: "Closed" },
] as const;

export default async function RepliesPage({ searchParams }: { searchParams: Promise<{ f?: string }> }) {
  await verifySession();
  const { f } = await searchParams;
  const filter = FILTERS.some((x) => x.key === f) ? f ?? null : null;
  const rows = await listConversations(filter);

  return (
    <>
      <PageHeader title="Replies" description="Every answer, classified. Opt-outs are honoured automatically; the rest is yours to answer." />
      <PageBody className="space-y-4">
        <div className="flex gap-1.5">
          {FILTERS.map((x) => (
            <Chip key={x.label} href={x.key ? `/replies?f=${x.key}` : "/replies"} active={(filter ?? undefined) === x.key}>{x.label}</Chip>
          ))}
        </div>
        <Card>
          {rows.length === 0 ? (
            <Empty title="No replies here">WF-08 reads the inbox and files every reply here, with a suggested answer on Telegram.</Empty>
          ) : (
            <ul className="divide-y">
              {rows.map((r) => (
                <li key={r.id}>
                  <Link href={`/companies/${r.company_id}`} className="flex flex-col gap-1.5 px-4 py-3.5 hover:bg-bg-subtle/60 md:flex-row md:items-start md:gap-4">
                    <div className="w-56 shrink-0">
                      <p className="font-medium">{r.company_name}</p>
                      <p className="truncate text-[12px] text-fg-muted">{r.full_name ?? r.email}</p>
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-1.5">
                        <Badge tone={classificationTone(r.classification)}>{classificationLabel(r.classification)}</Badge>
                        <Badge>{humanize(r.status)}</Badge>
                        {r.deal_value_eur ? <Badge tone="success">{eur(r.deal_value_eur)}</Badge> : null}
                        {r.confidence != null ? <span className="text-[11px] text-fg-subtle">{Math.round(r.confidence * 100)}% confident</span> : null}
                      </div>
                      <p className="mt-1 line-clamp-2 text-fg-muted">{r.last_body ?? "—"}</p>
                    </div>
                    <span className="shrink-0 text-[12px] text-fg-subtle">{ago(r.last_message_at)}</span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </PageBody>
    </>
  );
}
