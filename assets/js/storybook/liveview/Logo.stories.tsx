import type { Meta, StoryObj } from '@storybook/react-vite';

import { Showcase, Section, Row, Specimen } from '../_shared/showcase';

/**
 * React clones of `LightningWeb.Components.Common.openfn_logo/1` and
 * `openfn_logo_collapsed/1` (lib/lightning_web/live/components/common.ex).
 *
 * The SVG path data is copied verbatim from the HEEx source. Both components
 * are purely presentational; `class` and `fill` are mirrored as props with the
 * same defaults ("h-8"/"h-6" and "currentColor").
 */
function OpenfnLogo({
  className = 'h-8',
  fill = 'currentColor',
}: {
  className?: string;
  fill?: string;
}) {
  return (
    <svg
      viewBox="0 0 2185 800"
      className={className}
      fill={fill}
      aria-label="OpenFn"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g transform="translate(2093.4261,112.28066)">
        <g transform="translate(-846.97982)">
          <path
            d="M 136.21805,-92.133614 H 895.92398 V 667.57232 H 136.21805 Z"
            fillOpacity="0"
            stroke="currentColor"
            strokeWidth="40.2941"
          />
          <path
            d="m 271.68852,467.23065 h 69.5073 V 322.19209 H 472.7963 V 260.0989 H 341.19582 V 180.86058 H 476.03998 V 118.7674 H 271.68852 Z m 403.1422,0 h 66.72701 V 305.51034 c 0,-45.87482 -25.94939,-82.94538 -83.40876,-82.94538 -26.87615,0 -50.50864,8.80426 -70.43406,37.53394 h -0.92677 v -31.04659 h -63.94671 v 238.17834 h 66.72701 V 331.92311 c 0,-32.43674 16.68175,-55.60584 43.5579,-55.60584 20.85219,0 41.70438,11.58455 41.70438,45.87482 z"
            transform="scale(1.0183501,0.98198054)"
          />
          <path
            d="m 755.16541,287.71933 h 140.75856 v 0 z"
            stroke="currentColor"
            strokeWidth="0.561"
          />
        </g>
        <path
          d="m -1788.7957,292.9783 c 0,62.55657 -32.4367,118.62579 -97.3102,118.62579 -64.8735,0 -97.3102,-56.06922 -97.3102,-118.62579 0,-62.55657 32.4367,-118.62579 97.3102,-118.62579 64.8735,0 97.3102,56.06922 97.3102,118.62579 z m -266.908,0 c 0,93.60316 61.1664,180.71898 169.5978,180.71898 108.4314,0 169.5978,-87.11582 169.5978,-180.71898 0,-93.60316 -61.1664,-180.71897 -169.5978,-180.71897 -108.4314,0 -169.5978,87.11581 -169.5978,180.71897 z m 582.4715,53.75231 c 0,36.1438 -19.9254,70.43407 -58.3861,70.43407 -41.7044,0 -61.1665,-33.82689 -61.1665,-69.5073 0,-39.85085 21.3156,-71.36083 59.3129,-71.36083 39.3875,0 60.2397,32.90012 60.2397,70.43406 z m -183.9627,224.27689 h 66.727 V 434.77319 h 0.9268 c 22.2423,29.19307 44.9481,38.92409 75.5313,38.92409 68.5805,0 110.2849,-58.84951 110.2849,-125.11314 0,-66.26362 -44.9481,-126.0399 -111.2117,-126.0399 -30.5832,0 -58.3861,11.58455 -77.3848,39.85085 h -0.9267 v -33.3635 h -63.9468 z m 536.1329,-203.88808 v -18.53528 c 0,-76.92141 -50.0452,-126.0399 -121.8694,-126.0399 -71.8242,0 -121.8695,49.11849 -121.8695,126.0399 0,75.99465 50.0453,125.11314 121.8695,125.11314 56.0692,0 99.6271,-25.48601 115.8455,-74.14112 l -64.8735,-5.0972 c -9.2677,18.53528 -27.3396,28.2663 -47.7284,28.2663 -35.6804,0 -52.8255,-27.80292 -55.6058,-55.60584 z m -174.2316,-42.63114 c 3.7071,-26.87616 20.8522,-50.97202 55.6058,-50.97202 31.9734,0 49.5819,27.80292 51.8988,50.97202 z m 377.65664,142.72165 h 66.72701 V 305.48962 c 0,-45.87482 -25.94939,-82.94538 -83.40876,-82.94538 -26.87616,0 -50.50864,8.80426 -70.43409,37.53394 h -0.9267 v -31.04659 h -63.9468 v 238.17834 h 66.7271 V 331.90239 c 0,-32.43674 16.68171,-55.60584 43.55786,-55.60584 20.85219,0 41.70438,11.58455 41.70438,45.87482 z"
          transform="scale(1.0183501,0.98198055)"
        />
      </g>
    </svg>
  );
}

