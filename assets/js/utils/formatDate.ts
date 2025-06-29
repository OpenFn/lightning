/**
 * Formats a date in a user-friendly relative format (e.g., "2 hours ago")
 * Falls back to ISO format if the date is too old or relative formatting fails
 */
export default function formatDate(date: Date): string {
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffSeconds = Math.floor(diffMs / 1000);
  
  // If date is in the future, show absolute format
  if (diffSeconds < 0) {
    return date.toISOString().replace('T', ' ').replace('Z', ' UTC');
  }
  
  // Relative time ranges matching Timex.Format.DateTime.Formatters.Relative
  if (diffSeconds < 45) {
    return diffSeconds <= 1 ? 'now' : 'a few seconds ago';
  } else if (diffSeconds < 90) {
    return 'a minute ago';
  } else if (diffSeconds < 2700) { // 45 minutes
    return `${Math.round(diffSeconds / 60).toString()} minutes ago`;
  } else if (diffSeconds < 5400) { // 90 minutes
    return 'an hour ago';
  } else if (diffSeconds < 79200) { // 22 hours
    return `${Math.round(diffSeconds / 3600).toString()} hours ago`;
  } else if (diffSeconds < 129600) { // 36 hours
    return 'a day ago';
  } else if (diffSeconds < 2160000) { // 25 days
    return `${Math.round(diffSeconds / 86400).toString()} days ago`;
  } else if (diffSeconds < 3888000) { // 45 days
    return 'a month ago';
  } else if (diffSeconds < 29808000) { // 345 days
    const months = Math.round(diffSeconds / 2592000);
    return months === 1 ? 'a month ago' : `${months.toString()} months ago`;
  } else if (diffSeconds < 47174400) { // 545 days
    return 'a year ago';
  } else {
    const years = Math.round(diffSeconds / 31536000);
    return `${years.toString()} years ago`;
  }
}

/**
 * Formats a date in absolute format for copying or detailed display
 */
export function formatDateAbsolute(date: Date): string {
  const yyyy = date.getFullYear();
  const mm = String(date.getMonth() + 1).padStart(2, '0');
  const dd = String(date.getDate()).padStart(2, '0');
  const hh = String(date.getHours()).padStart(2, '0');
  const mins = String(date.getMinutes()).padStart(2, '0');
  const secs = String(date.getSeconds()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd} ${hh}:${mins}:${secs}`;
}
