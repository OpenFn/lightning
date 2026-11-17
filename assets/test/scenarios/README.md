# Scenario tests

Playwright tests for the behaviour annotations in `annotations/`. Each
annotation (a page, a shared part or a flow) has scenarios with ids (`@S01`,
`@S02`, ...); each test here is named after the scenario it checks. They test
today's Lightning, end to end, against a running instance.

- `STATUS.md`: what passed, failed or has no test on the last run, and the
  Lightning commit it ran against. Generated; don't edit.
- `<annotation>.spec.ts`: the tests for one annotation. `steps.ts`, `pages/` and
  `shared/` hold the steps and page objects they share.
- `annotations/TEMPLATE.md`: the annotation format.

## Run them

Needs Postgres running and the app bootstrapped (`./bin/bootstrap`). From the
repo root:

```sh
assets/test/scenarios/start      # e2e Lightning on :4003, seeded; a few minutes the first time
cd assets
./test/scenarios/run             # all tests, then writes STATUS.md
./test/scenarios/run channels-index.spec.ts   # one file (or file:line, --grep); leaves STATUS.md alone
cd .. && bin/e2e stop
```

Tests run in parallel, each worker with its own seeded users and projects. Tests
tagged `@serial` change instance-wide state and run afterwards, alone.

## Keep them in step with Lightning

- `npm run check:annotations` (in `assets/`) lists every annotation scenario
  without a test, and every test whose id has no scenario.
- When Lightning changes: update the scenarios of the annotations it affects
  (keep ids, add new ones with the next free id), update their tests, then run
  and commit the new `STATUS.md`.
- A page test that also covers a shared scenario says so with
  `// covers shared-x@S01 with @S05`.
