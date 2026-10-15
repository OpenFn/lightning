# Changeset error codes: what was tagged with what

The record of the sweep that gave every changeset error in `lib/lightning` a
`code:` (error-format spec §6.2 and §6.3, plan D3 and D4). Line numbers are at
`7e5c724f1c`, before the sweep. `Lightning.Credo.Check.ChangesetErrorCode` keeps
new errors tagged; this file is not kept up to date after the sweep.

`add_error` rows name the line the call starts on. `validate_change` rows name
the line of the error the validator returns, which is where the code goes.

| site                                                         | call            | error                                                                             | code                   |
| ------------------------------------------------------------ | --------------- | --------------------------------------------------------------------------------- | ---------------------- |
| lib/lightning/utils/validators.ex:85                         | validate_change | message                                                                           | format                 |
| lib/lightning/utils/validators.ex:88                         | validate_change | "can't be blank"                                                                  | required               |
| lib/lightning/utils/validators.ex:117                        | validate_change | message                                                                           | format                 |
| lib/lightning/utils/validators.ex:131                        | validate_change | message                                                                           | format                 |
| lib/lightning/utils/validators.ex:213                        | add_error       | message                                                                           | exclusive              |
| lib/lightning/utils/validators.ex:231                        | add_error       | message                                                                           | required               |
| lib/lightning/utils/validators.ex:254                        | add_error       | message                                                                           | required               |
| lib/lightning/utils/validators.ex:305                        | validate_change | "is not a valid UUID"                                                             | format                 |
| lib/lightning/utils/validators.ex:326                        | validate_change | "must be either a http or https URL"                                              | format                 |
| lib/lightning/utils/validators.ex:329                        | validate_change | "host can't be blank"                                                             | format                 |
| lib/lightning/utils/validators.ex:332                        | validate_change | "host must be less than 255 characters"                                           | format                 |
| lib/lightning/utils/validators.ex:335                        | validate_change | "host has invalid characters"                                                     | format                 |
| lib/lightning/utils/validators.ex:341                        | validate_change | "must be a valid URL"                                                             | format                 |
| lib/lightning/accounts.ex:842                                | validate_change | "has not changed"                                                                 | unchanged              |
| lib/lightning/accounts.ex:855                                | validate_change | "does not match password"                                                         | mismatch               |
| lib/lightning/accounts/user.ex:203                           | validate_change | "Please accept the terms and conditions to register."                             | must_accept            |
| lib/lightning/accounts/user.ex:245                           | validate_change | "has already been taken"                                                          | taken                  |
| lib/lightning/accounts/user.ex:331                           | add_error       | "did not change"                                                                  | unchanged              |
| lib/lightning/accounts/user.ex:414                           | add_error       | "is not valid"                                                                    | mismatch               |
| lib/lightning/accounts/user.ex:420                           | add_error       | "You can't delete a superuser account."                                           | not_allowed            |
| lib/lightning/accounts/user.ex:434                           | add_error       | "This email doesn't match your current email"                                     | mismatch               |
| lib/lightning/accounts/user_totp.ex:41                       | add_error       | "invalid code"                                                                    | mismatch               |
| lib/lightning/adaptors/catalogue_adaptor.ex:127              | add_error       | "must be nil when #{ext_field} is nil"                                            | not_allowed            |
| lib/lightning/adaptors/catalogue_adaptor.ex:134              | add_error       | "must not be nil when #{ext_field} is set"                                        | required               |
| lib/lightning/ai_assistant/chat_session.ex:97                | add_error       | "must be either 'job_code' or 'workflow_template'"                                | not_allowed            |
| lib/lightning/auth_providers/auth_config_form.ex:75          | add_error       | "could not connect to discovery endpoint"                                         | discovery_failed       |
| lib/lightning/auth_providers/auth_config_form.ex:78          | add_error       | message                                                                           | discovery_failed       |
| lib/lightning/auth_providers/auth_config_form.ex:81          | add_error       | "error parsing .well-known"                                                       | discovery_failed       |
| lib/lightning/auth_providers/auth_config_form.ex:84          | add_error       | message                                                                           | discovery_failed       |
| lib/lightning/auth_providers/auth_config_form.ex:88          | add_error       | "discovery endpoint must use https"                                               | format                 |
| lib/lightning/auth_providers/auth_config_form.ex:92          | add_error       | "could not fetch the discovery document"                                          | discovery_failed       |
| lib/lightning/channels.ex:322                                | add_error       | Scoping.violation_message(:project_credential_id)                                 | credential_not_allowed |
| lib/lightning/channels/channel_auth_method.ex:78             | add_error       | "client auth must use a webhook auth method, not a project credential"            | not_allowed            |
| lib/lightning/channels/channel_auth_method.ex:89             | add_error       | "destination auth must use a project credential, not a webhook auth method"       | not_allowed            |
| lib/lightning/credentials.ex:532                             | add_error       | "the owner has no access to these projects: " <> ...                              | no_access              |
| lib/lightning/credentials.ex:580                             | add_error       | message (external id already used in the project)                                 | taken                  |
| lib/lightning/credentials.ex:708                             | add_error       | "adaptor catalogue is not ready yet, try again shortly"                           | not_ready              |
| lib/lightning/credentials.ex:715                             | add_error       | "Invalid body types"                                                              | type                   |
| lib/lightning/credentials.ex:1897                            | add_error       | "User doesn't have access to these projects: #{project_names}"                    | no_access              |
| lib/lightning/credentials.ex:1965                            | add_error       | "You cannot transfer a credential to yourself"                                    | not_allowed            |
| lib/lightning/credentials.ex:1972                            | add_error       | "User does not exist"                                                             | not_found              |
| lib/lightning/credentials/credential_body.ex:73              | validate_change | message                                                                           | too_many_secrets       |
| lib/lightning/credentials/keychain_credential.ex:66          | validate_change | message                                                                           | format                 |
| lib/lightning/credentials/keychain_credential.ex:107         | add_error       | "cannot be checked without knowing the project"                                   | required               |
| lib/lightning/credentials/keychain_credential.ex:117         | add_error       | "must belong to the same project"                                                 | not_found              |
| lib/lightning/credentials/schema.ex:189                      | add_error       | error_msg ("expected to be a URI" or "an email")                                  | format                 |
| lib/lightning/credentials/schema.ex:200                      | add_error       | "expected to be #{formatted_types}"                                               | type                   |
| lib/lightning/credentials/schema.ex:207                      | add_error       | "can't be blank"                                                                  | required               |
| lib/lightning/credentials/schema.ex:212                      | add_error       | "can't be blank"                                                                  | required               |
| lib/lightning/credentials/schema.ex:217                      | add_error       | "can't be blank"                                                                  | required               |
| lib/lightning/credentials/schema.ex:225                      | add_error       | "invalid JSON"                                                                    | type                   |
| lib/lightning/credentials/schema.ex:230                      | add_error       | "must be an object"                                                               | type                   |
| lib/lightning/credentials/scoping.ex:143                     | add_error       | violation_message(field)                                                          | credential_not_allowed |
| lib/lightning/credentials/scoping.ex:166                     | add_error       | "#{subject}: #{violation_message(field)} (#{field})"                              | credential_not_allowed |
| lib/lightning/extensions/project_hook.ex:62                  | add_error       | "#{length(remaining)} stored file(s) could not be deleted from storage"           | storage_failed         |
| lib/lightning/invocation/dataclip.ex:86                      | add_error       | "must be a map"                                                                   | type                   |
| lib/lightning/invocation/dataclip.ex:139                     | add_error       | "cannot be set for this type"                                                     | not_allowed            |
| lib/lightning/invocation/log_line.ex:69                      | add_error       | "can't be blank"                                                                  | required               |
| lib/lightning/projects/project.ex:130                        | add_error       | "cannot be self"                                                                  | not_allowed            |
| lib/lightning/projects/project.ex:262                        | add_error       | "dataclip retention period must be less or equal to the history retention period" | out_of_range           |
| lib/lightning/projects/project.ex:337                        | add_error       | "Every project must have exactly one owner. Please specify one below."            | one_owner              |
| lib/lightning/projects/project.ex:344                        | add_error       | "A project can have only one owner."                                              | one_owner              |
| lib/lightning/projects/provisioner.ex:312                    | add_error       | message (Scoping.violation_message)                                               | credential_not_allowed |
| lib/lightning/projects/provisioner.ex:318                    | add_error       | message (Scoping.violation_message)                                               | credential_not_allowed |
| lib/lightning/projects/provisioner.ex:569                    | add_error       | message (workflow activation limiter)                                             | exceeds_limit          |
| lib/lightning/projects/provisioner.ex:578                    | add_error       | message (collection creation limiter)                                             | exceeds_limit          |
| lib/lightning/projects/provisioner.ex:763                    | add_error       | "channel deletion is not supported via the provisioning API; ..."                 | not_supported          |
| lib/lightning/projects/provisioner.ex:891                    | add_error       | "extraneous parameters: %{params}"                                                | unknown_key            |
| lib/lightning/projects/provisioner.ex:919                    | add_error       | "cannot change or add a record while deleting"                                    | deleting               |
| lib/lightning/projects/provisioner.ex:935                    | add_error       | "cannot change or add a record while deleting"                                    | deleting               |
| lib/lightning/projects/provisioner.ex:982                    | add_error       | "No credential found with name #{cred_params["name"]}"                            | not_found              |
| lib/lightning/projects/provisioner.ex:1022                   | add_error       | "extraneous parameters: %{params}"                                                | unknown_key            |
| lib/lightning/runs.ex:303                                    | validate_change | "must be associated with the run"                                                 | not_found              |
| lib/lightning/runs.ex:367                                    | validate_change | "must be associated with the run"                                                 | not_found              |
| lib/lightning/runs/handlers.ex:311                           | add_error       | "does not exist"                                                                  | not_found              |
| lib/lightning/runs/handlers.ex:373                           | add_error       | "does not exist"                                                                  | not_found              |
| lib/lightning/runs/handlers.ex:394                           | add_error       | "does not exist"                                                                  | not_found              |
| lib/lightning/runs/handlers.ex:489                           | add_error       | "not found"                                                                       | not_found              |
| lib/lightning/runs/run.ex:243                                | add_error       | "cannot mark run #{to} that has not been claimed by a worker"                     | not_allowed            |
| lib/lightning/runs/run.ex:252                                | add_error       | "already in completed state"                                                      | not_allowed            |
| lib/lightning/version_control/project_repo_connection.ex:94  | validate_change | "please tick the box"                                                             | must_accept            |
| lib/lightning/version_control/project_repo_connection.ex:144 | add_error       | @tree_branch_error (was `reason:`)                                                | tree_branch_conflict   |
| lib/lightning/version_control/project_repo_connection.ex:208 | validate_change | "you must specify a path to an existing config file"                              | required               |
| lib/lightning/webhook_auth_methods.ex:680                    | add_error       | "already scheduled for deletion"                                                  | already_scheduled      |
| lib/lightning/work_orders.ex:349                             | add_error       | "cannot retry run using a wiped dataclip"                                         | dataclip_wiped         |
| lib/lightning/workflows.ex:549                               | add_error       | base_message (a rescued Ecto exception)                                           | invalid                |
| lib/lightning/workflows/edge.ex:127                          | add_error       | "source_job_id or source_trigger_id must be present"                              | required               |
| lib/lightning/workflows/edge.ex:197                          | add_error       | "target_job_id must be different from source_job_id"                              | cycle                  |
| lib/lightning/workflows/job.ex:145                           | validate_change | "adaptor has invalid format"                                                      | format                 |
| lib/lightning/workflows/job.ex:167                           | validate_change | "is not a recognised adaptor"                                                     | not_found              |
| lib/lightning/workflows/job.ex:170                           | validate_change | "adaptor catalogue is not ready yet, try again shortly"                           | not_ready              |
| lib/lightning/workflows/job.ex:193                           | add_error       | Scoping.violation_message(:keychain_credential_id)                                | credential_not_allowed |
| lib/lightning/workflows/trigger.ex:276                       | add_error       | "needs a project, which comes from the trigger's workflow"                        | required               |
| lib/lightning/workflows/trigger.ex:312                       | validate_change | "cannot be a UUID"                                                                | format                 |
| lib/lightning/workflows/trigger.ex:330                       | validate_change | error_message                                                                     | format                 |
| lib/lightning/workflows/trigger.ex:372                       | add_error       | "must only contain lowercase letters, numbers, hyphens and underscores"           | format                 |
| lib/lightning/workorders/manual.ex:42                        | validate_change | "Workflow must be saved first."                                                   | not_allowed            |
| lib/lightning/workorders/manual.ex:66                        | add_error       | "Must be an object"                                                               | type                   |
| lib/lightning/workorders/manual.ex:67                        | add_error       | "Invalid JSON"                                                                    | type                   |
| lib/lightning/workorders/manual.ex:82                        | add_error       | "does not belong to this project"                                                 | not_found              |

