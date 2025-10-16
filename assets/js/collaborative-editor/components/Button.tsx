import type { ReactNode } from "react";

interface ButtonProps {
  children: ReactNode;
  variant?: "primary" | "danger" | "secondary";
  disabled?: boolean;
  loading?: boolean;
  onClick?: () => void;
  type?: "button" | "submit";
  className?: string;
}

/**
 * Reusable button component with consistent styling
 * across the collaborative editor.
 *
 * @example
 * <Button variant="danger" onClick={handleDelete}>
 *   Delete
 * </Button>
 */
export function Button({
  children,
  variant = "primary",
  disabled = false,
  loading = false,
  onClick,
  type = "button",
  className = "",
}: ButtonProps) {
  const isDisabled = disabled || loading;

  // Base classes for all buttons
  const baseClasses = `
    rounded-md px-3 py-2 text-sm font-semibold shadow-xs
    focus-visible:outline-2 focus-visible:outline-offset-2
    disabled:opacity-50 disabled:cursor-not-allowed
  `;

  // Variant-specific classes
  const variantClasses = {
    primary: `
      bg-primary-600 hover:bg-primary-500 text-white
      focus-visible:outline-primary-600
      disabled:hover:bg-primary-600
    `,
    danger: `
      bg-red-600 hover:bg-red-500 text-white
      focus-visible:outline-red-600
      disabled:hover:bg-red-600
    `,
    secondary: `
      bg-white text-gray-900 shadow-xs
      inset-ring inset-ring-gray-300
      hover:inset-ring-gray-400
    `,
  };

  return (
    <button
      type={type}
      onClick={onClick}
      disabled={isDisabled}
      className={`
        ${baseClasses}
        ${variantClasses[variant]}
        ${className}
      `
        .replace(/\s+/g, " ")
        .trim()}
    >
      {children}
    </button>
  );
}
