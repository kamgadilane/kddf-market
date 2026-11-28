# Modèles d'emails Supabase (inscription, mot de passe oublié...)

Ce sont les emails **envoyés par Supabase Auth** (pas par Resend). Pour les utiliser :

1. Supabase > **Authentication** > **Emails** (ou *Email Templates*).
2. Pour chaque modèle ci-dessous : ouvrez-le, remplacez le **Subject** et le **Message body (HTML)** par le contenu du fichier, puis **Save**.

| Modèle Supabase | Fichier | Objet (Subject) conseillé |
|---|---|---|
| Confirm signup | `confirm-signup.html` | Confirmez votre email - KDDF Market |
| Reset password | `reset-password.html` | Réinitialisez votre mot de passe - KDDF Market |
| Magic link | `magic-link.html` | Votre lien de connexion - KDDF Market |
| Change email address | `change-email.html` | Confirmez votre nouvelle adresse - KDDF Market |

Ne modifiez pas les variables `{{ .TokenHash }}`, `{{ .SiteURL }}`, `{{ .Email }}`, `{{ .NewEmail }}` : Supabase les remplace.

**Pourquoi `token_hash` (V3.2.1) :** les liens de ces modèles pointent vers `/auth/callback?token_hash=…&type=…`. Ils fonctionnent dans n'importe quel navigateur ou application mail (l'ancien lien `{{ .ConfirmationURL }}` échouait quand l'email était ouvert ailleurs que sur l'appareil d'inscription, et renvoyait sur la page de connexion). Après confirmation, l'utilisateur arrive directement sur `/dashboard` déjà connecté.

## Réglages indispensables (Authentication > URL Configuration)
- **Site URL** : l'adresse exacte de votre site, ex. `https://kddf-market.vercel.app`
- **Redirect URLs** : ajoutez `https://kddf-market.vercel.app/auth/callback` (et `http://localhost:3000/auth/callback` pour les tests)

Sans cela, les liens des emails (confirmation, mot de passe oublié) échouent avec « lien expiré ».

## Envoi fiable (recommandé en production)
Le service d'email intégré de Supabase est limité (quelques emails par heure). Dans Authentication > **SMTP Settings**, activez *Custom SMTP* avec Resend :
host `smtp.resend.com`, port `465`, utilisateur `resend`, mot de passe = votre clé API Resend, expéditeur = une adresse de votre domaine vérifié dans Resend.

## Emails de l'application (envoyés par Resend, pas par Supabase)
Les emails « reçu de paiement », « nouvelle vente », « nouvelle commission », « litige » et « bienvenue » sont dans `src/lib/emails/*.html` (envoyés par `src/lib/resend.ts`). L'email de bienvenue (`confirmation_inscription.html`) part à la première connexion ; l'email de confirmation d'adresse ci-dessus (`confirm-signup.html`) reste géré par Supabase Auth.
