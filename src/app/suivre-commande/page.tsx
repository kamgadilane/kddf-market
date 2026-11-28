import TrackOrder from "@/components/TrackOrder";

export const dynamic = "force-dynamic";
export const metadata = { title: "Suivre ma commande" };

/** Page publique : le client suit sa commande physique avec son Numéro + son Code KDDF-XXXX (aucun compte nécessaire). */
export default function SuivreCommandePage({ searchParams }: { searchParams: { code?: string } }) {
  const code = typeof searchParams.code === "string" ? searchParams.code.slice(0, 12).replace(/[^A-Za-z0-9-]/g, "") : "";
  return (
    <div className="mx-auto max-w-xl space-y-6">
      <div className="space-y-2">
        <h1 className="font-display text-3xl font-bold text-white">Suivre ma commande</h1>
        <p className="text-sm text-zinc-400">Entrez le numéro utilisé pour commander et votre code (ex. KDDF-8421). Pas besoin de compte.</p>
      </div>
      <TrackOrder defaultCode={code} />
    </div>
  );
}
