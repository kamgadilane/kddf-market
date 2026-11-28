"use client";
import { explainError } from "@/lib/errors";
import { useMemo, useState } from "react";
import { formatFcfa } from "@/lib/money";
import { DELIVERY_LABELS } from "@/lib/labels";
import { CITIES } from "@/lib/shop";
import { MAX_ORDER_QUANTITY } from "@/lib/order";
import { PROVIDER_LABELS, type PaymentProvider } from "@/lib/payments";
import { DEFAULT_FEE_RULES, computeServiceFee, feeRuleText, type FeeRules } from "@/lib/serviceFee";
import { GUEST_DIGITAL_MESSAGE } from "@/lib/guest";
import FxPanel from "@/components/FxPanel";
import { useFxRates } from "@/lib/useFx";
import { DEFAULT_PAYPAL_CURRENCY, currencyInfo, formatMoney, quoteFromFcfa, type FxCurrency } from "@/lib/fxCore";
import type { DeliveryMethod, DeliveryOptions, PaymentMethod, ProductType } from "@/lib/types";

interface Props {
  productId: string;
  productType: ProductType;
  price: number;
  stock: number | null;
  deliveryOptions: DeliveryOptions | null;
  defaultEmail: string;
  loggedIn: boolean;
  providers: PaymentProvider[];
  /** Frais de service par moyen de paiement (réglés dans l'admin) */
  feeRules?: FeeRules;
  /** V4.0 : commande de GROS : prix par palier (dès 10 / dès 50 pièces), stock gros, paiement en ligne seulement. Le prix est recalculé par la base. */
  wholesale?: { price10: number; price50: number; stockGros: number };
}

/** Quantité minimale d'une commande de gros (même valeur dans la base). */
const WHOLESALE_MIN = 10;

const ORDER: DeliveryMethod[] = ["pickup_douala", "delivery_douala", "shipping_cameroon"];

