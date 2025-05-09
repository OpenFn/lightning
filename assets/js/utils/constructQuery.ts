function constructQuery(payload: {
  query: string;
  filters: Record<string, string>;
}) {
  let output = payload.query;
  Object.entries(payload.filters).forEach(
    ([key, value]) => (output += ` ${key}:${value}`)
  );
  return output;
}

export default constructQuery;
