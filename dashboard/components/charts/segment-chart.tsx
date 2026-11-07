"use client";

import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

export function SegmentChart({ data }: { data: { name: string; contacted: number; replied: number; conversations: number }[] }) {
  return (
    <div className="h-[240px]">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} barGap={2} barCategoryGap="28%">
          <CartesianGrid vertical={false} stroke="var(--border)" />
          <XAxis dataKey="name" interval={0} tickLine={false} axisLine={false} tick={{ fontSize: 10.5, fill: "var(--fg-subtle)" }} />
          <YAxis allowDecimals={false} tickLine={false} axisLine={false} width={28} tick={{ fontSize: 11, fill: "var(--fg-subtle)" }} />
          <Tooltip
            cursor={{ fill: "var(--bg-subtle)" }}
            contentStyle={{ background: "var(--surface-raised)", border: "1px solid var(--border)", borderRadius: 8, fontSize: 12 }}
            labelStyle={{ color: "var(--fg)", fontWeight: 600 }}
            itemStyle={{ color: "var(--fg-muted)", padding: 0 }}
          />
          <Bar dataKey="contacted" name="Contacted" fill="var(--chart-2)" radius={[3, 3, 0, 0]} maxBarSize={22} />
          <Bar dataKey="replied" name="Replied" fill="var(--chart-1)" radius={[3, 3, 0, 0]} maxBarSize={22} />
          <Bar dataKey="conversations" name="Conversations" fill="var(--chart-3)" radius={[3, 3, 0, 0]} maxBarSize={22} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
