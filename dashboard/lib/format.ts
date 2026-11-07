import type { Tone } from "@/components/ui/badge";

const nf = new Intl.NumberFormat("en-US");
export const num = (v: number | null | undefined) => (v == null ? "—" : nf.format(v));
export const eur = (v: number | null | undefined) =>
  v == null ? "—" : new Intl.NumberFormat("en-IE", { style: "currency", currency: "EUR", maximumFractionDigits: 0 }).format(v);
export const pct = (v: number | null | undefined, digits = 1) => (v == null ? "—" : `${v.toFixed(digits)}%`);

export function ago(d: Date | string | null | undefined, now = Date.now()) {
  if (!d) return "—";
  const t = typeof d === "string" ? new Date(d).getTime() : d.getTime();
  const s = Math.round((now - t) / 1000);
  if (s < 0) return "just now";
  if (s < 60) return `${s}s ago`;
  const m = Math.round(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.round(m / 60);
  if (h < 48) return `${h}h ago`;
  const days = Math.round(h / 24);
  if (days < 60) return `${days}d ago`;
  return `${Math.round(days / 30)}mo ago`;
}

export function dateTime(d: Date | string | null | undefined, timeZone: string) {
  if (!d) return "—";
  return new Intl.DateTimeFormat("en-GB", {
    timeZone, day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit",
  }).format(typeof d === "string" ? new Date(d) : d);
}

export function duration(ms: number | null | undefined) {
  if (ms == null) return "—";
  if (ms < 1000) return `${ms} ms`;
  const s = ms / 1000;
  if (s < 90) return `${s.toFixed(s < 10 ? 1 : 0)} s`;
  return `${(s / 60).toFixed(1)} min`;
}

export const humanize = (v: string | null | undefined) =>
  !v ? "—" : v.replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase());

export function bandTone(band: string | null | undefined): Tone {
  switch (band) {
    case "HOT": return "danger";
    case "HIGH_PRIORITY": return "warning";
    case "OUTREACH": return "accent";
    case "NURTURE": return "neutral";
    default: return "neutral";
  }
}
export const bandLabel = (band: string | null | undefined) =>
  ({ HOT: "Hot", HIGH_PRIORITY: "High priority", OUTREACH: "Outreach", NURTURE: "Nurture", IGNORE: "Ignore", UNSCORED: "Unscored" } as Record<string, string>)[band ?? ""] ?? "—";

export function companyStatusTone(s: string): Tone {
  if (["opportunity", "won"].includes(s)) return "success";
  if (["replied", "contacted"].includes(s)) return "accent";
  if (["ready"].includes(s)) return "warning";
  if (["lost", "suppressed"].includes(s)) return "danger";
  return "neutral";
}

export function outreachTone(s: string): Tone {
  switch (s) {
    case "pending_approval": return "warning";
    case "approved": case "queued": return "accent";
    case "sent": case "replied": return "success";
    case "rejected": case "cancelled": return "neutral";
    case "bounced": case "failed": return "danger";
    default: return "neutral";
  }
}
export const outreachLabel = (s: string) =>
  ({ pending_approval: "Awaiting approval", approved: "Approved", queued: "Queued", sent: "Sent", replied: "Replied",
     rejected: "Rejected", cancelled: "Cancelled", bounced: "Bounced", failed: "Failed", draft: "Draft" } as Record<string, string>)[s] ?? humanize(s);

export function classificationTone(c: string | null): Tone {
  switch (c) {
    case "POSITIVE": return "success";
    case "QUESTION": case "PRICE": case "REFERRAL": return "accent";
    case "NOT_NOW": return "warning";
    case "NEGATIVE": case "UNSUBSCRIBE": return "danger";
    default: return "neutral";
  }
}
export const classificationLabel = (c: string | null) =>
  ({ POSITIVE: "Interested", QUESTION: "Question", PRICE: "Asked price", NOT_NOW: "Not now", NEGATIVE: "Not interested",
     REFERRAL: "Referral", UNSUBSCRIBE: "Unsubscribe", OUT_OF_SCOPE: "Out of scope" } as Record<string, string>)[c ?? ""] ?? "Unclassified";

export const segmentLabel = (s: string | null | undefined) => humanize(s);
export const offerLabel = (o: string | null | undefined) =>
  ({ infrastructure_audit: "Infrastructure audit", devops_improvement_sprint: "DevOps sprint",
     fractional_devops_sre: "Fractional SRE", process_audit: "Process audit", none: "None" } as Record<string, string>)[o ?? ""] ?? humanize(o);
