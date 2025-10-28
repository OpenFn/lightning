import type { AnyFieldMeta } from '@tanstack/react-form';

export function ErrorMessage({ meta }: { meta: AnyFieldMeta }) {
  const firstError = meta.errors[0];
  return firstError ? (
    <p
      data-tag="error_message"
      className="mt-1 inline-flex items-center gap-x-1.5 text-xs text-danger-600"
    >
      <span className="hero-exclamation-circle size-4"></span>
      {firstError}
    </p>
  ) : null;
}
