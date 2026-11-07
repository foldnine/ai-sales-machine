"use server";

import { revalidatePath } from "next/cache";
import { sql } from "@/lib/db";
import { verifySession } from "@/lib/session";
import { isUuid } from "@/lib/utils";

// Every write goes through a SECURITY DEFINER function in 0033_dashboard.sql.
// The dashboard's database role cannot UPDATE a table itself, so these are the
// only writes that exist - and each is logged in operator_actions.

export type ActionResult = { ok: boolean; message: string };

function done(message: string): ActionResult {
  revalidatePath("/", "layout");
  return { ok: true, message };
}

function failed(e: unknown): ActionResult {
  const msg = e instanceof Error ? e.message : String(e);
  return { ok: false, message: msg.replace(/^.*?ERROR:\s*/i, "") };
}

export async function approveDrafts(ids: string[]): Promise<ActionResult> {
  const session = await verifySession();
  const clean = [...new Set(ids)].filter(isUuid);
  if (clean.length === 0 || clean.length > 100) return { ok: false, message: "Nothing to approve." };
  try {
    const rows = await sql<{ outreach_id: string; outcome: string }[]>`
      SELECT outreach_id, outcome FROM dashboard_approve(${clean}::uuid[], ${session.actor})`;
    const approved = rows.filter((r) => r.outcome === "approved").length;
    if (approved === 0) return { ok: false, message: "Already handled elsewhere - nothing was waiting." };
    return done(approved === 1 ? "Approved. WF-06 sends it in the next send window." : `Approved ${approved} drafts.`);
  } catch (e) {
    return failed(e);
  }
}

export async function rejectDraft(id: string, reason: string): Promise<ActionResult> {
  const session = await verifySession();
  if (!isUuid(id)) return { ok: false, message: "Unknown draft." };
  try {
    const [r] = await sql<{ outcome: string }[]>`
      SELECT dashboard_reject(${id}::uuid, ${reason.slice(0, 500)}, ${session.actor}) AS outcome`;
    if (r.outcome !== "rejected") return { ok: false, message: "Already handled elsewhere - nothing was waiting." };
    return done("Rejected.");
  } catch (e) {
    return failed(e);
  }
}

export async function editDraft(id: string, subject: string, body: string): Promise<ActionResult> {
  const session = await verifySession();
  if (!isUuid(id)) return { ok: false, message: "Unknown draft." };
  try {
    const [r] = await sql<{ outcome: string }[]>`
      SELECT dashboard_edit(${id}::uuid, ${subject}, ${body}, ${session.actor}) AS outcome`;
    if (r.outcome === "not_pending") return { ok: false, message: "This draft is no longer waiting for approval." };
    if (r.outcome === "unchanged") return { ok: true, message: "No changes." };
    return done("Saved. Approve when it reads right.");
  } catch (e) {
    return failed(e);
  }
}
