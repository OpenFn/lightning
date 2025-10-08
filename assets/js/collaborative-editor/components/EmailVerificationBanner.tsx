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

import { useAppConfig, useUser } from "../hooks/useSessionContext";
import { calculateDeadline, formatDeadline } from "../utils/dateFormatting";

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
      className="alert-danger"
      role="alert"
      phx-click="lv:clear-flash"
      phx-value-key="info"
    >
      <span className="hero-x-circle-solid" />
      <p>
        You must verify your email by {formattedDeadline} or your account will
        be deleted.{" "}
        <a href="/users/send-confirmation-email">
          Resend confirmation email &rarr;
        </a>
      </p>
    </div>
  );
}
