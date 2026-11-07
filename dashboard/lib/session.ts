import "server-only";
import { cache } from "react";
import { cookies, headers } from "next/headers";
import { redirect } from "next/navigation";
import { SignJWT, jwtVerify } from "jose";
import { createHash, timingSafeEqual } from "node:crypto";
import { env, assertConfigured } from "./env";

// One operator, one password (DASHBOARD_PASSWORD), a signed stateless session.
// The stack binds the dashboard to 127.0.0.1; remote access goes through
// `tailscale serve`, which terminates TLS, so the cookie is Secure whenever the
// request arrived over HTTPS.
export const SESSION_COOKIE = "aism_session";
const SESSION_DAYS = 7;

function key() {
  assertConfigured();
  return new TextEncoder().encode(env.sessionSecret);
}

export function passwordMatches(candidate: string) {
  assertConfigured();
  const a = createHash("sha256").update(candidate).digest();
  const b = createHash("sha256").update(env.password).digest();
  return timingSafeEqual(a, b);
}

export async function createSession() {
  const token = await new SignJWT({ sub: "operator" })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime(`${SESSION_DAYS}d`)
    .sign(key());
  const h = await headers();
  const https = h.get("x-forwarded-proto") === "https";
  (await cookies()).set(SESSION_COOKIE, token, {
    httpOnly: true,
    secure: https,
    sameSite: "lax",
    path: "/",
    maxAge: SESSION_DAYS * 24 * 3600,
  });
}

export async function deleteSession() {
  (await cookies()).delete(SESSION_COOKIE);
}

async function readSession() {
  const token = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, key(), { algorithms: ["HS256"] });
    return payload.sub === "operator" ? { actor: "operator" } : null;
  } catch {
    return null;
  }
}

// The data access layer calls this before every read and every action; the
// proxy's cookie check only spares a round trip.
export const verifySession = cache(async () => {
  const session = await readSession();
  if (!session) redirect("/login");
  return session;
});
