/**
 * # Email Verification Banner
 *
 * Displays a warning banner when email verification is required but not completed.
 * Only shows when:
 * - config.require_email_verification === true
 * - user.email_confirmed === false
 *
 * Uses yellow/orange styling for warning emphasis.
 */

import { useAppConfig, useUser } from "../hooks/useSessionContext";

export function EmailVerificationBanner() {
  const user = useUser();
  const config = useAppConfig();

  // Don't show banner if conditions aren't met
  if (!config?.require_email_verification || user?.email_confirmed !== false) {
    return null;
  }

  return (
    <div className="bg-yellow-50 border-b border-yellow-200">
      <div className="mx-auto sm:px-6 lg:px-8 py-3">
        <div className="flex items-center gap-3">
          <span className="hero-exclamation-triangle h-5 w-5 text-yellow-600 flex-shrink-0" />
          <p className="text-sm text-yellow-800">
            Please verify your email address to continue using all features.{" "}
            <a
              href="/users/confirm"
              className="font-semibold underline hover:text-yellow-900"
            >
              Resend verification email
            </a>
          </p>
        </div>
      </div>
    </div>
  );
}
