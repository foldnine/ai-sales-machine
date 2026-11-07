import { cn } from "@/lib/utils";

export type Tone = "neutral" | "accent" | "success" | "warning" | "danger";

const tones: Record<Tone, string> = {
  neutral: "bg-bg-subtle text-fg-muted border-border",
  accent: "bg-accent-soft text-accent border-transparent",
  success: "bg-success-soft text-success border-transparent",
  warning: "bg-warning-soft text-warning border-transparent",
  danger: "bg-danger-soft text-danger border-transparent",
};

export function Badge({ tone = "neutral", className, children, dot }: {
  tone?: Tone; className?: string; children: React.ReactNode; dot?: boolean;
}) {
  return (
    <span className={cn("inline-flex h-5 items-center gap-1.5 whitespace-nowrap rounded-full border px-2 text-[11px] font-medium", tones[tone], className)}>
      {dot ? <span className="size-1.5 rounded-full bg-current" /> : null}
      {children}
    </span>
  );
}
