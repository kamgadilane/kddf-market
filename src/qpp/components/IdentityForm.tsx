"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { compressImage } from "@/lib/imageCompress";
import { explainError } from "@/lib/errors";

const MAX_VIDEO_BYTES = 25 * 1024 * 1024; // limite du stockage « identity »

/**
 * Vérification d'identité du vendeur : recto, verso de la carte + selfie (photo) OU courte vidéo en tenant la carte.
 * Les fichiers vont dans un espace PRIVÉ (seul le propriétaire et l'administrateur peuvent les voir).
 */
export default function IdentityForm({ userId }: { userId: string }) {
  const router = useRouter();
  const [front, setFront] = useState<File | null>(null);
  const [back, setBack] = useState<File | null>(null);
  const [selfie, setSelfie] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  async function upload(path: string, file: File): Promise<void> {
    const { error } = await createClient().storage.from("identity").upload(path, file, { contentType: file.type, upsert: false });
    if (error) throw new Error(error.message);
  }

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (busy || !front || !back || !selfie) return;
    setBusy(true);
    setMsg(null);
    try {
      const isVideo = selfie.type.startsWith("video/");
      if (isVideo && selfie.size > MAX_VIDEO_BYTES) {
        throw new Error("Cause : la vidéo dépasse 25 Mo.\nSolution : refaites une vidéo de 10 secondes maximum, ou envoyez une simple photo de vous tenant votre carte.");
      }
      const stamp = Date.now();
      // Photos de la carte : assez grandes pour être lisibles (1600 px, 700 Ko maximum)
      const frontSmall = await compressImage(front, { maxSide: 1600, maxBytes: 700 * 1024 });
      const backSmall = await compressImage(back, { maxSide: 1600, maxBytes: 700 * 1024 });
      const selfieFile = isVideo ? selfie : await compressImage(selfie, { maxSide: 1600, maxBytes: 700 * 1024 });
      const ext = isVideo ? (selfie.type.includes("webm") ? "webm" : selfie.type.includes("quicktime") ? "mov" : "mp4") : "jpg";
      const frontPath = `${userId}/recto-${stamp}.jpg`;
      const backPath = `${userId}/verso-${stamp}.jpg`;
      const selfiePath = `${userId}/selfie-${stamp}.${ext}`;
      await upload(frontPath, frontSmall);
      await upload(backPath, backSmall);
      await upload(selfiePath, selfieFile);
      const { error } = await createClient().rpc("identity_submit", { p_front: frontPath, p_back: backPath, p_selfie: selfiePath, p_selfie_kind: isVideo ? "video" : "photo" });
      if (error) throw new Error(explainError(error.message));
      setMsg({ ok: true, text: "Documents envoyés. L'administrateur va les vérifier (24 à 48 h) : vous serez prévenu dans la cloche." });
      router.refresh();
    } catch (err) {
      const raw = err instanceof Error ? err.message : "";
      setMsg({ ok: false, text: raw.startsWith("Cause") ? raw : explainError(raw) });
    }
    setBusy(false);
  }

  return (
    <form onSubmit={submit} className="glass space-y-5 p-5">
      <p className="font-display text-lg font-bold text-white">Envoyer mes documents</p>
      <ol className="space-y-1 text-sm text-zinc-300">
        <li>1. Posez votre carte sur une surface plane, bien éclairée : tout le texte doit être lisible, sans reflet.</li>
        <li>2. Photographiez le <strong>recto</strong>, puis le <strong>verso</strong>.</li>
        <li>3. Filmez-vous (10 secondes) <strong>en tenant votre carte à côté de votre visage</strong>, ou prenez une photo de vous avec la carte.</li>
      </ol>
      <div>
        <label className="label" htmlFor="id-front">Recto de la carte (photo)</label>
        <input id="id-front" type="file" accept="image/*" capture="environment" className="input" onChange={(e) => setFront(e.target.files?.[0] ?? null)} required />
      </div>
      <div>
        <label className="label" htmlFor="id-back">Verso de la carte (photo)</label>
        <input id="id-back" type="file" accept="image/*" capture="environment" className="input" onChange={(e) => setBack(e.target.files?.[0] ?? null)} required />
      </div>
      <div>
        <label className="label" htmlFor="id-selfie">Vous avec votre carte (vidéo de 10 s ou photo)</label>
        <input id="id-selfie" type="file" accept="video/*,image/*" capture="user" className="input" onChange={(e) => setSelfie(e.target.files?.[0] ?? null)} required />
        <p className="mt-1 text-xs text-zinc-500">Vidéo : 25 Mo maximum. Sur téléphone, le bouton ouvre directement la caméra avant.</p>
      </div>
      <p className="rounded-xl bg-white/5 px-4 py-3 text-xs text-zinc-400">
        Vos documents sont stockés dans un espace privé, vus uniquement par vous et l&apos;administrateur, et servent uniquement à vérifier que vous êtes une vraie personne. Ils ne sont jamais affichés sur le site.
      </p>
      <button className="btn-primary w-full" disabled={busy || !front || !back || !selfie}>{busy ? "Envoi en cours… (ne fermez pas la page)" : "Envoyer pour vérification"}</button>
      {msg && <p role="status" className={`whitespace-pre-line text-sm ${msg.ok ? "text-jade-soft" : "text-red-300"}`}>{msg.text}</p>}
    </form>
  );
}
