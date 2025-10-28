import type { z } from 'zod';

/**
 * Creates a TanStack Form validator function using a Zod schema.
 * This approach provides full Zod validation while maintaining TanStack Form compatibility.
 *
 * @param schema - Zod schema to use for validation
 * @returns TanStack Form compatible validator function
 */
export const createZodValidator = <T, S extends z.ZodType>(schema: S) => {
  return ({ value }: { value: T }) => {
    const result = schema.safeParse(value);
    if (!result.success) {
      // Convert Zod errors to TanStack Form format
      const formErrors: Record<string, string> = {};
      result.error.issues.forEach((issue: z.core.$ZodIssue) => {
        const path = issue.path.join('.');
        formErrors[path] = issue.message;
      });
      return { fields: formErrors };
    }
    return undefined;
  };
};
