import Link from "next/link";

const items = [
  ["/", "Overview"], ["/approvals", "Approvals"], ["/companies", "Companies"], ["/outreach", "Outreach"],
  ["/replies", "Replies"], ["/performance", "Performance"], ["/system", "System"],
] as const;

export function MobileNav({ pending }: { pending: number }) {
  return (
    <nav className="scroll-thin flex gap-1 overflow-x-auto border-b bg-bg-subtle px-3 py-2 md:hidden">
      {items.map(([href, label]) => (
        <Link key={href} href={href} className="whitespace-nowrap rounded-md px-2.5 py-1 text-[12px] text-fg-muted hover:bg-surface hover:text-fg">
          {label}{href === "/approvals" && pending > 0 ? ` (${pending})` : ""}
        </Link>
      ))}
    </nav>
  );
}
