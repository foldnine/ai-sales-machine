export function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="inline-flex h-[18px] min-w-[18px] items-center justify-center rounded border border-border-strong bg-bg-subtle px-1 font-mono text-[10px] text-fg-muted">
      {children}
    </kbd>
  );
}
