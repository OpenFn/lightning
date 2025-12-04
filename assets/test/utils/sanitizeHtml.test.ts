import { describe, it, expect } from 'vitest';

import { sanitizeHtml } from '../../js/utils/sanitizeHtml';

describe('sanitizeHtml', () => {
  describe('allowed tags', () => {
    it('should allow block elements', () => {
      expect(sanitizeHtml('<p>text</p>')).toBe('<p>text</p>');
      expect(sanitizeHtml('<br>')).toBe('<br>');
      expect(sanitizeHtml('<hr>')).toBe('<hr>');
      expect(sanitizeHtml('<blockquote>quote</blockquote>')).toBe(
        '<blockquote>quote</blockquote>'
      );
      expect(sanitizeHtml('<pre>code</pre>')).toBe('<pre>code</pre>');
    });

    it('should allow all heading levels', () => {
      expect(sanitizeHtml('<h1>H1</h1>')).toBe('<h1>H1</h1>');
      expect(sanitizeHtml('<h2>H2</h2>')).toBe('<h2>H2</h2>');
      expect(sanitizeHtml('<h3>H3</h3>')).toBe('<h3>H3</h3>');
      expect(sanitizeHtml('<h4>H4</h4>')).toBe('<h4>H4</h4>');
      expect(sanitizeHtml('<h5>H5</h5>')).toBe('<h5>H5</h5>');
      expect(sanitizeHtml('<h6>H6</h6>')).toBe('<h6>H6</h6>');
    });

    it('should allow list elements', () => {
      expect(sanitizeHtml('<ul><li>item</li></ul>')).toBe(
        '<ul><li>item</li></ul>'
      );
      expect(sanitizeHtml('<ol><li>item</li></ol>')).toBe(
        '<ol><li>item</li></ol>'
      );
    });

    it('should allow inline formatting', () => {
      expect(sanitizeHtml('<strong>bold</strong>')).toBe(
        '<strong>bold</strong>'
      );
      expect(sanitizeHtml('<b>bold</b>')).toBe('<b>bold</b>');
      expect(sanitizeHtml('<em>italic</em>')).toBe('<em>italic</em>');
      expect(sanitizeHtml('<i>italic</i>')).toBe('<i>italic</i>');
      expect(sanitizeHtml('<code>code</code>')).toBe('<code>code</code>');
      expect(sanitizeHtml('<del>deleted</del>')).toBe('<del>deleted</del>');
      expect(sanitizeHtml('<s>strikethrough</s>')).toBe('<s>strikethrough</s>');
    });

    it('should allow links with href', () => {
      expect(sanitizeHtml('<a href="https://example.com">link</a>')).toBe(
        '<a href="https://example.com">link</a>'
      );
    });

    it('should allow table elements', () => {
      const table =
        '<table><thead><tr><th>Header</th></tr></thead><tbody><tr><td>Cell</td></tr></tbody></table>';
      expect(sanitizeHtml(table)).toBe(table);
    });

    it('should preserve align attribute on table cells', () => {
      // Table cells need to be in a table context to be preserved
      expect(
        sanitizeHtml('<table><tr><th align="center">Header</th></tr></table>')
      ).toBe(
        '<table><tbody><tr><th align="center">Header</th></tr></tbody></table>'
      );
      expect(
        sanitizeHtml('<table><tr><td align="right">Cell</td></tr></table>')
      ).toBe(
        '<table><tbody><tr><td align="right">Cell</td></tr></tbody></table>'
      );
    });

    it('should preserve class attribute', () => {
      expect(sanitizeHtml('<code class="language-js">code</code>')).toBe(
        '<code class="language-js">code</code>'
      );
    });
  });

  describe('XSS prevention', () => {
    it('should strip script tags', () => {
      expect(sanitizeHtml('<script>alert("xss")</script>')).toBe('');
      expect(sanitizeHtml('before<script>bad()</script>after')).toBe(
        'beforeafter'
      );
    });

    it('should strip img tags', () => {
      expect(sanitizeHtml('<img src="x" onerror="alert(1)">')).toBe('');
    });

    it('should strip iframe tags', () => {
      expect(sanitizeHtml('<iframe src="https://evil.com"></iframe>')).toBe('');
    });

    it('should strip object and embed tags', () => {
      expect(sanitizeHtml('<object data="x"></object>')).toBe('');
      expect(sanitizeHtml('<embed src="x">')).toBe('');
    });

    it('should strip event handlers', () => {
      expect(sanitizeHtml('<a href="#" onclick="alert(1)">click</a>')).toBe(
        '<a href="#">click</a>'
      );
      expect(sanitizeHtml('<p onmouseover="alert(1)">text</p>')).toBe(
        '<p>text</p>'
      );
    });

    it('should strip javascript: URLs', () => {
      const result = sanitizeHtml('<a href="javascript:alert(1)">click</a>');
      expect(result).not.toContain('javascript:');
    });

    it('should strip style attribute', () => {
      expect(sanitizeHtml('<p style="color:red">text</p>')).toBe('<p>text</p>');
    });

    it('should allow data attributes (they are not dangerous)', () => {
      // data-* attributes are safe and commonly used for JS frameworks
      expect(sanitizeHtml('<p data-foo="bar">text</p>')).toBe(
        '<p data-foo="bar">text</p>'
      );
    });

    it('should strip form elements', () => {
      expect(sanitizeHtml('<form action="/"><input type="text"></form>')).toBe(
        ''
      );
    });

    it('should handle nested dangerous content', () => {
      expect(sanitizeHtml('<div><script>bad()</script><p>safe</p></div>')).toBe(
        '<p>safe</p>'
      );
    });

    it('should handle malformed HTML safely', () => {
      // DOMPurify handles malformed HTML by parsing it first
      // The important thing is that script content is never executed
      const result1 = sanitizeHtml('<script>bad()<p>text</p>');
      expect(result1).not.toContain('<script');
      expect(result1).not.toContain('bad()');

      const result2 = sanitizeHtml(
        '<<script>script>alert(1)<</script>/script>'
      );
      expect(result2).not.toContain('<script');
    });
  });

  describe('edge cases', () => {
    it('should handle empty string', () => {
      expect(sanitizeHtml('')).toBe('');
    });

    it('should handle plain text', () => {
      expect(sanitizeHtml('just plain text')).toBe('just plain text');
    });

    it('should escape angle brackets in text', () => {
      expect(sanitizeHtml('1 < 2 and 3 > 2')).toBe('1 &lt; 2 and 3 &gt; 2');
    });

    it('should preserve safe content while stripping dangerous parts', () => {
      const input =
        '<h1>Title</h1><script>bad()</script><p>Safe <strong>content</strong></p>';
      expect(sanitizeHtml(input)).toBe(
        '<h1>Title</h1><p>Safe <strong>content</strong></p>'
      );
    });
  });
});
