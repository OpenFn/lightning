---
id: shared-hash-tabs
type: shared
title: Hash-addressed tabs
status: not-started
owner:

trigger:
  old_route: >-
    any page that renders `LightningWeb.Components.Tabbed.container` (tabbed.ex:24-98): today
    /projects/:project_id/settings (settings.html.heex:25-29, :1101) and
    /projects/:project_id/runs/:id (router.ex:297; run_live/show.ex:228-297)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the host page renders `Tabbed.container` and its LiveView socket has connected, so the `TabbedContainer` hook has mounted (tabbed.ex:37, :72; TabbedContainer.ts:13)

inherits: []                                  # the host pages bring their own scope gates (shared-project-scope)

url_params:
  - name: "#<hash> (URL fragment naming a tab)"
    set_by: >-
      the tab links themselves (tabbed.ex:132); any page, email or redirect that links to a host
      page with a fragment (listed per host: shared-project-settings-tab-chrome url_params, run-show url_params)
    effect: >-
      client-side only; on mount the hook selects the tab whose `aria-controls` is "<hash>-panel",
      falling back to the container's `default_hash` when there is no fragment (TabbedContainer.ts:27,
      :32-44, getHash :71-73). The server never receives the fragment.

config_variants:
  default: {}                                 # read under this one; nothing here depends on config or build

inventory:
  routes: []                                  # owns no route; host routes are catalogued by their views
  events: []
  js_hooks:
    - TabbedContainer                         # assets/js/hooks/TabbedContainer.ts:12-69, registered hooks/index.ts:28, :36
    - lv-keep-aria / lv-keep-class DOM patch rules as used by tabs and panels (assets/js/app.js:80-85, :101-107; tabbed.ex:120, :133, :156)
    - Tooltip on disabled tabs (tabbed.ex:117; hooks/index.ts:567)
  policies: []
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - TabbedContainer `push-hash` server event (TabbedContainer.ts:16-19); no LiveView pushes it (see 6.3)

related:
  - shared-project-settings-tab-chrome          # settings host; vertical orientation (settings.html.heex:27)
  - project-settings-setup
  - project-settings-credentials
  - project-settings-collections
  - project-settings-webhook-security
  - project-settings-collaborators
  - project-settings-security
  - project-settings-github-sync
  - project-settings-data-storage
  - project-settings-history-exports
  - run-show                                    # horizontal orientation, disabled tabs (run_live/show.ex:228-261)
flows: []
---

## 1. Purpose

Two pages put several panels behind one URL and pick the open panel from the URL fragment:
project settings (nine tabs) and the run page (Log, Input, Output). The fragment is what makes a
tab addressable, so people and other pages can link straight to a panel, and what keeps the right
panel open while the page re-renders. Without it, every link would land on the first panel and a
save would throw the user back to it mid-task.

## 2. What it does

- A host page with no fragment opens on its default tab
- A link with a fragment opens that tab
- Choosing a tab puts its name in the address bar, so a reload or a shared link reopens it
- Browser Back and Forward move between tabs already visited
- The open tab stays open while the server re-renders the page
- A disabled tab cannot be opened by clicking it

## 3. Who can do what

The component checks no role. Which tabs exist, and whether one is disabled, is decided by the
host page (shared-project-settings-tab-chrome section 3; run-show `show.ex:53`, `:240-255`).

| Action                               | Anyone who can open the host page |
|--------------------------------------|-----------------------------------|
| See the tab strip                    | yes                               |
| Open an enabled tab                  | yes                               |
| Open a disabled tab by clicking      | no                                |

**Preconditions beyond role**
- Tab selection needs JavaScript and a connected LiveView: until the hook runs, every panel carries the server-rendered `hidden` class and no tab is marked selected (`tabbed.ex:112`, `:128`, `:147`; `TabbedContainer.ts:13`, `:46-62`).

## 4. What it touches

**Reads**: `window.location.hash` only (`TabbedContainer.ts:71-73`); no database reads

**Writes**: none; the URL fragment changes through the tab's plain `href` (`tabbed.ex:132`)

**Immediate side effects** (in the same request)
- none; no server event is sent when a tab is chosen

**Deferred side effects** (later, elsewhere)
- none

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- none

## 5. Scenarios

Steps say "the host page" so the views can run them against their own tabs; settings uses default
`project`, the run page uses default `log`.

