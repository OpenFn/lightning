/**
 * Puts Prism in manual mode before it is ever imported.
 *
 * With `manual` unset, importing Prism schedules `highlightAll()` on load,
 * which rewrites the innerHTML of every `code[class*="language-"]` in the
 * document. react-markdown emits exactly those classes for fenced code blocks
 * in chat messages, so Prism would otherwise mutate other components' DOM
 * outside React's knowledge.
 *
 * This lives in its own module because import statements are hoisted and
 * evaluated before any code in the importing file, so setting the flag beside
 * the import would run too late. Side-effect imports evaluate in source
 * order, which is what makes importing this first work.
 */
const globalWithPrism = globalThis as {
  Prism?: { manual?: boolean };
};

globalWithPrism.Prism = { ...globalWithPrism.Prism, manual: true };

export {};
