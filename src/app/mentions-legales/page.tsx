import LegalPage from "@/components/LegalPage";
import { legalInfo } from "@/lib/legal";
import { appName } from "@/lib/env";

export const dynamic = "force-dynamic";
export const metadata = { title: "Mentions légales" };

export default function MentionsLegales() {
  const l = legalInfo();
  return (
    <LegalPage title="Mentions légales">
      <section className="space-y-2">
        <h2>Éditeur du site</h2>
        <ul>
          <li>Site : {appName()}</li>
          <li>Statut : {l.status}</li>
          <li>Nom ou raison sociale : {l.name}</li>
          <li>Adresse postale : {l.address}</li>
          <li>Email de contact : <a className="text-volt-soft underline" href={`mailto:${l.email}`}>{l.email}</a></li>
          <li>Téléphone : <a className="text-volt-soft underline" href={`tel:${l.phone.replace(/\s/g, "")}`}>{l.phone}</a></li>
          <li>Directeur de la publication : {l.director}</li>
        </ul>
      </section>
      <section className="space-y-2">
        <h2>Hébergement</h2>
        <p>Le site est hébergé par : {l.host}.</p>
        <p>Les données de la plateforme (comptes, commandes, fichiers) sont stockées chez Supabase, prestataire d&apos;hébergement de bases de données.</p>
      </section>
      <section className="space-y-2">
        <h2>Rôle de la plateforme</h2>
        <p>{appName()} est une place de marché : elle met en relation des vendeurs indépendants et des acheteurs. Chaque vendeur est seul responsable de la description, de la qualité, de la légalité et de la livraison de ses produits. Le détail figure dans les conditions d&apos;utilisation et de vente.</p>
      </section>
      <section className="space-y-2">
        <h2>Propriété intellectuelle</h2>
        <p>La marque, le logo, le design et le code du site appartiennent à son éditeur. Les produits, textes et images publiés par les vendeurs restent la propriété de leurs auteurs, qui garantissent détenir les droits nécessaires. Pour signaler un contenu qui porte atteinte à vos droits, écrivez-nous à l&apos;adresse ci-dessus en précisant le lien de la page concernée : le contenu sera examiné rapidement et retiré si le signalement est fondé.</p>
      </section>
      <section className="space-y-2">
        <h2>Données personnelles</h2>
        <p>Le traitement de vos données est décrit dans la page « Confidentialité ». Vous pouvez à tout moment télécharger vos données ou supprimer votre compte depuis votre espace (Mon profil).</p>
      </section>
    </LegalPage>
  );
}
