import { cn } from "@/lib/utils";

export function ScorePill({ score }: { score: number | null }) {
  const tone = score == null ? "text-fg-subtle" : score >= 75 ? "text-danger" : score >= 60 ? "text-accent" : "text-fg-muted";
  return (
    <span className={cn("tabular inline-flex size-8 shrink-0 items-center justify-center rounded-md border bg-bg-subtle text-[12px] font-semibold", tone)}>
      {score ?? "—"}
    </span>
  );
}
