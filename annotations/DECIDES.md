# Section 6 items at `decide`

Every row in section 6.1 to 6.4 whose disposition is `decide`, grouped by annotation. Each blocks that annotation from `migrated`. Generated from the annotation files; regenerate rather than edit by hand. Total: 990.

## Views

### [admin-audit](views/admin-audit.md) (8)

- 6.2: No filtering or search of any kind; `list_all(params)` passes the URL params straight to Scrivener, which reads only `page` and `page_size`
- 6.2: Ordering is by `inserted_at` only, stored at second precision; events written in the same transaction (a credential `created` and its `added_to_project`) have no stable relative order
- 6.2: Subject shows only the item type and an 8-character id, with no name and no link; two subjects share the type "project" (`projects/audit.ex:7`, `version_control/audit.ex:7`)
- 6.2: The page does not subscribe to anything; new events appear only after a reload or a pagination patch re-runs the query
- 6.2: Credential environment bodies are shown as Base64 of the Cloak ciphertext; the values are useless on screen but put every credential body's ciphertext in the page HTML
- 6.2: The `actor_type` column was added with default `"user"`; rows written before it by a non-user actor would read as "(User deleted)"
- 6.4: No index on `audit_events.inserted_at` (only the primary key and `item_id`); every page sorts the whole table and Scrivener also counts it, joining three tables
- 6.4: No retention for `audit_events`: nothing deletes rows except the dev reset helper; workflow `snapshot_created` is written on every save

### [admin-auth-providers](views/admin-auth-providers.md) (9)

- 6.2: Save does not require a passing Test; the form's URL check accepts `http://`, so a plaintext discovery URL can be saved and then fails every sign-in under `default`
- 6.2: Test checks only that the discovery document fetches, parses and names authorization and token endpoints; the client ID and secret are never checked against the provider
- 6.2: The discovery fetch ignores the HTTP status, so a 404 or 500 with a JSON body passes Test
- 6.2: Remove has no confirmation, although its copy says it "disables external authentication for Lightning"
- 6.2: /settings/authentication/new renders an empty form even when a provider exists (also shared-admin-space 6.2)
- 6.2: Changing the name silently changes the redirect URI the provider must accept; only the preview shows it
- 6.2: The client secret is stored in plaintext in `auth_providers.client_secret`, unlike project credentials
- 6.2: No audit event for creating, editing, removing the provider or turning on "trust unverified emails"
- 6.4: Test fetches the discovery document inside the LiveView process with HTTPoison default timeouts and no loading state on the button (no `phx-disable-with`)

### [admin-collections](views/admin-collections.md) (18)

- 6.1: Moving a collection (S09) calls no `CollectionHook`; the source project is never credited and the target never checked
- 6.2: Superuser writes bypass every project-level gate: membership, the project's MFA requirement and scheduled deletion; a superuser without MFA can rename, move or delete collections of an MFA-required project
- 6.2: Create, rename, move and delete write no audit event, so cross-project superuser changes leave no trace
- 6.2: The project picker lists every project, including sandboxes and projects scheduled for deletion, by name only; projects with the same name can't be told apart
- 6.2: The create form has no blank project option, so the first project alphabetically is preselected
- 6.2: The name field's value is bound to the derived name, so once it loses focus the typed text ("New Collection") is replaced by the slug ("new-collection"); the project tab keeps what was typed
- 6.2: No preview and no download on this page; both exist on the project tab (project-settings-collections S13 to S15, S19)
- 6.2: Every save, limit refusal and form close (X or Cancel) ends in `push_navigate`, remounting the page and resetting sort; Escape or a click outside only hides the modal and keeps typed text for next time
- 6.2: Switching sort column always starts ascending; ties have no secondary order; sort state is not in the URL; the Project column is not sortable
- 6.2: Flash copy differs from the project tab: "Collection created successfully" and "Collection updated successfully" here, "Collection created" and "Collection updated" there
- 6.2: Modal titles are title case ("Create Collection", "Edit Collection") while the page uses sentence case
- 6.2: Delete copy renders "the collection patients ?" with a space before the question mark and tells the user to "click on the delete button" (same as the project tab)
- 6.2: Empty-state copy "No collection found." and "Create a new one." differs from the project tab's "No collections found."
- 6.2: Name hint reads "This collection will be named x."; the project tab reads "Your collection will be named x."
- 6.2: Delete is a plain confirm (no typed name) that removes every record and cannot be undone
- 6.2: The project cell is plain text, not a link to the project
- 6.2: Markup oddities: the empty-state button id is spelled "buttton"; the delete modal's close button carries a `variant` attribute that a raw `<button>` ignores; the create button sets `role="button"` on a button
- 6.4: The list holds every collection on the instance, unpaginated

### [admin-live-dashboard](views/admin-live-dashboard.md) (7)

- 6.2: The request logger plug runs on every request to the endpoint, before routing and auth, including `/i/*` webhooks and the APIs; a valid `?request_logger=` link streams that request's logs to the superuser's tab whoever opens it, so a superuser can capture another user's or an anonymous caller's request logs
- 6.2: The request logger is on because the library enables it by default; Lightning never passes `request_logger:`
- 6.2: The dashboard runs in the library's own live_session `:live_dashboard` with its own root layout: no Lightning sidebar, menu, flash, banners or Back link
- 6.2: HTTP refusal shows the "No Access" card without Back (`:no_access_no_back`); a socket refusal by the hook shows it with Back. Recorded by shared-admin-space 6.2
- 6.2: The home page shows "Dashboard" and the LiveDashboard version, not Lightning's name and version, because `home_app` is not passed
- 6.2: "Sys Info" uses a warning triangle icon for a monitoring page; owned by shared-project-header S17
- 6.4: Ecto stats runs catalogue and statistics queries against the production database on every page refresh

### [admin-maintenance](views/admin-maintenance.md) (7)

- 6.2: Error flashes interpolate `inspect(reason)`, so admins see raw Elixir terms such as `:unavailable` or `{:refresh_failed, ...}`
- 6.2: The completion flash copy uses an em dash and counts rows with no upstream icon, and rows answered 304, as "unchanged"
- 6.2: Neither "Run" button is disabled or shows progress while work runs; repeated icon clicks each start a new Scheduler task that refetches every icon (icon refreshes are not coalesced, unlike registry refreshes)
- 6.2: Card titles use title case ("Refresh Adaptor Registry", "Refresh Adaptor Icons")
- 6.2: The page checks the policy itself rather than using `:ensure_admin`, and refuses with `push_navigate`; recorded on shared-admin-space 6.2
- 6.2: The registry refresh only refetches adaptors whose version changed or whose schema is missing within the grace window; it is not a forced refetch, though the copy says "Re-fetch"
- 6.2: An icon update bumps `updated_at`, which restarts the 1 hour schema grace window for a row still missing its schema

### [admin-projects](views/admin-projects.md) (15)

- 6.1: A project scheduled for deletion can still be edited here; a member added to it gets "You now have access to ..." while shared-project-scope S04 refuses them
- 6.1: Adding a disabled account or one scheduled for deletion is allowed: the form lists every user row, and the access email is sent to them
- 6.2: Creating a project writes no audit event for the project or its initial members, while editing members does
- 6.2: Description is listed, filtered and sorted on, but the form has no description field
- 6.2: Removing a member here has no confirmation and no warning that their credentials leave the project, unlike project-settings-collaborators
- 6.2: Removal goes through `cast_assoc` delete, not `Projects.delete_project_user!/2`, so its refusal to remove a parent-project admin from a sandbox does not apply here (the owner case is covered by S06)
- 6.2: Sandboxes are listed with root projects, under their bare name, with no parent shown; "Delete" on a sandbox takes the root path (flow-schedule-project-deletion 6.2)
- 6.2: Root project names are not unique (the unique index covers children only), so two root projects can share a name
- 6.2: The name input's value is the derived slug (`value={f[:name].value}`), so after a re-render the field shows "malawi-hiv" rather than what was typed
- 6.2: Cancel deletion has no confirmation, writes no audit event and does not re-enable the triggers scheduling disabled (flow-schedule-project-deletion 6.2)
- 6.2: The list does not subscribe to anything; changes by another superuser or by owners show only after a reload or a patch
- 6.2: Dates are `%d %b %H:%M` (double space, no year, UTC with no zone) for both created and scheduled deletion
- 6.2: The admin menu and global picker on /edit and /delete (active item, picker marking the edited project) are recorded on shared-admin-space 6.1 and 6.2
- 6.4: No pagination: every list render, filter keystroke and sort re-reads all projects with all members and users, then filters and sorts in memory
- 6.4: The edit and new form lists every user on the instance with five radios each, and every change re-casts the whole member set

### [admin-user-edit](views/admin-user-edit.md) (15)

- 6.1: A superuser can demote or disable themselves, or change their own email, password or support access here; their own tab is disconnected before `push_navigate` returns (flow-account-revocation-teardown 6.1 row 3)
- 6.2: Live validation always uses `User.changeset/2`, which does not cast `support_user`, `disabled` or `scheduled_deletion`; save on edit uses `details_changeset/2`. A malformed "Scheduled Deletion" value shows no error and leaves "Save" enabled until it is submitted
- 6.2: "Scheduled Deletion" is a free text input for a UTC datetime, with no format hint; a date set here revokes every token and blocks login like a deletion, but sends no deletion email and does not disable the account (flow-account-revocation-teardown 6.2)
- 6.2: An admin email change keeps `confirmed_at`, so the account stays confirmed at an address nobody verified; nothing is sent to the old or new address
- 6.2: An admin email change does not delete pending `change:<old email>` tokens (flow-change-email-confirm 6.1 row 1)
- 6.2: A superuser-set password is never told to the account owner; they are only signed out, and the superuser knows the password
- 6.2: Granting superuser signs the promoted person out, because any role change revokes sessions
- 6.2: Saving as a superuser silently clears a stored scheduled deletion, so promoting a scheduled user cancels the deletion without the "Cancel deletion" flash or the re-enable
- 6.2: An unknown or malformed id on /settings/users/:id raises in `get_user!` instead of showing "Not Found"
- 6.2: "Save" and "Cancel" go from the `:settings` live_session to `/settings/users` in `:services`, so each is a full page load
- 6.2: The confirmation token is inserted with `Repo.insert!` after the create transaction, so a failure there raises after the account exists
- 6.2: Labels are title case ("First Name", "Last Name", "Support User", "Scheduled Deletion", "Heads Up!", "New User", "Edit User")
- 6.2: The module doc says it edits "a single job" with `JobLive.BigFormComponent`
- 6.4: Every `validate` event with a password present runs bcrypt: `maybe_hash_password` hashes on each change once the password is valid, and on edit `keep_current_password` also verifies it
- 6.4: The confirmation email is sent inline before the redirect

### [admin-users](views/admin-users.md) (16)

- 6.1: Cancel re-enables the account unconditionally; whether it was disabled for another reason before deletion was scheduled is not kept anywhere
- 6.2: The list is loaded once when the table component mounts and never refreshed; other superusers' edits, deletions and the nightly purge show only after navigation
- 6.2: `/settings/users` is in the `:services` live_session and `/settings/users/:id/delete` in `:settings`; "Delete", "Delete now" and closing the dialog each cross sessions and do a full page load
- 6.2: Filter and sort live only in component assigns: not in the URL, lost on reload, on opening the dialog and on the navigation after cancel
- 6.2: Sorting compares raw strings, so it is case-sensitive ("alice" sorts after "Zoe")
- 6.2: The role filter is a substring match, so "user" matches superusers too
- 6.2: The scheduled date is `Calendar.strftime("%d %b %H:%M")`: UTC without saying so, no year, two spaces, and not `Common.datetime`, so it does not inherit shared-local-datetime
- 6.2: Role is shown as the raw enum, lowercase "user" or "superuser"; the header "Role*" points to the footnote
- 6.2: The inert "Delete" and "Delete now" for superusers are plain spans with `cursor-not-allowed` and no explanation
- 6.2: "Cancel user deletion failed" drops the changeset errors, so the reason is never shown
- 6.2: Cancel goes through `details_changeset` but straight to `Repo.update`, not `update_user/3`, so unlike other admin edits it writes no audit event (also flow-account-revocation-teardown 6.2)
- 6.2: An unknown or malformed id on `/settings/users/:id/delete` raises in `get_user!` rather than showing the "No Access" or "Not Found" panel
- 6.2: Labels are title case ("New User", "Scheduled Deletion") against sentence case elsewhere
- 6.2: The index route is injected from config while its own delete route, the menu link and `push_navigate` targets are hard-coded
- 6.4: Every user row is loaded with `Repo.all`, then filtered and sorted in memory; no pagination
- 6.4: The full user table is re-queried on every filter keystroke, sort click and clear

### [auth-confirm-access](views/auth-confirm-access.md) (8)

- 6.2: No limit, delay or lockout on failed attempts, and no audit event for success or failure: a hijacked session can guess the password or code here without bound and nobody is told
- 6.2: The token is returned in the URL query string, so it stays in the address bar and history
- 6.2: Recovery codes are not accepted here, unlike the login two-factor page
- 6.2: Renders in the bare `:app` layout: no header, sidebar, banners or flash
- 6.2: The logo is a link to `#`, the form has `action="#"`, and the page has two `h1` elements
- 6.2: Copy uses title case and "!" ("Authentication Code", "Invalid password! Try again.", "Invalid OTP code! Try again.") and mixes "authentication code" with "OTP code"; the button reads "Confirm" for passwords and "Verify" for codes
- 6.2: "Having problems?" box renders with an empty list for users without MFA
- 6.4: Every success inserts a `sudo_session` row; expired rows are never purged here (only on logout or password change)

### [auth-confirm-account](views/auth-confirm-account.md) (10)

- 6.2: Nothing in the app links to `/users/confirm`; the signed-out resend form is reachable only by typing the URL
- 6.2: The resend form redirects to /projects, so a signed-out visitor bounces on to /users/log_in to read the flash
- 6.2: The resend form sends the welcome copy ("Welcome to OpenFn ... If you didn't create an account with us, please ignore this.") rather than the reminder copy the banner sends; an admin-created account also gets the welcome copy instead of its enroller copy
- 6.2: The resend form's allowance is the `confirmation_request` bucket that the sign-up welcome email also spends; owned as a decide row in flow-resend-account-confirmation 6.2
- 6.2: The resend form has no per-requester or per-IP limit; anyone can send up to 3 emails per 15 minutes to every unconfirmed account
- 6.2: Opening the link renders a "Confirm my account" button; only the POST confirms; owned as a decide row in flow-resend-account-confirmation 6.2
- 6.2: Both templates wrap the form in `id="reset-password"` (copied from the reset password page)
- 6.2: The pages use the bare logo nav and call the header without `current_user`, so a signed-in user on the confirm page gets no sidebar, no log out, no confirmation banner and the signed-out title size
- 6.2: `/users/confirm` is not behind `redirect_if_user_is_authenticated`, so a signed-in user can use the signed-out form, for any address
- 6.4: Mail is sent synchronously inside the request

### [auth-confirmation-required](views/auth-confirmation-required.md) (9)

- 6.1: The same blur check says whether any address has an account ("This value should be unique."), unmetered; the same disclosure exists at sign-up (auth-register 6.5)
- 6.2: A mount with no valid session (revoked, disabled, expired) redirects to /projects, which then redirects to /users/log_in, with no flash; only reachable on a websocket remount, since the HTTP plug refuses first
- 6.2: The plug's lockout flash ("Your account is blocked pending email confirmation. Confirm your email address, or update it below...") repeats the page's own body copy, so both show on arrival
- 6.2: Flashes auto-hide after 5 seconds, including an "Email change link is invalid or it has expired." carried in from a failed link (flow-change-email-confirm S09)
- 6.2: The typed address is used raw for the token's `sent_to` and the success alert, while validation downcases it
- 6.2: After a correction is requested, the page still names the old address and "Resend confirmation email" still sends to it, since the email only changes when the link is opened
- 6.2: "Log out" is a GET link
- 6.2: A failed correction send shows "could not be updated, please try again" under the field, where the profile shows a flash (owned by flow-change-email-confirm 6.2)
- 6.4: Emails are sent synchronously in the event. The correction button shows "Sending confirmation email..." while it waits; the resend button has no `phx-disable-with`, so a slow mailer allows repeat clicks, each spending allowance

