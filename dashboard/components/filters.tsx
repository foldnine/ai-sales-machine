import Link from "next/link";
import { Search } from "lucide-react";
import { cn } from "@/lib/utils";

// Filters live in the URL, so a filtered view can be bookmarked, shared with
// yourself on another device, and survives a reload.
export function hrefWith(base: string, params: Record<string, string | undefined>, change: Record<string, string | undefined>) {
  const next = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...params, ...change })) if (v) next.set(k, v);
  next.delete("page");
  if (change.page) next.set("page", change.page);
  const s = next.toString();
  return s ? `${base}?${s}` : base;
}

export function Chip({ href, active, children, count }: { href: string; active: boolean; children: React.ReactNode; count?: number }) {
  return (
    <Link href={href} scroll={false}
      className={cn("chip inline-flex h-7 items-center gap-1.5 whitespace-nowrap rounded-md border px-2.5 text-[12px] transition-colors",
        active ? "border-accent/40 bg-accent-soft text-accent" : "bg-surface text-fg-muted hover:border-border-strong hover:text-fg")}>
      {children}
      {count != null ? <span className="tabular text-[11px] opacity-70">{count}</span> : null}
    </Link>
  );
}

export function SearchBox({ action, defaultValue, hidden, placeholder }: {
  action: string; defaultValue?: string; hidden: Record<string, string | undefined>; placeholder: string;
}) {
  return (
    <form action={action} className="relative">
      <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-fg-subtle" />
      {Object.entries(hidden).map(([k, v]) => (v && k !== "q" && k !== "page" ? <input key={k} type="hidden" name={k} value={v} /> : null))}
      <input name="q" defaultValue={defaultValue} placeholder={placeholder}
        className="h-8 w-64 rounded-md border bg-surface pl-8 pr-3 text-[13px] outline-none placeholder:text-fg-subtle focus:border-accent focus:ring-2 focus:ring-[var(--ring)]" />
    </form>
  );
}

export function Pagination({ base, params, page, total, pageSize }: {
  base: string; params: Record<string, string | undefined>; page: number; total: number; pageSize: number;
}) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  if (pages <= 1) return null;
  return (
    <div className="flex items-center justify-between border-t px-4 py-2.5 text-[12px] text-fg-muted">
      <span className="tabular">{(page - 1) * pageSize + 1}–{Math.min(page * pageSize, total)} of {total}</span>
      <div className="flex gap-1">
        {page > 1 ? <Link className="rounded-md border bg-surface px-2.5 py-1 hover:text-fg" href={hrefWith(base, params, { page: String(page - 1) })}>Previous</Link> : null}
        {page < pages ? <Link className="rounded-md border bg-surface px-2.5 py-1 hover:text-fg" href={hrefWith(base, params, { page: String(page + 1) })}>Next</Link> : null}
      </div>
    </div>
  );
}
