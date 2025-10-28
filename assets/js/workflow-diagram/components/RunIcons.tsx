import { cn } from "../../utils/cn";

const STATE_ICONS = {
  pending: "hero-ellipsis-horizontal-circle-solid",
  success: "hero-check-circle-solid",
  fail: "hero-x-circle-solid",
  crash: "hero-x-circle-solid",
  cancel: "hero-no-symbol-solid",
  shield: "hero-shield-exclamation-solid",
  clock: "hero-clock-solid",
  circle_ex: "hero-exclamation-circle-solid",
  triangle_ex: "hero-exclamation-triangle-solid",
};

const STATE_COLORS = {
  pending: "text-gray-400",
  success: "text-green-500",
  fail: "text-red-500",
  crash: "text-orange-800",
  cancel: "text-grey-600",
  shield: "text-yellow-800",
  clock: "text-yellow-800",
  circle_ex: "text-yellow-800",
  triangle_ex: "text-black-800",
};

export const renderIcon = (
  type: keyof typeof STATE_COLORS,
  options: Partial<{ tooltip: string; size: number }> = {}
) => {
  const { tooltip, size = 8 } = options;
  const bgSize = size - 2;
  if (!(type in STATE_COLORS)) {
    console.error("ERROR: Unknown run state:", type);
    // what do we do here?
    type = "success";
  }
  return (
    <div className="relative">
      {/* Draw a solid background behind the icon with a white fill */}
      <div
        className={`absolute inset-0 bg-white rounded-full ml-1 mt-1 w-${bgSize} h-${bgSize}`}
      ></div>
      {/* Render the icon itself */}
      <div
        className={cn(
          `relative flex justify-center items-center w-${size} h-${size} rounded-full`,
          STATE_COLORS[type]
        )}
      >
        <span
          data-tooltip={tooltip}
          data-tooltip-placement="top"
          className={cn(STATE_ICONS[type], "w-full h-full")}
        ></span>
      </div>
    </div>
  );
};
