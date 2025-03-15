export const mergeChildren = (a: React.ReactNode, b: React.ReactNode) =>
  !a ? (
    b
  ) : !b ? (
    a
  ) : (
    <>
      {a}
      {b}
    </>
  );
