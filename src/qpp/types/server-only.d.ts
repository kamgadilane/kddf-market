// Le paquet « server-only » n'a pas de types : cette déclaration évite l'erreur TS2882 (import à effet de bord) selon la version de TypeScript.
declare module "server-only";
