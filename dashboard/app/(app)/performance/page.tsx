import type { Metadata } from "next";
import { verifySession } from "@/lib/session";
import { getPerformance } from "@/lib/queries/activity";
import { PageBody, PageHeader } from "@/components/page-header";
import { Card, CardBody, CardHeader } from "@/components/ui/card";
import { Table, THead, Th, Tr, Td } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Empty } from "@/components/ui/empty";
import { SegmentChart } from "@/components/charts/segment-chart";
import { eur, humanize, num, offerLabel, pct, segmentLabel } from "@/lib/format";

export const metadata: Metadata = { title: "Performance" };

const STAGES = [
  ["replied", "Replied"], ["opportunity", "Opportunity"], ["meeting", "Meeting"], ["audit", "Audit"],
  ["proposal", "Proposal"], ["closed_won", "Won"], ["closed_lost", "Lost"], ["nurture", "Nurture"],
] as const;

export default async function PerformancePage() {
  await verifySession();
  const { segments, campaigns, variants, stages } = await getPerformance();
  const byStage = new Map(stages.map((s) => [s.stage, s]));

  return (
    <>
      <PageHeader title="Performance" description="Which segments, campaigns and message variants turn into conversations." />
      <PageBody className="space-y-6">
        <section className="grid grid-cols-2 gap-px overflow-hidden rounded-lg border bg-border shadow-card md:grid-cols-4 xl:grid-cols-8">
          {STAGES.map(([key, label]) => {
            const s = byStage.get(key);
            return (
              <div key={key} className="bg-surface px-4 py-3">
                <p className="text-[12px] text-fg-muted">{label}</p>
                <p className="tabular mt-1 text-[20px] font-semibold tracking-tight">{num(s?.n ?? 0)}</p>
                <p className="tabular text-[11px] text-fg-subtle">{s?.value ? eur(s.value) : "—"}</p>
              </div>
            );
          })}
        </section>

        <div className="grid gap-6 xl:grid-cols-5">
          <Card className="xl:col-span-2">
            <CardHeader title="By segment" description="Contacted, replied, and real conversations." />
            <CardBody>
              {segments.length ? (
                <SegmentChart data={segments.filter((s) => s.contacted > 0 || s.companies > 0).map((s) => ({ name: segmentLabel(s.segment), contacted: s.contacted, replied: s.replied, conversations: s.conversations }))} />
              ) : <Empty title="No segments" />}
            </CardBody>
          </Card>
          <Card className="xl:col-span-3">
            <CardHeader title="Segments" description="Configured in the icp_segments table (docs/customizing.md)." />
            <Table>
              <THead>
                <tr><Th>Segment</Th><Th className="text-right">Companies</Th><Th className="text-right">Qualified</Th><Th className="text-right">Contacted</Th><Th className="text-right">Reply rate</Th><Th className="text-right">Conv.</Th><Th className="text-right">Won</Th></tr>
              </THead>
              <tbody>
                {segments.map((s) => (
                  <Tr key={s.segment}>
                    <Td>
                      <span className="font-medium">{segmentLabel(s.segment)}</span>
                      {!s.active ? <Badge className="ml-2">Off</Badge> : null}
                      <span className="block text-[11px] text-fg-subtle">Bar: {s.min_score}</span>
                    </Td>
                    <Td className="tabular text-right">{num(s.companies)}</Td>
                    <Td className="tabular text-right">{num(s.qualified)}</Td>
                    <Td className="tabular text-right">{num(s.contacted)}</Td>
                    <Td className="tabular text-right">{pct(s.reply_rate_pct)}</Td>
                    <Td className="tabular text-right">{num(s.conversations)}</Td>
                    <Td className="tabular text-right">{num(s.won)}</Td>
                  </Tr>
                ))}
              </tbody>
            </Table>
          </Card>
        </div>

        <Card>
          <CardHeader title="Campaigns" description="A campaign is a hypothesis: a segment, an offer and a message variant, measured end to end." />
          {campaigns.length === 0 ? <Empty title="No campaigns yet" /> : (
            <Table>
              <THead>
                <tr><Th>Campaign</Th><Th>Offer</Th><Th className="text-right">Contacted</Th><Th className="text-right">Reply rate</Th><Th className="text-right">Conversations</Th><Th className="text-right">Calls</Th><Th className="text-right">Won</Th><Th className="text-right">Revenue</Th></tr>
              </THead>
              <tbody>
                {campaigns.map((c) => (
                  <Tr key={c.campaign}>
                    <Td className="max-w-[420px]">
                      <div className="flex items-center gap-2">
                        <span className="font-medium">{c.campaign}</span>
                        <Badge tone={c.active ? "success" : "neutral"} dot>{c.active ? "Running" : "Ended"}</Badge>
                      </div>
                      {c.hypothesis ? <p className="mt-0.5 line-clamp-2 text-[12px] text-fg-subtle">{c.hypothesis}</p> : null}
                    </Td>
                    <Td className="text-fg-muted">{offerLabel(c.offer)}</Td>
                    <Td className="tabular text-right">{num(c.contacted)}</Td>
                    <Td className="tabular text-right">{pct(c.reply_rate_pct)}</Td>
                    <Td className="tabular text-right">{num(c.conversations)}</Td>
                    <Td className="tabular text-right">{num(c.calls)}</Td>
                    <Td className="tabular text-right">{num(c.won)}</Td>
                    <Td className="tabular text-right font-medium">{eur(c.revenue_eur)}</Td>
                  </Tr>
                ))}
              </tbody>
            </Table>
          )}
        </Card>

        <Card>
          <CardHeader title="Message variants" description="Call to action and language of the first message." />
          {variants.length === 0 ? <Empty title="No variants measured yet" /> : (
            <Table>
              <THead><tr><Th>Segment</Th><Th>Call to action</Th><Th>Language</Th><Th className="text-right">Contacted</Th><Th className="text-right">Replied</Th><Th className="text-right">Conversations</Th></tr></THead>
              <tbody>
                {variants.map((v, i) => (
                  <Tr key={i}>
                    <Td>{segmentLabel(v.segment)}</Td>
                    <Td className="text-fg-muted">{humanize(v.cta)}</Td>
                    <Td className="text-fg-muted">{v.language?.toUpperCase() ?? "—"}</Td>
                    <Td className="tabular text-right">{num(v.contacted)}</Td>
                    <Td className="tabular text-right">{num(v.replied)}</Td>
                    <Td className="tabular text-right">{num(v.conversations)}</Td>
                  </Tr>
                ))}
              </tbody>
            </Table>
          )}
        </Card>
      </PageBody>
    </>
  );
}