function OpenfnLogoCollapsed({
  className = 'h-6',
  fill = 'currentColor',
}: {
  className?: string;
  fill?: string;
}) {
  return (
    <svg
      viewBox="0 0 800 800"
      className={className}
      fill={fill}
      aria-label="Fn"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g transform="translate(-110, 120)">
        {/* Box frame */}
        <path
          d="M 136.21805,-92.133614 H 895.92398 V 667.57232 H 136.21805 Z"
          fillOpacity="0"
          stroke="currentColor"
          strokeWidth="40.2941"
        />
        {/* Fn text inside the box */}
        <path
          d="m 271.68852,467.23065 h 69.5073 V 322.19209 H 472.7963 V 260.0989 H 341.19582 V 180.86058 H 476.03998 V 118.7674 H 271.68852 Z m 403.1422,0 h 66.72701 V 305.51034 c 0,-45.87482 -25.94939,-82.94538 -83.40876,-82.94538 -26.87615,0 -50.50864,8.80426 -70.43406,37.53394 h -0.92677 v -31.04659 h -63.94671 v 238.17834 h 66.72701 V 331.92311 c 0,-32.43674 16.68175,-55.60584 43.5579,-55.60584 20.85219,0 41.70438,11.58455 41.70438,45.87482 z"
          transform="scale(1.0183501,0.98198054)"
        />
      </g>
    </svg>
  );
}

const meta = {
  title: 'LiveView Clones/Logo (LiveView Clone)',
  parameters: { layout: 'fullscreen' },
} satisfies Meta;

export default meta;

type Story = StoryObj<typeof meta>;

export const Logos: Story = {
  render: () => (
    <Showcase>
      <Section
        title="openfn_logo/1"
        description="The full OpenFn wordmark. Inherits color from `currentColor` and is sized via the `class` attribute (defaults to h-8)."
      >
        <Row className="items-center gap-8">
          <Specimen label="h-8 (default)">
            <OpenfnLogo className="h-8 text-gray-900" />
          </Specimen>
          <Specimen label="h-12">
            <OpenfnLogo className="h-12 text-primary-600" />
          </Specimen>
          <Specimen label="on dark">
            <div className="rounded-md bg-gray-900 p-4">
              <OpenfnLogo className="h-10 text-white" />
            </div>
          </Specimen>
        </Row>
      </Section>

      <Section
        title="openfn_logo_collapsed/1"
        description='The collapsed mark — just "Fn" inside the box frame — shown when the sidebar is collapsed (defaults to h-6).'
      >
        <Row className="items-center gap-8">
          <Specimen label="h-6 (default)">
            <OpenfnLogoCollapsed className="h-6 text-gray-900" />
          </Specimen>
          <Specimen label="h-10">
            <OpenfnLogoCollapsed className="h-10 text-primary-600" />
          </Specimen>
          <Specimen label="on dark">
            <div className="rounded-md bg-gray-900 p-3">
              <OpenfnLogoCollapsed className="h-8 text-white" />
            </div>
          </Specimen>
        </Row>
      </Section>
    </Showcase>
  ),
};
