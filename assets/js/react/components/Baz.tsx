export type BazProps = {
  baz: number;
  children: React.ReactNode;
};

export const Baz = ({ baz, children }: BazProps) => (
  <>
    <p>Baz: {baz}</p>
    {children}
  </>
);
