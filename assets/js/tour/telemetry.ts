/**
 * Fire-and-forget telemetry for the guided tour.
 *
 * Frozen contract: POST /api/tour_events with a JSON body
 * `{event, page?, element?, tab?, reason?, step_index?, steps_total?}`,
 * same-origin cookie auth, 204 response.
 *
 * Emission must never affect the tour: no throws, no retries, and callers
 * must not await.
 */

export type TourEventName =
  | 'button_shown'
  | 'button_clicked'
  | 'tour_started'
  | 'tour_completed'
  | 'tour_abandoned'
  | 'spotlight_shown'
  | 'notice_shown';

export interface TourEventFields {
  page?: string;
  element?: string;
  tab?: string;
  reason?: string;
  step_index?: number;
  steps_total?: number;
}

const TOUR_EVENTS_URL = '/api/tour_events';

function csrfToken(): string {
  return (
    document
      .querySelector("meta[name='csrf-token']")
      ?.getAttribute('content') ?? ''
  );
}

export function emitTourEvent(
  event: TourEventName,
  fields: TourEventFields = {}
): void {
  try {
    void fetch(TOUR_EVENTS_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-csrf-token': csrfToken(),
      },
      credentials: 'same-origin',
      keepalive: true,
      body: JSON.stringify({ event, ...fields }),
    }).catch(() => {
      // Telemetry is best-effort; drop failures silently.
    });
  } catch {
    // fetch unavailable or threw synchronously: ignore.
  }
}
