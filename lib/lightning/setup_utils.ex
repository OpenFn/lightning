defmodule Lightning.SetupUtils do
  @moduledoc """
  SetupUtils encapsulates logic for setting up initial data for various sites.
  """
  import Ecto.Query
  import Ecto.Changeset

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Credentials
  alias Lightning.Jobs
  alias Lightning.OauthClients
  alias Lightning.Projects
  alias Lightning.Repo
  alias Lightning.Runs
  alias Lightning.Workflows
  alias Lightning.WorkOrders

  defmodule Ticker do
    @moduledoc """
    Time ticker to assure time progress/sequence specially for multiple logs.
    """
    use Agent

    def start_link(%DateTime{} = start_time) do
      Agent.start_link(fn -> start_time end)
    end

    def next(ticker) do
      Agent.get_and_update(ticker, fn time ->
        increment = :rand.uniform(4) + 1
        next = DateTime.add(time, increment, :millisecond)
        {next, next}
      end)
    end

    def stop(pid) do
      Agent.stop(pid)
    end
  end

  @spec setup_demo(nil | maybe_improper_list | map) :: %{
          jobs: [...],
          oauth_clients: map(),
          projects: [atom | %{:id => any, optional(any) => any}, ...],
          users: [atom | %{:id => any, optional(any) => any}, ...],
          workflows: [atom | %{:id => any, optional(any) => any}, ...],
          workorders: [atom | %{:id => any, optional(any) => any}, ...]
        }
  @doc """
  Creates initial data and returns the created records.
  """
  def setup_demo(opts \\ [create_super: false]) do
    %{super_user: super_user, admin: admin, editor: editor, viewer: viewer} =
      create_users(opts) |> confirm_users()

    # Create demo OAuth clients owned by super user if available, otherwise admin
    oauth_clients = create_demo_oauth_clients(super_user || admin)

    %{
      project: openhie_project,
      workflow: openhie_workflow,
      jobs: openhie_jobs,
      workorder: openhie_workorder
    } =
      create_openhie_project([
        %{user_id: super_user.id, role: :owner},
        %{user_id: admin.id, role: :admin},
        %{user_id: editor.id, role: :editor},
        %{user_id: viewer.id, role: :viewer}
      ])

    %{
      project: dhis2_project,
      workflow: dhis2_workflow,
      jobs: dhis2_jobs,
      workorders: [failure_dhis2_workorder]
    } =
      create_dhis2_project([
        %{user_id: admin.id, role: :owner}
      ])

    %{
      jobs: openhie_jobs ++ dhis2_jobs,
      users: [super_user, admin, editor, viewer],
      projects: [openhie_project, dhis2_project],
      workflows: [openhie_workflow, dhis2_workflow],
      workorders: [
        openhie_workorder,
        failure_dhis2_workorder
      ],
      oauth_clients: oauth_clients
    }
  end

  defp to_log_lines(log) do
    log
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.map(fn {log, index} ->
      %{
        message: log,
        timestamp: DateTime.utc_now() |> DateTime.add(index, :millisecond)
      }
    end)
  end

  defp create_dhis2_credential(%Accounts.User{id: user_id}) do
    {:ok, credential} =
      Credentials.create_credential(%{
        body: %{
          username: "admin",
          password: "district",
          hostUrl: "https://play.dhis2.org/dev"
        },
        name: "DHIS2 play",
        user_id: user_id,
        schema: "dhis2"
      })

    credential
  end

  @doc """
  Creates demo OAuth clients for Google (Drive, Sheets, Gmail), Salesforce, and Microsoft
  (SharePoint, Outlook, Calendar, OneDrive, Teams).

  These are global OAuth clients that can be used across all projects.
  Client IDs and secrets are read from application configuration (set via environment
  variables in `config/runtime.exs`), falling back to dummy placeholder values for
  development/testing.

  ## Environment Variables

  Each service reads from two environment variables:
  - `{SERVICE}_CLIENT_ID` - The OAuth client ID
  - `{SERVICE}_CLIENT_SECRET` - The OAuth client secret

  Where `{SERVICE}` is one of:
  - `GOOGLE_DRIVE`, `GOOGLE_SHEETS`, `GMAIL`
  - `SALESFORCE`
  - `MICROSOFT_SHAREPOINT`, `MICROSOFT_OUTLOOK`, `MICROSOFT_CALENDAR`,
    `MICROSOFT_ONEDRIVE`, `MICROSOFT_TEAMS`

  ## Parameters
  - user: The user who will own the OAuth clients.

  ## Returns
  - A map containing the created OAuth clients keyed by provider name.
  """
  def create_demo_oauth_clients(%Accounts.User{id: user_id}) do
    oauth_clients = [
      # Google services
      google_oauth_client(
        "Google Drive",
        :google_drive,
        "openid,https://www.googleapis.com/auth/userinfo.email,https://www.googleapis.com/auth/userinfo.profile,https://www.googleapis.com/auth/drive",
        user_id
      ),
      google_oauth_client(
        "Google Sheets",
        :google_sheets,
        "openid,https://www.googleapis.com/auth/userinfo.email,https://www.googleapis.com/auth/userinfo.profile,https://www.googleapis.com/auth/spreadsheets",
        user_id
      ),
      google_oauth_client(
        "Gmail",
        :gmail,
        "openid,https://www.googleapis.com/auth/userinfo.email,https://www.googleapis.com/auth/userinfo.profile,https://www.googleapis.com/auth/gmail.readonly,https://www.googleapis.com/auth/gmail.send",
        user_id
      ),
      # Salesforce
      salesforce_oauth_client(
        "Salesforce",
        :salesforce,
        "login.salesforce.com",
        user_id
      ),
      salesforce_oauth_client(
        "Salesforce Sandbox",
        :salesforce_sandbox,
        "test.salesforce.com",
        user_id
      ),
      # Microsoft services
      microsoft_oauth_client(
        "Microsoft SharePoint",
        :microsoft_sharepoint,
        "openid,email,profile,offline_access,Sites.Read.All,Sites.ReadWrite.All",
        user_id
      ),
      microsoft_oauth_client(
        "Microsoft Outlook",
        :microsoft_outlook,
        "openid,email,profile,offline_access,Mail.Read,Mail.Send",
        user_id
      ),
      microsoft_oauth_client(
        "Microsoft Calendar",
        :microsoft_calendar,
        "openid,email,profile,offline_access,Calendars.Read,Calendars.ReadWrite",
        user_id
      ),
      microsoft_oauth_client(
        "Microsoft OneDrive",
        :microsoft_onedrive,
        "openid,email,profile,offline_access,Files.Read,Files.ReadWrite",
        user_id
      ),
      microsoft_oauth_client(
        "Microsoft Teams",
        :microsoft_teams,
        "openid,email,profile,offline_access,Team.ReadBasic.All,Channel.ReadBasic.All,Chat.Read",
        user_id
      )
    ]

    oauth_clients
    |> Enum.reduce(%{}, fn client_attrs, acc ->
      {:ok, client} = OauthClients.create_client(client_attrs)

      key =
        client_attrs.name
        |> String.downcase()
        |> String.replace(" ", "_")
        |> String.to_atom()

      Map.put(acc, key, client)
    end)
  end

  defp google_oauth_client(name, config_key, mandatory_scopes, user_id) do
    {client_id, client_secret} = get_oauth_credentials(config_key)

    %{
      name: name,
      client_id: client_id,
      client_secret: client_secret,
      authorization_endpoint: "https://accounts.google.com/o/oauth2/v2/auth",
      token_endpoint: "https://oauth2.googleapis.com/token",
      revocation_endpoint: "https://oauth2.googleapis.com/revoke",
      userinfo_endpoint: "https://openidconnect.googleapis.com/v1/userinfo",
      scopes_doc_url:
        "https://developers.google.com/identity/protocols/oauth2/scopes",
      mandatory_scopes: mandatory_scopes,
      global: true,
      user_id: user_id
    }
  end

  defp salesforce_oauth_client(name, config_key, domain, user_id) do
    {client_id, client_secret} = get_oauth_credentials(config_key)

    %{
      name: name,
      client_id: client_id,
      client_secret: client_secret,
      authorization_endpoint: "https://#{domain}/services/oauth2/authorize",
      token_endpoint: "https://#{domain}/services/oauth2/token",
      revocation_endpoint: "https://#{domain}/services/oauth2/revoke",
      userinfo_endpoint: "https://#{domain}/services/oauth2/userinfo",
      scopes_doc_url:
        "https://help.salesforce.com/s/articleView?id=sf.remoteaccess_oauth_tokens_scopes.htm",
      mandatory_scopes: "openid,api,refresh_token,full",
      global: true,
      user_id: user_id
    }
  end

  defp microsoft_oauth_client(name, config_key, mandatory_scopes, user_id) do
    {client_id, client_secret} = get_oauth_credentials(config_key)

    %{
      name: name,
      client_id: client_id,
      client_secret: client_secret,
      authorization_endpoint:
        "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
      token_endpoint:
        "https://login.microsoftonline.com/common/oauth2/v2.0/token",
      revocation_endpoint:
        "https://login.microsoftonline.com/common/oauth2/v2.0/logout",
      userinfo_endpoint: "https://graph.microsoft.com/oidc/userinfo",
      scopes_doc_url:
        "https://learn.microsoft.com/en-us/entra/identity-platform/scopes-oidc",
      mandatory_scopes: mandatory_scopes,
      global: true,
      user_id: user_id
    }
  end

  defp get_oauth_credentials(config_key) do
    default_id = "demo-#{config_key}-client-id"
    default_secret = "demo-#{config_key}-client-secret"

    config = Application.get_env(:lightning, :demo_oauth_clients, [])
    client_config = Keyword.get(config, config_key, [])

    client_id = Keyword.get(client_config, :client_id) || default_id
    client_secret = Keyword.get(client_config, :client_secret) || default_secret

    {client_id, client_secret}
  end

  def create_users(opts) do
    super_user =
      if opts[:create_super] do
        {:ok, super_user} =
          Accounts.register_superuser(%{
            first_name: "Sizwe",
            last_name: "Super",
            email: "super@openfn.org",
            password: "welcome12345"
          })

        Repo.insert!(%Lightning.Accounts.UserToken{
          user_id: super_user.id,
          context: "api",
          token:
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJKb2tlbiIsImlhdCI6MTY4ODAzNzE4NSwiaXNzIjoiSm9rZW4iLCJqdGkiOiIydG1ocG8zYm0xdmR0MDZvZDgwMDAwdTEiLCJuYmYiOjE2ODgwMzcxODUsInVzZXJfaWQiOiIzZjM3OGU2Yy02NjBhLTRiOTUtYWI5Ni02YmQwZGMyNjNkMzMifQ.J1FnACGpqtQbmXNvyUCwCY4mS5S6CohRU3Ey-N0prP4"
        })

        super_user
      else
        nil
      end

    {:ok, admin} =
      Accounts.create_user(%{
        first_name: "Amy",
        last_name: "Admin",
        email: "demo@openfn.org",
        password: "welcome12345"
      })

    {:ok, editor} =
      Accounts.create_user(%{
        first_name: "Esther",
        last_name: "Editor",
        email: "EditOr@openfn.org",
        password: "welcome12345"
      })

    {:ok, viewer} =
      Accounts.create_user(%{
        first_name: "Vikram",
        last_name: "Viewer",
        email: "viewer@openfn.org",
        password: "welcome12345"
      })

    %{super_user: super_user, admin: admin, editor: editor, viewer: viewer}
  end

  def confirm_users(users) do
    confirm_user = fn user ->
      case user do
        nil ->
          :ok

        _ ->
          User.confirm_changeset(user)
          |> Repo.update!()
      end
    end

    users
    |> Map.values()
    |> Enum.each(confirm_user)

    users
  end

  def create_starter_project(name, project_users, with_workflow \\ false) do
    {:ok, project} =
      Projects.create_project(
        %{
          name: name,
          history_retention_period:
            Application.get_env(:lightning, :default_retention_period),
          project_users: project_users
        },
        false
      )

    if with_workflow do
      user = get_most_privileged_user!(project)

      {:ok, workflow} =
        Workflows.save_workflow(
          %{
            name: "Sample Workflow",
            project_id: project.id
          },
          user
        )

      {:ok, source_trigger} =
        Workflows.build_trigger(%{
          type: :webhook,
          workflow_id: workflow.id
        })

      {:ok, job_1} =
        Jobs.create_job(
          %{
            name: "Job 1 - Check if age is over 18 months",
            body: """
              fn(state => {
                if (state.data.age_in_months > 18) {
                  console.log('Eligible for program.');
                  return state;
                }
                else { throw 'Error, patient ineligible.' }
              });
            """,
            adaptor: "@openfn/language-common@latest",
            workflow_id: workflow.id
          },
          user
        )

      {:ok, _root_edge} =
        Workflows.create_edge(
          %{
            workflow_id: workflow.id,
            condition_type: :always,
            source_trigger: source_trigger,
            target_job: job_1,
            enabled: true
          },
          user
        )

      {:ok, job_2} =
        Jobs.create_job(
          %{
            name: "Job 2 - Convert data to DHIS2 format",
            body: """
              fn(state => {
                const names = state.data.name.split(' ');
                return { ...state, names };
              });
            """,
            adaptor: "@openfn/language-common@latest",
            workflow_id: workflow.id
          },
          user
        )

      {:ok, _job_2_edge} =
        Workflows.create_edge(
          %{
            workflow_id: workflow.id,
            source_job: job_1,
            condition_type: :on_job_success,
            target_job: job_2,
            enabled: true
          },
          user
        )

      dhis2_credential = create_dhis2_credential(user)

      {:ok, job_3} =
        Workflows.Job.changeset(%Workflows.Job{}, %{
          name: "Job 3 - Upload to DHIS2",
          body: """
            create('trackedEntityInstances', {
              trackedEntityType: 'nEenWmSyUEp', // a person
              orgUnit: 'DiszpKrYNg8',
              attributes: [
                {
                  attribute: 'w75KJ2mc4zz', // attribute id for first name
                  value: state.names[0] // the first name from submission
                },
                {
                  attribute: 'zDhUuAYrxNC', // attribute id for last name
                  value: state.names[1] // the last name from submission
                }
              ]
            });
          """,
          adaptor: "@openfn/language-dhis2@latest",
          workflow_id: workflow.id
        })
        |> put_assoc(:project_credential, %{
          project: project,
          credential: dhis2_credential
        })
        |> Repo.insert()

      {:ok, _job_3_edge} =
        Workflows.create_edge(
          %{
            workflow_id: workflow.id,
            source_job: job_2,
            condition_type: :on_job_success,
            target_job: job_3,
            enabled: true
          },
          user
        )

      %{
        project: project,
        workflow: workflow,
        jobs: [job_1, job_2, job_3]
      }
    else
      %{
        project: project,
        workflow: nil,
        jobs: []
      }
    end
  end

  def create_openhie_project(project_users) do
    {:ok, openhie_project} =
      Projects.create_project(
        %{
          name: "openhie-project",
          id: "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa",
          project_users: project_users
        },
        false
      )

    user = get_most_privileged_user!(openhie_project)

    {:ok, openhie_workflow} =
      Workflows.save_workflow(
        %{
          name: "OpenHIE Workflow",
          project_id: openhie_project.id
        },
        user
      )

    {:ok, openhie_trigger} =
      Workflows.build_trigger(%{
        type: :webhook,
        # Id is hard-coded to support external test scripts (e.g. benchmarking/script.js)
        id: "cae544ab-03dc-4ccc-a09c-fb4edb255d7a",
        workflow_id: openhie_workflow.id
      })

    {:ok, fhir_standard_data} =
      Jobs.create_job(
        %{
          name: "Transform data to FHIR standard",
          # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
          inserted_at: NaiveDateTime.utc_now(),
          body: """
          fn(state => state);
          """,
          adaptor: "@openfn/language-http@latest",
          workflow_id: openhie_workflow.id
        },
        user
      )

    {:ok, _openhie_root_edge} =
      Workflows.create_edge(
        %{
          workflow_id: openhie_workflow.id,
          condition_type: :always,
          source_trigger: openhie_trigger,
          target_job: fhir_standard_data,
          enabled: true
        },
        user
      )

    {:ok, send_to_openhim} =
      Jobs.create_job(
        %{
          name: "Send to OpenHIM to route to SHR",
          # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
          inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(1, :second),
          body: """
          fn(state => state);
          """,
          adaptor: "@openfn/language-http@latest",
          # enabled: true,
          workflow_id: openhie_workflow.id
        },
        user
      )

    {:ok, notify_upload_successful} =
      Jobs.create_job(
        %{
          name: "Notify CHW upload successful",
          # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
          inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(2, :second),
          body: """
          fn(state => state);
          """,
          adaptor: "@openfn/language-http@latest",
          # enabled: true,
          workflow_id: openhie_workflow.id
        },
        user
      )

    {:ok, notify_upload_failed} =
      Jobs.create_job(
        %{
          name: "Notify CHW upload failed",
          # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
          inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(3, :second),
          body: """
          fn(state => state);
          """,
          adaptor: "@openfn/language-http@latest",
          # enabled: true,
          workflow_id: openhie_workflow.id
        },
        user
      )

    {:ok, _send_to_openhim_edge} =
      Workflows.create_edge(
        %{
          workflow_id: openhie_workflow.id,
          condition_type: :on_job_success,
          target_job_id: send_to_openhim.id,
          source_job_id: fhir_standard_data.id,
          enabled: true
        },
        user
      )

    {:ok, _success_upload} =
      Workflows.create_edge(
        %{
          workflow_id: openhie_workflow.id,
          condition_type: :on_job_success,
          target_job_id: notify_upload_successful.id,
          source_job_id: send_to_openhim.id,
          enabled: true
        },
        user
      )

    {:ok, _failed_upload} =
      Workflows.create_edge(
        %{
          workflow_id: openhie_workflow.id,
          condition_type: :on_job_failure,
          target_job_id: notify_upload_failed.id,
          source_job_id: send_to_openhim.id,
          enabled: true
        },
        user
      )

    http_body = %{
      "formId" => "early_enrollment",
      "patientId" => 1234,
      "patientData" => %{"name" => "Wally", "surname" => "Robertson"}
    }

    dataclip =
      create_dataclip(%{
        body: %{data: http_body},
        project_id: openhie_project.id,
        type: :http_request
      })

    step_params = [
      %{
        job_id: fhir_standard_data.id,
        exit_reason: "success",
        log_lines:
          to_log_lines("""
          -- THIS IS ONLY A SAMPLE --
          [CLI] ℹ Versions:
               ▸ node.js                  18.12.0
               ▸ cli                      0.0.32
               ▸ runtime                  0.0.20
               ▸ compiler                 0.0.26
               ▸ @openfn/language-http    4.2.6
          [CLI] ✔ Loaded state from /tmp/state-1686840746-126941-1hou2fm.json
          [CLI] ℹ Loaded typedefs for @openfn/language-http@latest
          [CLI] ℹ Loaded typedefs for @openfn/language-http@latest
          [CMP] ℹ Added import statement for @openfn/language-http
          [CMP] ℹ Added export * statement for @openfn/language-http
          [CLI] ✔ Compiled job from /tmp/expression-1686840746-126941-1wuk06h.js
          [R/T] ℹ Resolved adaptor @openfn/language-http to version 4.2.6
          [R/T] ✔ Operation 1 complete in 0ms
          [CLI] ✔ Writing output to /tmp/output-1686840746-126941-i2yb2g.json
          [CLI] ✔ Done in 223ms! ✨
          """),
        input_dataclip_id: dataclip.id,
        output_dataclip: %{data: http_body, references: []} |> Jason.encode!()
      },
      %{
        job_id: send_to_openhim.id,
        exit_reason: "success",
        log_lines:
          to_log_lines("""
          -- THIS IS ONLY A SAMPLE --
          [CLI] ℹ Versions:
               ▸ node.js                  18.12.0
               ▸ cli                      0.0.32
               ▸ runtime                  0.0.20
               ▸ compiler                 0.0.26
               ▸ @openfn/language-http    4.2.6
          [CLI] ✔ Loaded state from /tmp/state-1686840746-126941-1hou2fm.json
          [CLI] ℹ Loaded typedefs for @openfn/language-http@latest
          [CMP] ℹ Added import statement for @openfn/language-http
          [CMP] ℹ Added export * statement for @openfn/language-http
          [CLI] ✔ Compiled job from /tmp/expression-1686840746-126941-1wuk06h.js
          [R/T] ℹ Resolved adaptor @openfn/language-http to version 4.2.6
          [R/T] ✔ Operation 1 complete in 0ms
          [CLI] ✔ Writing output to /tmp/output-1686840746-126941-i2yb2g.json
          [CLI] ✔ Done in 223ms! ✨
          """),
        output_dataclip: %{data: http_body, references: []} |> Jason.encode!()
      },
      %{
        job_id: notify_upload_successful.id,
        exit_reason: "success",
        log_lines:
          to_log_lines("""
          -- THIS IS ONLY A SAMPLE --
          [CLI] ℹ Versions:
               ▸ node.js                  18.12.0
               ▸ cli                      0.0.32
               ▸ runtime                  0.0.20
               ▸ compiler                 0.0.26
               ▸ @openfn/language-http    4.2.6
          [CLI] ✔ Loaded state from /tmp/state-1686840747-126941-n44hwo.json
          [CLI] ℹ Loaded typedefs for @openfn/language-http@latest
          [CMP] ℹ Added import statement for @openfn/language-http
          [CMP] ℹ Added export * statement for @openfn/language-http
          [CLI] ✔ Compiled job from /tmp/expression-1686840747-126941-1qi9xrb.js
          [R/T] ℹ Resolved adaptor @openfn/language-http to version 4.2.6
          [R/T] ✔ Operation 1 complete in 0ms
          [CLI] ✔ Writing output to /tmp/output-1686840747-126941-16ewhef.json
          [CLI] ✔ Done in 209ms! ✨
          """),
        output_dataclip: %{data: http_body, references: []} |> Jason.encode!()
      }
    ]

    {:ok, openhie_workorder} =
      create_workorder(
        openhie_workflow,
        openhie_trigger,
        dataclip,
        step_params
      )

    %{
      project: openhie_project,
      workflow: openhie_workflow,
      workorder: openhie_workorder,
      jobs: [
        fhir_standard_data,
        send_to_openhim,
        notify_upload_successful,
        notify_upload_failed
      ]
    }
  end

  def create_dhis2_project(project_users) do
    {:ok, project} =
      Projects.create_project(
        %{
          name: "dhis2-project",
          project_users: project_users
        },
        false
      )

    user = get_most_privileged_user!(project)

    {:ok, dhis2_workflow} =
      Workflows.save_workflow(
        %{
          name: "DHIS2 to Sheets",
          project_id: project.id
        },
        user
      )

    dhis2_credential = create_dhis2_credential(user)

    {:ok, get_dhis2_data} =
      Workflows.Job.changeset(%Workflows.Job{}, %{
        name: "Get DHIS2 data",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: NaiveDateTime.utc_now(),
        body: """
        get('trackedEntityInstances/PQfMcpmXeFE');
        """,
        adaptor: "@openfn/language-dhis2@latest",
        # enabled: true,
        workflow_id: dhis2_workflow.id
      })
      |> put_assoc(:project_credential, %{
        project: project,
        credential: dhis2_credential
      })
      |> Repo.insert()

    {:ok, dhis_trigger} =
      Workflows.build_trigger(%{
        type: :cron,
        cron_expression: "0 * * * *",
        workflow_id: dhis2_workflow.id
      })

    {:ok, _root_edge} =
      Workflows.create_edge(
        %{
          workflow_id: dhis2_workflow.id,
          condition_type: :always,
          source_trigger: dhis_trigger,
          target_job: get_dhis2_data,
          enabled: true
        },
        user
      )

    {:ok, upload_to_google_sheet} =
      Jobs.create_job(
        %{
          name: "Upload to Google Sheet",
          # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
          inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(1, :second),
          body: """
          fn(state => state);
          """,
          adaptor: "@openfn/language-http@latest",
          # enabled: true,
          workflow_id: dhis2_workflow.id
        },
        user
      )

    {:ok, _success_upload} =
      Workflows.create_edge(
        %{
          workflow_id: dhis2_workflow.id,
          condition_type: :on_job_success,
          target_job_id: upload_to_google_sheet.id,
          source_job_id: get_dhis2_data.id,
          enabled: true
        },
        user
      )

    input_dataclip =
      create_dataclip(%{
        body: %{
          data: %{
            attributes: [
              %{
                attribute: "zDhUuAYrxNC",
                created: "2016-08-03T23:49:43.309",
                displayName: "Last name",
                lastUpdated: "2016-08-03T23:49:43.309",
                value: "Kelly",
                valueType: "TEXT"
              },
              %{
                attribute: "w75KJ2mc4zz",
                code: "MMD_PER_NAM",
                created: "2016-08-03T23:49:43.308",
                displayName: "First name",
                lastUpdated: "2016-08-03T23:49:43.308",
                value: "John",
                valueType: "TEXT"
              }
            ],
            created: "2014-03-06T05:49:28.256",
            createdAtClient: "2014-03-06T05:49:28.256",
            lastUpdated: "2016-08-03T23:49:43.309",
            orgUnit: "DiszpKrYNg8",
            trackedEntityInstance: "PQfMcpmXeFE",
            trackedEntityType: "nEenWmSyUEp"
          },
          references: [
            %{}
          ]
        },
        project_id: project.id,
        type: :http_request
      })

    # Make it fail for demo purposes
    step_params = [
      %{
        job_id: get_dhis2_data.id,
        exit_reason: "success",
        log_lines:
          to_log_lines("""
            -- THIS IS ONLY A SAMPLE --
            [CLI] ✔ Compiled job from /tmp/expression-1686836010-94749-1cn5qct.js
            [R/T] ℹ Resolved adaptor @openfn/language-dhis2@latest to version 3.2.11
            [R/T] ✔ Operation 1 complete in 0ms
            [CLI] ✔ Writing output to /tmp/output-1686836010-94749-1v3ppcw.json
            [CLI] ✔ Done in 179ms! ✨
            -- THIS IS ONLY A SAMPLE --
            [CLI] ℹ Versions:
                 ▸ node.js                   18.12.0
                 ▸ cli                       0.0.32
                 ▸ runtime                   0.0.20
                 ▸ compiler                  0.0.26
                 ▸ @openfn/language-dhis2@latest            3.2.11
            [CLI] ✔ Loaded state from /tmp/state-1686836010-94749-17tka8f.json
            [CLI] ℹ Loaded typedefs for @openfn/language-dhis2@latest
            [CMP] ℹ Added import statement for @openfn/language-dhis2@latest
            [CMP] ℹ Added export * statement for @openfn/language-dhis2@latest
          """),
        input_dataclip_id: input_dataclip.id,
        output_dataclip:
          %{
            data: %{
              spreadsheetId: "wv5ftwhte",
              tableRange: "A3:D3",
              updates: %{
                updatedCells: 4
              }
            },
            references: [
              %{}
            ]
          }
          |> Jason.encode!()
      },
      %{
        job_id: upload_to_google_sheet.id,
        exit_reason: "fail",
        log_lines:
          to_log_lines("""
          -- THIS IS ONLY A SAMPLE --
          [CLI] ℹ Versions:
               ▸ @openfn/language-http    4.2.8
               ▸ compiler                 0.0.29
               ▸ runtime                  0.0.21
               ▸ cli                      0.0.35
               ▸ node.js                  18.12.0
          [CLI] ✔ Loaded state from /var/folders/v9/rvycxf0j6kx8py3m2bw8d1gr0000gn/T/state-1686240004-30184-1qywkh4.json
          [CLI] ℹ Added import statement for @openfn/language-http
          [CLI] ℹ Added export * statement for @openfn/language-http
          [CLI] ✔ Compiled job from /var/folders/v9/rvycxf0j6kx8py3m2bw8d1gr0000gn/T/expression-1686240004-30184-sd2j6r.js
          [R/T] ℹ Resolved adaptor @openfn/language-http to version 4.2.8
          [CLI] ✘ Error: 503 Service Unavailable, please try again later
          [CLI] ✘ Took 1.634s.
          """)
      }
    ]

    {:ok, failure_dhis2_workorder} =
      create_workorder(
        dhis2_workflow,
        dhis_trigger,
        input_dataclip,
        step_params
      )

    %{
      project: project,
      workflow: dhis2_workflow,
      workorders: [failure_dhis2_workorder],
      jobs: [get_dhis2_data, upload_to_google_sheet]
    }
  end

  def tear_down(opts \\ [destroy_super: false]) do
    delete_other_tables([
      "oban_jobs",
      "oban_peers",
      "trigger_webhook_auth_methods"
    ])

    delete_all_entities([
      Lightning.Run,
      Lightning.RunStep,
      Lightning.AuthProviders.AuthConfig,
      Lightning.Auditing.Audit,
      Lightning.Projects.ProjectCredential,
      Lightning.WorkOrder,
      Lightning.Invocation.Step,
      Lightning.Credentials.Credential,
      Lightning.KafkaTriggers.TriggerKafkaMessageRecord,
      Lightning.Workflows.Job,
      Lightning.Workflows.Trigger,
      Lightning.Workflows.WebhookAuthMethod,
      Lightning.Workflows.Workflow,
      Lightning.Projects.ProjectUser,
      Lightning.Invocation.Dataclip,
      Lightning.Projects.File,
      Lightning.Projects.ProjectOauthClient,
      Lightning.Credentials.OauthClient,
      Lightning.Projects.Project,
      Lightning.Collaboration.DocumentState
    ])

    if opts[:destroy_super] do
      Repo.delete_all(Lightning.Accounts.User)
    else
      from(u in Lightning.Accounts.User, where: u.role != :superuser)
      |> Repo.all()
      |> Enum.each(fn user -> Lightning.Accounts.delete_user(user) end)
    end
  end

  defp delete_all_entities(entities),
    do: Enum.each(entities, fn entity -> Repo.delete_all(entity) end)

  defp delete_other_tables(tables_names) do
    Enum.each(tables_names, fn name ->
      Ecto.Adapters.SQL.query!(Repo, "DELETE FROM #{name}")
    end)
  end

  defp create_workorder(
         workflow,
         trigger,
         input_dataclip,
         step_params
       ) do
    workflow |> Repo.preload(:project)
    {:ok, ticker} = Ticker.start_link(DateTime.utc_now())

    workorder =
      Repo.transaction(fn ->
        workorder =
          %{runs: [run]} =
          WorkOrders.build_for(trigger, %{
            workflow: workflow,
            dataclip: input_dataclip
          })
          |> then(fn changeset ->
            [run] = changeset |> get_change(:runs)

            put_change(changeset, :runs, [
              run
              |> change(%{state: :claimed, claimed_at: Ticker.next(ticker)})
            ])
          end)
          |> Repo.insert!()

        Runs.start_run(run)

        _steps =
          step_params
          |> Enum.reduce(%{}, fn step, previous ->
            step_id = Ecto.UUID.generate()

            input_dataclip_id =
              Map.get(
                step,
                :input_dataclip_id,
                Map.get(previous, :output_dataclip_id, input_dataclip.id)
              )

            Runs.start_step(run, %{
              step_id: step_id,
              job_id: step.job_id,
              input_dataclip_id: input_dataclip_id,
              started_at: Ticker.next(ticker)
            })

            step.log_lines
            |> Enum.each(fn line ->
              Runs.append_run_log(run, %{
                step_id: step_id,
                message: line.message,
                timestamp: Ticker.next(ticker)
              })
            end)

            complete_step_params =
              %{
                run_id: run.id,
                project_id: workflow.project_id,
                step_id: step_id,
                reason: step.exit_reason,
                finished_at: Ticker.next(ticker)
              }
              |> Map.merge(
                if step[:output_dataclip] do
                  %{
                    output_dataclip_id: Ecto.UUID.generate(),
                    output_dataclip: step.output_dataclip
                  }
                else
                  %{}
                end
              )

            {:ok, step} = Runs.complete_step(complete_step_params)

            step
          end)

        state =
          List.last(step_params)
          |> Map.get(:exit_reason)
          |> case do
            "fail" -> "failed"
            reason -> reason
          end

        {:ok, _} = Runs.complete_run(run, %{state: state})

        workorder
      end)

    Ticker.stop(ticker)

    workorder
  end

  defp create_dataclip(params) do
    {:ok, dataclip} = Lightning.Invocation.create_dataclip(params)

    dataclip
  end

  defp get_most_privileged_user!(project) do
    role_ordering_query =
      from(
        s in fragment(
          "SELECT * FROM UNNEST(?::varchar[]) WITH ORDINALITY o(role, ord)",
          ~w[owner admin editor viewer]
        ),
        select: %{role: s.role, ord: s.ord}
      )

    Ecto.assoc(project, :project_users)
    |> join(:inner, [pu], o in ^role_ordering_query, on: pu.role == o.role)
    |> join(:inner, [pu], u in assoc(pu, :user))
    |> order_by([pu, o], asc: o.ord)
    |> select([pu, _o, u], u)
    |> limit(1)
    |> Repo.one!()
  end

  @doc """
  In some (mostly remote-controlled) deployments, it's necessary to create a
  user, and apiToken, and multiple credentials (owned by the user) so that later
  `openfn deploy` calls can make use of these artifacts.

  When run _before_ `openfn deploy`, this function makes it possible to set up
  an entire lightning instance with a working project (including secrets)
  without using the web UI.

  ## Examples

    iex> setup_user(%{email: "td@openfn.org", first_name: "taylor", last_name: "downs", password: "shh12345!"}, "secretToken", [%{name: "openmrs", schema: "raw", body: %{"a" => "secret"}}, %{ name: "dhis2", schema: "raw", body: %{"b" => "safe"}}])
    :ok

  """
  @spec setup_user(map(), String.t() | nil, list(map()) | nil) ::
          :ok | {:error, any()}
  def setup_user(user, token \\ nil, credentials \\ nil) do
    {role, user} = Map.pop(user, :role)

    Repo.transaction(fn ->
      # create user
      {:ok, user} =
        if role == :superuser,
          do: Accounts.register_superuser(user),
          else: Accounts.create_user(user)

      # create token
      if token,
        do:
          Repo.insert!(%Lightning.Accounts.UserToken{
            user_id: user.id,
            context: "api",
            token: token
          })

      # create credentials
      if credentials,
        do:
          Enum.each(credentials, fn credential ->
            {:ok, _credential} =
              Credentials.create_credential(
                credential
                |> Map.put(:user_id, user.id)
              )
          end)

      :ok
    end)
  end
end
