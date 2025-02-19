export const Bar = ({
  before,
  after,
  children,
}: {
  before: React.ReactNode;
  after: React.ReactNode;
  children: React.ReactNode;
}) => (
  <>
    {before}
    <p>Bar</p>
    {children}
    {after}
  </>
);
