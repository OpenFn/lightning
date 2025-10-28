import useAdaptorIcons from "#/workflow-diagram/useAdaptorIcons";

import { extractAdaptorName } from "../utils/adaptorUtils";

interface AdaptorIconProps {
  name: string;
  size?: "sm" | "md" | "lg";
}

const sizeClasses = {
  sm: "h-6 w-6",
  md: "h-8 w-8",
  lg: "h-12 w-12",
};

export function AdaptorIcon({ name, size = "md" }: AdaptorIconProps) {
  const adaptorIconsData = useAdaptorIcons();
  const displayName = extractAdaptorName(name) ?? null;

  if (!adaptorIconsData || !displayName) {
    return (
      <div
        className={`${sizeClasses[size]} rounded-md bg-gray-200
        flex items-center justify-center`}
      >
        <span className="text-xs font-semibold text-gray-500">
          {displayName?.[0]?.toUpperCase() || "?"}
        </span>
      </div>
    );
  }

  const iconPath = adaptorIconsData[displayName]?.square;

  if (!iconPath) {
    return (
      <div
        className={`${sizeClasses[size]} rounded-md bg-gray-200
        flex items-center justify-center`}
      >
        <span className="text-xs font-semibold text-gray-500">
          {displayName?.[0]?.toUpperCase() || "?"}
        </span>
      </div>
    );
  }

  return (
    <img
      src={iconPath}
      alt={displayName}
      className={`${sizeClasses[size]} rounded-md object-cover`}
    />
  );
}
