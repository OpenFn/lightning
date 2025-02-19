export const Baz = ({
  baz,
  children,
}: {
  baz: number;
  children: React.ReactNode;
}) => (
  <>
    <p>Baz: {baz}</p>
    {children}
  </>
);