### [auth-login](views/auth-login.md) (7)

- 6.2: Failed and refused logins re-render with status 200, not 401 or 422
- 6.2: The disabled and scheduled-for-deletion messages are shown only after the password matched, so they confirm to anyone holding the right password that it is right and what state the account is in
- 6.2: "Remember me" is the checkbox's label (humanised field name); "Keep me logged in for 60 days" is a separate span under it, not part of the label
- 6.2: Only the first handler in the cache is offered; the page has no provider name, only "via external provider"
- 6.2: "Forgot your password?" is shown even when no mail provider is configured (MAIL_PROVIDER unset), so the reset email may never be delivered
- 6.2: Page title is the root layout fallback, "Lightning · OpenFn Lightning", since no `page_title` is assigned
- 6.4: The SSO button reads only the in-memory handler cache, refreshed by a warmer every 30 minutes (the moduledoc says 30 seconds); a provider added on another node may not show until the warmer runs

### [auth-register](views/auth-register.md) (13)

- 6.2: A signed-in visitor with signup off gets the plain-text 404, not the redirect to /projects; already recorded in shared-authenticated-session 6.2
- 6.2: A pending return path is honoured only when the new user has no project; under init-project-for-new-user the user always goes to the starter project's /w/new. Already recorded in flow-login-return-to 6.2
- 6.2: The confirmation email is sent even when `require_email_verification` is false, and with MAIL_PROVIDER unset it goes to Swoosh's local mailbox; the delivery result is discarded, so a failed send is invisible to the user
- 6.2: `contact_preference` is cast from the POST, so a hand-built request can choose `any`; the form has no control for it
- 6.2: Labels "First Name" and "Last Name" are title case; "Email" and "Password" are not
- 6.2: No hint of the 12-character minimum before the first failed submit
- 6.2: Password length is counted in codepoints (12 to 72), then, if valid, in bytes (8 to 72); a password of up to 72 multibyte characters but over 72 bytes passes the first check and fails the second
- 6.2: Two people with the same first name both get a project named `<name>-demo`; repeated inner spaces become repeated hyphens ("emory--h-demo")
- 6.2: The terms text always links to openfn.org/terms, whoever hosts the instance
- 6.2: Signup disabled is a bare `text/plain` 404, not a page
- 6.2: Validation errors re-render with status 200
- 6.2: Page title is the root layout fallback "Lightning · OpenFn Lightning"; no `page_title` is assigned
- 6.4: The confirmation email is delivered synchronously inside the POST, so a slow SMTP relay or Mailgun call delays the redirect

### [auth-reset-password](views/auth-reset-password.md) (10)

- 6.2: After requesting instructions, and after a refused link, the redirect is to /projects, which a signed-out browser bounces to /users/log_in, storing /projects as the return path; the flash survives both redirects
- 6.2: A signed-in browser can't reach any of these routes, even to set a password from a link meant for a different account; it goes to /projects with no message
- 6.2: Every request adds another valid token; all outstanding links stay valid until one is used or they age out
- 6.2: A reset does not confirm the email address, though following the link proves ownership (variant `require-email-verification`; owned by flow-invite-new-collaborator 6.1 row 1)
- 6.2: `password_confirmation` is enforced only when the param is present; a PUT without it succeeds. The form marks it `required`
- 6.2: The expiry is set in two places: the email copy reads `Config.reset_password_token_validity_in_days/0`, enforcement reads `@reset_password_validity_in_days` in `UserToken`; both are 1
- 6.2: With no mail provider configured the base config's Local adapter keeps the email in memory; the user is still told instructions are on their way (also auth-login 6.2)
- 6.2: "Register" link on both pages when signup is allowed
- 6.2: Page title is the root layout fallback since no `page_title` is assigned
- 6.4: Reset tokens are never removed except by a successful reset of the same account; expired rows accumulate

### [auth-two-factor](views/auth-two-factor.md) (8)

- 6.2: A wrong code re-renders with status 200, not 401 or 422
- 6.2: The form is built `for={@conn}`, so after a wrong code the input is pre-filled with the code just rejected
- 6.2: Backup codes are compared exactly: lowercase or spaced entry is refused; an authenticator code with a space is refused because it is not 6 bytes
- 6.2: The page has two `h1` headings ("Two-factor authentication" and "Authentication Code"/"Backup Code"); the second is title case; the logo links to "#"
- 6.2: Backup code help reads "Kindly note that a backup code can only be used once" with no closing period
- 6.2: No log out or cancel link; a person without their device or backup codes has no visible way off this page except closing the browser or knowing /users/log_out
- 6.2: The `title/1` component declares `authentication_type` as `:string` but is passed atoms
- 6.2: Page title is the root layout fallback ("Lightning · OpenFn Lightning"); no `page_title` is assigned

### [channel-request-show](views/channel-request-show.md) (11)

- 6.1: "(deleted)" can't appear through the database: deleting the credential nilifies the id, so the page reads "None", the same as never configured
- 6.1: A request with no event yet (state pending) renders empty Request and Response cards with no explanation
- 6.2: No PubSub subscription or refresh: a pending request never updates until reload
- 6.2: Not-found and experimental-off both redirect to the work orders tab (`/history`), not the channel logs, with no flash
- 6.2: Title-case labels: page title "Channel Request", breadcrumb "Channel Request", Context "Channel Name", "Config Version", "Destination URL"
- 6.2: "Config changed" sits inside Context, which is collapsed by default
- 6.2: Durations are microseconds shown as ms with no thousands separator ("30000 ms"), while segment labels switch to seconds at 1000 ms ("30.0s")
- 6.2: The text body hash is truncated to 16 characters; the binary body hash is shown in full
- 6.2: A body with unknown size and an empty-string preview falls through to an empty `<pre>` with a copy button
- 6.2: Admin and owner emails are loaded on every mount and exposed in the tooltip to any member, including viewers
- 6.2: The timing bar background is a hatch when all Finch phases exist ("Proxy overhead") and plain grey otherwise, regardless of whether any overhead was measured

### [channels-index](views/channels-index.md) (14)

- 6.1: Deleting a channel deletes all its request history, though `channel_requests` was made RESTRICT "so that deleting a channel cannot silently destroy its request history"; the confirm says only "This cannot be undone."
- 6.1: A channel with no client credentials forwards any request and attaches the destination credential; the form gives no warning
- 6.2: Only the side menu link checks experimental features; the routes mount for everyone on the project
- 6.2: Channels sorted by name ascending; webhook auth methods by name; project credentials in no particular order
- 6.2: Webhook auth methods scheduled for deletion are not offered, and one already attached is neither shown nor removed by a save
- 6.2: Heading count "Channels (n)" repeats the Total channels card
- 6.2: The toggle tooltip "<name> (disabled)" appears only on disabled channels
- 6.2: Viewers see a disabled "New Channel" button with a tooltip, but Edit and Delete are hidden
- 6.2: Copy is in title case ("New Channel", "Total Channels", "Destination Credential", "Client Credentials", "Edit Channel")
- 6.2: "Client Credentials" lists webhook auth methods and its empty state says "No webhook auth methods available."
- 6.2: The client credentials "Add New" link goes to a tab only admins can change, while editors create channels
- 6.2: "Add New" opens a new tab, and the open form's lists are loaded only in `update/2`, so a newly made credential appears only after reopening the form
- 6.4: Channel delete removes requests in batches of `activity_cleanup_chunk_size`, each with 3x the default DB timeout, synchronously in the LiveView process
- 6.4: No live updates: counts, last activity and enabled state change only on reload or patch

### [credentials-index](views/credentials-index.md) (6)

- 6.1: With `purge_deleted_after_days` 0 the deletion is dated now and the email says secrets are scrubbed "after a few minutes", but the purge cron is only registered when the setting is above 0
- 6.1: The transfer form tells the owner whether an email has an account ("User does not exist") and, on blur, which of the credential's projects that person is not in
- 6.2: Project picker lists top-level projects only; sandboxes get access through propagation, and removing the parent does not remove the sandbox copies
- 6.2: `@openfn/language-googlesheets` and `@openfn/language-gmail` are excluded from the credential type list
- 6.2: OAuth client "Client ID" is a password input
- 6.4: OAuth token and userinfo fetches run as `start_async` tasks with no timeout of their own

### [dataclip-show](views/dataclip-show.md) (11)

- 6.1: "Updated" does not change when the body is wiped, because the wipe is an `update_all` that never sets `updated_at`; it changes only on rename, which this page does not show
- 6.2: `active_menu_item: :dataclip` matches no menu item, so nothing is marked current in the side menu (already recorded in shared-project-header 6.2)
- 6.2: The breadcrumb has no link back to History or the run; only the project picker and "Dataclip <short id>"
- 6.2: The dataclip's name is not shown, though named dataclips are exactly the ones retention never wipes
- 6.2: The type pill shows the raw type value ("step_result", "http_request"); an unknown type gets no colour
- 6.2: Headings use title case: "Dataclip Details", "No Data Available"
- 6.2: `saved_input`, `global` and `kafka` bodies are not scrubbed; a `kafka` body is wrapped with its `request` like a webhook, but the request is never scrubbed
- 6.2: While the body is loading the viewer is an empty editor with no loading text; the Monaco "Loading..." shows only while the editor itself loads
- 6.2: A 403 from the body endpoint (access lost, or the project scheduled for deletion, after the page mounted) reads "Failed to load content" with no reason
- 6.2: The route keeps a trailing `/show` segment, unlike `/runs/:id`
- 6.4: The whole body is sent and loaded into the editor; there is no size cap or truncation

### [first-setup](views/first-setup.md) (3)

- 6.2: The route sits outside any explicit `live_session`, so Phoenix places it in an implicit `:default` session, the same name as Lightning's `live_session :default`. Live navigation from those pages reaches mount with no plug and no `on_mount`, which is why mount re-checks the flag
- 6.2: The token exchange route is behind `redirect_if_user_is_authenticated`. A browser already signed in as another (non-superuser) account keeps that session; the new superuser's auth token is never used and expires
- 6.2: The flag is not its own setting: it is the absence of `SERVICE_ACCOUNT_PUBLIC_KEY`, so an operator can't turn first setup off without configuring a service account

### [history-channel-logs](views/history-channel-logs.md) (11)

- 6.1: The route has no experimental-features check, unlike the request detail page
- 6.1: `channel_state_pill` raises on a state missing from its map
- 6.2: The list does not update live; new requests and state changes appear only on reload, filter change or paging
- 6.2: The channel dropdown is loaded once per component lifetime (`assign_new`), so a channel added or renamed in another tab is missing until the tab is reopened
- 6.2: An empty result shows both "No channel requests found." in the table and "No results found" in the pagination bar
- 6.2: Old copy is title case ("Channel Logs", "Work Orders", "All Channels", "Request Path", "Channel Name", "Started At", "Error Message", "In Progress"); scenarios here use sentence case
- 6.2: The breadcrumb reads "History" only, while the detail page's breadcrumb names this tab "Channels"
- 6.2: Switching project from the picker on this tab lands on `/history` (work orders), dropping the channel filter
- 6.2: The old `/projects/:id/channels/requests` route raises `FunctionClauseError` rather than redirecting
- 6.2: Error message cell is truncated to one line with no tooltip
- 6.4: Mount on this tab still loads workflows, evaluates two policies, reads the work order count limit and subscribes to work order events that are then dropped

### [history-work-orders](views/history-work-orders.md) (15)

- 6.1: A malformed filter in the URL (bad date, unknown sort) raises during render, because the template calls `SearchParams.new/1` for the modals; the code comment says failing loud is deliberate
- 6.2: The 30-day window and "logs only" search default apply only when the URL has no `filters` at all, so any incoming link (alert email, health page, run page) shows all time
- 6.2: Received and last activity bounds are inclusive; the run created upper bound is exclusive
- 6.2: Received and last activity date pickers are `datetime-local` values cast as UTC, while only the run created chip says UTC
- 6.2: Work orders created while the page is open are put at the top of whatever page and sort is showing, and the page grows past its size
- 6.2: Live updates to a listed work order replace it even if it no longer matches the filters
- 6.2: The single-row retry button also toggles the row open, which the navigate immediately throws away
- 6.2: The rerun-from job list is the workflow's current jobs sorted by name, not the version that ran
- 6.2: Work orders of deleted workflows are still listed, but the workflow chip doesn't offer deleted workflows
- 6.2: The bulk retry button's click is chosen at render time: either opening the modal or pushing an `invalid-rerun:<limiter text>` event, which shows whatever text follows the colon as an error flash
- 6.2: A step killed with an unknown error type logs a warning and sends a Sentry message every time it renders
- 6.4: Every `WorkOrderCreated` event re-runs the search for every open history page
- 6.4: The usage limiter is called on every render while bulk retry is available
- 6.4: The rerun-from modal re-queries the workflow, its jobs and retriable steps on every parent render
- 6.4: "All matching" retry and cancel load every matching work order into memory

### [mfa-required](views/mfa-required.md) (4)

- 6.2: The page does not name the project that sent the user here, and nothing passes it along (also flow-require-project-mfa 6.2)
- 6.2: Page title and card heading are title case ("MFA Required for Project") (also flow-require-project-mfa 6.2)
- 6.2: The top bar renders an empty heading: the header gets neither a title nor breadcrumbs
- 6.2: The global project picker still lists the MFA-required projects; picking one returns the user to this page

### [profile-account](views/profile-account.md) (9)

- 6.1: After a password change the LiveView broadcasts `disconnect` to its own transport before it returns the redirect; both messages go from the same process to the transport in that order, so the transport may close before the redirect arrives, and the reconnect finds the session token already deleted
- 6.2: An address already used by another account shows "This value should be unique." on blur, so any signed-in user can test whether an address has an account
- 6.2: The email form checks the current password on every blur, before submit, with no rate limit; an unattended session can be used to guess the password
- 6.2: A password change deletes every user token, including API tokens (`api` context), so CLI and integration tokens stop working; the page gives no warning
- 6.2: The email change token is inserted before mail is sent and not removed if mail fails; a warning can go out with no instructions behind it
- 6.2: `/profile` sits in the config-injected `:services` live_session and `/profile/:id/delete` in `:default`, so "Delete my account" and the modal's return are full page loads, not live navigation
- 6.2: A password change ends on `/projects` via `/users/token_exchange/:token`, not back on the profile
- 6.4: `:assign_projects` loads every project the user can reach on each mount, and this page never reads `@projects`
- 6.4: Email change requests from `/profile` are unmetered by design; each submit sends two emails

### [profile-backup-codes](views/profile-backup-codes.md) (10)

- 6.2: "Generate new backup codes" acts on one click with no confirmation, and invalidates every old code immediately
- 6.2: Regenerating sends no email and records no audit event; neither does viewing or printing
- 6.2: A user without MFA still sees the full codes block and can regenerate codes below the "MFA Disabled" notice; regenerating creates ten codes for an account that has never enrolled
- 6.2: A user with no codes at all sees an empty grid, and "Copy Codes" does nothing (empty text is skipped)
- 6.2: Codes are stored reversibly encrypted (`Lightning.Encrypted.Binary`), not hashed, which is what lets this page show them again at any time
- 6.2: Copy drifts: "Recovery codes" in the intro and warning, "Backup Codes" as the card heading, "Two-factor backup codes" as the page title; title case in "Backup Codes", "MFA Disabled", "Print Codes", "Copy Codes"; "!" in the flash
- 6.2: The intro says MFA can be enabled "by visiting your profile page" while the button below says "Back to profile", even when the user did not come from there
- 6.2: The used-code tooltip shows the raw UTC timestamp, not the viewer's local time
- 6.2: "Print Codes" is a plain `<button>` with an inline `onclick` `window.open`, without `noopener`; the print page does not open the browser's print dialog
- 6.2: The print page's logo is a link to `#`

### [profile-delete-account](views/profile-delete-account.md) (7)

