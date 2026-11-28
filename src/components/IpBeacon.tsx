"use client";
import { useEffect } from "react";

/**
 * Au premier affichage d'un compte connecté :
 *  1) enregistre l'IP (anti-fraude) ; 2) déclenche l'email de bienvenue (une seule fois par compte, côté serveur).
 * Anti-fraude : demande au SERVEUR d'enregistrer l'adresse IP du compte connecté (une fois par onglet).
 * L'IP n'est jamais lue ni envoyée par le navigateur : le serveur la lit lui-même dans les en-têtes de la requête.
 * N'affiche rien. Une erreur est ignorée.
 */
export default function IpBeacon() {
  useEffect(() => {
    try {
      if (sessionStorage.getItem("kddf_ip_sent") === "1") return;
    } catch {
      // stockage indisponible : on enverra à chaque chargement, sans gravité
    }
    fetch("/api/welcome", { method: "POST", credentials: "same-origin" }).catch(() => undefined);
    fetch("/api/antifraud/ip", { method: "POST", credentials: "same-origin" })
      .then((r) => {
        if (!r.ok) return;
        try {
          sessionStorage.setItem("kddf_ip_sent", "1");
        } catch {
          // ignoré
        }
      })
      .catch(() => undefined);
  }, []);
  return null;
}
