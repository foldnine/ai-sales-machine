export function PageHeader({ title, description, actions, children }: {
  title: React.ReactNode; description?: React.ReactNode; actions?: React.ReactNode; children?: React.ReactNode;
}) {
  return (
    <header className="border-b bg-bg">
      <div className="mx-auto flex max-w-[1400px] flex-wrap items-end justify-between gap-3 px-4 pb-4 pt-6 md:px-8">
        <div className="min-w-0">
          <h1 className="text-[20px] font-semibold tracking-tight">{title}</h1>
          {description ? <p className="mt-1 text-fg-muted">{description}</p> : null}
        </div>
        {actions ? <div className="flex items-center gap-2">{actions}</div> : null}
      </div>
      {children}
    </header>
  );
}

export function PageBody({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return <div className={`mx-auto max-w-[1400px] px-4 py-6 md:px-8 ${className}`}>{children}</div>;
}
