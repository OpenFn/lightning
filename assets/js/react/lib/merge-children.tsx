export const mergeChildren = (a: React.ReactNode, b: React.ReactNode) =>
  a == null ? (
    b
  ) : b == null ? (
    a
  ) : (
    <>
      {a}
      {b}
    </>
  );
