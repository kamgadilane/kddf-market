// Génère src/lib/emails/templates.generated.ts à partir des fichiers src/lib/emails/*.html.
// Pourquoi : Next.js n'importe pas les .html ; ce script (lancé par "prebuild" et "predev") embarque les modèles dans le code.
// Le fichier généré est AUSSI versionné dans le dépôt : si le script ne tourne pas, le build fonctionne quand même.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const dir = join(dirname(fileURLToPath(import.meta.url)), "..", "src", "lib", "emails");
const files = readdirSync(dir).filter((f) => f.endsWith(".html")).sort();
const entries = files.map((f) => `  ${JSON.stringify(f.replace(/\.html$/, ""))}: ${JSON.stringify(readFileSync(join(dir, f), "utf8"))},`);
const out = `// FICHIER GÉNÉRÉ par scripts/build-emails.mjs : ne le modifiez pas à la main, modifiez les .html puis lancez "npm run build:emails".\nexport const EMAIL_TEMPLATES: Record<string, string> = {\n${entries.join("\n")}\n};\n`;
writeFileSync(join(dir, "templates.generated.ts"), out);
console.log(`[emails] ${files.length} modèle(s) embarqué(s) : ${files.join(", ")}`);