- 6.1: The scheduling write broadcasts `disconnect` to this page's own transport before `push_navigate` to `/users/log_out` returns; same as flow-account-revocation-teardown 6.1 row 2
- 6.2: The dialog is titled "Delete user" and the field labelled "User email" when a user is deleting their own account; the copy is shared with the admin list
- 6.2: "Your account and credential data will be deleted" reads as immediate, but the account is only disabled now; the date is not shown in the dialog (only in the email), and the purge skips anyone with runs, project files or keychain credentials
- 6.2: The activity note checks only runs created by the user, while the purge is also blocked by project files and keychain credentials the user created; the note says "active projects" but counts runs in any project
- 6.2: The typed email is compared to the stored email exactly; stored emails are lowercase, so typing the address with capitals is refused as "doesn't match"
- 6.2: `/profile/:id/delete` is in `:default` and `/profile` in `:services`, so opening the dialog and "Cancel" are full page loads; same as profile-account 6.2
- 6.2: The profile reads the modal module from `/profile`'s route metadata, while the admin users list hard-codes `UserDeletionModal`, so a deployment's substitute applies to self-deletion only

### [profile-experimental-features](views/profile-experimental-features.md) (3)

- 6.2: Other open tabs keep the old setting until they remount; there is no broadcast
- 6.2: No audit event is recorded for opting in or out
- 6.2: The card does not say which features the setting turns on; the gated behaviour is spread across a dozen call sites

### [profile-github](views/profile-github.md) (7)

- 6.1: When revocation on GitHub fails (refresh fails, network error, any non-204), the error is only logged and the local token is removed, so OpenFn's grant stays live on GitHub
- 6.1: GitHub's grant is per GitHub user and app, so revoking it invalidates every token the app holds for that GitHub user, including one stored on another OpenFn account (or another instance sharing the app) linked to the same GitHub user; that account still looks valid locally because `oauth_token_valid?` only checks expiry
- 6.2: On an instance with GitHub not configured, a user who still has a stored token is shown only the disabled connect button; there is no way to remove the token from the UI
- 6.2: Card title "GitHub Access" is title case; the disabled button reads "Connect your GitHub account" and the link "Connect your GitHub Account" (copy mismatch owned by flow-github-connect 6.2)
- 6.2: The disabled button's tooltip says "GitHub OAuth has not been enabled for this instance." but the gate also needs cert and app id (owned by flow-github-connect 6.2)
- 6.2: Revocation failure is logged at error level with the full response inspected
- 6.2: Disconnect records no audit event

### [profile-mfa](views/profile-mfa.md) (12)

- 6.1: A user with `mfa_enabled: true` but no `user_totps` row sees the "on" switch and the disable modal, and "Disable" calls `delete_user_totp(nil)`, which crashes; reachable only with inconsistent data (factories create it, no app path does)
- 6.2: Starting setup, moving to another device and turning MFA off need no password, code or sudo window; someone with an unattended signed-in session can enrol their own device or remove the owner's second factor
- 6.2: Turning MFA off sends no email and records no audit event; neither does enrolling or changing device
- 6.2: Turning MFA off keeps the old recovery codes; re-enrolling later reuses them instead of issuing new ones, and lands on the backup codes page showing the old set
- 6.2: The switch is driven by the session's `mfa_enabled`, so while setting up another device the switch opens the disable modal rather than closing the form
- 6.2: A well-formed wrong code shows the untranslated, lowercase "invalid code"; a malformed one shows both "Invalid OTP code." and "invalid code" under the same field
- 6.2: The card says "multi-factor authentication" and "MFA", the error flash says "2FA", the setup copy says "two-factor"; the heading "Enable multi-factor authentication" stays the same when MFA is already on
- 6.2: The success flash is "MFA Setup" for both a first enrolment and a device change
- 6.2: Issuer and account label in the authenticator are hard-coded "OpenFn" and the user's email, whatever the instance
- 6.2: The disable warning talks about attackers but not about losing access to projects that require MFA
- 6.2: The sudo token for the backup codes page is passed Base64 in the URL query string
- 6.2: The secret modal's close button is hidden below the `sm` breakpoint; on phones it closes only by escape or tapping outside

### [profile-tokens](views/profile-tokens.md) (9)

- 6.1: Escape, click-away and the backdrop hide the modal client-side only, leaving the URL on `/profile/tokens/:id/delete`; clicking the same row's trash icon again patches to the same URL, the live component keeps its id, and `phx-mounted` does not fire again
- 6.2: Tokens never expire, carry no name or description, and have no scope: each grants the owner's full API access until deleted
- 6.2: Opening the delete modal (or any patch back to the index) clears the just-generated token, so a user who clicks a trash icon before copying loses the only view of the new token
- 6.2: The new token field is a disabled input, so in most browsers the copy button is the only way to copy it
- 6.2: Naming differs across the surface: page title "Personal Access Tokens", side menu and account menu "API Tokens", modal "Delete API Access Token"; labels are title case ("Generate New Token", "Last Used at")
- 6.2: The confirm button reads "Yes" rather than naming the action
- 6.2: The delete link on each row is an icon with no text or accessible label
- 6.2: Generating and deleting tokens write no audit event
- 6.4: No cap on how many tokens a user can generate, and the list is unpaginated

### [project-settings-collaborators](views/project-settings-collaborators.md) (14)

- 6.1: Invitation emails are sent with `Enum.each` and the mailer result is ignored; the flash reports success regardless
- 6.2: Collaborators are ordered by first name only (ties in database order)
- 6.2: After adding only existing users the page does a full `push_navigate`; when some need inviting it does a `push_patch` and opens the invite modal by sending itself a message, relying on the patch's `handle_params` running before that message
- 6.2: Removal success re-mounts the whole page via `push_navigate`
- 6.2: Refusals from the add and invite components navigate back to the tab (re-running the scope gate); refusals from the host page only flash
- 6.2: Non-admins see the "Add collaborator(s)" button disabled rather than hidden; tooltip shows the limit message only to admins
- 6.2: Remove tooltip reasons are checked in a fixed order (permission, self, owner, parent admin), so only the first applicable reason shows
- 6.2: An admin can remove other admins
- 6.2: The removal confirmation lists credentials sorted case-insensitively by name
- 6.2: The add form starts with one row; the remove-row button appears only when there are two or more
- 6.2: The invite form has no "add row" control; it can only drop rows carried over from the add form
- 6.2: The support access switch renders only on this tab, though it is a security setting
- 6.4: Email inputs debounce 300 ms
- 6.4: Project addition email job runs once (`max_attempts: 1`) on the `background` queue

### [project-settings-collections](views/project-settings-collections.md) (9)

- 6.2: Every success, refusal and not-found ends in `push_navigate` back to `settings#collections`, remounting the whole settings page rather than patching the list
- 6.2: Switching sort column always starts ascending; ties (equal storage) have no secondary order; sort state is not in the URL and survives parent re-renders only through `socket.assigns`
- 6.2: `url_safe_name` keeps non-ASCII letters, so the hint shows a name ("café-data") that the format check then rejects
- 6.2: Modal titles are title case ("Create Collection", "Edit Collection", "Collection Preview: x") while the header and buttons are sentence case
- 6.2: Delete copy renders "the collection patients ?" with a space before the question mark, and tells the user to "click on the delete button"
- 6.2: The section header wraps the "Create collection" button in `aria-hidden="true"`, hiding it from screen readers (shared `section_header`)
- 6.2: Create, rename and delete write no audit event
- 6.2: Delete removes every record in the collection with a plain confirm (no typed name), and cannot be undone
- 6.4: The collection list is unpaginated

### [project-settings-credentials](views/project-settings-credentials.md) (6)

- 6.1: Scheduling deletion removes every project share, so the credential disappears from this tab, and "Cancel deletion" and "Delete now" can't be reached here; the owner must go to /credentials
- 6.1: "Projects with access" lists every project a credential is shared with, including projects the viewer is not a member of
- 6.2: The "Add new" button is never disabled; `new_credential_menu_button` takes `disabled` but never reads it, only the options are disabled
- 6.2: Disabled options are `<span>`s with `phx-click={false}` and grey text, with no tooltip saying why
- 6.2: Keychain create and update record no audit event, unlike credentials and OAuth clients
- 6.2: Label casing is mixed: menu "OAuth Client" with an "Advanced" badge, tables "OAuth Clients" and "Keychain Credentials", modal "Delete Oauth Client", flash "Oauth client deleted", button "Save Changes"

### [project-settings-data-storage](views/project-settings-data-storage.md) (7)

- 6.1: Changing only the I/O storage policy records no audit event and sends no email, although the email exists to catch unapproved retention changes and lists the policy
- 6.1: The server validates periods against the fixed list, not the plan's list, so a crafted save can pick a period the plan doesn't offer; choosing the "Select Period" prompt also clears history to unlimited on a limited plan
- 6.1: On a single-period plan, a project with no history period can never set one: the history select is disabled at "Select Period", which also keeps the I/O select disabled
- 6.2: One `project_changeset` backs the Setup, concurrency and retention forms; a retention `validate` rebuilds it from the saved project plus retention params, dropping unsaved Setup edits, and Cancel here resets the Setup form too
- 6.2: Labels are title case: "History Retention Period", "Input/Output Data Storage Policy", "Input/Output Data Retention Period", "Heads Up!", "Select Period", "7 Days"
- 6.2: Warning says "When enabled" for a radio choice that is selected, not enabled
- 6.2: Retention changes take effect without confirmation, although "Never retain" stops retries

### [project-settings-github-sync](views/project-settings-github-sync.md) (16)

- 6.1: The "Connect your GitHub Account" link is only restyled when a limit banner disables it; its `href` still opens GitHub OAuth
- 6.1: `on_mount :limit_github_sync` matches only `{:error, %{function: f}}`; a limiter returning `{:error, _, %{text: ...}}` (the shape the connect path handles) raises a CaseClauseError
- 6.2: Unrelated projects (no shared root) may connect to the same repo and branch; only a project family is guarded
- 6.2: Reconnect re-pushes files, rewrites the secret and, for export, dispatches a sync, but records no audit event
- 6.2: Disconnect cleanup runs only with the remover's own GitHub token and its results are ignored, so files and secret can be left behind with no message
- 6.2: The manual sync commit message embeds the user's email ("user <email> initiated a sync from Lightning"); the first sync on connect passes the bare email as the commit message
- 6.2: Only "GitHub Installation" and the connect button honour the limit banner; repository, branch, refresh-branches and "Remove Integration." stay active
- 6.2: The connected view loads the viewer's own installation list on every mount, for every role, just to decide whether to show reconnect
- 6.2: "Path to config" placeholder suggests `./openfn-<project_id>-config.json`, the default path for export, on a field shown only for import
- 6.2: The YAML format toggle is hidden when "Import from GitHub" is chosen, so an import can't be marked v2
- 6.2: Collision errors come from export and end "Rename one of them and export again.", and start lowercase in the flash
- 6.2: Labels in title case and arrow glyphs: "Connect Branch & Initiate First Sync", "Initiate Sync to Branch", "Remove Integration.", "OpenFn --> GitHub"
- 6.2: The verify banner prints raw GitHub error text inside `<code>`
- 6.4: Repos for every installation are fetched in parallel with a 30 s per-installation timeout; a timed-out installation is silently dropped from the repo map
- 6.4: Every mount of a connected tab makes about six GitHub calls to verify (repo, three files, secret) plus the installation lookup, for every viewer
- 6.4: Connect holds a DB transaction open across a chain of GitHub HTTP calls

### [project-settings-history-exports](views/project-settings-history-exports.md) (4)

- 6.1: The list is loaded once at mount and nothing refreshes it; no `handle_info` touches `project_files`
- 6.2: Rows are ordered newest `inserted_at` first, by default arg of `list_project_files`
- 6.2: Column headers are title case ("Export Date", "Export Requested By") and the tab label is "History Exports", while the section heading is sentence case
- 6.2: Status label is the enum humanized ("In progress", "Enqueued")

### [project-settings-security](views/project-settings-security.md) (7)

- 6.1: An admin who hasn't enrolled in MFA can turn the requirement on, which immediately fails every policy check for them, including turning it back off
- 6.1: The inherited banner says sandbox security settings come from the parent, but `requires_mfa` is copied once at creation and not propagated
- 6.2: The toggle flips the value held in the socket, not the stored one; if another tab changed it, the click writes the value already stored, records no audit (no change), but still flashes "updated successfully"
- 6.2: Changing the requirement doesn't broadcast; another admin's open Security tab keeps showing the old state until reload
- 6.2: The success flash is the same in both directions and doesn't say whether MFA is now required
- 6.2: UI labels are title case ("Multi-Factor Authentication") next to a sentence-case section heading ("Project security") and a question-style switch label ("Require MFA?")
- 6.2: The limiter banner is rendered by calling `Phoenix.LiveView.TagEngine.component/3` directly with the adapter's function and attrs, inside an always-present empty `<div>`

### [project-settings-setup](views/project-settings-setup.md) (11)

- 6.2: `/settings` lives in the config-injected `:services` live_session and `/settings/delete` in `:default`, so opening and closing the delete modal are full page loads, and the unauthorised bounce is a `push_patch` across sessions
- 6.2: On `/settings/delete` the route metadata is not read, so the concurrency switch is missing behind the modal, and other tabs' lists (`project_users`, `webhook_auth_methods`) are empty
- 6.2: The project deletion modal's "Delete project" button is enabled before anything is typed (an empty deletion changeset is valid); submitting empty is still refused
- 6.2: Name confirmation validates on blur only
- 6.2: The name input's value is `@name`, the derived slug, so after blur the field shows "my-project" instead of what was typed
- 6.2: Under `no-concurrency-slot` the "Concurrency Override" card and its "Save" still render with no control
- 6.2: Under `purge-immediate` the project is scheduled for "today", but the purge cron is only registered when the setting is above 0, so the project stays scheduled and inaccessible indefinitely
- 6.2: Saving name, description or concurrency writes no audit event
- 6.2: Sandbox delete modal closes on click-away and Escape (pushes `close-delete-modal`, a full navigation); the project deletion modal does neither
- 6.4: Scheduling deletion updates triggers one Multi step each and emails every member inside one transaction
- 6.4: Sandbox delete runs synchronously in the LiveView process (work orders and dataclips in batches of 1000)

### [project-settings-webhook-security](views/project-settings-webhook-security.md) (9)

- 6.1: A deleted method keeps its name reserved until it is purged (forever under `purge-disabled`), but it is hidden from the list
- 6.1: Usernames are slugified (lowercased, spaces to hyphens) during validation but not on save
- 6.2: A masked password is one asterisk per character, so its length is visible before re-authentication
- 6.2: Re-authentication accepts a password or a TOTP code, not a backup code; the "2FA Code" field shows even for users with no authenticator
- 6.2: Server-side save and delete events in the components don't re-check the policy; they rely on the mount-time flag that gated opening the modal, and on shared-project-scope S08 remounting on a role change
- 6.2: `find_for_project` doesn't exclude methods scheduled for deletion, so a crafted id can open a deleted method's edit form
- 6.2: The sandbox notice links to the direct parent; for a nested sandbox that parent shows the same notice again
- 6.2: Modal titles and column headers are title case ("Webhook Authentication Method", "Delete Authentication Method", "Associated Triggers & Channels", "Linked Triggers & Channels")
- 6.4: Re-authentication attempts are not rate limited (each costs a bcrypt check)

### [projects-dashboard](views/projects-dashboard.md) (22)

- 6.2: "Last Updated" is the latest `updated_at` of a non-deleted workflow, not of the project, its settings or its runs; a project with no workflows shows "N/A"
- 6.2: The dashboard renders its own "N/A" for a missing date, where `Common.datetime` would show "--" (shared-local-datetime S07)
- 6.2: Clicking the timestamp copies it instead of opening the row (row in shared-local-datetime 6.2)
- 6.2: Support users' lists are merged and sorted in Elixir: names compare bytewise (uppercase before lowercase) and projects with no workflows sort first ascending; everyone else is sorted by Postgres collation with nulls last both ways
- 6.2: Top-level project names need not be unique; the unique index only covers sandboxes
- 6.2: Sandboxes are never listed, so a user whose only membership is a sandbox sees "No projects found." while the global picker lists that sandbox
- 6.2: The collaborators count uses `href` (full page load) while "History" and the row use LiveView navigation
- 6.2: Cancel and the close button reload the page with `push_navigate` instead of hiding the modal
- 6.2: After a successful create the user stays on the list rather than being taken into the new project
- 6.2: The modal and its form are always in the page, hidden; both create buttons only reveal it client-side
- 6.2: A crafted sort column is stored in `sort_key`, so no header shows as active and the next "Name" click sorts A to Z rather than toggling
- 6.2: The list never updates live: being added to or removed from a project elsewhere, or another user creating one, shows only after reload; `ProjectCreated` is broadcast but nothing in `lib/` subscribes
- 6.2: Creating a project writes no audit event
- 6.2: The greeting depends on the browser's clock ("Good evening, Ama. You're up late!" from 10pm to 3am)
- 6.2: Without JavaScript the heading and welcome text are empty; the text exists only in a data attribute
- 6.2: The empty state shows the button text "Create a new one." above the message "No projects found."
- 6.2: Column headers are title case ("Last Updated")
- 6.4: No pagination; every mount and every sort click re-runs the full overview query
- 6.4: Support users run two queries and merge and sort in memory, including every support-access project on the instance
- 6.4: An unused `get_projects_for_user` query on every mount
- 6.4: Global picker tree rebuilt on renders (row in shared-project-header 6.4)
- 6.4: The typewriter types at 50 ms per character with 200 ms and 1000 ms pauses, so the help links take several seconds to become clickable

