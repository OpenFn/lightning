export const Foo = ({
  foo,
  children,
}: {
  foo: number;
  children: React.ReactNode;
}) => (
  <>
    <p>Foo: {foo}</p>
    {children}
  </>
);
