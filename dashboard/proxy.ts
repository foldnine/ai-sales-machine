import { NextResponse, type NextRequest } from "next/server";

// An optimistic check only: no cookie, go to /login. The real check is
// verifySession() in lib/session.ts, run by every page and action.
export function proxy(request: NextRequest) {
  if (!request.cookies.has("aism_session")) {
    return NextResponse.redirect(new URL("/login", request.url));
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!login|api/health|_next/static|_next/image|favicon.ico|icon.svg).*)"],
};
