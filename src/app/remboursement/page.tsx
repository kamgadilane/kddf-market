import LegalPage from "@/components/LegalPage";
import { legalInfo } from "@/lib/legal";

export const dynamic = "force-dynamic";
export const metadata = { title: "Remboursement et litiges" };

export default function Remboursement() {
  const l = legalInfo();
  return (
    <LegalPage title="Remboursement et litiges">
      <section className="space-y-2">
        <h2>Principe : vos paiements sont protégés</h2>
        <p>Votre paiement n&apos;est pas versé tout de suite au vendeur. Il est d&apos;abord conservé par la plateforme : 24 heures après l&apos;achat pour un produit digital, et jusqu&apos;à la confirmation de réception (ou 7 jours après la livraison sans litige) pour un produit physique, et au minimum 7 jours après le paiement. Pendant ce délai, vous pouvez signaler un problème.</p>
      </section>
      <section className="space-y-2">
        <h2>Produit digital (fichier, formation, licence, coaching, service)</h2>
        <ul>
          <li>Le produit est livré immédiatement après le paiement : en règle générale, il n&apos;est donc pas remboursable une fois téléchargé ou consulté.</li>
          <li>Nous remboursons dans les cas suivants : fichier introuvable ou inutilisable que le vendeur ne corrige pas, clé de licence invalide, produit très différent de sa description, paiement en double.</li>
          <li>Écrivez-nous dans les 24 heures qui suivent l&apos;achat via la page Support, avec le nom du produit et une capture d&apos;écran si possible.</li>
        </ul>
      </section>
      <section className="space-y-2">
        <h2>Produit physique</h2>
        <ul>
          <li>Après réception, cliquez sur « J&apos;ai reçu mon produit » seulement si tout est conforme : cette confirmation libère l&apos;argent au vendeur.</li>
          <li>Si le colis n&apos;arrive pas, arrive abîmé ou ne correspond pas à l&apos;annonce, ouvrez un litige depuis la page de suivi de votre commande (avec ou sans compte : votre numéro de téléphone et le code KDDF-XXXX suffisent) et ajoutez jusqu&apos;à 3 photos.</li>
          <li>Tant que le litige est ouvert, l&apos;argent reste bloqué. L&apos;équipe étudie les preuves des deux parties puis décide : remboursement de l&apos;acheteur ou versement au vendeur.</li>
          <li>Paiement à la livraison : vous ne payez le vendeur en cash que si le produit vous convient. Vous pouvez refuser le colis à la remise s&apos;il n&apos;est pas conforme.</li>
        </ul>
      </section>
      <section className="space-y-2">
        <h2>Montant remboursé</h2>
        <p>Quand la plateforme décide un remboursement complet (produit non livré, erreur de la plateforme, paiement en double), vous récupérez le montant payé, frais de service compris. Dans les autres cas (par exemple un remboursement partiel décidé avec le vendeur), le montant est précisé dans la décision. Le remboursement est renvoyé par le même moyen de paiement ou, à défaut, par Mobile Money, dans un délai habituel de 3 à 10 jours ouvrés selon l&apos;opérateur.</p>
      </section>
      <section className="space-y-2">
        <h2>Paiement bloqué ou débité sans commande</h2>
        <p>Si vous avez été débité sans recevoir de confirmation, ne payez pas une deuxième fois : conservez le message de votre opérateur et écrivez-nous. Les paiements reçus mais non rattachés à une commande sont vérifiés à la main et remboursés ou validés.</p>
      </section>
      <section className="space-y-2">
        <h2>Nous contacter</h2>
        <p>Page Support du site, ou par email à <a className="text-volt-soft underline" href={`mailto:${l.email}`}>{l.email}</a>, ou au {l.phone} (WhatsApp). Nous répondons généralement sous 48 heures.</p>
      </section>
    </LegalPage>
  );
}
