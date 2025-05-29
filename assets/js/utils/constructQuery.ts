function constructQuery(data: Record<string, string | undefined>) {
  // removing undefines
  const n = Object.entries(data).filter(([_, value]) => value !== undefined);
  const obj = Object.fromEntries(n) as Record<string, string>;
  const params = new URLSearchParams(obj);

  return params.toString();
}

export default constructQuery;
