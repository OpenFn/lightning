# Component analysis

A working classification of the UI represented in Storybook, to help us decide
which components are **key**. Every component is sorted into one of three
buckets:

- **Core** - highly reusable primitives. This set alone should be enough to
  build most screens.
- **Useful** - earning their keep in the app and worth keeping, but tied to a
  feature/domain and not broadly reusable.
- **Redundant** - duplicates another component; should be merged.

Composites (`Pages/*`, `Editor/Canvas`, `Editor/IDE`) and design tokens
(`Foundations/*`) are not classified: they are assemblies/tokens, not
components. They are tagged `composite` / `foundation` in Storybook for
filtering.

> This is a proposal to react to, not a verdict. Classifications and merge
> calls are judgement; please sanity-check with the component owners before
> acting on the redundant list.

## Headline finding

The biggest source of redundancy is that **two parallel design systems**
coexist: the server-rendered HEEx set (`new_inputs.ex`, `pills.ex`, `table.ex`,
`modal.ex`, `core_components.ex`) and the React set in
`collaborative-editor/components/`. Button, Tabs, Tooltip, Badge, Toggle,
Modal, and form inputs each exist in **both**. The Core picks below choose one
canonical version per concept; the duplicate is listed as Redundant. Long term
the highest-leverage move is a single documented class contract shared by both
worlds (one set of Tailwind classes, rendered from either HEEx or React).

---

## Stack ranking (with cut lines)

Ranked most-key first. Two cut lines separate the buckets.

| #  | Component | Bucket |
| -- | --------- | ------ |
| 1  | Button (themed) | Core |
| 2  | Form Inputs (text/select/textarea/checkbox) | Core |
| 3  | Table primitives (table/tr/th/td + empty state) | Core |
| 4  | Pills / tags | Core |
| 5  | Modal | Core |
| 6  | Tabs | Core |
| 7  | Tooltip | Core |
| 8  | Flash / toast | Core |
| 9  | Alert (inline) | Core |
| 10 | Dropdown | Core |
| 11 | Badge | Core |
| 12 | Spinner | Core |
| 13 | Toggle | Core |
| ═══ | **CORE ▲  /  USEFUL ▼** | ═══ |
| 14 | Data Tables (credentials/oauth/collections/collaborators) | Useful |
| 15 | Admin Tables (users/projects) | Useful |
| 16 | Sidebar | Useful |
| 17 | Navigation (breadcrumbs/menus/section header) | Useful |
| 18 | Layout (header/centered/avatar/footer) | Useful |
| 19 | State Pill | Useful |
| 20 | Step Icon | Useful |
| 21 | Tabbed Selector (tab + panel container) | Useful |
| 22 | Dashboard cards (workflow/metric/state cards) | Useful |
| 23 | Banners (workflow info / deprecated / sandbox) | Useful |
| 24 | Viewers (log / dataclip) | Useful |
| 25 | Run Components (step list / detail list) | Useful |
| 26 | Dataclip Type Pill | Useful |
| 27 | Trigger Type Badge | Useful |
| 28 | Adaptor Icon | Useful |
| 29 | Run Retry Button | Useful |
| 30 | Elapsed Indicator | Useful |
| 31 | Log Level Filter | Useful |
| 32 | Run Skeleton | Useful |
| 33 | Shortcut Keys | Useful |
| 34 | Chips (version / beta / snapshot) | Useful |
| 35 | Input Variants (password / radio / tag) | Useful |
| 36 | OAuth (scopes / status) | Useful |
| 37 | GitHub connect | Useful |
| 38 | Sandbox (workspace list / merge / palette) | Useful |
| 39 | Channel Request (badges / headers) | Useful |
| 40 | Diagram: Shape | Useful |
| 41 | Diagram: Nodes (job/trigger/placeholder) | Useful |
| 42 | Diagram: Icons (run/trigger) | Useful |
| 43 | Diagram: Path Button | Useful |
| 44 | Diagram: MiniMap Node | Useful |
| 45 | Diagram: Error Message | Useful |
| 46 | Disclaimer Screen | Useful |
| 47 | Sandbox Indicator Banner | Useful |
| 48 | Collaborative Editor Promo Banner | Useful |
| 49 | Metadata Explorer Empty | Useful |
| 50 | Utilities (link / table-action / gradients) | Useful |
| 51 | Logo | Useful |
| ═══ | **USEFUL ▲  /  REDUNDANT ▼** | ═══ |
| 52 | Legacy Form fields (`form.ex`) | Redundant → Form Inputs |
| 53 | Confirm Modals (4 deletion dialogs) | Redundant → Modal + one ConfirmDialog |
| 54 | Icon Set (`icon.ex` hand SVGs) | Redundant → Heroicons |
| 55 | Loaders (button_loader / text_ping) | Redundant → Spinner + Button loading |
| 56 | Tab Bar (`pill_tabs`) | Redundant → Tabs (pills) |
| 57 | Switch | Redundant → Toggle |
| 58 | Run Badge | Redundant → State Pill |
| 59 | Loading Indicator | Redundant → Spinner |
| 60 | Tabs (Responsive) | Redundant → Tabs (responsive option) |

