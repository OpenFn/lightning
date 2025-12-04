import DOMPurify, { Config as DOMPurifyConfig } from 'dompurify';

/**
 * DOMPurify configuration for sanitizing markdown HTML output.
 * Only allows safe tags/attributes that marked.js produces from standard markdown.
 */
const SANITIZE_CONFIG: DOMPurifyConfig = {
  ALLOWED_TAGS: [
    // Block elements
    'p',
    'br',
    'hr',
    'blockquote',
    'pre',
    // Headings
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    // Lists
    'ul',
    'ol',
    'li',
    // Inline formatting
    'strong',
    'b',
    'em',
    'i',
    'code',
    'del',
    's',
    // Links
    'a',
    // Tables (GFM)
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
  ],
  ALLOWED_ATTR: ['href', 'class', 'align'],
};

/**
 * Sanitizes HTML content to prevent XSS attacks.
 * Uses a strict whitelist of allowed tags and attributes suitable for markdown output.
 */
export function sanitizeHtml(html: string): string {
  return DOMPurify.sanitize(html, SANITIZE_CONFIG);
}
