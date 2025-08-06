export function duration(dateStr1: string, dateStr2: string) {
  const date1 = new Date(dateStr1).getTime();
  const date2 = new Date(dateStr2).getTime();
  const diffMs = Math.abs(date2 - date1);

  if (diffMs >= 3600000) {
    return `${(diffMs / 3600000).toFixed(2)}hrs`;
  } else if (diffMs >= 60000) {
    return `${(diffMs / 60000).toFixed(2)}m`;
  } else if (diffMs >= 1000) {
    return `${(diffMs / 1000).toFixed(2)}s`;
  } else {
    return `${diffMs.toString()}ms`;
  }
}
