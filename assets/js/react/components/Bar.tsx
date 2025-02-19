export type BarProps = {
  before: React.ReactNode;
  after: React.ReactNode;
  children: React.ReactNode;
};

export const Bar = ({ before, after, children }: BarProps) => (
  <>
    {before}
    <p>Bar:</p>
    {children}
    {after}
  </>
);