---

## Core (13)

The minimum set to build most screens. Notes = how to make each more reusable.

| Component | Story | How to make it more reusable |
| --------- | ----- | ---------------------------- |
| **Button** | `LiveView Clones/Button` | Single source of truth shared by HEEx + React (today there are two). Add a left/right icon slot and a built-in `loading` state so `button_loader` and ad-hoc icon buttons collapse into it. Expose `size` consistently everywhere. |
| **Form Inputs** | `LiveView Clones/Form Inputs` | Standardise the field wrapper (label + sublabel + error + tooltip) as one component and compose every input type through it. Document the error/disabled contract once. Retire `form.ex` in its favour. |
| **Table** | `LiveView Clones/Table` | Already composable (tr/th/td). Make the sort header and empty state first-class sub-components and provide a thin `columns`-driven wrapper so the 8 domain tables stop re-declaring `<thead>`. |
| **Pills** | `LiveView Clones/Pills` | Promote to the one base pill: a `color` + `size` + optional leading icon + dismissible affordance. Most other badges/pills should be thin wrappers over this. |
| **Modal** | `LiveView Clones/Modal` | Generic shell is good. Add a `ConfirmDialog` preset (title/body/confirm/cancel/variant) so the deletion modals stop hand-rolling. Parameterise width and footer layout. |
| **Tabs** | `Components/Tabs` | The React `Tabs` (pills + underline variants) should be the one tab system. Fold in the responsive behaviour as an option and replace `tab_bar.ex`/`tabbed.ex` usages. |
| **Tooltip** | `Components/Tooltip` | Radix-based and solid. Make it the only tooltip (retire the tippy `phx-hook` path) and expose `side`/`delay`/rich-content props as the public API. |
| **Flash** | `LiveView Clones/Flash` | Generalise kinds beyond info/error (add warning/success) and drive position/auto-dismiss via props so it is a reusable toast, not a fixed bottom bar. |
| **Alert** | `LiveView Clones/Alerts` | Already variant-driven. Make `banner` a layout option of `alert` (it already shares the theme) rather than a separate concept. |
| **Dropdown** | `LiveView Clones/Dropdown` | Keep the trigger + menu split; expose items as a slot/array and reuse for the user menu, table row actions and the "Actions" buttons that currently re-implement it. |
| **Badge** | `Components/Badge` | Pick one of Badge/Pill as the base and express the other as a preset; today they overlap heavily. Add semantic `variant`s (default/info/success/warning/danger). |
| **Spinner** | `Components/Spinner` | Make it the single loading primitive (size + label). `LoadingIndicator`, `button_loader` and the ping loaders should all route through it. |
| **Toggle** | `Components/Toggle` | One switch component with `checked`/`disabled`/`label`. Absorb `inputs/Switch`, the HEEx `toggle` and `integer-toggle` so there is a single accessible switch. |

## Useful (38)

Worth keeping; tied to a feature. Notes = the smallest change that would lift
them toward reusable.

