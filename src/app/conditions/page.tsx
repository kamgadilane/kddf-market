import LegalPage from "@/components/LegalPage";
import Link from "next/link";
import { legalInfo } from "@/lib/legal";
import { appName } from "@/lib/env";
import { getTarifs, percentText } from "@/lib/tarifs";
import { getFreeProductLimit } from "@/lib/freePlan";
import { getServiceFeeRules } from "@/lib/serviceFeeServer";
import { feeRuleText } from "@/lib/serviceFee";
import { PROVIDERS, PROVIDER_LABELS } from "@/lib/payments";
import { formatFcfa } from "@/lib/money";

export const dynamic = "force-dynamic";
export const metadata = { title: "Conditions d'utilisation et de vente" };

export default async function Conditions() {
  const l = legalInfo();
  const name = appName();
  const [t, limit, rules] = await Promise.all([getTarifs(), getFreeProductLimit(), getServiceFeeRules()]);
  return (
    <LegalPage title="Conditions d'utilisation et de vente">
      <section className="space-y-2">
        <h2>1. Objet</h2>
        <p>{name} (« la plateforme ») est une place de marché en ligne où des vendeurs indépendants proposent des produits digitaux (guides, fichiers, formations, clés de licence, coaching, services) et des produits physiques. En utilisant le site, vous acceptez les présentes conditions. Éditeur : {l.name} ({l.status}), {l.address}.</p>
      </section>
      <section className="space-y-2">
        <h2>2. Rôle de la plateforme</h2>
        <p>La plateforme met en relation vendeurs et acheteurs et encaisse les paiements pour leur compte. Le contrat de vente est conclu entre le vendeur et l&apos;acheteur : le vendeur est responsable de son produit (description, qualité, légalité, livraison). La plateforme contrôle les produits avant leur mise en ligne, sans garantir qu&apos;aucune erreur ne subsiste, et intervient en cas de litige selon la page <Link href="/remboursement" className="text-volt-soft underline">Remboursement et litiges</Link>.</p>
      </section>
      <section className="space-y-2">
        <h2>3. Comptes</h2>
        <ul>
          <li>Un compte gratuit est obligatoire pour acheter un produit digital et pour vendre. Un produit physique peut être acheté sans compte (nom, numéro de téléphone, ville et quartier).</li>
          <li>Vous devez avoir 18 ans, ou l&apos;accord de vos parents ou tuteurs si vous êtes mineur. Les informations fournies doivent être exactes.</li>
          <li>Vous protégez votre mot de passe et êtes responsable de l&apos;activité de votre compte. Un compte peut être suspendu en cas de fraude, d&apos;abus ou de non-respect des présentes conditions.</li>
        </ul>
      </section>
      <section className="space-y-2">
        <h2>4. Produits autorisés et interdits</h2>
        <p>Il est interdit de vendre : contenus illégaux ou contrefaits, produits volés, armes, drogues, médicaments sans autorisation, contenus pour adultes, faux documents, produits dangereux, arnaques, « systèmes pyramidaux », et tout produit dont la vente est interdite au Cameroun. Pour publier, chaque vendeur doit faire vérifier son identité (carte d&apos;identité et vidéo ou photo avec la carte) ; l&apos;administrateur peut refuser la vérification ou suspendre un compte en cas de doute. Chaque produit est examiné avant publication ; la plateforme peut refuser ou retirer un produit sans préavis, et suspendre le vendeur.</p>
      </section>
      <section className="space-y-2">
        <h2>5. Prix et paiement</h2>
        <ul>
          <li>Les prix sont en francs CFA (FCFA), fixés par les vendeurs. La livraison d&apos;un produit physique est indiquée avant le paiement.</li>
          <li>Moyens de paiement selon disponibilité : Mobile Money (MTN, Orange), cartes bancaires, PayPal, cryptomonnaies. Les paiements sont traités par nos partenaires de paiement : la plateforme ne conserve jamais votre numéro de carte ni votre code secret.</li>
          <li>Paiement en devise étrangère : le total en FCFA est converti au taux du jour, puis verrouillé au moment du paiement. Votre banque ou PayPal peut appliquer ses propres frais de change.</li>
          <li>
            Frais de service : selon le moyen de paiement choisi, des frais de service s&apos;ajoutent au prix pour couvrir les frais de la passerelle. Ils sont affichés avant le paiement et ne sont jamais prélevés sur le vendeur. Barème actuel :{" "}
            {PROVIDERS.map((p) => `${PROVIDER_LABELS[p].title} : ${feeRuleText(rules[p])}`).join(" ; ")}.
          </li>
          <li>Paiement à la livraison (produits physiques, lorsque proposé) : vous réglez le vendeur en cash à la réception.</li>
        </ul>
      </section>
      <section className="space-y-2">
        <h2>6. Livraison</h2>
        <ul>
          <li>Produit digital : accès immédiat à la page de téléchargement et copie envoyée par email après paiement confirmé. Les liens sont personnels : ne les partagez pas.</li>
          <li>Produit physique : retrait ou livraison selon l&apos;option choisie. Un code de commande KDDF-XXXX permet de suivre le colis et d&apos;ouvrir un litige. Les délais dépendent du vendeur.</li>
        </ul>
      </section>
      <section className="space-y-2">
        <h2>7. Commissions, portefeuille et retraits des vendeurs</h2>
        <ul>
          <li>Commission de la plateforme sur le prix des articles (hors livraison) : {percentText(t.normalPercent)} actuellement, {percentText(t.proPercent)} pour les vendeurs Pro. Elle peut évoluer ; le taux appliqué à une vente est celui en vigueur au moment du paiement. Si vous recrutez un affilié, sa part (choisie par produit) est prélevée sur la vente.</li>
          <li>Le paiement d&apos;un produit digital est disponible après 24 heures ; celui d&apos;un produit physique après confirmation de réception (ou 7 jours après la livraison sans litige), et jamais avant 7 jours après le paiement. Il est bloqué tant qu&apos;un litige est ouvert.</li>
          <li>Retrait : minimum 1 000 FCFA, frais de {percentText(t.withdrawalFeePercent)} (minimum {formatFcfa(t.withdrawalFeeMin)}) ; option « express » avec un supplément de {percentText(t.expressFeePercent)}. Les retraits sont validés par l&apos;équipe, généralement sous 48 heures ouvrées.</li>
          <li>Plan gratuit : jusqu&apos;à {limit === 0 ? "un nombre illimité de" : limit} produits publiés. L&apos;abonnement Pro ({formatFcfa(t.proPrice)} pour 30 jours, non renouvelé automatiquement) supprime cette limite et réduit la commission.</li>
          <li>Le vendeur est responsable de ses obligations fiscales et légales liées à son activité.</li>
        </ul>
      </section>
      <section className="space-y-2">
        <h2>8. Affiliation</h2>
        <p>Un affilié reçoit la commission affichée sur le produit lorsqu&apos;une vente est conclue via son lien (suivi de 30 jours). Il est interdit d&apos;acheter via son propre lien : la commission est alors annulée. Les ventes frauduleuses annulent les commissions.</p>
      </section>
      <section className="space-y-2">
        <h2>9. Fraude et sécurité</h2>
        <p>La plateforme utilise des contrôles anti-fraude (par exemple limite de commandes par numéro de téléphone). Un paiement dont le montant ne correspond pas à la commande est bloqué et vérifié à la main. Toute tentative de fraude peut entraîner le blocage du compte et la rétention des fonds concernés.</p>
      </section>
      <section className="space-y-2">
        <h2>10. Responsabilité</h2>
        <p>La plateforme s&apos;efforce d&apos;assurer un service continu mais ne peut garantir l&apos;absence d&apos;interruption (maintenance, incident chez un partenaire de paiement ou d&apos;hébergement). Elle n&apos;est pas responsable des produits des vendeurs au-delà de ce que prévoit la loi et de la page Remboursement et litiges. Aucun résultat financier n&apos;est garanti par l&apos;achat d&apos;une formation ou d&apos;un guide.</p>
      </section>
      <section className="space-y-2">
        <h2>11. Propriété intellectuelle</h2>
        <p>Le vendeur garantit détenir les droits sur ce qu&apos;il publie. L&apos;acheteur reçoit un droit d&apos;usage personnel du produit digital ; la revente ou la diffusion du fichier sont interdites sauf accord écrit du vendeur.</p>
      </section>
      <section className="space-y-2">
        <h2>12. Données personnelles</h2>
        <p>Voir la page <Link href="/confidentialite" className="text-volt-soft underline">Confidentialité</Link>.</p>
      </section>
      <section className="space-y-2">
        <h2>13. Modification des conditions</h2>
        <p>Les conditions peuvent évoluer ; la date de mise à jour figure en haut de la page. En cas de changement important (par exemple une hausse de commission), les vendeurs sont prévenus à l&apos;avance. Continuer à utiliser le site après la mise à jour vaut acceptation.</p>
      </section>
      <section className="space-y-2">
        <h2>14. Droit applicable et contact</h2>
        <p>Les présentes conditions sont soumises au droit camerounais. En cas de désaccord, nous cherchons d&apos;abord une solution à l&apos;amiable ; à défaut, les tribunaux compétents de Douala seront saisis. Contact : <a className="text-volt-soft underline" href={`mailto:${l.email}`}>{l.email}</a>.</p>
      </section>
    </LegalPage>
  );
}