Two sites carry no code of their own, and the check is disabled on each. In
`lib/lightning/credentials.ex`, `handle_transaction_result/2` re-adds a
credential body's errors onto the credential, and `cast_credential_body_change`
re-adds a typed body's schema errors onto the body. Both keep the options
unchanged, so each error keeps the code its producer gave it, and add `key:` to
place it in the request.

## Added with the credentials API's problem answers

OAuth token refusals are not changeset errors where they are made. Each
`Lightning.Credentials.OauthValidation.Error` carries `code:` and the token
`field:` it is about, and `validate_credential_bodies` in
`lib/lightning/credentials.ex` adds it to the credential at
`#/credential_bodies/<i>/body/<field>`. The message is the entry's detail, so
none quotes a value from the token.

| type                     | field         | code              | message                                                                                                        |
| ------------------------ | ------------- | ----------------- | -------------------------------------------------------------------------------------------------------------- |
| `invalid_token_format`   | (the body)    | type              | "OAuth token must be a valid map"                                                                              |
| `invalid_token_format`   | token_type    | type              | "token_type must be a string"                                                                                  |
| `missing_access_token`   | access_token  | required          | "Missing required OAuth field: access_token"                                                                   |
| `invalid_access_token`   | access_token  | type              | "access_token must be a non-empty string"                                                                      |
| `invalid_access_token`   | access_token  | required          | "access_token cannot be empty"                                                                                 |
| `missing_refresh_token`  | refresh_token | required          | "Missing required OAuth field: refresh_token"                                                                  |
| `invalid_refresh_token`  | refresh_token | type              | "refresh_token must be a non-empty string"                                                                     |
| `invalid_refresh_token`  | refresh_token | required          | "refresh_token cannot be empty"                                                                                |
| `missing_token_type`     | token_type    | required          | "Missing required OAuth field: token_type"                                                                     |
| `unsupported_token_type` | token_type    | not_allowed       | "Unsupported token type. Expected 'Bearer'"                                                                    |
| `missing_scope`          | scope         | required          | "Missing required OAuth field: scope or scopes"; "scope field cannot be empty"                                 |
| `missing_scope`          | scopes        | required          | "scopes array cannot be empty"                                                                                 |
| `invalid_oauth_response` | scope         | type              | "scope must be a string"                                                                                       |
| `invalid_oauth_response` | scope         | required          | "OAuth token missing scope information"                                                                        |
| `invalid_oauth_response` | scopes        | type              | "scopes must be a list"; "scopes array must contain only strings"                                              |
| `missing_expiration`     | expires_in    | required          | "Missing expiration field: either expires_in or expires_at is required"                                        |
| `invalid_expiration`     | expires_in    | out_of_range      | "expires_in must be greater than 0 seconds"; "expires_in seems unreasonably long"                              |
| `invalid_expiration`     | expires_in    | type              | "expires_in string must represent a valid positive integer"; "expires_in must be a positive integer (seconds)" |
| `invalid_expiration`     | expires_at    | out_of_range      | "expires_at timestamp appears to be too far in the past (possible clock skew)"; "... too far in the future"    |
| `invalid_expiration`     | expires_at    | format            | "expires_at must be a Unix timestamp or ISO 8601 date string"                                                  |
| `invalid_expiration`     | expires_at    | type              | "expires_at must be an integer timestamp or date string"                                                       |
| `missing_scopes`         | scope         | scope_not_granted | "Missing required scopes. Please reauthorize and grant all selected permissions."                              |
