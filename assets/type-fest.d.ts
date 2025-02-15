export {};

declare global {
  export namespace t {
    export type * from 'type-fest';
    import('type-fest');
  }
}
