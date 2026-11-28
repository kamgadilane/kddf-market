export default function StatCard({
  label,
  value,
  hint,
  tone = "default",
  className = "",
}: {
  label: string;
  value: string;
  hint?: string;
  tone?: "default" | "jade" | "volt";
  className?: string;
}) {
  const color = tone === "jade" ? "text-jade-soft" : tone === "volt" ? "text-volt-soft" : "text-white";
  return (
    <div className={`card-float min-w-0 p-4 sm:p-5 ${className}`}>
      <p className="label !mb-1 !text-[10px] leading-tight sm:!text-xs">{label}</p>
      <p className={`font-display text-xl font-bold leading-tight [overflow-wrap:anywhere] sm:text-2xl ${color}`}>{value}</p>
      {hint && <p className="mt-1 text-xs text-zinc-500">{hint}</p>}
    </div>
  );
}
