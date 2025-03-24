declare module 'tiny-invariant' {
  export default function invariant(
    condition: unknown,
    message: string | (() => string)
  ): asserts condition;
}
