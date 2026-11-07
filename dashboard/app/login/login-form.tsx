"use client";

import { useActionState } from "react";
import { login, type LoginState } from "./actions";
import { Button } from "@/components/ui/button";

export function LoginForm() {
  const [state, action, pending] = useActionState<LoginState, FormData>(login, {});
  return (
    <form action={action} className="mt-5 space-y-3">
      <label className="block">
        <span className="mb-1.5 block text-xs font-medium text-fg-muted">Password</span>
        <input
          name="password"
          type="password"
          autoComplete="current-password"
          autoFocus
          required
          className="h-9 w-full rounded-md border bg-bg px-3 text-[13px] outline-none transition focus:border-accent focus:ring-2 focus:ring-[var(--ring)]"
        />
      </label>
      {state.error ? (
        <p role="alert" className="text-[12px] text-danger">{state.error}</p>
      ) : null}
      <Button type="submit" className="w-full" disabled={pending}>
        {pending ? "Signing in…" : "Sign in"}
      </Button>
    </form>
  );
}