export default function CheckoutForm({ productId, productType, price, stock, deliveryOptions, defaultEmail, loggedIn, providers, feeRules = DEFAULT_FEE_RULES, wholesale }: Props) {
  const physical = productType === "physical";
  const gros = wholesale !== undefined && physical;
  const minQty = gros ? WHOLESALE_MIN : 1;
  const soldOut = physical && (stock ?? 0) <= 0;
  const notEnoughGros = gros && Math.min(stock ?? 0, wholesale.stockGros) < WHOLESALE_MIN;
  const available = ORDER.filter((m) => deliveryOptions?.[m]?.enabled === true);

  const [email, setEmail] = useState(defaultEmail);
  const [name, setName] = useState("");
  const [qtyText, setQtyText] = useState(String(minQty)); // texte tapé : on peut effacer et retaper (ex. 25)
  const [method, setMethod] = useState<DeliveryMethod | "">("");
  const [payment, setPayment] = useState<PaymentMethod>("online");
  const [provider, setProvider] = useState<PaymentProvider>(providers[0] ?? "fapshi");
  const [address, setAddress] = useState(""); // repère (facultatif)
  const [phone, setPhone] = useState("");
  const [citySel, setCitySel] = useState(""); // ville choisie dans la liste (ou « Autre »)
  const [cityOther, setCityOther] = useState(""); // nom tapé si « Autre »
  const city = citySel === "Autre" ? cityOther.trim() : citySel;
  const [district, setDistrict] = useState("");
  const [needAccount, setNeedAccount] = useState(false);
  const [currency, setCurrency] = useState<FxCurrency>("XAF"); // devise d'affichage choisie par l'acheteur
  const fx = useFxRates();
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const maxQty = physical ? Math.max(minQty, Math.min(stock ?? 1, gros ? wholesale.stockGros : MAX_ORDER_QUANTITY, MAX_ORDER_QUANTITY)) : 1;
  const quantity = Math.min(maxQty, Math.max(minQty, Math.trunc(Number(qtyText)) || minQty));
  // Prix unitaire : au détail = prix du produit ; en gros = palier (jamais au-dessus du prix détail, comme dans la base)
  const unitPrice = gros ? Math.min(price, quantity >= 50 ? wholesale.price50 : wholesale.price10) : price;
  const deliveryPrice = useMemo(() => (method ? deliveryOptions?.[method]?.price ?? 0 : 0), [method, deliveryOptions]);
  const total = unitPrice * quantity + deliveryPrice; // total = prix x quantité + livraison (la base le recalcule à l'identique)
  // PayPal encaisse en devise étrangère : la devise choisie si PayPal l'accepte, sinon USD. Les autres moyens encaissent en FCFA.
  // Frais de service payés par l'acheteur (seulement en paiement en ligne) : affichés AVANT de payer, ajoutés au total par le serveur
  const online = !physical || gros || payment === "online";
  const serviceFee = online ? computeServiceFee(total, feeRules[provider]) : 0;
  const payTotal = total + serviceFee;
  const paysInForeign = provider === "paypal" && online;
  const chargeCurrency: FxCurrency = currencyInfo(currency).paypal ? currency : DEFAULT_PAYPAL_CURRENCY;

  async function submit(e: React.FormEvent): Promise<void> {
    e.preventDefault();
    setError("");
    setNeedAccount(false);
    if (physical && !method) {
      setError("Choisissez un mode de livraison.");
      return;
    }
    setLoading(true);
    try {
      const res = await fetch("/api/checkout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          productId,
          email: physical && !loggedIn ? "" : email, // achat physique sans compte : pas d'email
          name,
          quantity,
          deliveryMethod: physical ? method : null,
          address: physical ? address : "",
          phone: physical ? phone : "",
          city: physical ? city : "",
          district: physical ? district : "",
          provider,
          currency: chargeCurrency,
          paymentMethod: physical && !gros ? payment : "online", // le cash à la livraison n'existe que pour les produits physiques de détail
          wholesale: gros,
        }),
      });
      const json: unknown = await res.json().catch(() => null);
      const body = json !== null && typeof json === "object" ? (json as { url?: unknown; error?: unknown; needAccount?: unknown }) : {};
      if (body.needAccount === true) setNeedAccount(true);
      if (res.ok && typeof body.url === "string") {
        window.location.href = body.url; // page de paiement Fapshi (Orange Money / MTN MoMo) ou suivi de commande (cash)
        return;
      }
      setError(typeof body.error === "string" ? body.error : explainError(undefined));
    } catch {
      setError(explainError("failed to fetch"));
    }
    setLoading(false);
  }

  if (soldOut) {
    return <button className="btn-primary w-full" disabled>Rupture de stock</button>;
  }
  if (notEnoughGros) {
    return <p className="rounded-xl bg-amber-500/10 px-4 py-3 text-sm text-amber-200">Il reste moins de {WHOLESALE_MIN} pièces en gros pour ce produit. Contactez le grossiste par WhatsApp (bouton « Demander un devis »).</p>;
  }

  // Produit DIGITAL : un compte est OBLIGATOIRE pour recevoir le fichier (téléchargement et reçu rattachés au compte).
  // Produit PHYSIQUE : achat SANS compte (nom + téléphone + ville + quartier), aucun mot de passe.
  const next = encodeURIComponent(gros ? `/grossistes/commander/${productId}` : `/p/${productId}`);
  if (gros && !loggedIn) {
    return (
      <div className="space-y-3" role="status">
        <p className="rounded-xl bg-volt/10 px-4 py-3 text-sm text-white">Pour commander en gros, crée un compte gratuit en 30 secondes : c&apos;est ce qui protège ton argent et le grossiste.</p>
        <a href={`/login?mode=signup&next=${next}`} className="btn-primary w-full">Créer mon compte gratuit</a>
        <a href={`/login?next=${next}`} className="btn-ghost w-full">J&apos;ai déjà un compte</a>
      </div>
    );
  }
  if (!physical && !loggedIn) {
    return (
      <div className="space-y-3" role="status">
        <p className="rounded-xl bg-volt/10 px-4 py-3 text-sm text-white">{GUEST_DIGITAL_MESSAGE}</p>
        <a href={`/login?mode=signup&next=${next}`} className="btn-primary w-full">Créer mon compte gratuit</a>
        <a href={`/login?next=${next}`} className="btn-ghost w-full">J&apos;ai déjà un compte</a>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      {(!physical || gros) && (
        <div>
          <label className="label" htmlFor="co-email">{gros ? "Email (confirmation de commande)" : "Email (reçu et téléchargement)"}</label>
          <input id="co-email" type="email" required className="input" value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>
      )}
      <div>
        <label className="label" htmlFor="co-name">{physical ? "Nom complet" : "Nom"}</label>
        <input id="co-name" className="input" required={physical} autoComplete="name" value={name} onChange={(e) => setName(e.target.value)} />
      </div>
      {physical && (
        <div>
          <label className="label" htmlFor="co-phone">Numéro WhatsApp / MoMo</label>
          <input id="co-phone" type="tel" required inputMode="tel" autoComplete="tel" className="input" placeholder="6XX XX XX XX" value={phone} onChange={(e) => setPhone(e.target.value)} />
          <p className="mt-1 text-xs text-zinc-500">Pas de compte ni de mot de passe : ce numéro et le code KDDF-XXXX reçu après la commande servent à suivre votre colis.</p>
        </div>
      )}
      {physical && (
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="label" htmlFor="co-city">Ville</label>
            <select id="co-city" required className="input select" value={citySel} onChange={(e) => setCitySel(e.target.value)} autoComplete="address-level2">
              <option value="" disabled>Choisir…</option>
              {CITIES.map((c) => <option key={c} value={c}>{c === "Autre" ? "Autre ville…" : c}</option>)}
            </select>
          </div>
          <div>
            <label className="label" htmlFor="co-district">Quartier</label>
            <input id="co-district" required className="input" placeholder="Akwa" value={district} onChange={(e) => setDistrict(e.target.value)} />
          </div>
          {citySel === "Autre" && (
            <div className="col-span-2">
              <label className="label" htmlFor="co-city-other">Nom de votre ville</label>
              <input id="co-city-other" required className="input" placeholder="Ex. Édéa" autoComplete="address-level2" value={cityOther} onChange={(e) => setCityOther(e.target.value)} />
            </div>
          )}
        </div>
      )}

      {physical && (
        <>
          <div>
            <label className="label" htmlFor="co-qty">Quantité</label>
            <div className="flex items-stretch gap-2">
              <button type="button" aria-label="Diminuer la quantité" className="btn-ghost !px-4 text-xl" disabled={quantity <= minQty} onClick={() => setQtyText(String(quantity - 1))}>−</button>
              <input id="co-qty" type="number" inputMode="numeric" min={minQty} max={maxQty} className="input text-center" value={qtyText}
                onChange={(e) => setQtyText(e.target.value)}
                onBlur={() => setQtyText(String(quantity))} />
              <button type="button" aria-label="Augmenter la quantité" className="btn-ghost !px-4 text-xl" disabled={quantity >= maxQty} onClick={() => setQtyText(String(quantity + 1))}>+</button>
            </div>
            {gros ? (
              <p className="mt-1 text-xs text-zinc-400">Minimum {WHOLESALE_MIN} pièces · {formatFcfa(Math.min(price, wholesale.price10))} l&apos;unité dès 10, {formatFcfa(Math.min(price, wholesale.price50))} dès 50 · {Math.min(stock ?? 0, wholesale.stockGros)} disponibles en gros{quantity >= maxQty ? " : maximum atteint" : ""}.</p>
            ) : (
              stock !== null && stock !== undefined && <p className="mt-1 text-xs text-zinc-500">{stock} en stock{quantity >= maxQty && maxQty > 0 ? " : maximum atteint" : ""}.</p>
            )}
          </div>

          <fieldset className="space-y-2">
            <legend className="label">Mode de livraison</legend>
            {available.map((m) => {
              const p = deliveryOptions?.[m]?.price ?? 0;
              return (
                <label key={m} className={`flex cursor-pointer items-center justify-between gap-3 rounded-xl border p-3 text-sm transition ${method === m ? "border-volt bg-volt/10" : "border-white/10 hover:border-white/30"}`}>
                  <span className="flex items-center gap-3">
                    <input type="radio" name="delivery" value={m} checked={method === m} onChange={() => setMethod(m)} className="accent-indigo-500" />
                    <span className="text-white">{DELIVERY_LABELS[m]}</span>
                  </span>
                  <span className={p === 0 ? "font-semibold text-jade-soft" : "text-zinc-300"}>{p === 0 ? "Gratuit" : formatFcfa(p)}</span>
                </label>
              );
            })}
          </fieldset>

          {method !== "" && method !== "pickup_douala" && (
            <div>
              <label className="label" htmlFor="co-addr">Repère pour le livreur (facultatif)</label>
              <input id="co-addr" className="input" placeholder="Près de la pharmacie, portail bleu…" value={address} onChange={(e) => setAddress(e.target.value)} />
            </div>
          )}
        </>
      )}

      {physical && !gros && (
        <fieldset className="space-y-2">
          <legend className="label">Moyen de paiement</legend>
          <label className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 text-sm transition ${payment === "online" ? "border-volt bg-volt/10" : "border-white/10 hover:border-white/30"}`}>
            <input type="radio" name="payment" checked={payment === "online"} onChange={() => setPayment("online")} className="mt-1 accent-indigo-500" />
            <span><span className="block text-white">Payer en ligne maintenant</span><span className="text-xs text-zinc-400">Mobile Money, carte ou crypto selon les options disponibles</span></span>
          </label>
          <label className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 text-sm transition ${payment === "cod" ? "border-volt bg-volt/10" : "border-white/10 hover:border-white/30"}`}>
            <input type="radio" name="payment" checked={payment === "cod"} onChange={() => setPayment("cod")} className="mt-1 accent-indigo-500" />
            <span><span className="block text-white">Paiement à la livraison</span><span className="text-xs text-zinc-400">Vous ne payez rien en ligne : vous réglez en cash quand vous recevez le produit.</span></span>
          </label>
        </fieldset>
      )}

      {online && providers.length > 1 && (
        <fieldset className="space-y-2">
          <legend className="label">Payer avec</legend>
          {providers.map((p) => (
            <label key={p} className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 text-sm transition ${provider === p ? "border-volt bg-volt/10" : "border-white/10 hover:border-white/30"}`}>
              <input type="radio" name="provider" checked={provider === p} onChange={() => setProvider(p)} className="mt-1 accent-indigo-500" />
              <span><span className="block text-white">{PROVIDER_LABELS[p].title}</span><span className="text-xs text-zinc-400">{PROVIDER_LABELS[p].detail}</span></span>
            </label>
          ))}
        </fieldset>
      )}

      <div className="rounded-xl bg-white/5 p-4 text-sm">
        <div className="flex justify-between text-zinc-400"><span>{gros ? `${quantity} pièces × ${formatFcfa(unitPrice)}` : `Produit${quantity > 1 ? ` × ${quantity}` : ""}`}</span><span>{formatFcfa(unitPrice * quantity)}</span></div>
        {physical && <div className="mt-1 flex justify-between text-zinc-400"><span>Livraison</span><span>{method ? (deliveryPrice === 0 ? "Gratuit" : formatFcfa(deliveryPrice)) : "—"}</span></div>}
        {serviceFee > 0 && <div className="mt-1 flex justify-between text-zinc-400"><span>Frais de service ({PROVIDER_LABELS[provider].title.split(" ")[0]})</span><span>{formatFcfa(serviceFee)}</span></div>}
        <div className="mt-2 flex justify-between border-t border-white/10 pt-2 font-display text-lg font-bold text-white"><span>Total à payer</span><span>{formatFcfa(payTotal)}</span></div>
        {online && providers.length > 1 && <p className="mt-2 text-xs text-zinc-500">Frais de service selon le moyen de paiement : {providers.map((p) => `${PROVIDER_LABELS[p].title.split(" ")[0]} ${feeRuleText(feeRules[p])}`).join(" · ")}.</p>}
      </div>

      <FxPanel totalFcfa={payTotal} fx={fx} currency={currency} onCurrency={setCurrency} paysInForeign={paysInForeign} chargeCurrency={chargeCurrency} />

      {error && (
        <div role="alert" className="space-y-2 whitespace-pre-line rounded-xl bg-red-500/10 px-4 py-2.5 text-sm text-red-300">
          <p>{error}</p>
          {needAccount && <a href={`/login?mode=signup&next=${next}`} className="btn-primary w-full">Créer mon compte gratuit</a>}
        </div>
      )}
      <button className="btn-primary w-full" disabled={loading}>{loading ? "Patientez…" : paysInForeign && fx.status === "ok" ? `Payer ${formatMoney(quoteFromFcfa(payTotal, chargeCurrency, fx.rates, fx.marginPercent).minor, chargeCurrency)} avec PayPal` : physical && payment === "cod" ? "Commander (payer à la livraison)" : physical ? `Payer ${formatFcfa(payTotal)}` : `Acheter maintenant sur KDDF Market · ${formatFcfa(payTotal)}`}</button>
      <p className="text-center text-xs text-zinc-500">{physical && payment === "cod" ? "Vous payez le vendeur en cash à la réception." : paysInForeign ? "Paiement PayPal : le total en FCFA est converti au taux du jour, puis verrouillé au moment du paiement." : provider === "crypto" ? "Paiement crypto sécurisé : le montant est converti en euros (1 EUR = 655,957 FCFA) puis en crypto au taux du jour." : "Paiement 100 % sécurisé."}</p>
    </form>
  );
}