| Component | Story | Note |
| --------- | ----- | ---- |
| Data Tables | `LiveView Clones/Data Tables` | Generic once Table grows a `columns` API; today each repeats header markup. |
| Admin Tables | `LiveView Clones/Admin Tables` | Same: share the sort-header + filter-input shell with Data Tables. |
| Sidebar | `LiveView Clones/Sidebar` | App-specific, but the `menu-item` + collapse behaviour could be a reusable nav primitive. |
| Navigation | `LiveView Clones/Navigation` | Breadcrumbs and section-header are the reusable bits; extract them from the menu specifics. |
| Layout | `LiveView Clones/Layout` | `user_avatar` and `header` are reusable; the rest is shell. |
| State Pill | `Components/State Pill` | Reusable if it sits on the base Pill with a state→color map passed in. |
| Step Icon | `Components/Step Icon` | Reusable status-icon if the reason→icon/color map is a prop, not hard-coded. |
| Tabbed Selector | `LiveView Clones/Tabbed Selector` | Merge candidate with Tabs; keep only if the tab+panel container earns its place. |
| Dashboard cards | `LiveView Clones/Dashboard` | `metric_card`/`state_card` could generalise to a small `StatCard`. |
| Banners | `LiveView Clones/Banners` | All are `alert` instances; keep as content, not new components. |
| Viewers | `LiveView Clones/Viewers` | Log/dataclip viewers are domain-specific; the code panel chrome is reusable. |
| Run Components | `LiveView Clones/Run Components` | `detail_list`/`list_item` are near-generic description lists. |
| Dataclip Type Pill | `Components/Dataclip Type Pill` | Wrapper over base Pill with a type→color map. |
| Trigger Type Badge | `Components/Trigger Type Badge` | Wrapper over base Pill/Badge. |
| Adaptor Icon | `Components/Adaptor Icon` | Reusable; document the manifest/fallback contract. |
| Run Retry Button | `Components/Run Retry Button` | Composes Button + dropdown; keep as a domain button. |
| Elapsed Indicator | `Components/Elapsed Indicator` | Reusable "live duration" if the ticker is decoupled from run state. |
| Log Level Filter | `Components/Log Level Filter` | A segmented control; could generalise. |
| Run Skeleton | `Components/Run Skeleton` | Skeleton blocks are reusable; extract a `Skeleton` primitive. |
| Shortcut Keys | `Components/Shortcut Keys` | Already small and reusable; promote to Core if used more widely. |
| Chips | `LiveView Clones/Chips` | Version/beta/snapshot chips are content over the base Pill. |
| Input Variants | `LiveView Clones/Input Variants` | password/radio/tag are real input types; `button_link` overlaps Button. |
| OAuth | `LiveView Clones/OAuth` | Feature-specific. |
| GitHub | `LiveView Clones/GitHub` | Feature-specific; the connect link is a Button preset. |
| Sandbox | `LiveView Clones/Sandbox` | Feature-specific; color palette could be a reusable swatch picker. |
| Channel Request | `LiveView Clones/Channel Request` | Status/method badges should sit on the base Pill. |
| Diagram: Shape | `Editor/Diagram/Shape` | Editor primitive; reusable within the diagram only. |
| Diagram: Nodes | `Editor/Diagram/Nodes` | Editor-specific node renderers. |
| Diagram: Icons | `Editor/Diagram/Icons` | Editor-specific. |
| Diagram: Path Button | `Editor/Diagram/PathButton` | Editor-specific. |
| Diagram: MiniMap Node | `Editor/Diagram/MiniMapNode` | Editor-specific. |
| Diagram: Error Message | `Editor/Diagram/ErrorMessage` | Generic inline error; could route through Alert. |
| Disclaimer Screen | `Components/Disclaimer Screen` | Feature-specific gate screen. |
| Sandbox Indicator Banner | `Components/Sandbox Indicator Banner` | An `alert` instance. |
| Collaborative Editor Promo Banner | `Components/Collaborative Editor Promo Banner` | An `alert`/callout instance. |
| Metadata Explorer Empty | `Components/Metadata Explorer Empty` | An empty-state instance; route through a shared `EmptyState`. |
| Utilities | `LiveView Clones/Utilities` | CSS utility classes; foundational, keep documented. |
| Logo | `LiveView Clones/Logo` | Brand asset. |

## Redundant (9)

| Component | Story | Merge into | Why |
| --------- | ----- | ---------- | --- |
| Legacy Form fields | `LiveView Clones/Legacy Form` | Form Inputs (`new_inputs.ex`) | `form.ex` predates `new_inputs.ex`; same fields, older styling. Migrate call sites and delete. |
| Confirm Modals | `LiveView Clones/Confirm Modals` | Modal + one `ConfirmDialog` | The 4 deletion modals are the same dialog with different copy. Replace with one preset (the React `AlertDialog` already does this). |
| Icon Set | `LiveView Clones/Icon Set` | Heroicons | `icon.ex` already documents that it is migrating to Heroicons; the hand-drawn SVGs are leftovers. |
| Loaders | `LiveView Clones/Loaders` | Spinner + Button `loading` | `button_loader` is a Button with a spinner; `text_ping_loader` is a Spinner+label. Consolidate. |
| Tab Bar | `LiveView Clones/Tab Bar` | Tabs (pills variant) | `pill_tabs` docstring literally says it matches the React `Tabs`; it should be that. |
| Switch | `Components/Switch` | Toggle | Two switch components with the same behaviour. |
| Run Badge | `Components/Run Badge` | State Pill | Both render a run state as a colored pill. |
| Loading Indicator | `Components/Loading Indicator` | Spinner | Duplicate loading primitive. |
| Tabs (Responsive) | `Components/Tabs (Responsive)` | Tabs | Responsiveness should be an option on the one Tabs, not a separate component. |

---

## Storybook tags

Each story is tagged with its bucket so the catalogue is filterable:

- `core`, `useful`, `redundant` - the classification above.
- `composite` - `Pages/*`, `Editor/Canvas`, `Editor/IDE` (assemblies).
- `foundation` - `Foundations/*` (tokens).

In Storybook, use the tag filter in the sidebar (or the `tags` toolbar) to show
just the core set, or to review merge candidates. See
https://storybook.js.org/docs/writing-stories/tags.
