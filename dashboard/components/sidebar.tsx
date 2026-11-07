"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard, Inbox, Building2, Send, MessagesSquare, BarChart3, Activity, LogOut, Moon, Sun,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { logout } from "@/app/login/actions";

type Counts = { pending: number; conversations: number; failures: number; paused: boolean; autosend: boolean | null; autosendMaster: boolean };

const nav = [
  { href: "/", label: "Overview", icon: LayoutDashboard },
  { href: "/approvals", label: "Approvals", icon: Inbox, count: "pending" as const },
  { href: "/companies", label: "Companies", icon: Building2 },
  { href: "/outreach", label: "Outreach", icon: Send },
  { href: "/replies", label: "Replies", icon: MessagesSquare, count: "conversations" as const },
  { href: "/performance", label: "Performance", icon: BarChart3 },
  { href: "/system", label: "System", icon: Activity, count: "failures" as const },
];

export function Sidebar({ counts }: { counts: Counts }) {
  const pathname = usePathname();
  const sending = !counts.paused;
  return (
    <aside className="sticky top-0 hidden h-dvh w-[232px] shrink-0 flex-col border-r bg-bg-subtle md:flex">
      <div className="flex h-12 items-center gap-2.5 px-4">
        <svg viewBox="0 0 32 32" className="size-6" aria-hidden>
          <rect width="32" height="32" rx="8" className="fill-accent" />
          <path d="M9 21.5 14.5 10h3L23 21.5h-3.1l-1.1-2.5h-5.6l-1.1 2.5Zm5.2-5h3.6L16 12.3Z" fill="#fff" />
        </svg>
        <span className="text-[13px] font-semibold tracking-tight">AI Sales Machine</span>
      </div>

      <nav className="flex-1 space-y-0.5 px-2 py-2">
        {nav.map((item) => {
          const active = item.href === "/" ? pathname === "/" : pathname.startsWith(item.href);
          const n = item.count ? counts[item.count] : 0;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "group flex h-8 items-center gap-2.5 rounded-md px-2.5 text-[13px] transition-colors",
                active ? "bg-surface text-fg shadow-card" : "text-fg-muted hover:bg-surface/60 hover:text-fg",
              )}
            >
              <item.icon className={cn("size-4", active ? "text-accent" : "text-fg-subtle group-hover:text-fg-muted")} strokeWidth={1.75} />
              <span className="flex-1">{item.label}</span>
              {n > 0 ? (
                <span className={cn(
                  "tabular rounded px-1.5 text-[11px] font-medium",
                  item.count === "failures" ? "bg-danger-soft text-danger" : item.count === "pending" ? "bg-accent text-accent-fg" : "bg-border text-fg-muted",
                )}>{n}</span>
              ) : null}
            </Link>
          );
        })}
      </nav>

      <div className="space-y-2 border-t p-3">
        <Link href="/system" className="block rounded-md border bg-surface px-3 py-2 shadow-card hover:border-border-strong">
          <div className="flex items-center gap-2 text-[12px] font-medium">
            <span className={cn("relative flex size-2")}>
              {sending ? <span className="absolute inline-flex size-full animate-ping rounded-full bg-success opacity-60" /> : null}
              <span className={cn("relative inline-flex size-2 rounded-full", sending ? "bg-success" : "bg-warning")} />
            </span>
            {sending ? "Sending is on" : "Sending is paused"}
          </div>
          <p className="mt-0.5 text-[11px] text-fg-subtle">
            {counts.autosendMaster && counts.autosend ? "Guarded autosend on" : "Every email needs approval"}
          </p>
        </Link>
        <div className="flex items-center gap-1">
          <ThemeToggle />
          <form action={logout} className="ml-auto">
            <button className="inline-flex h-7 items-center gap-1.5 rounded-md px-2 text-[12px] text-fg-muted hover:bg-surface hover:text-fg" title="Sign out">
              <LogOut className="size-3.5" /> Sign out
            </button>
          </form>
        </div>
      </div>
    </aside>
  );
}

function ThemeToggle() {
  function toggle() {
    const dark = !document.documentElement.classList.contains("dark");
    document.documentElement.classList.toggle("dark", dark);
    try { localStorage.setItem("theme", dark ? "dark" : "light"); } catch {}
  }
  return (
    <button onClick={toggle} className="inline-flex size-7 items-center justify-center rounded-md text-fg-muted hover:bg-surface hover:text-fg" title="Toggle theme" aria-label="Toggle theme">
      <Sun className="hidden size-3.5 dark:block" />
      <Moon className="size-3.5 dark:hidden" />
    </button>
  );
}
