import { sql } from "@/lib/db";

// Liveness for the container healthcheck and `make health`. Unauthenticated,
// so it says only whether the database answers - no data.
export const dynamic = "force-dynamic";

export async function GET() {
  try {
    await sql`SELECT 1`;
    return Response.json({ ok: true });
  } catch {
    return Response.json({ ok: false }, { status: 503 });
  }
}
