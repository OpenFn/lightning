// Scenarios from annotations/shared/shared-flash-messages.md.
//
// Each takes the page, the message the host page puts, and `act`: the host's
// own action that puts it. The host owns the Given; the functions hold the
// When (by calling `act`) and the Then.
import { expect, type Locator, type Page } from '@playwright/test';

import { liveViewJoined } from '../steps';

// The toast the user sees reading `text`: announced as an alert, or as a
// status where a design marks info messages politely
export const toast = (page: Page, text: string | RegExp) =>
  page
    .getByRole('alert')
    .or(page.getByRole('status'))
    .filter({ hasText: text });

// The box the screen paints behind an element: the element itself or the
// nearest ancestor with a background. Defined inside each evaluate, which
// can't reach this module.
type PaintedBox = (el: Element) => Element;

// The hue (0-360) of the background behind an element, as the screen paints it
async function hueOf(box: Locator) {
  const [r, g, b] = await box.evaluate(el => {
    const painted: PaintedBox = e =>
      getComputedStyle(e).backgroundColor !== 'rgba(0, 0, 0, 0)' ||
      !e.parentElement
        ? e
        : painted(e.parentElement);
    const ctx = document.createElement('canvas').getContext('2d')!;
    ctx.fillStyle = getComputedStyle(painted(el)).backgroundColor;
    ctx.fillRect(0, 0, 1, 1);
    return [...ctx.getImageData(0, 0, 1, 1).data].map(v => v / 255);
  });
  const max = Math.max(r, g, b);
  const d = max - Math.min(r, g, b);
  if (d === 0) return NaN;
  const h =
    max === r
      ? ((g - b) / d) % 6
      : max === g
        ? (b - r) / d + 2
        : (r - g) / d + 4;
  return (h * 60 + 360) % 360;
}

const isBlue = (hue: number) => hue >= 190 && hue <= 250;
const isRed = (hue: number) => hue <= 15 || hue >= 345;

// Whether the toast's painted box shows the heroicon <name>. The icon is
// decorative and has no accessible name, so its class is the only thing that
// says which icon it is.
const showsIcon = (box: Locator, name: string) =>
  box.evaluate((el, name) => {
    const painted: PaintedBox = e =>
      getComputedStyle(e).backgroundColor !== 'rgba(0, 0, 0, 0)' ||
      !e.parentElement
        ? e
        : painted(e.parentElement);
    return [...painted(el).querySelectorAll(`[class*="hero-${name}"]`)].some(
      icon => icon.getBoundingClientRect().width > 0
    );
  }, name);

// @S01 An info flash appears as a toast and hides itself
//   When an action on the page puts the info flash "<text>"
//   Then I see a blue toast with a check icon reading "<text>"
//   And after about 5 seconds the toast is gone
export async function S01(page: Page, text: string, act: () => Promise<void>) {
  await act();
  const box = toast(page, text);
  await expect(box).toBeVisible();
  const shownAt = Date.now();

  expect(isBlue(await hueOf(box)), 'the toast should be blue').toBe(true);
  expect(await showsIcon(box, 'check-circle'), 'a check icon').toBe(true);
  await expect(box).toHaveText(text);
  await expect(box).toBeHidden({ timeout: 8000 });
  expect(Date.now() - shownAt).toBeGreaterThan(4000);
}

// @S02 An error flash is styled as an error
//   When an action on the page puts the error flash "<text>"
//   Then I see a red toast with an exclamation icon reading "<text>"
//   And the toast is marked as an alert
export async function S02(
  page: Page,
  text: string | RegExp,
  act: () => Promise<void>
) {
  await act();
  const box = toast(page, text);
  await expect(box).toBeVisible();

  expect(isRed(await hueOf(box)), 'the toast should be red').toBe(true);
  expect(
    await showsIcon(box, 'exclamation-circle'),
    'an exclamation icon'
  ).toBe(true);
  await expect(page.getByRole('alert').filter({ hasText: text })).toHaveText(
    text
  );
}

