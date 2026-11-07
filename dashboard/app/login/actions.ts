"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { createSession, deleteSession, passwordMatches } from "@/lib/session";

// Brute force is slow by design: a fixed delay on every attempt, and at most
// five failures per client address in fifteen minutes. One process, one
// operator - an in-memory window is enough.
const failures = new Map<string, number[]>();
const WINDOW_MS = 15 * 60 * 1000;
const MAX_FAILURES = 5;

export type LoginState = { error?: string };

export async function login(_: LoginState, formData: FormData): Promise<LoginState> {
  const h = await headers();
  const client = h.get("x-forwarded-for")?.split(",")[0]?.trim() || h.get("x-real-ip") || "local";
  const now = Date.now();
  const recent = (failures.get(client) ?? []).filter((t) => now - t < WINDOW_MS);

  await new Promise((r) => setTimeout(r, 400));
  if (recent.length >= MAX_FAILURES) {
    return { error: "Too many attempts. Wait fifteen minutes and try again." };
  }

  const password = String(formData.get("password") ?? "");
  if (!password || !passwordMatches(password)) {
    failures.set(client, [...recent, now]);
    return { error: "That password is not right." };
  }

  failures.delete(client);
  await createSession();
  redirect("/");
}

export async function logout() {
  await deleteSession();
  redirect("/login");
}
