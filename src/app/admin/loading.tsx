import { LoadingShell, SkeletonBlock } from "@/components/Skeleton";

// Chargement de l'administration.
export default function Loading() {
  return (
    <LoadingShell>
      <div className="space-y-6">
        <SkeletonBlock className="h-8 w-1/3 max-w-xs" />
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }, (_, i) => <SkeletonBlock key={i} className="h-24" />)}
        </div>
        <SkeletonBlock className="h-56 w-full" />
      </div>
    </LoadingShell>
  );
}
