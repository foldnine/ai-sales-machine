import type { Metadata } from "next";
import { GeistSans } from "geist/font/sans";
import { GeistMono } from "geist/font/mono";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "AI Sales Machine", template: "%s · AI Sales Machine" },
  description: "Pipeline, approvals and system health for your self-hosted sales pipeline.",
  robots: { index: false, follow: false },
};

// Set the theme class before first paint, so a dark-mode user never sees a
// white flash: the saved choice, else the system preference.
const themeScript = `(function(){try{var t=localStorage.getItem('theme');var d=t?t==='dark':matchMedia('(prefers-color-scheme: dark)').matches;document.documentElement.classList.toggle('dark',d)}catch(e){}})()`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" data-style={process.env.DASHBOARD_STYLE === "apple" ? "apple" : "default"} className={`${GeistSans.variable} ${GeistMono.variable}`} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
