export function Empty({ title, children, icon }: { title: string; children?: React.ReactNode; icon?: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-14 text-center">
      {icon ? <div className="mb-3 text-fg-subtle">{icon}</div> : null}
      <p className="text-[13px] font-medium">{title}</p>
      {children ? <div className="mt-1 max-w-sm text-[12px] text-fg-muted">{children}</div> : null}
    </div>
  );
}
