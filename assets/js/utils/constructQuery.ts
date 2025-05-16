function constructQuery(payload: {
  query: string;
  filters: Record<string, string>;
}) {
  const params = new URLSearchParams({
    query: payload.query,
    ...payload.filters,
  });

  return params.toString();
}

export default constructQuery;
