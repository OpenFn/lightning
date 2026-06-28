import type { Meta, StoryObj } from '@storybook/react-vite';

import {
  Breadcrumbs,
  BreadcrumbLink,
  BreadcrumbText,
} from '#/collaborative-editor/components/Breadcrumbs';

import { Showcase, Section } from '../_shared/showcase';

/**
 * `Breadcrumbs` lays out a navigation trail. It takes an array of children and
 * treats the last one as the page title; chevrons are inserted automatically
 * between the remaining crumbs. Crumbs are built from `BreadcrumbLink` (a link
 * or action) and `BreadcrumbText` (static text), each optionally prefixed with
 * a heroicon class.
 */
const meta = {
  title: 'Components/Breadcrumbs',
  component: Breadcrumbs,
  parameters: { layout: 'padded' },
  args: { children: [] },
} satisfies Meta<typeof Breadcrumbs>;

export default meta;

type Story = StoryObj<typeof meta>;

const noop = (e: React.MouseEvent) => {
  e.preventDefault();
};

export const Default: Story = {
  render: () => (
    <Breadcrumbs>
      <BreadcrumbLink icon="hero-squares-2x2" onClick={noop}>
        Projects
      </BreadcrumbLink>
      <BreadcrumbLink href="#" onClick={noop}>
        Demo Project
      </BreadcrumbLink>
      <BreadcrumbText>Daily sync workflow</BreadcrumbText>
    </Breadcrumbs>
  ),
};

export const Variants: Story = {
  render: () => (
    <Showcase>
      <Section title="Full trail">
        <Breadcrumbs>
          <BreadcrumbLink icon="hero-squares-2x2" onClick={noop}>
            Projects
          </BreadcrumbLink>
          <BreadcrumbLink href="#" onClick={noop}>
            Demo Project
          </BreadcrumbLink>
          <BreadcrumbText>Daily sync workflow</BreadcrumbText>
        </Breadcrumbs>
      </Section>
      <Section
        title="Project + title only"
        description="With a single visible crumb the title renders without a leading chevron."
      >
        <Breadcrumbs>
          <BreadcrumbLink icon="hero-squares-2x2" onClick={noop}>
            Projects
          </BreadcrumbLink>
          <BreadcrumbText>Daily sync workflow</BreadcrumbText>
        </Breadcrumbs>
      </Section>
      <Section title="With link icon">
        <Breadcrumbs>
          <BreadcrumbLink icon="hero-squares-2x2" onClick={noop}>
            Projects
          </BreadcrumbLink>
          <BreadcrumbLink href="#" onClick={noop}>
            Demo Project
          </BreadcrumbLink>
          <BreadcrumbText icon="hero-bolt">Daily sync workflow</BreadcrumbText>
        </Breadcrumbs>
      </Section>
    </Showcase>
  ),
};
