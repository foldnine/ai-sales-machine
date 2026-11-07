"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Check, Pencil, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Kbd } from "@/components/ui/kbd";
import { approveDrafts, editDraft, rejectDraft, type ActionResult } from "./actions";

const REASONS = ["Hook too generic", "Wrong person", "Wrong offer for them", "Not a fit", "Already in touch"];

export function EmailReview({ id, subject, body, nextId, prevId }: {
  id: string; subject: string; body: string; nextId: string | null; prevId: string | null;
}) {
  const router = useRouter();
  const [mode, setMode] = useState<"view" | "edit" | "reject">("view");
  const [draftSubject, setDraftSubject] = useState(subject);
  const [draftBody, setDraftBody] = useState(body);
  const [reason, setReason] = useState("");
  const [result, setResult] = useState<ActionResult | null>(null);
  const [pending, start] = useTransition();
  const bodyRef = useRef<HTMLTextAreaElement>(null);
  const reasonRef = useRef<HTMLInputElement>(null);

  const goNext = () => router.push(nextId ? `/approvals?id=${nextId}` : "/approvals", { scroll: false });

  function run(action: () => Promise<ActionResult>, advance: boolean) {
    start(async () => {
      const r = await action();
      setResult(r);
      if (r.ok && advance) goNext();
      if (r.ok && !advance) { setMode("view"); router.refresh(); }
    });
  }

  const approve = () => run(() => approveDrafts([id]), true);
  const save = () => run(() => editDraft(id, draftSubject, draftBody), false);
  const reject = () => run(() => rejectDraft(id, reason || "Rejected from the dashboard"), true);

  // Keyboard: j/k move, a approve, e edit, r reject, Esc cancels. Never while
  // typing in a field - except Esc, and Cmd/Ctrl+Enter to save or confirm.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const typing = e.target instanceof HTMLElement && (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA");
      if (e.key === "Escape") { setMode("view"); setDraftSubject(subject); setDraftBody(body); return; }
      if (typing) {
        if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
          e.preventDefault();
          if (mode === "edit") save(); else if (mode === "reject") reject();
        }
        return;
      }
      if (e.metaKey || e.ctrlKey || e.altKey || pending) return;
      if (e.key === "j" && nextId) router.push(`/approvals?id=${nextId}`, { scroll: false });
      else if (e.key === "k" && prevId) router.push(`/approvals?id=${prevId}`, { scroll: false });
      else if (e.key === "a" && mode === "view") approve();
      else if (e.key === "e") { e.preventDefault(); setMode("edit"); setTimeout(() => bodyRef.current?.focus(), 0); }
      else if (e.key === "r") { e.preventDefault(); setMode("reject"); setTimeout(() => reasonRef.current?.focus(), 0); }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  return (
    <div>
      {mode === "edit" ? (
        <div className="space-y-3 p-4">
          <input
            value={draftSubject}
            onChange={(e) => setDraftSubject(e.target.value)}
            maxLength={200}
            aria-label="Subject"
            className="h-9 w-full rounded-md border bg-bg px-3 font-medium outline-none focus:border-accent focus:ring-2 focus:ring-[var(--ring)]"
          />
          <textarea
            ref={bodyRef}
            value={draftBody}
            onChange={(e) => setDraftBody(e.target.value)}
            rows={Math.min(24, Math.max(10, draftBody.split("\n").length + 2))}
            aria-label="Body"
            className="w-full resize-y rounded-md border bg-bg px-3 py-2.5 text-[13px] leading-relaxed outline-none focus:border-accent focus:ring-2 focus:ring-[var(--ring)]"
          />
          <p className="text-[11px] text-fg-subtle">
            The signature and opt-out block below the <code className="font-mono">--</code> line must stay as it is - it identifies you and lets the recipient say stop.
          </p>
        </div>
      ) : (
        <div className="px-4 py-4">
          <p className="text-[15px] font-semibold tracking-tight">{subject}</p>
          <div className="mt-3 whitespace-pre-wrap text-[13.5px] leading-relaxed text-fg">
            {renderBody(body)}
          </div>
        </div>
      )}

      {mode === "reject" ? (
        <div className="space-y-2 border-t bg-bg-subtle/50 px-4 py-3">
          <p className="text-[12px] font-medium">Why reject it? <span className="font-normal text-fg-subtle">Kept on the draft; it helps tune the prompts.</span></p>
          <div className="flex flex-wrap gap-1.5">
            {REASONS.map((r) => (
              <button key={r} type="button" onClick={() => setReason(r)}
                className={`rounded-full border px-2.5 py-0.5 text-[12px] ${reason === r ? "border-accent bg-accent-soft text-accent" : "bg-surface text-fg-muted hover:text-fg"}`}>
                {r}
              </button>
            ))}
          </div>
          <input ref={reasonRef} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} placeholder="Or write your own reason"
            className="h-8 w-full rounded-md border bg-surface px-3 outline-none focus:border-accent focus:ring-2 focus:ring-[var(--ring)]" />
        </div>
      ) : null}

      <div className="flex flex-wrap items-center gap-2 border-t px-4 py-3">
        {mode === "view" ? (
          <>
            <Button onClick={approve} disabled={pending}><Check className="size-4" /> Approve <Kbd>A</Kbd></Button>
            <Button variant="secondary" onClick={() => setMode("edit")} disabled={pending}><Pencil className="size-3.5" /> Edit <Kbd>E</Kbd></Button>
            <Button variant="ghost" onClick={() => setMode("reject")} disabled={pending}><X className="size-4" /> Reject <Kbd>R</Kbd></Button>
            <span className="ml-auto hidden items-center gap-1 text-[11px] text-fg-subtle lg:inline-flex">
              <Kbd>J</Kbd><Kbd>K</Kbd> next / previous
            </span>
          </>
        ) : mode === "edit" ? (
          <>
            <Button onClick={save} disabled={pending}>{pending ? "Saving…" : "Save changes"}</Button>
            <Button variant="ghost" onClick={() => { setMode("view"); setDraftSubject(subject); setDraftBody(body); }} disabled={pending}>Cancel <Kbd>Esc</Kbd></Button>
            <span className="ml-auto text-[11px] text-fg-subtle"><Kbd>⌘</Kbd> <Kbd>↵</Kbd> to save</span>
          </>
        ) : (
          <>
            <Button variant="danger" onClick={reject} disabled={pending}>{pending ? "Rejecting…" : "Reject draft"}</Button>
            <Button variant="ghost" onClick={() => setMode("view")} disabled={pending}>Cancel <Kbd>Esc</Kbd></Button>
          </>
        )}
        {result ? (
          <p role="status" className={`w-full text-[12px] ${result.ok ? "text-success" : "text-danger"}`}>{result.message}</p>
        ) : null}
      </div>
    </div>
  );
}

// The signature block (after the last "--" line) is shown muted, so the eye
// reads the message, and still sees that the opt-out line is there.
function renderBody(body: string) {
  const i = body.lastIndexOf("\n--\n");
  if (i < 0) return body;
  return (
    <>
      {body.slice(0, i)}
      <span className="mt-3 block border-t border-dashed pt-3 text-[12.5px] text-fg-muted">{body.slice(i + 1)}</span>
    </>
  );
}
