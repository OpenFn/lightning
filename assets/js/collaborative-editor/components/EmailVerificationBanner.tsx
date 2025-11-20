/**
 * # Email Verification Banner
 *
 * Displays a danger banner when email verification is required but not completed.
 * Only shows when:
 * - config.require_email_verification === true
 * - user.email_confirmed === false
 *
 * Shows a 48-hour deadline for verification calculated from user.inserted_at.
 * Uses red danger styling to match LiveView banner appearance.
 */

import { useAppConfig, useUser } from '../hooks/useSessionContext';
import { calculateDeadline, formatDeadline } from '../utils/dateFormatting';

export function EmailVerificationBanner() {
  const user = useUser();
  const config = useAppConfig();

  // Don't show banner if conditions aren't met
  if (!config?.require_email_verification || user?.email_confirmed !== false) {
    return null;
  }

  // Calculate and format the verification deadline
  const deadline = calculateDeadline(user.inserted_at);
  const formattedDeadline = formatDeadline(deadline);

  return (
    <div
      id="account-confirmation-alert"
      className="alert-danger w-full flex items-center gap-x-6 px-6 py-2.5 sm:px-3.5 sm:before:flex-1"
      data-testid="email-verification-banner"
      role="alert"
    >
      <p className="text-sm leading-6">
        <span className="hero-x-circle-solid h-5 w-5 inline-block align-middle mr-2" />{' '}
        Please confirm your account before {formattedDeadline} to continue using
        OpenFn.{' '}
        <a
          href="/users/send-confirmation-email"
          className="whitespace-nowrap font-semibold"
        >
          Resend confirmation email
          <span aria-hidden="true"> &rarr;</span>
        </a>
      </p>
      <div className="flex flex-1 justify-end"></div>
    </div>
  );
}
