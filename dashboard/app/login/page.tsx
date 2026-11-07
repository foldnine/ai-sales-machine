import type { Metadata } from "next";
import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Sign in" };

export default function LoginPage() {
  return (
    <main className="flex min-h-dvh items-center justify-center bg-bg-subtle px-4">
      <div className="w-full max-w-[360px]">
        <div className="mb-8 flex items-center gap-2.5">
          <Logo />
          <span className="text-[15px] font-semibold tracking-tight">AI Sales Machine</span>
        </div>
        <div className="rounded-xl border bg-surface p-6 shadow-card">
          <h1 className="text-base font-semibold tracking-tight">Sign in</h1>
          <p className="mt-1 text-fg-muted">
            The password is <code className="font-mono text-[12px]">DASHBOARD_PASSWORD</code> in your <code className="font-mono text-[12px]">.env</code>.
          </p>
          <LoginForm />
        </div>
        <p className="mt-6 text-center text-xs text-fg-subtle">Self-hosted. Nothing here leaves your machine.</p>
      </div>
    </main>
  );
}

function Logo() {
  return (
    <svg viewBox="0 0 32 32" className="size-7" aria-hidden>
      <rect width="32" height="32" rx="8" className="fill-accent" />
      <path d="M9 21.5 14.5 10h3L23 21.5h-3.1l-1.1-2.5h-5.6l-1.1 2.5Zm5.2-5h3.6L16 12.3Z" fill="#fff" />
    </svg>
  );
}
