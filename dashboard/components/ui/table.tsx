import { cn } from "@/lib/utils";

export function Table({ className, ...props }: React.TableHTMLAttributes<HTMLTableElement>) {
  return (
    <div className="overflow-x-auto scroll-thin">
      <table className={cn("w-full border-collapse text-left text-[13px]", className)} {...props} />
    </div>
  );
}
export function THead(props: React.HTMLAttributes<HTMLTableSectionElement>) {
  return <thead className="border-b bg-bg-subtle/60 text-[11px] uppercase tracking-wide text-fg-subtle" {...props} />;
}
export function Th({ className, ...props }: React.ThHTMLAttributes<HTMLTableCellElement>) {
  return <th className={cn("h-8 px-3 font-medium first:pl-4 last:pr-4", className)} {...props} />;
}
export function Tr({ className, ...props }: React.HTMLAttributes<HTMLTableRowElement>) {
  return <tr className={cn("border-b last:border-0 transition-colors hover:bg-bg-subtle/60", className)} {...props} />;
}
export function Td({ className, ...props }: React.TdHTMLAttributes<HTMLTableCellElement>) {
  return <td className={cn("h-10 px-3 align-middle first:pl-4 last:pr-4", className)} {...props} />;
}
