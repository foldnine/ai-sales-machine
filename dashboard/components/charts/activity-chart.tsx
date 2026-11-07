"use client";

import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

type Day = { day: string; discovered: number; drafted: number; sent: number; replies: number };

const series = [
  { key: "discovered", label: "Discovered", color: "var(--chart-2)" },
  { key: "drafted", label: "Drafted", color: "var(--chart-1)" },
  { key: "sent", label: "Sent", color: "var(--chart-3)" },
  { key: "replies", label: "Replies", color: "var(--chart-4)" },
] as const;

export function ActivityChart({ data }: { data: Day[] }) {
  return (
    <div>
      <div className="mb-3 flex flex-wrap gap-4 px-1">
        {series.map((s) => (
          <span key={s.key} className="inline-flex items-center gap-1.5 text-[12px] text-fg-muted">
            <span className="size-2 rounded-sm" style={{ background: s.color }} /> {s.label}
          </span>
        ))}
      </div>
      <div className="h-[220px]">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={data} barGap={1} barCategoryGap="22%">
            <CartesianGrid vertical={false} stroke="var(--border)" />
            <XAxis
              dataKey="day" tickLine={false} axisLine={false} minTickGap={24}
              tick={{ fontSize: 11, fill: "var(--fg-subtle)" }}
              tickFormatter={(d: string) => new Date(d + "T00:00:00").toLocaleDateString("en-GB", { day: "numeric", month: "short" })}
            />
            <YAxis allowDecimals={false} tickLine={false} axisLine={false} width={28} tick={{ fontSize: 11, fill: "var(--fg-subtle)" }} />
            <Tooltip
              cursor={{ fill: "var(--bg-subtle)" }}
              contentStyle={{ background: "var(--surface-raised)", border: "1px solid var(--border)", borderRadius: 8, fontSize: 12, boxShadow: "var(--shadow)" }}
              labelStyle={{ color: "var(--fg)", fontWeight: 600, marginBottom: 4 }}
              itemStyle={{ color: "var(--fg-muted)", padding: 0 }}
              labelFormatter={(d) => new Date(String(d) + "T00:00:00").toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" })}
            />
            {series.map((s) => (
              <Bar key={s.key} dataKey={s.key} name={s.label} stackId="a" fill={s.color} radius={0} maxBarSize={18} />
            ))}
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
