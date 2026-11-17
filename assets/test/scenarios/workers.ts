// Which copy of the seeded data this Playwright worker uses (see global-setup.ts).
export const STATE = '/tmp/verify-lightning/state';

export const workerManifest = (n: number) =>
  n ? `${STATE}/manifest-w${n}.json` : `${STATE}/manifest.json`;

export const WORKER = Number(process.env.TEST_PARALLEL_INDEX || 0);

/** This worker's copy of a seeded email: owner@openfn.org → owner-w2@openfn.org. */
export const forWorker = (email: string) =>
  WORKER && /^[\w.]+@openfn\.org$/.test(email)
    ? email.replace('@', `-w${WORKER}@`)
    : email;
