import { FooContext } from '#/react/contexts/FooContext';

export type FooProps = {
  foo: number;
  children: React.ReactNode;
};

export const Foo = ({ foo, children }: FooProps) => (
  <FooContext.Provider value={foo}>
    <p>Foo: {foo}</p>
    {children}
  </FooContext.Provider>
);