### [run-show](views/run-show.md) (13)

- 6.1: Highlight ranges start one line early (a 0-based marker is passed to Monaco's 1-based lines) and always extend the previous range (`last.end <= nextMarker` is always true), so a step's range swallows other steps' lines logged in between
- 6.1: `save-log-filter` stores any client-sent string as the preference, and pattern-matches `{:ok, _}` on the update
- 6.2: `RunUpdated` replaces the run but not `@workflow`, so the "latest" chip and the version link are computed against the workflow version loaded at mount
- 6.2: The version chip tooltip formats the snapshot time as `%F at %T` with no timezone (it is UTC)
- 6.2: "Started" and "Finished" are empty, not "--", when unset, because the page skips `Common.datetime` rather than passing nil
- 6.2: Labels are title case: "Work Order", "Final Output"
- 6.2: Log lines whose level is `success` or `always` (or anything unrecognised) score above "error" and are shown whatever the filter
- 6.2: A fragment that names no tab (`#foo`) hides every panel and highlights no tab (same as shared-project-settings-tab-chrome 6.2)
- 6.2: "No input state could be saved for this run." appears only for a finished step whose dataclip id is set but whose row isn't loaded, or for no step at all; a missing id reads as "not retained" instead (flow-zero-persistence-runs 6.1)
- 6.2: A failed async load shows the raw text "there was an error loading the run"
- 6.4: The run is fetched by the mount hook and again by the async load, on both the dead and the connected mount
- 6.4: Logs are pushed to the browser in chunks of 100 with no overall cap; the browser keeps and re-sorts every line on each push
- 6.4: Log streaming runs inside `Repo.transaction` with the default timeout; a stream that outlasts it fails the async silently

### [sandboxes-index](views/sandboxes-index.md) (18)

- 6.1: "Deleted in sandbox" compares target workflows with the source sandbox's creation time, not with the sandbox's own history; merging into a sibling or grandparent labels the target's older workflows as deleted in the sandbox
- 6.1: `limit_new_sandbox` is read once at mount (for the current project) and not refreshed after delete or restore; restore's tooltip uses the current project's limit while the context checks the sandbox's
- 6.1: Merge trusts `can_merge` captured when the list was last loaded; a demotion on the source sandbox (not the current project, so no remount) doesn't stop the merge, and only the post-merge deletion fails
- 6.1: Under `purge-immediate` the modal promises "retained for 0 days before being permanently removed", but no purge cron is registered, so the sandbox sits under "Scheduled for deletion" indefinitely
- 6.1: The "pre-merge commit" dispatch fires before the merge and its result is ignored; if the merge fails, GitHub has a commit for a merge that never happened, and a failed dispatch is silent
- 6.2: The list is flat and sorted by name; nesting is not shown
- 6.2: Create always sets env "dev"; env can't be changed here
- 6.2: "Sandbox not found" on `/:id/edit` stays on the edit URL with no modal; unauthorized redirects
- 6.2: Edit's submit isn't disabled when invalid; only create's is
- 6.2: Deletion tooltip date is the UTC date as `%d %b %Y`, and day counts truncate (23 hours is "today")
- 6.2: Restore does not re-enable the triggers deletion turned off, and is not transactional or broadcast
- 6.2: An editor merging can't carry a sandbox-only keychain into a target where they can't create one; the job arrives without it, silently
- 6.2: A merge target with an MFA requirement the user hasn't met is offered, then refused at confirm
- 6.2: Delete and merge modals close on click-away and Escape; the create and edit modal does not
- 6.2: Workflows are matched by name between sandbox and target, so a renamed workflow shows as "New" plus "Deleted in sandbox"
- 6.2: Child sandboxes of a merged sandbox are deleted with it, including ones the viewer can't see
- 6.4: Every merge-form change (each checkbox lives in the form) recomputes targets, both divergence directions, the workflow list and credentials
- 6.4: Merge runs synchronously in the LiveView, including two GitHub calls and one full YAML export per dispatch

### [workflow-editor-ai-assistant](views/workflow-editor-ai-assistant.md) (8)

- 6.2: Viewers can chat, so they add to shared history and spend the project's AI quota; this is a stated choice in the channel ("Requiring edit rights here would be a product change")
- 6.2: Auto-apply falls back to applying when the triggering message has no user id (legacy rows)
- 6.2: Cmd/Ctrl+K is disabled on a new workflow
- 6.2: Search and the Latest/Oldest toggle work only on the loaded page; in "Oldest" order, "Load more" appends the next page of newest-first results
- 6.2: Reply text is revealed one character every 15 ms regardless of how fast it arrived
- 6.2: The quota alert title is "Message limit exceeded" whatever the limit's own wording
- 6.2: Join errors are matched on reason text ("session not found", "session type mismatch") to clear the session from the store
- 6.4: Every change to the open job's code, name or adaptor in job page mode pushes `update_context`, which writes the session row

### [workflow-editor-canvas](views/workflow-editor-canvas.md) (8)

- 6.2: The lifecycle lock depends on the viewing user's experimental flag: a collaborator without it can edit and save a live workflow that an experimental collaborator sees as locked, in the same room
- 6.2: The "Workflows" breadcrumb is a plain link, so it is a full page load rather than a live navigation
- 6.2: Ctrl+Z, Ctrl+Y and Ctrl+Shift+Z are bound on `window` and call `preventDefault`, so inside any form field on the page they undo the shared document instead of the field
- 6.2: Every new path from the canvas is `on_job_success`, including one whose source is a trigger, which the edge changeset rejects (must be `always` or `js_expression`). Trigger nodes render no plus button, so this is probably unreachable
- 6.2: The unsaved-changes dot is hidden whenever save is disabled, so a disconnected user with unsaved edits sees no dot
- 6.2: The settings button is an unlabelled icon with no tooltip or accessible name
- 6.2: Clicking the plus button opens the adaptor picker first and only then animates the new step in; the older inline name input that the e2e specs still drive no longer appears
- 6.2: A connection-lost icon in the header follows the LiveView socket, not the collaboration channel

### [workflow-editor-ide](views/workflow-editor-ide.md) (13)

- 6.1: Jobs using a keychain credential get "no_credential": the server only follows `project_credential`
- 6.1: Comment says the job text persists for offline editing, but the editor is read-only while disconnected
- 6.2: panel=editor without a job param renders nothing and no inspector
- 6.2: Ctrl/Cmd+E is bound with Escape: it closes the IDE, but only blurs when the code has focus; on the canvas it opens the IDE
- 6.2: Code read-only uses `useCanSave` (includes disconnected and AI applying); adaptor controls use `useWorkflowReadOnly` (does not)
- 6.2: The editor gets the raw adaptor string (with "latest") for types; docs and metadata explorer get the resolved version
- 6.2: Job selector order is breadth-first from the last trigger found in the edges; jobs not reachable from it come last in document order
- 6.2: Any member who can join, viewers included, makes the server run the metadata CLI with the job's credential
- 6.2: A metadata fetch can refresh an expired OAuth token, writing the credential body and an audit event, on a viewer's page view
- 6.2: Ctrl/Cmd+Shift+Enter in the IDE only acts when the loaded run is retryable
- 6.2: Docs and examples use uppercase "COPY" and "ADD" labels
- 6.2: A sandbox with no environment reports "environment_not_configured" for metadata, shown as "No metadata found"
- 6.4: Metadata cached per job by adaptor and credential for the page's lifetime; no refresh control

### [workflow-editor-inspectors](views/workflow-editor-inspectors.md) (13)

- 6.2: Auth method changes are written to the database on Finish, while every other trigger field waits for the workflow save; Cancel after a save-less Finish cannot undo them
- 6.2: Path delete uses the browser `window.confirm`; step delete uses an in-app dialog
- 6.2: Path toggle and delete are gated only on read-only, not on connection; step delete also needs a connected session
- 6.2: Saving an edit to a credential row also selects that credential for the step
- 6.2: A newly picked adaptor is written as `@latest`, then reopening "Configure connection" pins it to the newest numbered version
- 6.2: "This adaptor does not require credentials" is shown only for common, while the step button treats http, testing, ping and the fhir adaptors as not needing one
- 6.2: `credentials_updated` is broadcast on the workflow's topic only, so editors open on other workflows in the project do not refresh
- 6.2: `webhook_auth_methods_updated` carries username, project id and timestamps, while `get_context` sends only id, name and auth type
- 6.2: Every client that receives `trigger_auth_methods_updated` writes `has_auth_method` into the shared Y.Doc
- 6.2: The auth method picker is labelled "Select a credential" and "Authentication credential N"
- 6.2: The publish button shows for any support user; the server accepts a support user with any role, viewer included
- 6.2: The form sync loop updates its reference from a stale snapshot when several fields change at once, so earlier keys are re-applied on the next pass
- 6.2: Template name error says "less than 255 characters" though 255 is accepted

### [workflow-editor-manual-run](views/workflow-editor-manual-run.md) (20)

- 6.2: Every run without an existing input, including "Empty", inserts a new `saved_input` dataclip
- 6.2: A trigger run resolves the first edge from the trigger, enabled or not; the client falls back to the workflow's first job for the list when the trigger has no edge, but the server answers 404
- 6.2: `retry_run` answers a run in another project or a missing run with 422 and an `inspect`ed atom (`":forbidden"`, `":not_found"`), not 403 or 404
- 6.2: A viewer refused by `retry_run` or `update_name` gets 401 "Authorization Error", a non-member on `create_run` gets 403
- 6.2: A duplicate input name is refused by a unique index, and the user sees only "Failed to update dataclip name"
- 6.2: Retry is offered only when the followed run's input for the step is among the 10 inputs fetched on open
- 6.2: A `dataclip=` link is honoured only if that input is in the first 10 results for the step; otherwise it is dropped silently
- 6.2: The list for a cron step can show 11 items (next cron input plus 10), under copy that says 10; with experimental features it includes named inputs from other steps under copy that says "for this step"
- 6.2: Client size check counts the raw body; the server limit applies to the whole JSON request, where the body is escaped inside a string, so a body just under the limit can still get 413 "Dataclip is too large. Reduce the size and try again."
- 6.2: File type is judged by the browser's MIME type ending in `/json`; a `.json` file with no MIME type is refused
- 6.2: The file input allows multiple files and then refuses more than one with "Only 1 files can be uploaded"
- 6.2: Copy and labels are title case: "Run From Here", "Run Workflow", "Run (New Work Order)", "Filter by Date Created", "Created After", "Default Next Input for Cron"
- 6.2: The panel title shows the trigger type in lowercase, "Run from Trigger (webhook)"; with no triggers or nodes it falls back to "Run Workflow"
- 6.2: The custom tab is "New" in the canvas panel and "Custom" in the IDE
- 6.2: Filter pills show raw keys and values: "named_only", "before: 2025-05-14T14:35"
- 6.2: The type pill styles four types; `kafka` renders unstyled
- 6.2: A disabled Run with no permission problem (no input chosen, invalid custom body) has no tooltip saying why
- 6.2: A changed step or trigger resets the selection and filters only when no run is followed; the tab and custom body are kept
- 6.2: The panel's Run and the header's Run show different success copy for retry ("re-running with previous input" against "re-running this input on v3")
- 6.2: Input dates show with `toLocaleDateString` in the preview and `formatDate` in the list

### [workflow-editor-new](views/workflow-editor-new.md) (8)

- 6.1: Every creation path saves triggers enabled (the YAML default when `enabled` is absent is true, and the blank workflow and both shipped templates set `enabled: true`), while the workflow row gets the schema default state `:draft`.
- 6.1: At the activation limit a new workflow's triggers are switched off silently: creation saves with `notify: 'error-only'` and the limiter message is not shown.
- 6.2: The LiveView's placeholder name is "Untitled Workflow" while the resolver and the unique-name default use "Untitled workflow"
- 6.2: Name suffixing appends to an already-numbered name ("My Workflow 1" becomes "My Workflow 1 1") and skips taken numbers ("My Workflow" becomes "My Workflow 2" when "1" is taken)
- 6.2: The workflow header, breadcrumbs and version picker are hidden until the first save, so the landing screen has no in-editor link back to the workflow list
- 6.2: Once "Build with AI" dismisses the landing screen it cannot be shown again, and the AI panel has no close button on a new workflow; switching to a template or import needs a reload
- 6.2: The type comment says base templates "are labelled so users can tell them apart", but the cards show no label distinguishing shipped from published templates
- 6.2: The LiveView generates a fresh workflow id on every mount, including a LiveView reconnect, while the React root keeps the first id (`phx-update="ignore"`)

### [workflow-editor-run-viewer](views/workflow-editor-run-viewer.md) (10)

- 6.2: The steps and logs panel exists only in the IDE; on the canvas a run is only painted onto nodes and edges, and the list of runs is MiniHistory
- 6.2: "Dismiss" on the load error clears it and leaves "No run data available" with no retry; only closing the chip or reloading tries again
- 6.2: The run chip shows 7 characters of the id, the details 8
- 6.2: "Started" uses the browser's `toLocaleString`, not the app's local datetime component
- 6.2: Labels are Title Case ("Work Order", "Run Steps", "Run Metadata")
- 6.2: A node that ran several times keeps a failure over a later success, but a crash is overwritten by a later success
- 6.2: The "ran N times" tooltip points to "the Inspector or History page"; whether the inspector shows other executions was not checked
- 6.2: `request_run_steps` accepts any run in the project, not only runs of the open workflow; another workflow's run paints nothing (no job ids match) but every node fades
- 6.2: The collapsed panel's expand button wraps the run chip, whose close control sits inside that button
- 6.2: StatePill gives "cancelled" grey text on a grey background (ported as is)

### [workflow-editor-versions-and-promote](views/workflow-editor-versions-and-promote.md) (12)

- 6.1: "Continue in a sandbox" lists every active sandbox of the project that holds the workflow, with its owner's name or email, whether or not the viewer is a member of it; joining one they are not on lands on "project not found"
- 6.2: A failed restore check, or one the server refuses (no permission, unknown version), shows no trigger warnings at all and lets the restore go ahead, so "nothing will break" and "we couldn't tell" look the same. Deliberate per its test
- 6.2: "Restore" is invisible until the row is hovered or the link focused
- 6.2: The discard guard on version switching exists only with experimental features; without them switching never asks
- 6.2: The saves list says "latest" in lower case and formats dates with the browser locale; the publishes list says "Latest" and uses "d MMM yyyy"
- 6.2: Save numbers are cut with `substring(0, 7)`, a leftover from hash-style versions; harmless for integers
- 6.2: The pinned label is built from the raw URL value, so `?release=abc` reads "vabc"
- 6.2: Without the flag, history rows are filled pills and runs carry no version tag; with it, coloured dots and tags
- 6.2: The IDE's history panel picks a run without pinning its version or opening it as executed, and is never filtered to a publish, unlike the canvas panel
- 6.2: The sandbox name typed is made URL-safe on the server ("Trying dates" becomes "trying-dates"); a name of only symbols becomes blank and is refused as a field error. Read from code
- 6.2: A sandbox made from the editor always gets env "dev" and a random colour; the sandboxes page lets people choose
- 6.2: "This run's input" is the first step's input of the open run

### [workflow-health](views/workflow-health.md) (9)

- 6.1: A failed refresh keeps the last numbers with no sign they are stale, and refreshes keep failing silently for as long as the tab is open (for example after the session expires, which answers 401). The Panel comment speaks of a "polite stamp above" that would fall silent, but no stamp or "last updated" time is rendered
- 6.1: A browser timezone that Tzdata does not know yet (a zone newer than the server's tz database) is refused with a 400, so the "Runs" tab shows "Could not load workflow stats" on every load; the controller says this is deliberate
- 6.1: "Steps with failures" labels a job with the name from its heaviest triage row, while the triage table labels each row from that row's newest snapshot, so after a rename the two panels can name the same job differently
- 6.2: The range and tab are React state only, so a reload, a shared link or an email link always opens on "Last 7 days" and "Work orders"
- 6.2: The browser tab title reads "Health Stats for <name>" while the heading reads the bare workflow name and the crumb reads "Health"
- 6.2: The workflow name and retention period reach React once, at mount, behind `phx-update="ignore"`; a rename or a retention change while the page is open shows only after a reload
- 6.2: Triage rows tied on count sort rows with no step name before named ones (Elixir term order puts `nil` before strings)
- 6.2: The disabled range explains itself in a hover tooltip only
- 6.2: The error copy says "Refresh to try again", but the panel also recovers on its own at the next 30-second refresh

### [workflows-index](views/workflows-index.md) (11)

- 6.1: The "last 30 days" period is passed to the header's `:period` slot, which the header never renders
- 6.1: Row has hover styling and `onclick={JS.navigate(...)}` on the `<tr>`; a JS struct in a plain `onclick` attribute renders as JSON, which does nothing (read from code, not run)
- 6.2: Search uses `ilike` with the raw term, so `%` and `_` act as wildcards
- 6.2: "Workflows (n)" counts the filtered list, not the project
- 6.2: Latest work order is chosen by `last_activity` but displayed, and sorted, by `updated_at`
- 6.2: Run counts fold cancelled, crashed, killed and the rest into "failed"; work order counts keep cancelled separate
- 6.2: Failed % divides by all work orders including pending and cancelled; success rate divides by finished runs only
- 6.2: `toggle_workflow_state` is still accepted in lifecycle mode, where no switch renders
- 6.2: The list does not live-update: other users' switches and deletes appear only after a reload or patch (`WorkflowDeleted` is ignored here)
- 6.2: History links carry `onclick="event.stopPropagation()"`, which only matters if the row click worked (see 6.1)
- 6.4: No pagination; every workflow is loaded with triggers, edges and jobs preloaded

## Shared

### [shared-adaptor-credential-config](shared/shared-adaptor-credential-config.md) (6)

- 6.1: Jobs given a keychain credential here get no metadata: the server follows only `project_credential`
- 6.2: Saving an edit to any credential row also selects that credential for the step
- 6.2: A changed adaptor is written as `@latest`, then opening "Configure connection" pins it to the newest numbered version; a new step from the canvas gets the numbered latest straight away
- 6.2: "This adaptor does not require credentials" is shown only for common, while the adaptor box treats http, testing, ping and the fhir adaptors as not needing one
- 6.2: `credentials_updated` goes to this workflow's topic only; editors open on other workflows of the project do not refresh
- 6.2: The dialogs have no read-only check of their own; only the entry buttons are hidden, and the IDE uses `useWorkflowReadOnly` there while its code editor uses `useCanSave`

### [shared-admin-space](shared/shared-admin-space.md) (8)

- 6.2: The gate is declared per LiveView module, not on the `:settings` live_session, which mounts only `InitAssigns`; an admin LiveView added to the session without the hook would open to every signed-in user
- 6.2: MaintenanceLive.Index does not use the hook; it checks the policy itself in `mount` and in each `handle_event`, and refuses with `push_navigate` instead of `redirect`
- 6.2: /dashboard refused over HTTP gets `:no_access_no_back` (no Back button); refused over the socket by the hook it gets `:no_access` (Back button)
- 6.2: `/settings/users` sits in the `:services` live_session (config-injected) while every other admin route is in `:settings`; menu links use `navigate`, so moving to or from Users is a full page load. UserLive.Index is mounted in both sessions (`/settings/users/:id/delete` is in `:settings`)
- 6.2: The "Authentication" item links to `/settings/authentication/new`; that route renders an empty provider form even when one exists, while `/settings/authentication` shows the existing provider and only redirects to `/new` when there is none
- 6.2: On `/settings/projects/:id` and its delete route the global picker marks the project being edited as the current project, because ProjectLive.Index assigns `project` and the picker reads `assigns[:project]`
- 6.2: /dashboard renders Phoenix LiveDashboard's own page with no app sidebar, admin menu or Back link
- 6.4: The settings layout calls `global_project_picker` with the whole `assigns`, so the project tree query and JSON encoding can re-run on every render of an admin page; same issue as the live layout in shared-project-header 6.4

### [shared-authenticated-session](shared/shared-authenticated-session.md) (5)

- 6.1: A websocket-only mount that finds no valid session redirects to log in without storing the current path or a flash
- 6.2: The lockout check in `on_mount` only fires on websocket mounts; the HTTP plug refuses first. A page left open when the 48-hour deadline passes keeps working until it reconnects
- 6.2: The book-a-demo banner only renders on views that place the `:banner` slot (11 views plus the workflow editor); settings-layout pages and others never show it
- 6.2: The GDPR banner is rendered only by the live layout; the six admin pages on the settings layout never show it
- 6.2: BlockRoutes runs before `redirect_if_user_is_authenticated`, so a signed-in user visiting `/users/register` with signup off gets a plain-text 404 instead of being sent to `/projects`

### [shared-credential-index-component](shared/shared-credential-index-component.md) (1)

- 6.1: `project_user` lookup has a TODO to reject a nil member; a non-member host would still load

### [shared-dataclip-body-viewer](shared/shared-dataclip-body-viewer.md) (8)

- 6.1: Masking uses the credential's current values, not the values the run used
- 6.1: A cached body survives a wipe and a loss of access: `max-age=86400` lets the browser reuse it without asking, and the wipe does not bump `updated_at`, so a revalidation answers 304
- 6.2: Masking is plain substring replacement, so short credential values mask unrelated text and numbers (`some-bars` to `some-***s`, `125534` to `12***34`)
- 6.2: `saved_input`, `global` and `kafka` bodies are not masked; `kafka` is wrapped with its `request` like a webhook but the request is never masked (moved here from dataclip-show 6.2)
- 6.2: While the body is loading the viewer is an empty editor with no copy button and no loading text; Monaco's own "Loading..." shows only while the editor bundle loads (moved here from dataclip-show 6.2)
- 6.2: A 403 reads "Failed to load content" with no reason, the same as a network failure (moved here from dataclip-show 6.2)
- 6.2: With no `navigator.clipboard` (an insecure origin), clicking copy does nothing and says nothing
- 6.4: The whole body is sent and loaded into the editor; no size cap or truncation (moved here from dataclip-show 6.4)

### [shared-editor-session](shared/shared-editor-session.md) (8)

- 6.2: The unload warning exists only with experimental features
- 6.2: The unsaved changes marker is hidden whenever Save is disabled, so a disconnected editor with unsaved edits sees no marker. Moved from workflow-editor-canvas 6.2
- 6.2: Save is disabled by settings errors but Ctrl/Cmd+S is not, so the shortcut sends a save the button would not and gets "Save failed: invalid workflow"
- 6.2: `read_only_view` and `workflow_deleted` save errors fall into the generic "Failed to save workflow" toast, whose "Retry" can never succeed
- 6.2: The client write guard checks only edit permission and the content lock, not a pinned view; on an older version the server drops the frames instead, so any control that escapes `useWorkflowReadOnly` changes the screen and snaps back on reload (workflow-editor-canvas 6.1 has the one known case)
- 6.2: The header's connection-lost icon follows the LiveView socket, not the collaboration channel. Moved from workflow-editor-canvas 6.2
- 6.2: The join resolves the workflow by id without checking `deleted_at`; only the LiveView mount refuses a deleted workflow, and the save path refuses it afterwards with "This workflow has been deleted"
- 6.2: A refused join never reaches the UI (the provider registers only an "ok" receiver, per the module comment; `y-phoenix-channel` itself was not inspected)

### [shared-flash-messages](shared/shared-flash-messages.md) (5)

- 6.1: Back on the `:nav` card is `javascript:history.back()`
- 6.2: Error toasts auto-hide after 5 seconds like info toasts, including failure messages carried in from another page
- 6.2: The settings layout uses `live_info_block`/`live_error_block`: no Flash hook, so toasts never auto-hide, and no icon or close button; it has no `live_nav_block` (also shared-admin-space 6.2)
- 6.2: Each render of `Common.flash` and the settings blocks generates a new random id, so any change to the flash map (for example clearing info) gives the other toast a new DOM id, remounting the hook and restarting its timer
- 6.2: The `:nav` card's heading carries `id="modal-title"` though it is not a modal

### [shared-hash-tabs](shared/shared-hash-tabs.md) (3)

- 6.2: Selection is applied in `requestAnimationFrame`, a frame after mount, so the first paint shows no panel
- 6.2: All panels render on every mount and tab switching only toggles a CSS class; the server never learns which tab is open
- 6.2: Tabs carry `role="tab"` and `aria-selected` but there is no arrow-key navigation, and the disabled tab is a `<span>` with no `aria-disabled`

### [shared-local-datetime](shared/shared-local-datetime.md) (8)

- 6.2: The doc says `:relative` shows "2 hours ago"; it actually shows calendar-relative text ("today at 10:30 AM", "last Monday at ...")
- 6.2: Display is always English with a 12-hour clock, whatever the viewer's locale
- 6.2: Relative text is computed on mount and update only; "today at" stays "today" after midnight until the host re-renders
- 6.2: `time_only` shows the clock time without a date; used only for step start times inside a run on History
- 6.2: Clicking a timestamp stops propagation, so on a row that navigates on click (projects dashboard) clicking the timestamp copies instead of opening the project
- 6.2: The timestamp is `select-none`, so click-to-copy is the only way to take the text
- 6.2: The millisecond branch matches only `%DateTime{}`; a `NaiveDateTime` with microseconds is shown to the second
- 6.2: A run's "Started" and "Finished" skip the component when nil, so run-show shows empty rather than "--" (owned by run-show 6.2)

### [shared-log-viewer](shared/shared-log-viewer.md) (9)

- 6.1: Highlight ranges start one line early (a 0-based marker is passed to Monaco's 1-based `Range`) and `last.end <= nextMarker` is always true, so every later line of the step extends the first range across any lines in between (moved here from run-show 6.1)
- 6.1: `save-log-filter` stores any client-sent string, and pattern-matches `{:ok, _}` on the update (moved here from run-show 6.1)
- 6.2: Lines at level `success` or `always` (or any unrecognised level) score above "error" and are shown whatever the filter (moved here from run-show 6.2)
- 6.2: The editor's filter is not saved and always starts at "info", ignoring the preference the run page saves
- 6.2: The two hosts show different waiting copy for an unfinished run with no lines ("Waiting for worker" vs a typed "Waiting for a worker to establish a secure claim...")
- 6.4: No cap on lines; every delivery re-sorts and re-stringifies the whole log, and highlight ranges are recomputed over every line
- 6.4: The editor loads the whole stored log in one channel reply
- 6.4: The editor never unmounts the Monaco root, while `LogTabPanel` itself unmounts on every switch away from the "Log" tab, so each return leaves an editor behind and refetches the whole log
- 6.4: `useRef(createLogStore())` builds and subscribes a throwaway store on every render

### [shared-project-deletion-modal](shared/shared-project-deletion-modal.md) (8)

- 6.1: Escape and click-away hide the modal client-side (the component leaves `close_on_keydown` and `close_on_click_away` at their `true` defaults) without pushing `close_modal`, so the URL stays on the `/delete` route
- 6.2: "Delete project" is enabled before anything is typed (an empty deletion changeset is valid); submitting empty is still refused
- 6.2: Name validates on blur only (`phx-debounce="blur"`), so the button state lags typing
- 6.2: `update/2` rebuilds an empty changeset every time the host re-renders, clearing any validation error
- 6.2: A hidden `id` field is rendered and submitted but never cast
- 6.2: "N day(s) from today" is approximate: the nightly sweep at 02:45 purges on the first run after the date, so up to a day later
- 6.2: Same title, button label and form id (`scheduled_deletion_form`, shared with the user deletion modal) in both branches; nothing on screen says which action will run
- 6.2: The delete-now branch `{:ok, _} = Oban.insert(...)` raises on an insert failure rather than returning an error

### [shared-project-header](shared/shared-project-header.md) (9)

- 6.2: Breadcrumb links use `patch` even when the target is another LiveView (run page to History, health to Workflows); LiveView then falls back to a full page load
- 6.2: Picker items and current project are rendered into a `phx-update="ignore"` container, so an open page does not pick up being added to, or removed from, another project until it navigates
- 6.2: Switching from channel logs (`/history/channels`) lands on the target's work orders tab, not its channel logs
- 6.2: Superusers do not get the Documentation, Community and Support links
- 6.2: "Support" is a mailto to `emails.admin_email`, which defaults to `lightning@example.com` when `EMAIL_ADMIN` is unset
- 6.2: `DataclipLive.Show` sets `active_menu_item: :dataclip`, which matches no menu item, so nothing is marked current on a dataclip page
- 6.2: The confirmation deadline in the banner is formatted in UTC regardless of the viewer's time zone
- 6.2: "Resend confirmation email" is a GET that sends mail, and returns to the referring path without its query string
- 6.4: The live layout calls `global_project_picker` with the whole `assigns`, which defeats change tracking, so the project tree queries and JSON encoding can re-run on every render of a project page

### [shared-project-scope](shared/shared-project-scope.md) (3)

- 6.1: Superuser with no membership row is refused by this gate, though the admin projects page lets them manage the project
- 6.2: When `current_uri` is not yet set the re-mount falls back to the workflow list instead of the current page
- 6.2: Sandbox archive redirect only applies when the viewer has experimental features on; otherwise they get the generic "Project deleted."

### [shared-project-settings-tab-chrome](shared/shared-project-settings-tab-chrome.md) (5)

- 6.1: The editable banner on Credentials and Collections says changes "will sync to the parent project on merge", but merge only attaches the credentials the merger selects and syncs collections by name, and never deletes a parent collection
- 6.1: The inherited banner on Security says the settings are inherited from the parent, but `requires_mfa` is copied once when the sandbox is created and the parent's MFA toggle updates only the parent
- 6.2: All nine panels are rendered for every viewer on every mount; tab switching only toggles a CSS class in the browser, and the server never learns which tab is open
- 6.2: Tabs carry `role="tab"` and `aria-selected`, but there is no arrow-key navigation, and no tab is marked selected until the hook runs
- 6.2: Tab labels are title case ("Webhook Security", "Data Storage", "History Exports") while section headings are sentence case ("Webhook security", "Data storage")

### [shared-run-components](shared/shared-run-components.md) (16)

- 6.1: `channel_state_pill` uses `Map.fetch!`, so any channel request state added to the enum without a config entry raises
- 6.1: On the run page, `step_item` (which contains an inspect `<a>`) is wrapped in another `<.link patch>`, giving nested anchors; the inner link is a `patch` to the workflow editor, a different LiveView
- 6.1: React port: `StepIcon` falls back to the grey pending icon for any unrecognised exit reason, where the LiveView raises (row 1)
- 6.1: React port: the run's state must be one of `ALL_RUN_STATES`, or `RunDetailSchema` rejects the whole payload
- 6.2: Channel request pill says "In Progress" for `pending`, where the run pill says "Enqueued"
- 6.2: `cancelled` pill is `bg-gray-500 text-gray-800`, low contrast compared with the others (ported as is)
- 6.2: The not-claimed flash differs by host: "it has already been claimed by a worker" on the run page, "it is no longer available" on History, both as info flashes
- 6.2: The running duration is computed from the browser clock against the server start time, so clock skew shows
- 6.2: The duration interval keeps ticking every second after the item has finished
- 6.2: History hides the duration for available and cancelled runs; the run page shows "Not started"
- 6.2: A carried-over step is detected by `step.inserted_at < run.inserted_at`, not by an explicit flag; the React port compares the JSON timestamps in the browser
- 6.2: React port: `StepIcon` shows the triangle for `exception` with any error type; the LiveView matches only an empty one
- 6.2: React port: an unknown kill error type only writes a browser console warning; nothing reaches Logger or Sentry
- 6.2: React port: the duration parses ISO timestamps from the run channel, with the same browser clock skew as the hook
- 6.2: React port: the clone marker uses the Radix `Tooltip` component, so the LiveView id problems (6.1) don't apply; its accessible name is "Cloned from previous run", where the LiveView puts the whole sentence in `aria-label`
- 6.4: An unknown kill error type sends a Sentry message on every render, not once

### [shared-run-retry-controls](shared/shared-run-retry-controls.md) (10)

- 6.2: Ctrl/Cmd+Shift+Enter means "Run with custom input" (opens the panel) in the header, and "force a new work order" in the panel and the IDE
- 6.2: Header retry starts from the run's first step and has no client check for a wiped input; panel and IDE retry from the chosen step and only when the selected input matches. The header offers Retry only for a finished run; the panel offers it whatever the run's state and shows "Processing"
- 6.2: Retry success copy differs: "Saved latest changes and re-running with previous input" (panel, IDE) against "Saved latest changes and re-running this input on v3." (header). Moved from workflow-editor-manual-run 6.2
- 6.2: A limiter refusal whose message has no text is read as allowed by the client; the server still refuses
- 6.2: `handleRetry` guards re-entry with a ref; `handleRun` and the header handlers rely on the control re-rendering as disabled
- 6.2: The header's disabled Run (panel or IDE open) still shows the Ctrl/Cmd+Enter shortcut as its tooltip, because the tooltip ignores the `disabled` prop
- 6.2: The panel and IDE show the fresh-run reason as the disabled tooltip even when the control is in Retry mode
- 6.2: A disabled run with no permission problem (no input chosen, invalid custom body) carries no reason. Moved from workflow-editor-manual-run 6.2
- 6.2: Labels are title case: "Run Workflow" (default), "Run From Here", "Run (New Work Order)". Moved from workflow-editor-manual-run 6.2
- 6.2: With experimental features the header shows its button with no trigger when a run is retryable; without the flag it needs a trigger

### [shared-usage-limits-banner](shared/shared-usage-limits-banner.md) (3)

- 6.1: The limits banner and the book-a-demo banner share the `:banner` assign; the limits check overwrites the demo banner when both apply
- 6.2: The limiter decides where the message goes (`position`), so it can target any assign, not only the banner
- 6.2: Limits are checked once at mount; a page left open does not pick up a limit being reached

### [shared-user-deletion-modal](shared/shared-user-deletion-modal.md) (9)

- 6.1: Delete now has no superuser check; a superuser with `scheduled_deletion` set, opened by URL, is purged. The app's own paths keep that state from arising (scheduling refuses superusers, promotion clears the date), but the admin tests build it directly
- 6.1: Escape and click-away hide the dialog client-side only; the modal sets no `on_close`, so the URL stays on the `/delete` route and a reload reopens it (also profile-delete-account 6.1 row 2)
- 6.2: Both branches share the title "Delete user", the "User email" label and the "Delete account" button; nothing on screen says whether this schedules or purges now
- 6.2: "account and credential data will be deleted" reads as immediate on the schedule branch, where the account is only disabled and the date is not shown
- 6.2: The activity note and the delete-now block count only runs, while the purge is also blocked by project files and keychain credentials, which surface only as the S08 failure
- 6.2: The email is compared exactly; stored emails are lowercase, so typing capitals is refused
- 6.2: The delete-now branch writes no user-level audit event and sends no email; the credential `deleted` audit rows are attributed to the user being purged
- 6.2: `purge_user/1` matches `{:ok, _}` on each credential delete, so a failure there raises instead of returning the error S08 handles
- 6.2: Only the profile host can be given a substitute module through route metadata; the admin list always uses this one

### [shared-webhook-auth-method-form](shared/shared-webhook-auth-method-form.md) (9)

- 6.1: Usernames are slugified (lowercased, spaces to hyphens) during validation but not on save
- 6.1: A deleted method keeps its name reserved until purged (forever under `purge-disabled` if the row is never purged), but no list shows it
- 6.2: A masked password is one asterisk per character, so its length is in the page before re-authentication
- 6.2: Re-authentication accepts a password or a TOTP code, not a backup code; "2FA Code" shows even for users with no authenticator, and a user with no password (SSO) can only use a code
- 6.2: Save and delete events trust the host's gate and re-check no policy (settings relies on its mount-time flag and the scope remount)
- 6.2: In a sandbox the editor host creates a method owned by the sandbox, while sandbox settings says webhook auth is managed in the parent
- 6.2: Channels in the delete warning are sorted by name; triggers are in load order
- 6.2: Modal titles are title case ("Webhook Authentication Method", "Delete Authentication Method") and the delete flash capitalises "Webhook Authentication"
- 6.4: Re-authentication attempts are not rate limited; each costs a bcrypt check

### [shared-workflow-yaml-format](shared/shared-workflow-yaml-format.md) (11)

- 6.1: The v1 schema allows `webhook_reply` of `before_start`, `after_completion` or null, but the server also allows `custom`, and the v1 export and AI payload emit it
- 6.2: Only one error is ever reported; the parser picks enum, then unknown property, then missing property, then type, then the first error, although the display can list several
- 6.2: Formatted copy repeats itself: "Missing required field: Missing required property 'body' at /jobs/fetch", "Invalid property: Unknown property ..."
- 6.2: The same error reads differently by host: the import dialog shows the code and formatted copy, the template preview and AI paths show the raw message
- 6.2: v1 `pos` restores the layout; v2 carries none, so templates published from the canvas (v2) lose their layout even though positions are stored next to the code and sent to the browser
- 6.2: Credentials in a file (`credential` in v1, `configuration` in v2) are accepted and discarded; the code view's v2 export omits `configuration` while the server's v2 export includes it
- 6.2: v2 accepts and ignores `start`, `schema_version`, the workflow `id`, and Kafka trigger fields (`hosts`, `topics`, `sasl`, `username`, `password` and others)
- 6.2: v2 has no `custom_path`: the schema refuses it as an unknown property and neither serializer emits it; v1 accepts it
- 6.2: `convertWorkflowSpecToState` defaults a missing trigger `enabled` to true, but v1 requires the key and v2 always fills it with false, so the true default is unreachable from any parse path
- 6.2: Every built-in starting point sets its trigger `enabled: true` (blank workflow, both shipped templates), so a created webhook is live and the "Scheduled workflow" cron fires daily against example.com, while the workflow row is `:draft`
- 6.2: The template catalogue is instance-wide: every editor sees every published template and its job code, whichever project published it

## Flows

### [flow-account-revocation-teardown](flows/flow-account-revocation-teardown.md) (9)

- 6.1: On a password change the LiveView broadcasts `disconnect` to its own `/live` transport before returning the redirect to `/users/token_exchange/:token`; the transport may close first, the redirect is lost, and the reconnect finds the session deleted. Same as profile-account 6.1 row 2
- 6.1: The same ordering on own deletion: the broadcast precedes `push_navigate` to `/users/log_out`
- 6.1: A superuser who changes their own email, role or password in the admin form, or disables themselves, disconnects their own tab before `push_navigate` returns
- 6.2: API tokens are deleted on the user's own password change but kept when a superuser sets a new password, disables, or changes email, role or support access; the profile gives no warning that scripts will stop
- 6.2: Other browsers land on "/users/log_in" with no message saying why they were signed out
- 6.2: Confirming an email change through the emailed link doesn't revoke sessions, while a superuser changing the email does
- 6.2: Setting "Scheduled Deletion" directly in the admin form revokes every token and blocks login like a deletion, but sends no deletion email and skips the email confirmation
- 6.2: "Cancel deletion" re-enables the account but its tokens are already gone, so the user signs in again and must reissue API tokens; it writes no audit event
- 6.2: The deletion email's delivery result is ignored

### [flow-adaptor-catalogue-update](flows/flow-adaptor-catalogue-update.md) (2)

- 6.2: On a cluster, every node's ChannelBroadcaster republishes on the cluster-wide client topic, so each editor gets one push per node per burst and each node's reconciler sweeps once per node
- 6.2: Two more entries reach this flow that the lead's scope does not list: `mix lightning.adaptors.refresh` (with `--name`, a forced refetch that can clear a schema) and `seed_from_file`

### [flow-admin-collection-reaches-project](flows/flow-admin-collection-reaches-project.md) (8)

- 6.1: Move is possible only because `Collection.changeset` casts `project_id` for updates as well as inserts; the admin edit form renders the project select in edit mode and sends it
- 6.1: A move calls no `CollectionHook`: the target project is not checked against its plan and the source is not credited
- 6.1: Rename and move give no warning that runs using the old name or project will start failing with 404 or 401
- 6.2: Writes on the entry page skip the project's MFA requirement and leave no audit event, though they change projects the superuser is not a member of
- 6.2: No broadcast: a project tab already open keeps listing a created, renamed, moved or deleted collection as it was until it remounts
- 6.2: Creating, renaming or moving to a name another project already holds makes every bare-name API call for it, from runs in either project, return 409 until callers add `?project_id=`
- 6.2: After a move, the old project's runs get 401 "Unauthorized" rather than 404, because the bare name still resolves to the moved collection before the project check
- 6.2: The project picker lists sandboxes, so a superuser can create or move a collection straight into a sandbox; it reaches the parent only by name and empty on merge

### [flow-admin-created-account-confirm](flows/flow-admin-created-account-confirm.md) (6)

- 6.2: The 48-hour grace period starts at the superuser's insert, so an account created on a Friday for someone who reads mail on Monday is already locked out when they first log in
- 6.2: The link is valid 7 days but the account locks after 48 hours; the email states neither
- 6.2: Confirming writes no audit event, though `confirmed_at` is one of the audited fields on update
- 6.2: Superusers can't see whether an account they created has confirmed, and have no resend control; nothing under `user_live/` reads `confirmed_at`
- 6.2: Every later email the new user can ask for is the reminder or the welcome copy, neither naming the creator; owned as a decide row in auth-confirm-account 6.2
- 6.2: Under `default` confirming changes nothing the user can see: only the banner and the lockout read `confirmed_at`, both behind require-email-verification

### [flow-ai-session-collaborators](flows/flow-ai-session-collaborators.md) (3)

- 6.2: "Revert changes" on the last reply is offered to every editor in the conversation, not only the asker; in a colleague's tab nothing was recorded, so it always asks to confirm with "Reverting replaces the whole workflow"
- 6.2: A colleague's message box is blocked by `message_processing`, not by the `user_message` that precedes it; between a question and the job starting, others can still send
- 6.2: A tab that opens the workflow while an apply runs is not locked; the lock exists only in the tabs that heard `workflow_applying`

### [flow-change-email-confirm](flows/flow-change-email-confirm.md) (9)

- 6.1: Nothing is broadcast when the change completes; open tabs keep the old state until they remount
- 6.2: The confirm step is a GET that writes; there is no confirm button, unlike `/users/confirm/:token`
- 6.2: A completed self-service change keeps every session and API token; an admin email change revokes sessions and disconnects sockets
- 6.2: No audit event for a self-service email change; an admin change through `update_user/3` with an actor is audited
- 6.2: The old address is warned at request time but gets no notice when the change completes
- 6.2: The controller lands on `/projects`, not back on the profile where the change started
- 6.2: A send failure after the token insert leaves a token and possibly a sent warning with no instructions; on the correction entry it also spends one of the 3 allowed requests
- 6.2: A send failure shows "Failed to request email update" as a flash on the profile but "could not be updated, please try again" under the field on the locked-out page
- 6.4: Requests from `/profile` are unmetered; each sends two emails (also listed in profile-account 6.4)

### [flow-channel-proxy-request](flows/flow-channel-proxy-request.md) (8)

- 6.1: A channel with no client credentials forwards any caller's request and attaches the destination credential; nothing warns about it
- 6.1: Deleting a channel's only client credential on the webhook security tab silently turns it into an open proxy; a test pins this with the message "the destination credential is still spent on an unauthenticated caller"
- 6.1: Refused requests (404, 401) are not recorded anywhere a project member can see
- 6.1: The client IP stored and shown on the request page is the first `X-Forwarded-For` value, which the caller controls
- 6.2: Wrong client credentials answer 401, unlike webhooks, which answer 404 for wrong credentials
- 6.2: The plug sits in the endpoint before `Plug.Parsers` and the router, so no rate limit, usage limit or body size limit applies
- 6.2: Experimental features gate only the menu link and exit views; the proxy serves every enabled channel
- 6.4: Timeouts, body preview size and connection pooling are Philter's defaults; Lightning sets only `collect_timing`

### [flow-collaborator-added-email](flows/flow-collaborator-added-email.md) (6)

- 6.1: `perform/1` returns `:ok` whatever `deliver/3` returns, so a mailer failure is recorded as a completed job; with `max_attempts: 1` it would not be retried anyway
- 6.1: The role in the email is read when the job runs, not when the person was added; a role change in between shows the new role
- 6.2: In `update_project_with_users` the jobs are inserted after the transaction commits and the `Oban.insert_all` result is ignored; in `create_project` they are inserted inside the transaction
- 6.2: The email is plain text only, no HTML part
- 6.2: The email does not go through the `MailRecipients.may_receive?` check used for project mail; it uses plain `deliver/3`, so it is sent even to a user who could not currently open the project (MFA not enrolled, login blocked)
- 6.4: Single attempt, on the shared `background` queue with concurrency 1

### [flow-credential-scheduled-deletion](flows/flow-credential-scheduled-deletion.md) (8)

- 6.1: A credential used in runs is scrubbed but stays scheduled, and "Cancel deletion" is still offered; cancelling restores a credential whose bodies are all `{}`
- 6.1: Cancelling an OAuth credential's deletion does not undo the token revocation done at scheduling
- 6.1: Under `purge-immediate` the credential is dated now and the email promises a scrub "after a few minutes", but no purge cron is registered (also credentials-index 6.1; owned here)
- 6.2: Scheduling writes no audit event of its own, and unsharing writes no `removed_from_project` events; only OAuth revocations are audited
- 6.2: The purge's `deleted` audit is attributed to the credential owner as actor, though the code comment says the purge has no actor
- 6.2: A failed email send is ignored; the transaction commits and the owner is not told
- 6.2: The list shows no scheduled date or badge; only the menu items change
- 6.4: Revocation HTTP calls (up to two per environment) run synchronously inside the scheduling transaction

### [flow-credential-transfer](flows/flow-credential-transfer.md) (4)

- 6.2: The audit event is spelled "transfered"
- 6.2: After confirming, the owner lands on `/projects`, not `/credentials`, for success and every error
- 6.2: The confirm is a state-changing GET with no confirmation page
- 6.4: Emails are sent synchronously inside the request with no retry

### [flow-dashboard-history-drilldown](flows/flow-dashboard-history-drilldown.md) (4)

- 6.2: Counts use `last_activity > window_start` computed at query time; links use `>=` with a second `window_start` computed at render, a few milliseconds later, so a work order whose last activity falls in that gap is counted but not listed
- 6.2: Links carry no `date_before`, and the dashboard does not live-update, so History evaluates at click time: work that arrived or finished after the page rendered shows up, and a pending work order that has since finished drops out of the pending list
- 6.2: The "Runs" and "Successful Runs" cards have no link; they count runs, while History lists work orders
- 6.2: Card links render even when their figure is 0 and open an empty History; row links are hidden at 0

### [flow-dashboard-request-logger](flows/flow-dashboard-request-logger.md) (6)

- 6.1: `filter_parameters` is not honoured for SQL: under debug logging Ecto's `QUERY` line prints bind values with `inspect(params)`, so a captured request shows emails, token hashes, credential and dataclip values it reads or writes, for any user's or anonymous request carrying the token
- 6.2: The plug runs on every request before session, auth and routing, including `/i/*` webhooks, `/channels/*`, the APIs and login; the token is the only gate, so a superuser who hands out a link captures other users' and anonymous requests
- 6.2: Enabled by library default; Lightning never passes `request_logger:`
- 6.2: Tokens are stateless and cannot be revoked; "Start a new stream" mints a new one but earlier links keep working for their hour
- 6.2: The token rides along in data Lightning keeps or forwards: webhook dataclip `request.query_params`, channel `request_query_string`, and the channel destination's URL
- 6.4: No cap on lines held in the page; the DOM grows for as long as the tab stays open

### [flow-data-retention-change-email](flows/flow-data-retention-change-email.md) (7)

- 6.1: Changing only the I/O storage policy (to or from "Never retain") sends no email, though the email reports the policy and exists to catch unapproved changes (same row in project-settings-data-storage 6.1)
- 6.1: Delivery results are discarded; a mailer error is only logged and the admin who saved is told "Project updated successfully"
- 6.2: The acting admin is emailed about their own change
- 6.2: The email doesn't say who made the change or what the previous values were, although the audit event records both
- 6.2: Emails are sent synchronously in the LiveView process, one per recipient, so SMTP latency delays the save's flash; other project mail goes through Oban
- 6.4: One permission check (scope build) and one SMTP call per admin and owner, in sequence, inside the save request
- 6.4: No retry on delivery failure

### [flow-delete-open-workflow](flows/flow-delete-open-workflow.md) (2)

- 6.2: A session that misses the broadcast (socket disconnected at the time) re-mounts on reconnect and is bounced by the mount check instead, with error "Workflow not found" rather than info "Workflow deleted."
- 6.2: The flash names neither the workflow nor who deleted it

### [flow-digest-email](flows/flow-digest-email.md) (11)

- 6.1: The history link filters on last activity, so a work order retried after the digest moves out of the window; the code comment says the link "still shows the runs these counts came from however long the mail sits unread"
- 6.1: A refused send is grouped as `failed` and the job still returns `{:ok, ...}` with `max_attempts: 1`, so nobody is retried
- 6.1: One exception (for example `Projects.get_project!` per workflow) aborts the single job, so every later project in that run gets no digest
- 6.2: The history link carries no status filter, so the list includes pending, running and cancelled work orders that neither count includes
- 6.2: Cancelled work orders are in neither count, and the failure line names the failure states followed by "etc."
- 6.2: A digest is sent with zero counts when the project has workflows but no activity; only a project with no workflows is skipped
- 6.2: Dates in the email header are formatted in UTC with the zone shown; the history chip shows them from the URL as UTC
- 6.2: Window bounds are inclusive at both ends, so a work order whose last activity is exactly 10:00 UTC can appear in two consecutive digests
- 6.2: Changing the digest writes no audit event
- 6.2: The email is plain text only
- 6.4: Single attempt per run

### [flow-download-collection](flows/flow-download-collection.md) (6)

- 6.1: The 200 status and opening `[` are sent before any item is read, so a database error mid-stream cannot become an error page
- 6.2: The controller re-implements the project gate with different outcomes from `shared-project-scope`: non-member, MFA-unenrolled and scheduled-for-deletion all get a 401 "Authorization Error" page, not "Not Found" or `/mfa_required`
- 6.2: The collection is looked up before access is checked, so a non-member gets 404 for a name the project doesn't have and 401 for one it does, revealing which collection names exist
- 6.2: `value` is written as the stored JSON string, not parsed, so the file is an array of objects whose `value` is an escaped string
- 6.2: Route sits under `/download/collections/:project_id/:name`, outside `/projects/:project_id`, beside `/download/yaml`
- 6.4: No cap on records or bytes; a multi-gigabyte collection streams for as long as it takes

### [flow-edit-in-sandbox](flows/flow-edit-in-sandbox.md) (5)

- 6.1: The sandbox is cloned from the database before the unsaved changes prompt; "Save and switch" then saves those changes to the parent, so the new sandbox never has them
- 6.1: The orphan cleanup deletes a sandbox after the sandbox-created metric has fired
- 6.2: `ProjectCreated` is broadcast inside the provisioning transaction, before it commits, and nothing in `lib/` subscribes to it
- 6.2: A failed copy reports the generic "An internal error occurred"
- 6.2: If the copy has no trigger the run panel does not open and `dataclip` stays in the URL

### [flow-editor-credentials-broadcast](flows/flow-editor-credentials-broadcast.md) (3)

- 6.2: Only this workflow's topic is told; editors on other workflows of the same project stay stale (already a `decide` row in shared-adaptor-credential-config 6.2, carried here as the flow's owner)
- 6.2: A malformed broadcast payload replaces the list with an error state rather than keeping the last good list
- 6.2: The full credential payload is written to the info log on every save

### [flow-export-project-yaml](flows/flow-export-project-yaml.md) (7)

- 6.1: Collision flash copy starts lowercase ("two workflows in this project...") and quotes keys with Elixir `inspect`
- 6.2: The controller re-implements the project gate with different outcomes from `shared-project-scope`: non-member, MFA-unenrolled and scheduled-for-deletion all get a 401 "Authorization Error" page, not "Not Found" or `/mfa_required`
- 6.2: A non-member is told the project exists (401) while an unknown id gets 404; the LiveView gate deliberately hides existence
- 6.2: `put_root_layout(false)` has no effect on a `send_resp`
- 6.2: Credentials whose owner has no email are dropped from the file without notice
- 6.2: Filename uses the project UUID, not its name
- 6.2: Route sits under `/download/yaml?id=` with the project id in the query string, outside `/projects/:project_id`

### [flow-failure-alert-email](flows/flow-failure-alert-email.md) (11)

- 6.1: Every final state except success alerts, including a worker-reported `cancel` or `kill`, and the copy always says "just failed"
- 6.1: The "failed N times" count is the number of alerts this recipient's bucket has counted for the workflow in the current window, not the number of failures; a member who opted in mid-burst, or whose earlier sends failed (decremented), sees a lower number
- 6.1: The rate window is a fixed Hammer bucket, not a sliding window, so "in the last 5 minutes" can span two buckets and allow up to 6 emails in a 5-minute stretch
- 6.1: Janitor alerts are sent inside the transaction that marks runs lost; a later failure in the transaction rolls back the state but not the emails
- 6.2: The alerter runs synchronously inside the run channel's `run:complete` handler, one mail call per recipient, before replying to the worker (a TODO says to move it to Oban)
- 6.2: Delivery failure is swallowed; only the mailer telemetry logs it, and the rate bucket is decremented
- 6.2: The email is addressed to the bare address, without the recipient's name (other mail uses the `User` recipient protocol)
- 6.2: HTML-only body, rendered from `failure_alert.html.heex`; greets by first name
- 6.2: Support users and superusers without a membership row can never receive alerts, even with support access on
- 6.4: Hammer buckets live in Mnesia with 4-hour expiry and 10-minute cleanup
- 6.4: One synchronous mail send per recipient in the worker's completion path; a slow mail provider or many subscribers delays the reply to the worker

### [flow-first-superuser-sign-in](flows/flow-first-superuser-sign-in.md) (2)

- 6.1: A browser that is already signed in as another account skips the exchange but keeps the flash, so /projects says "Superuser account created." while the operator is still the old account; the new superuser's token is never used
- 6.2: The page the operator first asked for is not remembered: the FirstSetup plug halts before `require_authenticated_user` can store `user_return_to`, so the flow always ends on /projects

### [flow-forgot-password](flows/flow-forgot-password.md) (4)

- 6.2: The request hop redirects to /projects, which a signed-out browser bounces to /users/log_in after overwriting any stored return path with "/projects"; a deep link that brought the visitor to log in is lost once they use "Forgot your password?" in the same browser
- 6.2: Every request adds another valid link; all stay valid until one is used or they age out (S04 covers the use case)
- 6.2: A disabled or scheduled-for-deletion account receives the email and completes the reset before being told at log in that it is blocked
- 6.4: The mail send blocks the request hop's response

### [flow-github-app-install](flows/flow-github-app-install.md) (6)

- 6.2: The original tab is never told an install happened: no PubSub, no focus or visibility listener; the admin must find and click the refresh icon. The lead's scope ("the sync tab picks up the new installation") holds only after that click
- 6.2: `/setup_vcs` ignores `installation_id` and `setup_action`, so the new installation is not preselected after refresh
- 6.2: Refreshing installations resets the whole form changeset to an empty connection, clearing installation, repository, branch and sync direction choices
- 6.2: A signed-out request to `/setup_vcs` stores it as the return path, so after login the user lands on a page that tries to close itself
- 6.2: Neither entry link is shown on a connected project, so adding repositories to an installation after connecting has no link from Lightning
- 6.2: Title case in "Create/update GitHub installations or modify permissions." and "Install or manage GitHub app installations" is owned by project-settings-github-sync 6.2

### [flow-github-connect](flows/flow-github-connect.md) (6)

- 6.1: The authorize URL carries no `state` and the callback checks none, so any page can drive a logged-in user's browser to `/oauth/github/callback?code=<attacker's code>` and link the attacker's GitHub account to them
- 6.2: The broadcast goes to every page the user has open on profile or any project's settings, whichever tab; a settings page open on another project and another tab is navigated to that project's `#vcs` with the success flash
- 6.2: The controller route is generic (`/oauth/:provider/callback`) but only GitHub is handled
- 6.2: Copy differs between the disabled profile button ("Connect your GitHub account") and the link ("Connect your GitHub Account")
- 6.2: The profile card checks `github_enabled?` (needs cert and app_id too) although its tooltip says "GitHub OAuth has not been enabled", which only needs client id and secret
- 6.2: The settings link is visually disabled under a GitHub sync limit but still opens GitHub (owned by project-settings-github-sync 6.1)

### [flow-github-sync-actions](flows/flow-github-sync-actions.md) (12)

- 6.2: A deploy does not reconcile open collaborative editors; an editor open on a deployed workflow keeps its pre-deploy Y.Doc. The provisioner documents this as deliberate
- 6.2: The editor path authorizes `:edit_workflow`, the settings tab `:initiate_github_sync`; both resolve to editor and above today
- 6.2: Three default commit messages: editor "<email> initiated a sync from Lightning", settings tab "user <email> initiated a sync from Lightning", first sync on connect the bare email
- 6.2: `WorkflowUpdated` is broadcast on `workflow_events:<project_id>` for every deployed workflow, but nothing in `lib/` subscribes to that topic
- 6.2: `WorkflowUpdated` and `WorkflowDeleted` are broadcast inside the import transaction, before commit
- 6.2: The repo connection token carries no expiry; it lasts as long as the connection row
- 6.2: The usage limit is checked at dispatch and deploy but not on `GET /api/provision`, so a run dispatched by hand in GitHub still reads the spec while the limit applies
- 6.2: A deploy from a repo connection never attaches project credentials named in the spec
- 6.2: Every connected project in one repository shares the `openfn-deployment` concurrency group, so deploys of different projects queue behind each other
- 6.2: The sync pre-flight always exports the v1 format, whatever `sync_version` says
- 6.2: "Save & Sync" uses an ampersand and title case; "Saving..." while in flight
- 6.4: Snapshot ids for every workflow in the project go into one workflow_dispatch input

### [flow-history-export](flows/flow-history-export.md) (7)

- 6.1: A failed export sends nothing, though the start flash promises an email
- 6.2: The email links straight to the download controller, not to the history exports panel, so the email path never passes the exit view
- 6.2: The history exports panel reads `project_files` only at mount and has no subscription; status changes appear only after a reload
- 6.2: The file row is loaded with `Repo.get!` before authorization, so a non-member gets 404 for an unknown id and 403 for a real one
- 6.2: A user who has requested an export cannot be deleted while the row exists
- 6.2: Panel lists newest first; status labels are the humanized enum ("In progress"); headers are title case ("Export Date", "Export Requested By")
- 6.2: The exports table reuses the id `project_users_table`

### [flow-history-live-updates](flows/flow-history-live-updates.md) (3)

- 6.2: Step progress is not live: step started and completed events go to the run topic only, so an expanded row gets new steps only when the run's state next changes
- 6.2: The page subscribes in `mount` without a `connected?` guard, so the static render's request process subscribes too
- 6.4: No batching or debounce: a retry chunk of 100 sends 100 `WorkOrderUpdated` and 100 `RunCreated`, and each open page reloads a full work order graph for each, in its own process

### [flow-invite-new-collaborator](flows/flow-invite-new-collaborator.md) (8)

- 6.1: Invited users are created unconfirmed and setting a password does not confirm them, though following the emailed link proves they own the address. No confirmation email is sent at invite time
- 6.1: The email says "If you did not request to join this project, please ignore this email", but the invitee never requested anything; ignoring it leaves an account and membership in place
- 6.2: The journey does not land in the project: a successful reset goes to log in, then `/projects`, and the invitee must pick the project
- 6.2: Opening the link in a browser where someone else is signed in redirects to that person's `/projects`, with no hint the link was for someone else
- 6.2: The email shows the role as its raw lowercase value ("editor")
- 6.2: The invitee is a full member from the moment the invite commits; there is no pending state before they set a password
- 6.2: The reset page shows a "Register" link when signup is allowed
- 6.4: Invitation emails are sent one by one, synchronously, while the transaction holds its locks

### [flow-legacy-editor-redirect](flows/flow-legacy-editor-redirect.md) (3)

- 6.1: `project_id` and `id` are interpolated into the target path without re-encoding; a `%2F` in a segment decodes to `/`, so a crafted link can redirect to another local path (for example `/users/log_out`)
- 6.2: If both `a` and `run` are present, `a` overwrites `run`; repeated params collapse to the last value
- 6.2: Legacy `s` and `m` are forwarded under their old names although the collaborative editor names selection and mode differently; they are ignored on landing

### [flow-log-out](flows/flow-log-out.md) (4)

- 6.1: Logout is a plain GET with no CSRF token or confirmation, so any cross-site top-level link (cookies are SameSite Lax by default, `endpoint.ex:12-16`) signs the user out
- 6.1: `renew_session/1` carries `user_return_to` across logout, so a path stored before logging out (for example by the re-auth redirect) sends the next person who signs in on that browser to the previous user's page
- 6.2: The action is `delete/2` and the test block says "DELETE /users/log_out", but the route is GET
- 6.2: No audit event is written for logout

### [flow-login-return-to](flows/flow-login-return-to.md) (6)

- 6.1: Logout renews the session but keeps any pending `user_return_to` (set by a signed-out GET or by the sudo gate and never used)
- 6.2: The redirect to login carries no flash, so the login page doesn't say why the visitor is there or that they will be returned
- 6.2: The URL fragment never reaches the server, so a link to a run's "#output" or "#input" tab returns to the run on the Log tab
- 6.2: One session key: opening two deep links in two tabs before logging in returns to whichever was opened last
- 6.2: A visitor who registers instead of logging in is sent to their first project's new-workflow page when they have a project (always under init-project-for-new-user), and to the stored path only when they have none
- 6.2: Under require-email-verification, a locked-out account consumes the stored path at login and is then sent to `/users/confirm-required`; after confirming it does not go back

### [flow-manual-run-live-follow](flows/flow-manual-run-live-follow.md) (5)

- 6.2: On the canvas the panel has no `onRunSubmitted`, so it stops "Processing" as soon as the request returns; in the IDE it waits for the run channel to deliver the new run, or 30 s
- 6.2: A run followed from creation has no step selected (first-step auto-select only applies to steps present at load), so the IDE log shows every step's lines
- 6.2: The run channel authorizes on the run's own project, not the editor's (owned by flow-open-run-in-editor 6.1)
- 6.4: The IDE log subscription depends on the whole run object, so every run or step event refetches the full log with `fetch:logs` and re-registers the listener; duplicates are dropped by id in the log store
- 6.4: `fetch:logs` loads every stored line in one transaction

### [flow-oauth-credential-authorize](flows/flow-oauth-credential-authorize.md) (7)

- 6.2: The redirect URI is the SSO login callback `/authenticate/callback`; credential callbacks are told apart from login callbacks only by having no `provider` param
- 6.2: Every authorize URL carries Google's `access_type=offline` and `prompt=consent`, whatever the provider
- 6.2: The PubSub topic is the LiveView socket id; reloading or navigating the originating page orphans an in-flight sign-in (noted in the helper)
- 6.2: A callback with neither `code` nor `error`, or with `error` but no `state`, redirects the second window to the login page instead of closing it
- 6.2: In the workflow editor the "new credential" modal opens without a server-side role check, so a project viewer could complete the provider sign-in; only save is refused. Whether the React side hides the control for viewers was not checked
- 6.2: /credentials offers the user's own and global clients; project contexts offer project-shared and global clients, so a user's own unshared client cannot start this flow from a project
- 6.4: Token and userinfo fetches run as `start_async` with no timeout of their own (also credentials-index 6.4)

### [flow-open-run-in-editor](flows/flow-open-run-in-editor.md) (5)

- 6.1: History lists runs of soft-deleted workflows and links them; the editor mount refuses deleted workflows
- 6.1: The run channel authorizes on the run's own project, not the editor's project, so a foreign run the user can access elsewhere still loads into the viewer once the client asks for it
- 6.2: Step inspect links append `#log`; nothing in the collaborative editor reads the hash
- 6.2: The run page link is `navigate` (live redirect) but the run-page step link is `patch` across LiveViews, nested inside another patch link
- 6.2: The legacy redirect forwards other old params (`s`, `m`) unchanged although the new editor names them differently

### [flow-personal-access-token-use](flows/flow-personal-access-token-use.md) (3)

- 6.2: The two hops are separate implementations of the same check: `/api` looks the raw string up in `user_tokens` with no signature or claim check, `/collections` verifies the JWT then checks the row and account. Consequence: rotating `token_signer` kills every token on `/collections` but not on `/api`, and the 60 s `iat` skew applies only to `/collections`
- 6.2: Both hops return the same bare 401 `{"error": "Unauthorized"}` with no `www-authenticate` header or reason, whether the token is unknown, revoked, or its owner is blocked or locked out; `/api/users` uses RFC 6750 style instead
- 6.2: On `/collections`, a valid token for a non-member is refused with the same 401 as a revoked token, so a user can't tell "no access" from "bad token"

### [flow-reauth-backup-codes](flows/flow-reauth-backup-codes.md) (8)

- 6.2: The window is checked only on HTTP requests and LiveView mounts, so an open codes page keeps working (including "Generate new backup codes") after the five minutes; a socket reconnect after expiry sends it to "Confirm access"
- 6.2: The sudo token travels Base64 in the URL query string and stays in the address bar and history; the same user can reuse it from another browser for up to five minutes
- 6.2: No limit or lockout on failed re-authentication attempts, and no audit event for success or failure
- 6.2: A user without MFA has no "View" link but can reach the codes by URL, re-authenticate with a password, and sees "MFA Disabled" above a codes block
- 6.2: Recovery codes are not accepted on "Confirm access"; only password or authenticator code
- 6.2: "Print Codes" opens a plain page through an inline `onclick` `window.open`; the page does not open the print dialog
- 6.2: Copy drifts: "Recovery codes" on the profile, "Two-factor backup codes" / "Backup Codes" on the landing and print pages, "Authentication Code" vs "OTP code" on re-auth, title-case headings and "!" in error copy
- 6.4: Expired `sudo_session` rows are never purged; only logout and a password change delete them

### [flow-register-first-workflow](flows/flow-register-first-workflow.md) (5)

- 6.2: On the project branch the stored `user_return_to` is neither honoured nor deleted; `renew_session` keeps it through sign-up and through a later logout, so it is applied at the next login in the same browser. The ignore half is already a decide row in flow-login-return-to 6.2 and auth-register 6.2
- 6.2: The redirect goes to the first of `user.projects` with no ordering; if an `account_hook` extension also adds the user to a project, which one is chosen is undefined
- 6.2: Repeated inner spaces in the first name become repeated hyphens in the project name ("emory--h-demo")
- 6.2: The landing URL carries no hint that this is a first visit; the landing screen is identical to the one an existing editor sees
- 6.4: The confirmation email is sent synchronously before the starter project is created and the redirect issued, so a slow mail relay delays landing on the editor; owned by auth-register 6.4

### [flow-require-project-mfa](flows/flow-require-project-mfa.md) (6)

- 6.1: An owner or admin who hasn't enrolled can turn the requirement on and is immediately locked out by it, including from turning it back off. If no owner or admin on the project has enrolled, nobody with a role can lift it, and the superuser project form has no control for it (it casts `requires_mfa` but renders nothing for it)
- 6.2: Turning the requirement on doesn't broadcast, so an unenrolled member's open pages stay mounted until they navigate, reload, or a membership event for them fires; handlers that re-authorize refuse with "You are not authorized to perform this action." in the meantime
- 6.2: `/mfa_required` doesn't name the project that sent the member there, and nothing remembers it, so after enrolling the member has to find the project again
- 6.2: A member who later disables MFA on their profile is warned only that their account is less secure, not that they will lose access to MFA-required projects
- 6.2: The MFA required page title is title case ("MFA Required for Project")
- 6.2: A sandbox's `requires_mfa` is copied at creation, so turning it on in the parent doesn't stop an unenrolled member reaching an existing sandbox

### [flow-resend-account-confirmation](flows/flow-resend-account-confirmation.md) (13)

- 6.2: Resend is a GET that sends mail, and returns to the referer path with its query string dropped (the editor loses its selected job or run); owned as a decide row in shared-project-header 6.2
- 6.2: With no Referer header the resend lands on /projects
- 6.2: Confirming lands on /projects, not the page the user came from
- 6.2: Opening the link does not confirm; it renders a "Confirm my account" button that POSTs
- 6.2: A confirmed user hitting the resend URL is silently redirected; an unconfirmed user on an instance with verification off still gets an email, because the controller does not check the flag
- 6.2: Confirm page wrapper has `id="reset-password"`
- 6.2: Email says "If you have not requested an account confirmation email, please ignore this."
- 6.2: The welcome email spends the `confirmation_request` allowance that the signed-out resend form at /users/confirm also uses, so straight after sign-up that form sends two more, not three; the banner's resend has its own `confirmation_resend` allowance
- 6.2: The welcome email is sent even when verification is not required, and its result is discarded; owned as a decide row in auth-register 6.2
- 6.2: Welcome and reminder share the subject "Confirm your OpenFn account", so an inbox shows identical subjects; each link works until one is used (S07)
- 6.2: The welcome email greets "Hi <first name>," and is addressed to the user struct (name and address); the reminder greets "Hello <first name>," and is addressed to the bare email
- 6.2: The surface ids proposed for the controller and email in workflow-editor-canvas and shared-project-header "Proposed flows" (`controller:user-confirmation-send-email`, `email:remind-account-confirmation`) differ from the ones used here
- 6.4: Hammer uses Mnesia `disc_copies` on the local node

### [flow-restore-version-open-editor](flows/flow-restore-version-open-editor.md) (2)

- 6.2: Under `colleague-can-edit`, a colleague's unsaved edits are wiped by the reset with no notice; `workflow_saved` shows no toast
- 6.2: The reset clears in one Y.Doc transaction and reserialises in a second, so connected clients may render an empty workflow between the two. Read from code

### [flow-run-show-live-updates](flows/flow-run-show-live-updates.md) (4)

- 6.2: `RunUpdated` is broadcast from inside an outer transaction for a claim, a completion and a lost-run sweep; the run page renders the payload, so it is not exposed to the stale-read problem in flow-history-live-updates 6.1, but would show a state that is later rolled back
- 6.2: `RunUpdated` replaces the run but not `@workflow`, so the version chip stays as computed at mount (owned by run-show 6.2)
- 6.4: Stored log lines are streamed inside `Repo.transaction` with the default timeout; a stream that outlasts it fails the async silently while live lines keep arriving
- 6.4: A batch of N log lines sends N broadcasts and N push events, each re-sorting and reformatting the whole log in the browser

### [flow-sandbox-merge](flows/flow-sandbox-merge.md) (8)

- 6.1: Promote never passes `selected_credential_ids`, so a job in the promoted workflow that uses a credential only the sandbox has arrives in the parent with no credential, silently
- 6.1: Promote passes no `skip_collections`, so every sandbox-only collection is created in the parent, including ones unrelated to the promoted workflow
- 6.1: The list merge commits to GitHub before and after and fires the "sandbox merged" metric; promote does neither
- 6.2: The two entries judge divergence differently: the list uses `diverged_workflows/2` (skips names the sandbox has no history for), promote uses `workflow_diverged?/3` (counts them)
- 6.2: Merge imports with `allow_stale: true`; a concurrent edit in the parent is overwritten, and the open parent editor is reset to the merged content
- 6.2: Without the experimental flag, archiving sends colleagues to `/projects` with "Project deleted." instead of the parent
- 6.2: Workflows match by name between sandbox and parent; a promoted rename lands as a new parent workflow and the old one stays
- 6.4: `promote` runs the whole merge synchronously in the channel process, unlike `request_promote_check`, which uses `async_task`

### [flow-sandbox-scheduled-deletion](flows/flow-sandbox-scheduled-deletion.md) (8)

- 6.1: Under `purge-immediate` the date is "now" and the modal says "0 days", but no purge cron exists, so the subtree is never purged (sandboxes-index 6.1)
- 6.2: Restore does not re-enable triggers; restore is not transactional and broadcasts nothing (also sandboxes-index 6.2)
- 6.2: Sandbox deletion sends no email, unlike the root path; members of a child sandbox learn only from teardown or the list
- 6.2: No audit event for scheduling, restoring or hard-deleting a sandbox
- 6.2: The settings UI admits only the owner while the server path admits admins and root admins; the list admits admins (project-settings-setup 6.5)
- 6.2: Hard delete and purge are not wrapped in a transaction; a failure after the files step leaves a partly deleted sandbox (purgeable on retry)
- 6.4: The sweep enqueues a job for every subtree member as well as the root of the subtree; the parent job deletes the children, the child jobs then find nothing and return `:ok`, or race the parent and retry (3 attempts)
- 6.4: Settings hard delete runs synchronously in the LiveView (batches of 1000), subtree included

### [flow-schedule-project-deletion](flows/flow-schedule-project-deletion.md) (8)

- 6.2: Cancelling a scheduled deletion does not re-enable the triggers it disabled (sandbox cancel behaves the same)
- 6.2: A failed send to one member is ignored (`Enum.each` drops `{:error, _}`), so the transaction commits and that member is silently not told
- 6.2: The notice uses `deliver/3`, not `deliver_project_mail/4`, so it skips the `MailRecipients.may_receive?` check other project mail runs
- 6.2: The admin list's modal always takes the root path, so a superuser "Delete" on a sandbox schedules it without the descendant cascade `Sandboxes.schedule_sandbox_deletion` applies
- 6.2: Admin cancel has no confirmation and uses `get_project!`, so a project purged in the meantime raises
- 6.2: Scheduling emits no audit event, from either entry
- 6.2: The admin "Scheduled deletion" column formats the date `%d %b %H:%M` (double space, UTC, no zone)
- 6.4: Scheduling updates triggers one Multi step each and sends every email synchronously inside one transaction

### [flow-spend-backup-code](flows/flow-spend-backup-code.md) (5)

- 6.2: Spending a recovery code sends no email, records no audit event and writes no log line, so an account owner whose codes were taken gets no sign of it
- 6.2: Nothing tells the user how many codes they have left after spending one, or prompts them to regenerate when they run low or out
- 6.2: Codes are compared exactly: lowercase or a pasted trailing space is refused (auth-two-factor 6.2)
- 6.2: `used_at` is set in UTC and the tooltip would show it raw, not in the viewer's time zone (profile-backup-codes 6.2; shared-local-datetime is the existing pattern)
- 6.4: No limit, delay or lockout on wrong recovery codes (auth-two-factor 6.5 and section 8 own the question for both code types)

### [flow-sso-login](flows/flow-sso-login.md) (5)

- 6.1: A provider error body from the token endpoint is not sent back to login: a map body renders the "Authorization Error" page with the provider's error fields, a string body returns raw JSON `{"error": ...}`. The comment above says failures shouldn't reveal which check tripped
- 6.2: "Keep me logged in for 60 days" is always on for SSO logins; the visitor never sees the choice
- 6.2: Refusal copy differs by account state ("Could not find user account", "disabled", "scheduled for deletion") while every other failure shares one generic message, so a verified provider identity learns whether and in what state a Lightning account exists for its email
- 6.2: A verified email from the provider does not mark an unconfirmed Lightning account confirmed; under require-email-verification such an account is signed in and then held by the confirmation lockout
- 6.2: A request to the provider-less `/authenticate/callback` carrying `code` and an SSO-style random `state` is treated as a credential callback and fails decrypting the state; only reachable by editing a URL, since the admin form always builds `/authenticate/<name>/callback`

### [flow-toggle-workflow-open-editor](flows/flow-toggle-workflow-open-editor.md) (2)

- 6.2: `state` (live/draft) is not among the reconciled fields, and no `lifecycle_changed` push is sent, so under experimental features the editor's Live/Draft badge and the channel's lifecycle lock keep the old state. The list only offers this outside sandboxes via a crafted event (see workflows-index 6.2)
- 6.2: The editor's "on" means any trigger enabled; the list's switch uses its own rule (workflows-index 6.1, "three definitions of enabled")

### [flow-webhook-auth-method-enforcement](flows/flow-webhook-auth-method-enforcement.md) (5)

- 6.1: In a sandbox, the inspector lists and shows only methods owned by the sandbox, but sandbox triggers carry the parent's methods and the plug enforces them
- 6.2: Attaching takes effect on Finish, outside the workflow's save, versions and snapshots; discarding or resetting the workflow does not undo it
- 6.2: Missing credentials get 401 but wrong ones get 404, so a request with no credentials confirms a protected URL exists; matters most for guessable legacy bare paths
- 6.2: The "methods updated" broadcast from the inspector's create link includes each basic method's username to every collaborator in the room, viewers included, while the initial session context omits it
- 6.4: Every `/i/` request, authenticated or not, costs a trigger lookup with three preloads before any rate limit applies; the rate limiter runs only after auth

### [flow-workflow-api-edit-conflict](flows/flow-workflow-api-edit-conflict.md) (4)

- 6.1: The 409 copy says the workflow "is being edited on the App UI", but any session counts: a viewer, someone looking at an old version or a run, or the caller's own idle tab
- 6.2: Read-only sessions (viewer role, version, release and run views) hold the lock too, because presence is tracked on the workflow id whatever the view
- 6.2: The gate is check-then-act: presence is read, then the save runs with reconcile on; an editor joining in between gets the API change reconciled into its live document without the `workflow_saved` baseline refresh (same gap as flow-toggle-workflow-open-editor 6.1)
- 6.2: `track_user_presence` also subscribes the Session to the presence topic; every join and leave on the workflow lands in the Session's catch-all and is logged at debug

### [flow-workflow-health-drilldown](flows/flow-workflow-health-drilldown.md) (7)

- 6.1: A band drill-down has no work order state filter, so "Rerun all N matching" from it retries work orders already retried to success, or still running, on later pages
- 6.1: The triage and outcome counts are cached for up to 5 minutes and the link carries only the window start, so History lists work orders that failed after the row was computed; a donut link filters on the work order's state now, so one retried since the count also drops out
- 6.1: The usage limiter check on the bulk retry button counts the selected work orders on the page, not all matching ones
- 6.2: "Failed" means all six failure states on the health page and one state in History's status chip; the link spells out the six so the chip reads "Status in Failed, Crashed, Killed, Exception, Lost, Rejected"
- 6.2: The runs-chart band is a mouse-only link: the chart is `aria-hidden` and the band uses `window.open`
- 6.2: Triage rows label a job by its newest failing snapshot's name; the History chip names it from the live jobs table
- 6.4: "All matching" retry loads every matching work order into memory before chunking

### [flow-zero-persistence-channel-requests](flows/flow-zero-persistence-channel-requests.md) (5)

- 6.1: Requests stored before the switch keep their paths, headers, bodies and client IPs; nothing wipes channel requests, and the cleanup job only deletes them by history period
- 6.1: The channel logs list never reads `is_wiped`; a wiped request's "—" path is the same as an errored request's (whose path is never read)
- 6.2: A wiped request's summary shows a blank path area and "—" for client IP rather than a not-retained label; the timing section still renders
- 6.2: The wiped viewer copy is title case "No Request/Response Data here!"
- 6.2: Non-admins see admin and owner email addresses in a tooltip

### [flow-zero-persistence-runs](flows/flow-zero-persistence-runs.md) (5)

- 6.1: Under "Never retain" a cron trigger's next run picks the last unwiped final state from before the switch, and `fetch:dataclip` then wipes it, so each cron run consumes an older pre-switch state
- 6.2: The policy is captured on the run at creation: runs queued before the save still store data, and runs queued under "Never retain" stay that way if the policy is switched back before they execute
- 6.2: Retrying a work order from before the switch runs under the new policy and wipes its stored input on fetch, so it can be retried once more at most
- 6.2: Non-admins see admin and owner email addresses in a tooltip
- 6.2: Title case "No Input Data here!" and "No Output Data here!"

