import StatCard from "@/components/StatCard";

/** Carte « Nombre d'affiliés » du tableau de bord admin (valeur fournie par la fonction SQL admin_overview : aucune requête ici). */
export default function AdminAffiliateCount({ value }: { value: number }) {
  return <StatCard label="Nombre d'affiliés" value={String(Number.isFinite(value) ? value : 0)} />;
}
