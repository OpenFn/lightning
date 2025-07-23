export function timeSpent(dateStr1: string, dateStr2: string) {
  const date1 = new Date(dateStr1).getTime();
  const date2 = new Date(dateStr2).getTime();
  const diffMs = Math.abs(date2 - date1);
  console.log(date1, date2, diffMs);

  if (diffMs >= 3600000) {
    return `${(diffMs / 3600000).toFixed(2)}hours`;
  } else if (diffMs >= 60000) {
    return `${(diffMs / 60000).toFixed(2)}mins`;
  } else if (diffMs >= 1000) {
    return `${(diffMs / 1000).toFixed(2)}secs`;
  } else {
    return `${diffMs.toString()}ms`;
  }
}
