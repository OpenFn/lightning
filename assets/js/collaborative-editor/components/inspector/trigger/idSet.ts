/**
 * Order-independent equality of two id sets.
 *
 * Shared by {@link useTriggerDraft} and {@link WebhookAuthMethodSelect}, which
 * both compare auth-method id sets (draft vs. committed / incoming vs. local
 * rows) where ordering is irrelevant.
 */
export function sameIdSet(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const setB = new Set(b);
  return a.every(id => setB.has(id));
}