// @S03 Pointing at a toast keeps it on screen
//   Given I see an info toast
//   When I move the pointer over it 4 seconds after it appeared
//   Then it is still visible 4 seconds later
export async function S03(page: Page, text: string, act: () => Promise<void>) {
  await act();
  const box = toast(page, text);
  await expect(box).toBeVisible();
  const shownAt = Date.now();

  await page.waitForTimeout(4000 - (Date.now() - shownAt));
  await box.hover();
  await page.waitForTimeout(4000);

  await expect(box).toBeVisible();
}

// @S04 Clicking a toast dismisses it
//   Given I see an info toast
//   When I click it
//   Then the toast is gone
//   And it does not reappear when the page next updates
// `update` is the host's action that makes the page render again.
export async function S04(
  page: Page,
  text: string,
  act: () => Promise<void>,
  update: () => Promise<void>
) {
  await act();
  const box = toast(page, text);
  await expect(box).toBeVisible();

  await box.click();
  // Short, so the toast closing itself (5 s) can't pass for the click
  await expect(box).toBeHidden({ timeout: 1000 });

  await update();
  await expect(page.getByText(text)).toHaveCount(0);
}

// @S05 A flash carried in by a redirect shows on the page I land on
//   Given an action put the info flash "<text>" and redirected me to "<path>"
//   When "<path>" renders
//   Then I see an info toast reading "<text>"
export async function S05(
  page: Page,
  text: string,
  act: () => Promise<void>,
  path: string
) {
  await act();
  await expect.poll(() => new URL(page.url()).pathname).toBe(path);
  const box = toast(page, text);
  await expect(box).toBeVisible();
  expect(isBlue(await hueOf(box)), 'the toast should be blue').toBe(true);
}

// @S06 A Not Found or No Access flash replaces the page with a card
//   Given I was redirected to "<path>" with the nav flash "not found"
//   Then the main area shows "Not Found" and "Sorry, we can't find anything here for you."
//   And <content> is not shown
//   And the side menu is still shown
//   When I click "Back"
//   Then the browser goes back one page
// `act` is the host's visit that redirects; it starts from the page Back
// should return to.
export async function S06(
  page: Page,
  act: () => Promise<void>,
  path: string,
  content: Locator
) {
  const before = page.url();
  await act();
  await expect.poll(() => new URL(page.url()).pathname).toBe(path);

  const main = page.getByRole('main');
  await expect(main.getByText('Not Found', { exact: true })).toBeVisible();
  await expect(
    main.getByText("Sorry, we can't find anything here for you.")
  ).toBeVisible();
  await expect(content).toHaveCount(0);
  await expect(page.getByRole('navigation')).toBeVisible();

  await main.getByRole('button', { name: 'Back' }).click();
  await expect.poll(() => page.url()).toBe(before);
}

// @S07 Admin pages show a toast that stays until clicked
//   Given I am a superuser on an admin page
//   When an action on the page puts the info flash "<text>"
//   Then I see the toast "<text>"
//   When I click the toast
//   Then it is gone
export async function S07(page: Page, text: string, act: () => Promise<void>) {
  await act();
  const box = toast(page, text);
  await expect(box).toBeVisible();
  // A toast that arrives with a redirect shows before the new page answers
  // clicks; a click in that gap is lost
  await liveViewJoined(page);

  await box.click();
  // Short, so a toast closing itself can't pass for the click
  await expect(box).toBeHidden({ timeout: 1000 });
}

// @S08 Sign-in and account forms show the flash inside the form
//   Given I am on "/users/log_in"
//   When I sign in with a wrong password
//   Then I see "<text>" at the top of the form card
//   And it stays there until the page is reloaded or submitted again
// `act` is the host's own action that puts the flash; `firstField` is the
// first field of the form, which the message must sit above.
export async function S08(
  page: Page,
  text: string,
  act: () => Promise<void>,
  firstField: Locator
) {
  await act();
  const message = page.getByRole('alert').filter({ hasText: text });
  await expect(message).toBeVisible();

  const [m, f] = [await message.boundingBox(), await firstField.boundingBox()];
  expect(m!.y + m!.height, 'the message sits above the fields').toBeLessThan(
    f!.y
  );
  // A toast would have gone by now
  await page.waitForTimeout(6000);
  await expect(message).toBeVisible();
}
