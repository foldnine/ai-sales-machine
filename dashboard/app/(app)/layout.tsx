import { verifySession } from "@/lib/session";
import { getShellCounts } from "@/lib/queries/shell";
import { Sidebar } from "@/components/sidebar";
import { MobileNav } from "@/components/mobile-nav";

// Everything behind the login reads live data: never prerender it.
export const dynamic = "force-dynamic";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  await verifySession();
  const counts = await getShellCounts();
  return (
    <div className="flex min-h-dvh">
      <Sidebar counts={counts} />
      <div className="min-w-0 flex-1">
        <MobileNav pending={counts.pending} />
        {children}
      </div>
    </div>
  );
}
