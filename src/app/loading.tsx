import { CardsSkeleton, LoadingShell, SkeletonBlock } from "@/components/Skeleton";

// Écran de chargement général : affiché pendant la navigation vers n'importe quelle page du site.
export default function Loading() {
  return (
    <LoadingShell>
      <div className="space-y-6">
        <SkeletonBlock className="h-10 w-2/3 max-w-md" />
        <SkeletonBlock className="h-12 w-full max-w-xl" />
        <CardsSkeleton />
      </div>
    </LoadingShell>
  );
}
