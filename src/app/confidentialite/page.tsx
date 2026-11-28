import LegalPage from "@/components/LegalPage";
import Link from "next/link";
import { legalInfo } from "@/lib/legal";
import { appName } from "@/lib/env";

export const dynamic = "force-dynamic";
export const metadata = { title: "Politique de confidentialité" };

export default function Confidentialite() {
  const l = legalInfo();
  const name = appName();
  return (
    <LegalPage title="Politique de confidentialité">
      <section className="space-y-2">
        <h2>Qui est responsable de vos données ?</h2>
        <p>{l.name} ({l.status}), éditeur de {name}, {l.address}. Contact : <a className="text-volt-soft underline" href={`mailto:${l.email}`}>{l.email}</a>.</p>
      </section>
      <section className="space-y-2">
        <h2>Quelles données collectons-nous, et pourquoi ?</h2>
        <ul>
          <li><strong>Compte</strong> : email, mot de passe (chiffré, jamais lisible par nous), nom, boutique, photo, numéros de téléphone / WhatsApp. Pour vous connecter et gérer votre espace.</li>
          <li><strong>Commandes</strong> : produit acheté, nom, téléphone, ville, quartier et repère de livraison (produits physiques), email (produits digitaux). Pour livrer, suivre la commande et gérer les litiges.</li>
          <li><strong>Paiements</strong> : montant, moyen utilisé, référence de la transaction. Vos numéros de carte ne passent jamais par nos serveurs : ils sont saisis chez nos partenaires de paiement.</li>
          <li><strong>Vendeurs</strong> : portefeuille, retraits (numéro Mobile Money, compte PayPal, adresse crypto ou compte bancaire que vous indiquez). Pour vous verser vos gains.</li>
          <li><strong>Vérification d&apos;identité des vendeurs</strong> : photos du recto et du verso de la carte d&apos;identité, et vidéo ou photo du vendeur tenant sa carte. Elles servent uniquement à vérifier qu&apos;il s&apos;agit d&apos;une vraie personne, avant de l&apos;autoriser à vendre. Elles sont stockées dans un espace privé, vues uniquement par vous et l&apos;administrateur, jamais affichées sur le site ni transmises aux acheteurs. Vous pouvez en demander la suppression en écrivant à l&apos;adresse de contact (votre boutique ne pourra alors plus publier de produits).</li>
          <li><strong>Sécurité du compte</strong> : numéro de téléphone confirmé par SMS et, si vous l&apos;activez, protection 2FA (le secret du code à 6 chiffres est géré par notre prestataire de connexion Supabase).</li>
          <li><strong>Grossistes</strong> : photo de pièce d&apos;identité et de boutique, stockées dans un espace privé, visibles uniquement par l&apos;équipe de vérification.</li>
          <li><strong>Sécurité</strong> : adresse IP, appareil et fréquence des commandes, pour détecter la fraude et limiter les abus ; erreurs techniques rencontrées sur le site.</li>
          <li><strong>Statistiques</strong> : nombre de vues des produits et provenance des liens d&apos;affiliation, sans outil publicitaire tiers.</li>
        </ul>
      </section>
      <section className="space-y-2">
        <h2>Qui reçoit vos données ?</h2>
        <p>Uniquement les prestataires nécessaires au service : Supabase (base de données, fichiers, connexion), Vercel (hébergement), Fapshi, Flutterwave, NOWPayments et PayPal (paiements), Resend (envoi d&apos;emails). Le vendeur reçoit le nom, le téléphone et l&apos;adresse de livraison de ses commandes physiques. Nous ne vendons jamais vos données. Certains prestataires sont situés hors du Cameroun (Europe, États-Unis) : vos données peuvent donc y être traitées.</p>
      </section>
      <section className="space-y-2">
        <h2>Combien de temps les conservons-nous ?</h2>
        <p>Les données de votre compte sont conservées tant que le compte existe. Les écritures liées aux ventes et aux retraits (montants, dates, références) sont conservées sans votre nom après suppression du compte, pour la durée de conservation légale des pièces comptables. Les journaux techniques et d&apos;erreurs sont supprimés automatiquement (30 à 60 jours en général).</p>
      </section>
      <section className="space-y-2">
        <h2>Cookies et stockage local</h2>
        <p>Nous utilisons uniquement des éléments nécessaires : cookie de connexion (session), mémorisation du lien d&apos;affiliation pendant 30 jours, choix du thème clair/sombre, panier et préférences de l&apos;application installée. Aucun cookie publicitaire.</p>
      </section>
      <section className="space-y-2">
        <h2>Vos droits</h2>
        <ul>
          <li><strong>Accès et copie</strong> : dans <Link href="/dashboard/settings" className="text-volt-soft underline">Mon profil</Link>, « Télécharger mes données ».</li>
          <li><strong>Correction</strong> : modifiez vos informations dans Mon profil.</li>
          <li><strong>Suppression</strong> : « Supprimer mon compte » dans Mon profil (conditions : portefeuille vide, aucun retrait, litige ou commande en cours).</li>
          <li><strong>Autre demande</strong> (opposition, limitation, question) : écrivez à <a className="text-volt-soft underline" href={`mailto:${l.email}`}>{l.email}</a>, nous répondons sous 30 jours.</li>
        </ul>
      </section>
      <section className="space-y-2">
        <h2>Sécurité</h2>
        <p>Connexion chiffrée (HTTPS), accès aux données limité par des règles strictes dans la base, mots de passe chiffrés, fichiers privés protégés par des liens temporaires, contrôles anti-fraude. Aucun système n&apos;est infaillible : en cas d&apos;incident touchant vos données, nous vous prévenons.</p>
      </section>
      <section className="space-y-2">
        <h2>Mineurs</h2>
        <p>Le site s&apos;adresse aux personnes de 18 ans et plus, ou aux mineurs agissant avec l&apos;accord de leurs parents. Si vous pensez qu&apos;un mineur nous a transmis des données sans accord, contactez-nous : nous les supprimerons.</p>
      </section>
    </LegalPage>
  );
}