```gherkin
Feature: Hash-addressed tabs
  In order to land on, share and stay on the part of a page I need
  As anyone using a tabbed page
  I want the URL fragment to choose the open tab

  @S01 @pending
  Scenario: A page with no fragment opens on its default tab
    # Value: someone arriving from navigation sees a panel with content, not an empty page.
    Given a host page whose tab container has default tab "log"
    When I open the host page with no fragment
    Then the "Log" tab is selected
    And only the "Log" panel is visible
    # tabbed.ex:36, :71, :145-159; TabbedContainer.ts:14, :27, :32-62; run_live/show.ex:231; settings.html.heex:28

  @S02 @pending
  Scenario: A fragment in the link opens that tab
    # Value: emails, flashes and other pages that point at a specific panel put the user on it.
    Given a host page with an enabled tab "data-storage" that is not the default
    When I open the host page with fragment "#data-storage"
    Then the "Data Storage" tab is selected
    And the default tab's panel is not visible
    # TabbedContainer.ts:27, :32-62

  @S03 @pending
  Scenario: Choosing a tab names it in the address bar
    # Value: a user can bookmark or send the exact tab, and a reload keeps them on it.
    Given I am on a host page on its default tab
    When I click the "Output" tab
    Then the URL ends in "#output"
    And the "Output" panel is the only one visible
    When I reload the page
    Then the "Output" tab is still selected
    # tabbed.ex:125-136 (href "#<hash>"); TabbedContainer.ts:21-25, :27

  @S04 @pending
  Scenario: Back returns to the previous tab
    # Value: the browser's Back button undoes a tab change instead of leaving the page.
    Given I opened a host page with fragment "#credentials"
    And I then clicked the "Collaboration" tab
    When I press the browser Back button
    Then the URL ends in "#credentials"
    And the "Credentials" tab is selected
    # tabbed.ex:132; TabbedContainer.ts:21-25

  @S05 @pending
  Scenario: The open tab survives a server re-render
    # Value: validating or saving a form inside a tab, or a live update, doesn't throw the user back to the default tab.
    Given I am on a host page on a non-default tab
    When the server re-renders the page
    Then the same tab is still selected
    And the default tab's panel is still hidden
    # tabbed.ex:120, :133 (lv-keep-aria), :156 (lv-keep-class); app.js:80-85, :101-107; TabbedContainer.ts:29-31

  @S06 @pending
  Scenario: Clicking a disabled tab does nothing
    # Value: a user can't open a panel whose content the host page says isn't available yet.
    Given a host page whose "Input" tab is disabled
    And the "Log" tab is selected
    When I click the "Input" tab
    Then the URL fragment does not change
    And the "Log" tab is still selected
    # tabbed.ex:108-123 (a <span> with no href); host-specific tooltip copy is run-show S09
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A fragment that names no tab (typo, old link, or any in-page anchor) on first load selects nothing: every panel keeps its server-rendered `hidden` class. After mount, the same fragment is ignored and the current tab stays open while the URL names something else | `TabbedContainer.ts:27`, `:38-44`; `tabbed.ex:147` | on load, a tab strip with an empty body until they click a tab; already raised by shared-project-settings-tab-chrome 6.1 and run-show 6.2 for their hosts | fix |
| A fragment naming a disabled tab opens it: the disabled `<span>` still carries `aria-controls`, which is all the hook matches on | `TabbedContainer.ts:37-62`; `tabbed.ex:109-111` | the disabled tab's panel is shown and highlighted; on the run page, `#input` with no step selected shows the empty input panel (run-show 6.1). Inferred from code | fix |
| Pressing Back to the entry with no fragment leaves the last tab open: `hashchange` fires with an empty hash, and `selectTab(null)` returns without falling back to the default | `TabbedContainer.ts:21-23`, `:33-35` | the address bar shows the bare page URL while a non-default tab is still open; a reload then switches to the default tab | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Tab and panel DOM ids are `<hash>-tab` and `<hash>-panel`, not namespaced by the container id, so they share the page's id space (the run page's log panel is `#log-panel`, which `show_test.exs:96` selects on) | `tabbed.ex:110-111`, `:126-127`, `:151-152` | preserve |
| Selection is applied in `requestAnimationFrame`, a frame after mount, so the first paint shows no panel | `TabbedContainer.ts:46` | decide |
| Panels keep their client-side class across patches (`lv-keep-class`), so a host can't change a panel's `class` after mount | `tabbed.ex:156`; `app.js:80-85` | preserve |
| A tab that switches between disabled and enabled is a different element (`<span>` vs `<a>`), so it is replaced rather than patched and loses `aria-selected`; the hook's `updated` reselects it only if the fragment names it | `tabbed.ex:108-137`; `TabbedContainer.ts:29-31` | preserve |
| All panels render on every mount and tab switching only toggles a CSS class; the server never learns which tab is open | `tabbed.ex:42-57`, `:91-97`; `TabbedContainer.ts:57-62` | decide |
| Tabs carry `role="tab"` and `aria-selected` but there is no arrow-key navigation, and the disabled tab is a `<span>` with no `aria-disabled` | `tabbed.ex:109-120`, `:125-133` | decide |
| Two orientations with different spacing; settings is vertical, the run page horizontal | `tabbed.ex:24-58`, `:60-98`; `settings.html.heex:27`; `run_live/show.ex:228-232` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `push-hash` handler | `TabbedContainer.ts:16-19` | no `push_event(..., "push-hash", ...)` in `lib/` |
| `default_hash: nil` path | `tabbed.ex:6`; `TabbedContainer.ts:14` | both callers pass a default (`settings.html.heex:28`, `run_live/show.ex:231`) |

### 6.4 Performance and operational limits

none

### 6.5 Things seen but not understood

- There are no tests for `Tabbed` or `TabbedContainer`: no Vitest file under `assets/test` and no ExUnit assertion on `aria-selected` or a tab fragment. The `#log` links asserted in `run_live/components_test.exs:135-374` point at the workflow editor's own `#log`, not this component; don't cite them as coverage.
- On the run page, choosing a step patches to `?step=<id>` (`run_live/show.ex:212`), a relative URL that drops the fragment; S05 says the open tab survives the re-render, but a reload afterwards returns to the default tab. Not checked in a browser (run-show 6.5 raises the same).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- shared-project-settings-tab-chrome S01 to S04 restate S01, S02, S03 and S05 here for the settings host. Should they become one-line references to this file, as the lead's scope says, leaving that file to own only the role notices and sandbox banners?
- In the rebuild, settings tabs become routes (`/settings/<tab>`). Does the run page keep fragment tabs, and if so does this annotation survive only for it?
- Should an unknown fragment, and Back to the bare URL, fall back to the default tab (6.1)?

## Proposed flows

none. Links that land on a tab belong to the flows of the pages and emails that send them; hosts assert the landing using S02.

## Proposed shared

none
