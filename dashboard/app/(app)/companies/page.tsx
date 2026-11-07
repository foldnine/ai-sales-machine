import type { Metadata } from "next";
import Link from "next/link";
import { verifySession } from "@/lib/session";
import { getFacets, listCompanies, PAGE_SIZE, SORTS } from "@/lib/queries/companies";
import { PageBody, PageHeader } from "@/components/page-header";
import { Card } from "@/components/ui/card";
import { Table, THead, Th, Tr, Td } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Empty } from "@/components/ui/empty";
import { Chip, hrefWith, Pagination, SearchBox } from "@/components/filters";
import { ago, bandLabel, bandTone, companyStatusTone, humanize, outreachLabel, outreachTone, segmentLabel } from "@/lib/format";

export const metadata: Metadata = { title: "Companies" };

type SP = { q?: string; status?: string; segment?: string; band?: string; sort?: string; page?: string };
const BANDS = ["HOT", "HIGH_PRIORITY", "OUTREACH", "NURTURE", "IGNORE"];

export default async function CompaniesPage({ searchParams }: { searchParams: Promise<SP> }) {
  await verifySession();
  const sp = await searchParams;
  const page = Math.max(1, Number(sp.page) || 1);
  const sort = (sp.sort && Object.hasOwn(SORTS, sp.sort) ? sp.sort : "score") as keyof typeof SORTS;
  const [{ rows, total }, facets] = await Promise.all([
    listCompanies({ q: sp.q, status: sp.status, segment: sp.segment, band: sp.band, sort, page }),
    getFacets(),
  ]);
  const params = { q: sp.q, status: sp.status, segment: sp.segment, band: sp.band, sort: sp.sort };

  return (
    <>
      <PageHeader title="Companies" description="Everything discovery found, with the evidence behind each score."
        actions={<SearchBox action="/companies" defaultValue={sp.q} hidden={params} placeholder="Search name or domain" />}
      />
      <PageBody className="space-y-4">
        <div className="flex flex-wrap items-center gap-1.5">
          <Chip href={hrefWith("/companies", params, { segment: undefined })} active={!sp.segment}>All segments</Chip>
          {facets.segments.map((s) => (
            <Chip key={s.segment} href={hrefWith("/companies", params, { segment: s.segment })} active={sp.segment === s.segment} count={s.n}>
              {segmentLabel(s.segment)}
            </Chip>
          ))}
          <span className="mx-1 h-5 w-px bg-border" />
          {BANDS.map((b) => (
            <Chip key={b} href={hrefWith("/companies", params, { band: sp.band === b ? undefined : b })} active={sp.band === b}>{bandLabel(b)}</Chip>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-1.5">
          <Chip href={hrefWith("/companies", params, { status: undefined })} active={!sp.status}>Any status</Chip>
          {facets.statuses.map((s) => (
            <Chip key={s.status} href={hrefWith("/companies", params, { status: s.status })} active={sp.status === s.status} count={s.n}>
              {humanize(s.status)}
            </Chip>
          ))}
        </div>

        <Card>
          {rows.length === 0 ? (
            <Empty title="No companies match">Clear a filter, or wait for the next discovery run.</Empty>
          ) : (
            <>
              <Table>
                <THead>
                  <tr>
                    <Th><SortLink label="Company" sort="name" current={sort} params={params} /></Th>
                    <Th>Segment</Th>
                    <Th>Status</Th>
                    <Th className="text-right"><SortLink label="Score" sort="score" current={sort} params={params} /></Th>
                    <Th>Band</Th>
                    <Th className="text-right">Signals</Th>
                    <Th>Outreach</Th>
                    <Th className="text-right"><SortLink label="Found" sort="newest" current={sort} params={params} /></Th>
                  </tr>
                </THead>
                <tbody>
                  {rows.map((c) => (
                    <Tr key={c.id}>
                      <Td>
                        <Link href={`/companies/${c.id}`} className="group block">
                          <span className="font-medium group-hover:text-accent">{c.name}</span>
                          <span className="block text-[12px] text-fg-subtle">{c.domain}{c.country ? ` · ${c.country}` : ""}</span>
                        </Link>
                      </Td>
                      <Td className="text-fg-muted">{segmentLabel(c.segment)}</Td>
                      <Td><Badge tone={companyStatusTone(c.status)}>{humanize(c.status)}</Badge></Td>
                      <Td className="tabular text-right font-medium">{c.total_score ?? "—"}</Td>
                      <Td>{c.score_band && c.score_band !== "UNSCORED" ? <Badge tone={bandTone(c.score_band)}>{bandLabel(c.score_band)}</Badge> : <span className="text-fg-subtle">—</span>}</Td>
                      <Td className="tabular text-right text-fg-muted">{c.signal_count}</Td>
                      <Td>{c.last_outreach ? <Badge tone={outreachTone(c.last_outreach)}>{outreachLabel(c.last_outreach)}</Badge> : <span className="text-fg-subtle">—</span>}</Td>
                      <Td className="text-right text-fg-subtle">{ago(c.created_at)}</Td>
                    </Tr>
                  ))}
                </tbody>
              </Table>
              <Pagination base="/companies" params={params} page={page} total={total} pageSize={PAGE_SIZE} />
            </>
          )}
        </Card>
      </PageBody>
    </>
  );
}

function SortLink({ label, sort, current, params }: { label: string; sort: string; current: string; params: Record<string, string | undefined> }) {
  return (
    <Link href={hrefWith("/companies", params, { sort })} className={current === sort ? "text-fg" : "hover:text-fg"}>
      {label}{current === sort ? " ↓" : ""}
    </Link>
  );
}
