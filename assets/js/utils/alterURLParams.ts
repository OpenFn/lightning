function alterURLParams(data: Record<string, string | undefined>) {
  const url = new URL(window.location.href);
  Object.entries(data).forEach(([key, value]) => {
    if (value === undefined) url.searchParams.delete(key);
    else url.searchParams.set(key, value);
  });
  return url;
}

export default alterURLParams;
