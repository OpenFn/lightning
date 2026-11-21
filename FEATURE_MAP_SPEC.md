# Feature Map Spec

## Overview
This feature map is a maintained overview of OpenFn’s functionality. It makes it easier to:
- Build automated tests of both front-end and API
- Check coverage of key edge cases
- Compare test results conducted using very different methodologies
- Generate and validate documentation
- Automatically generate RFPs

## Structure
The feature map organises information in a way designed to provide a mutually-exclusive, comprehensively exhaustive (MECE) overview of lightning’s functionality. However it is most decidedly a map, not the territory (see: Borges, “On Exactitude in Science.”). Every word of unnecessary detail creates additional risk.
- areas: the highest-level breakdown of functionality, for example “Editing Workflows” or “Managing Users.”
    - entities: a list of entities (drawn from list of API endpoints) that are involved in this area
    - stories: these are statements of capabilities that users should have using the product (ie “user can...”). These will often start as the product of database entity list x CRUD (eg “create a sandbox”), but then will extend to more complex or higher-order goals (eg “triage most common failure modes of work orders”).
        - scenarios: these are different cases where behaviour diverges. You can think of them as columns in a test matrix (ie “Given...” clauses in a gherkin spec). The default is that a story has no scenarios. Capture only the diverging cases (eg “user is a project viewer” / “user is a project editor”). Give each scenario on a story a short note saying how the story’s behaviour diverges (e.g. “Refused”, “Not offered”, “Changes stay with the sandbox”). Scenarios should be standardised across areas/stories wherever possible. Only create new scenario when unique.
        - requirements: these are essential details of what success looks like (eg “failure modes should have a clear count”). There is a long tail of requirements. Only most essential should be documented.

### Additional Detail
- Stories should have a single key capability each. For example,  “User can filter and search history, and share that view as a link” should push detail of sharing a view as either separate or put within a requirement, depending on how essential the detail is. In contrast “Editor can create, change, switch off and delete a channel” is too long, because those are totally different key flows. If it could pass while the other half fails, split it.
- Stories split by capability. The screen it’s done on becomes a requirement. For example, inspect a run in the editor and seeing a run history thing are the same story. The pages must go as requirements, else the feature smoke test might check one and fail the other.
- Versioning. The feature map should have a version number where things are introduced. minimum rule: if in lightning already (as of Nov 2026), say “v2.x.” else say “v3.x.” Don't note experimental feature tags. If it's in the lightning codebase it gets a version.
- Name the lowest role allowed as the actor (“Admin can…”). Lower roles are refused by implication, so don’t list them. List a role scenario only when the actor is not a project role (e.g. superuser, support user, credential owner) or when the refusal would surprise a reader (e.g. an owner being refused).
- Count side effects on other records as essential requirements.
- Every story gets an id of the form AREA-NN, where AREA is a short word from the app (e.g. COLLAB, SANDBOX). Ids may be renumbered until the first test report uses them; after that they are fixed, and a removed story is marked retired rather than deleted.
- Out of scope: which surface a story is done on (app or API), usage limits and plans.
- On Details: Status codes, timeouts, config flags, enum lists, screen layouts and route paths never belong here. In a verification pass, when a detail turns out to be wrong, consider deleting it rather than make it more precise. A smaller map that is correct beats a precise one that drifts.

## Usage

- Updating: The map will be updated with all new feature work.
- Front-end testing: this map should be sufficient for agents to go forth and conduct smoke testing of the user experience (and vice versa, feed back so that key UI cases are tracked here and fed into back-end testing).
- Back-end testing: this map should be sufficient for agents to verify that the backend correctly handles scenarios (and vice versa, feed back so that key cases are tracked here and fed into front-end testing).
- Reporting: Test reports will use this structure as the foundational building block of reporting. For example it might display a heading per section, and then a table with rows per story, columns for scenario, and red/amber/green emojis to describe status.
