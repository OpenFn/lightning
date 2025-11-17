export function RunSkeleton() {
  return (
    <div className="h-full p-4 animate-pulse">
      <div className="space-y-3">
        {/* Metadata skeleton */}
        {[...Array(5)].map((_, i) => (
          <div key={i} className="flex justify-between">
            <div className="h-4 bg-gray-200 rounded w-24" />
            <div className="h-4 bg-gray-200 rounded w-32" />
          </div>
        ))}
      </div>

      {/* Steps skeleton */}
      <div className="mt-6 space-y-2">
        <div className="h-4 bg-gray-200 rounded w-16 mb-3" />
        {[...Array(3)].map((_, i) => (
          <div key={i} className="flex items-center space-x-3 p-2">
            <div className="size-5 bg-gray-200 rounded-full" />
            <div className="flex-1 h-4 bg-gray-200 rounded" />
            <div className="h-3 bg-gray-200 rounded w-12" />
          </div>
        ))}
      </div>
    </div>
  );
}
