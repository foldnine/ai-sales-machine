import type { Metadata } from "next";
import Link from "next/link";
import { verifySession } from "@/lib/session";
import { env } from "@/lib/env";
import { listOutreach } from "@/lib/queries/activity";
import { PageBody, PageHeader } from "@/components/page-header";
import { Card } from "@/components/ui/card";
import { Table, THead, Th, Tr, Td } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Empty } from "@/components/ui/empty";
import { Chip, hrefWith, Pagination } from "@/components/filters";
import { ago, dateTime, outreachLabel, outreachTone, segmentLabel } from "@/lib/format";

export const metadata: Metadata = { title: "Outreach" };

export default async function OutreachPage({ searchParams }: { searchParams: Promise<{ status?: string; page?: string }> }) {
  await verifySession();
  const sp = await searchParams;
  const page = Math.max(1, Number(sp.page) || 1);
  const { rows, total, counts } = await listOutreach(sp.status ?? null, page);
  const params = { status: sp.status };
  const all = counts.reduce((a, c) => a + c.n, 0);

  return (
    <>
      <PageHeader title="Outreach" description="Every message the pipeline drafted, and what happened to it." />
      <PageBody className="space-y-4">
        <div className="flex flex-wrap gap-1.5">
          <Chip href="/outreach" active={!sp.status} count={all}>All</Chip>
          {counts.map((c) => (
            <Chip key={c.status} href={hrefWith("/outreach", params, { status: c.status })} active={sp.status === c.status} count={c.n}>
              {outreachLabel(c.status)}
            </Chip>
          ))}
        </div>
        <Card>
          {rows.length === 0 ? <Empty title="No messages here yet" /> : (
            <>
              <Table>
                <THead>
                  <tr><Th>Company</Th><Th>Subject</Th><Th>Status</Th><Th>Segment</Th><Th>Approved by</Th><Th className="text-right">When</Th></tr>
                </THead>
                <tbody>
                  {rows.map((o) => (
                    <Tr key={o.id}>
                      <Td>
                        <Link href={o.status === "pending_approval" ? `/approvals?id=${o.id}` : `/companies/${o.company_id}`} className="group block">
                          <span className="font-medium group-hover:text-accent">{o.company_name}</span>
                          <span className="block text-[12px] text-fg-subtle">{o.recipient ?? o.email}</span>
                        </Link>
                      </Td>
                      <Td className="max-w-[320px]">
                        <span className="block truncate">{o.subject}</span>
                        {o.rejection_reason ? <span className="block truncate text-[12px] text-fg-subtle">{o.rejection_reason}</span> : null}
                      </Td>
                      <Td>
                        <div className="flex items-center gap-1.5">
                          <Badge tone={outreachTone(o.status)}>{outreachLabel(o.status)}</Badge>
                          {o.reply_at ? <Badge tone="success">Replied</Badge> : null}
                          {o.sequence_step > 1 ? <Badge>Follow-up</Badge> : null}
                        </div>
                      </Td>
                      <Td className="text-fg-muted">{segmentLabel(o.segment)}</Td>
                      <Td className="text-[12px] text-fg-muted">{o.approved_by ? o.approved_by.replace(":", " · ") : "—"}</Td>
                      <Td className="text-right text-[12px] text-fg-subtle" title={dateTime(o.sent_at ?? o.created_at, env.timezone)}>
                        {o.sent_at ? `Sent ${ago(o.sent_at)}` : `Drafted ${ago(o.created_at)}`}
                      </Td>
                    </Tr>
                  ))}
                </tbody>
              </Table>
              <Pagination base="/outreach" params={params} page={page} total={total} pageSize={50} />
            </>
          )}
        </Card>
      </PageBody>
    </>
  );
}
