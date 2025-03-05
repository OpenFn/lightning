export type FooProps = {
  foo: number;
  children: React.ReactNode;
};

export const Foo = ({ foo, children }: FooProps) => (
  <>
    <p>Foo: {foo}</p>
    {children}
  </>
);
