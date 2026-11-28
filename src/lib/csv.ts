// Export CSV compatible Excel (séparateur « ; », BOM UTF-8 pour les accents) avec protection contre l'injection de formules :
// une cellule texte qui commence par = + - @ (tabulation, retour) est préfixée d'une apostrophe pour ne jamais être exécutée par Excel.
export function csvCell(v: string | number | boolean | null | undefined): string {
  if (v === null || v === undefined) return "";
  if (typeof v === "number") return Number.isFinite(v) ? String(v) : "";
  let s = typeof v === "boolean" ? (v ? "oui" : "non") : v;
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  return /[";\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function toCsv(header: readonly string[], rows: ReadonlyArray<ReadonlyArray<string | number | boolean | null | undefined>>): string {
  const lines = [header.map(csvCell).join(";"), ...rows.map((r) => r.map(csvCell).join(";"))];
  return `﻿${lines.join("\r\n")}\r\n`;
}

export function csvResponse(name: string, body: string): Response {
  return new Response(body, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${name}"`,
      "Cache-Control": "no-store",
    },
  });
}

export const dayStamp = (): string => new Date().toISOString().slice(0, 10);
