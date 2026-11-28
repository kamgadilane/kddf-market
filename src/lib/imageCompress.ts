// Compression des images AVANT l'envoi (navigateur) : 800 px maximum sur le plus grand côté, 200 Ko maximum.
// But : rester dans le plan gratuit Supabase (1 Go de stockage) et charger vite sur mobile (connexions lentes).
// Ce fichier ne s'exécute que dans le navigateur (canvas). Si la compression est impossible (navigateur très ancien), on lève une erreur claire.
export const MAX_IMAGE_SIDE = 800;
export const MAX_IMAGE_BYTES = 200 * 1024;

export interface CompressOptions {
  maxSide?: number;
  maxBytes?: number;
}

function loadImage(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve(img);
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("Image illisible : choisissez une photo JPG, PNG ou WebP."));
    };
    img.src = url;
  });
}

function toBlob(canvas: HTMLCanvasElement, quality: number): Promise<Blob | null> {
  return new Promise((resolve) => canvas.toBlob((b) => resolve(b), "image/jpeg", quality));
}

/** Dimensions après réduction (le plus grand côté ne dépasse jamais maxSide ; jamais d'agrandissement). */
export function fitWithin(width: number, height: number, maxSide: number): { width: number; height: number } {
  const longest = Math.max(width, height);
  if (longest <= maxSide) return { width, height };
  const ratio = maxSide / longest;
  return { width: Math.max(1, Math.round(width * ratio)), height: Math.max(1, Math.round(height * ratio)) };
}

/**
 * Réduit une image à 800 px / 200 Ko maximum (JPEG). Essaie des qualités décroissantes, puis réduit encore la taille si besoin.
 * Renvoie un NOUVEAU fichier JPEG ; le fichier d'origine n'est pas modifié.
 */
export async function compressImage(file: File, options: CompressOptions = {}): Promise<File> {
  const maxSide = options.maxSide ?? MAX_IMAGE_SIDE;
  const maxBytes = options.maxBytes ?? MAX_IMAGE_BYTES;
  if (!/^image\/(jpeg|png|webp)$/.test(file.type)) throw new Error("Seules les images JPG, PNG ou WebP sont acceptées.");

  const img = await loadImage(file);
  let side = maxSide;
  for (let round = 0; round < 6; round += 1) {
    const { width, height } = fitWithin(img.naturalWidth, img.naturalHeight, side);
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("Votre navigateur ne permet pas de réduire l'image : choisissez une photo plus légère.");
    ctx.fillStyle = "#ffffff"; // les PNG transparents deviennent blancs (le JPEG n'a pas de transparence)
    ctx.fillRect(0, 0, width, height);
    ctx.drawImage(img, 0, 0, width, height);
    for (const quality of [0.85, 0.75, 0.65, 0.55, 0.45, 0.35]) {
      const blob = await toBlob(canvas, quality);
      if (blob && blob.size <= maxBytes) {
        return new File([blob], file.name.replace(/\.[^.]+$/, "") + ".jpg", { type: "image/jpeg", lastModified: Date.now() });
      }
    }
    side = Math.round(side * 0.85); // toujours trop lourd : on réduit encore les dimensions
  }
  throw new Error("Image trop complexe pour être réduite à 200 Ko : choisissez une autre photo.");
}
