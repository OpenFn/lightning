defmodule Lightning.SetupUtils do
  @moduledoc """
  SetupUtils encapsulates logic for setting up initial data for various sites.
  """

  alias Lightning.{
    Projects,
    Accounts,
    Jobs,
    Workflows,
    Repo,
    Credentials,
    WorkOrders,
    VersionControl
  }

  alias Lightning.Invocation.Run
  alias Ecto.Multi

  import Ecto.Query

  @spec setup_demo(nil | maybe_improper_list | map) :: %{
          jobs: [...],
          projects: [atom | %{:id => any, optional(any) => any}, ...],
          users: [atom | %{:id => any, optional(any) => any}, ...],
          workflows: [atom | %{:id => any, optional(any) => any}, ...],
          workorders: [atom | %{:id => any, optional(any) => any}, ...]
        }
  @doc """
  Creates initial data and returns the created records.
  """
  def setup_demo(opts \\ [create_super: false]) do
    users = create_users(opts)

    %{super_user: super_user, admin: admin, editor: editor, viewer: viewer} =
      users

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

    Repo.insert!(%VersionControl.ProjectRepoConnection{
      github_installation_id: "39991761",
      repo: "OpenFn/demo-openhie",
      branch: "main",
      project_id: openhie_project.id,
      user_id: super_user.id
    })

    %{
      project: dhis2_project,
      workflow: dhis2_workflow,
      jobs: dhis2_jobs,
      workorders: [failure_dhis2_workorder]
    } =
      create_dhis2_project([
        %{user_id: admin.id, role: :admin}
      ])

    %{
      jobs: openhie_jobs ++ dhis2_jobs,
      users: [super_user, admin, editor, viewer],
      projects: [openhie_project, dhis2_project],
      workflows: [openhie_workflow, dhis2_workflow],
      workorders: [
        openhie_workorder,
        failure_dhis2_workorder
      ]
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

  defp create_dhis2_credential(project, user_id) do
    {:ok, credential} =
      Credentials.create_credential(%{
        body: %{
          username: "admin",
          password: "district",
          hostUrl: "https://play.dhis2.org/dev"
        },
        name: "DHIS2 play",
        user_id: user_id,
        schema: "dhis2",
        project_credentials: [
          %{project_id: project.id}
        ]
      })

    credential
  end

  def create_users(opts) do
    super_user =
      if opts[:create_super] do
        {:ok, super_user} =
          Accounts.register_superuser(%{
            first_name: "Sizwe",
            last_name: "Super",
            email: "super@openfn.org",
            password: "welcome123"
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
      Accounts.register_user(%{
        first_name: "Amy",
        last_name: "Admin",
        email: "demo@openfn.org",
        password: "welcome123"
      })

    {:ok, editor} =
      Accounts.register_user(%{
        first_name: "Esther",
        last_name: "Editor",
        email: "editor@openfn.org",
        password: "welcome123"
      })

    {:ok, viewer} =
      Accounts.register_user(%{
        first_name: "Vikram",
        last_name: "Viewer",
        email: "viewer@openfn.org",
        password: "welcome123"
      })

    %{super_user: super_user, admin: admin, editor: editor, viewer: viewer}
  end

  def create_starter_project(name, project_users) do
    {:ok, project} =
      Projects.create_project(%{
        name: name,
        project_users: project_users
      })

    {:ok, workflow} =
      Workflows.create_workflow(%{
        name: "Sample Workflow",
        project_id: project.id
      })

    {:ok, job_1} =
      Jobs.create_job(%{
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
        # enabled: true,
        workflow_id: workflow.id
      })

    {:ok, source_trigger} =
      Workflows.build_trigger(%{
        type: :webhook,
        workflow_id: workflow.id
      })

    {:ok, _job_1_edge} =
      Workflows.create_edge(%{
        workflow_id: workflow.id,
        source_trigger: source_trigger,
        target_job: job_1,
        enabled: true
      })

    {:ok, job_2} =
      Jobs.create_job(%{
        name: "Job 2 - Convert data to DHIS2 format",
        body: """
          fn(state => {
            const names = state.data.name.split(' ');
            return { ...state, names };
          });
        """,
        adaptor: "@openfn/language-common@latest",
        # enabled: true,
        workflow_id: workflow.id
      })

    Workflows.create_edge(%{
      workflow_id: workflow.id,
      source_job: job_1,
      condition: :on_job_success,
      target_job_id: job_2.id,
      enabled: true
    })

    user_id = List.first(project_users).user_id

    dhis2_credential = create_dhis2_credential(project, user_id)

    {:ok, job_3} =
      Jobs.create_job(%{
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
        # enabled: true,
        workflow_id: workflow.id,
        project_credential_id:
          List.first(dhis2_credential.project_credentials).id
      })

    Workflows.create_edge(%{
      workflow_id: workflow.id,
      source_job: job_2,
      condition: :on_job_success,
      target_job_id: job_3.id,
      enabled: true
    })

    input_dataclip =
      create_dataclip(%{
        body: %{
          data: %{},
          references: [
            %{}
          ]
        },
        project_id: project.id,
        type: :http_request
      })

    run_params = [
      %{
        job_id: job_2.id,
        exit_reason: "success",
        log_lines:
          to_log_lines("""
          -- THIS IS ONLY A SAMPLE --
          [CLI] ℹ Versions:
               ▸ node.js                    18.12.0
               ▸ cli                        0.0.32
               ▸ runtime                    0.0.20
               ▸ compiler                   0.0.26
               ▸ @openfn/language-common    1.7.5
          [CLI] ✔ Loaded state from /tmp/state-1686850600-169521-e1925t.json
          [CLI] ℹ Loaded typedefs for @openfn/language-common@latest
          [CMP] ℹ Added import statement for @openfn/language-common
          [CMP] ℹ Added export * statement for @openfn/language-common
          [CLI] ✔ Compiled job from /tmp/expression-1686850600-169521-1sqw0sl.js
          [R/T] ℹ Resolved adaptor @openfn/language-common to version 1.7.5
          [R/T] ✔ Operation 1 complete in 0ms
          [CLI] ✔ Writing output to /tmp/output-1686850600-169521-1drewz.json
          [CLI] ✔ Done in 304ms! ✨
          """),
        started_at: DateTime.utc_now() |> DateTime.add(-45, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(-40, :second),
        input_dataclip_id:
          create_dataclip(%{
            body: %{
              data: %{
                age_in_months: 19,
                name: "Genevieve Wimplemews"
              }
            },
            project_id: project.id,
            type: :run_result
          }).id,
        output_dataclip_id:
          create_dataclip(%{
            body: %{
              data: %{
                age_in_months: 19,
                name: "Genevieve Wimplemews"
              },
              names: [
                "Genevieve",
                "Wimplemews"
              ]
            },
            project_id: project.id,
            type: :run_result
          }).id
      },
      %{
        job_id: job_3.id,
        exit_reason: "success",
        log_lines:
          to_log_lines("""
          -- THIS IS ONLY A SAMPLE --
          [CLI] ℹ Versions:
               ▸ node.js                   18.12.0
               ▸ cli                       0.0.32
               ▸ runtime                   0.0.20
               ▸ compiler                  0.0.26
               ▸ @openfn/language-dhis2    3.2.11
          [CLI] ✔ Loaded state from /tmp/state-1686850601-169521-1eyevfx.json
          [CLI] ℹ Loaded typedefs for @openfn/language-dhis2@latest
          [CMP] ℹ Added import statement for @openfn/language-dhis2
          [CMP] ℹ Added export * statement for @openfn/language-dhis2
          [CLI] ✔ Compiled job from /tmp/expression-1686850601-169521-1i644ux.js
          [R/T] ℹ Resolved adaptor @openfn/language-dhis2 to version 3.2.11
          Preparing create operation...
          Using latest available version of the DHIS2 api on this server.
          Sending post request to https://play.dhis2.org/dev/api/trackedEntityInstances
          ✓ Success at Thu Jun 15 2023 17:36:44 GMT+0000 (Greenwich Mean Time):
          Created trackedEntityInstances with response {
            "httpStatus": "OK",
            "httpStatusCode": 200,
            "status": "OK",
            "message": "Import was successful.",
            "response": {
              "responseType": "ImportSummaries",
              "status": "SUCCESS",
              "imported": 1,
              "updated": 0,
              "deleted": 0,
              "ignored": 0,
              "total": 1
            }
          }
          [R/T] ✔ Operation 1 complete in 1.775s
          [CLI] ✔ Writing output to /tmp/output-1686850601-169521-1k3hzfw.json
          [CLI] ✔ Done in 2.052s! ✨
          """),
        started_at: DateTime.utc_now() |> DateTime.add(-35, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(-30, :second),
        input_dataclip_id:
          create_dataclip(%{
            body: %{
              data: %{
                age_in_months: 19,
                name: "Genevieve Wimplemews"
              },
              names: [
                "Genevieve",
                "Wimplemews"
              ]
            },
            project_id: project.id,
            type: :run_result
          }).id,
        output_dataclip_id:
          create_dataclip(%{
            body: %{
              data: %{
                httpStatus: "OK",
                httpStatusCode: 200,
                message: "Import was successful.",
                response: %{
                  importSummaries: [
                    %{
                      href:
                        "https://play.dhis2.org/dev/api/trackedEntityInstances/iqJrb85GmJb",
                      reference: "iqJrb85GmJb",
                      responseType: "ImportSummary",
                      status: "SUCCESS"
                    }
                  ],
                  imported: 1,
                  responseType: "ImportSummaries",
                  status: "SUCCESS",
                  total: 1,
                  updated: 0
                },
                status: "OK"
              },
              names: [
                "Genevieve",
                "Wimplemews"
              ],
              references: [
                %{
                  age_in_months: 19,
                  name: "Genevieve Wimplemews"
                }
              ]
            },
            project_id: project.id,
            type: :run_result
          }).id
      }
    ]

    {:ok, workorder} =
      create_workorder(
        workflow,
        source_trigger,
        input_dataclip,
        run_params
      )

    %{
      project: project,
      workflow: workflow,
      workorder: workorder,
      jobs: [job_1, job_2, job_3]
    }
  end

  def create_openhie_project(project_users) do
    {:ok, openhie_project} =
      Projects.create_project(%{
        name: "openhie-project",
        id: "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa",
        project_users: project_users
      })

    {:ok, openhie_workflow} =
      Workflows.create_workflow(%{
        name: "OpenHIE Workflow",
        project_id: openhie_project.id
      })

    {:ok, openhie_trigger} =
      Workflows.build_trigger(%{
        type: :webhook,
        # Id is hard-coded to support external test scripts (e.g. benchmarking/script.js)
        id: "cae544ab-03dc-4ccc-a09c-fb4edb255d7a",
        workflow_id: openhie_workflow.id
      })

    {:ok, fhir_standard_data} =
      Jobs.create_job(%{
        name: "Transform data to FHIR standard",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: NaiveDateTime.utc_now(),
        body: """
        fn(state => state);
        """,
        adaptor: "@openfn/language-http@latest",
        # enabled: true,
        workflow_id: openhie_workflow.id
      })

    {:ok, _openhie_root_edge} =
      Workflows.create_edge(%{
        workflow_id: openhie_workflow.id,
        condition: :always,
        source_trigger: openhie_trigger,
        target_job: fhir_standard_data,
        enabled: true
      })

    {:ok, send_to_openhim} =
      Jobs.create_job(%{
        name: "Send to OpenHIM to route to SHR",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(1, :second),
        body: """
        fn(state => state);
        """,
        adaptor: "@openfn/language-http@latest",
        # enabled: true,
        workflow_id: openhie_workflow.id
      })

    {:ok, _send_to_openhim_edge} =
      Workflows.create_edge(%{
        workflow_id: openhie_workflow.id,
        condition: :on_job_success,
        target_job_id: send_to_openhim.id,
        source_job_id: fhir_standard_data.id,
        enabled: true
      })

    {:ok, notify_upload_successful} =
      Jobs.create_job(%{
        name: "Notify CHW upload successful",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(2, :second),
        body: """
        fn(state => state);
        """,
        adaptor: "@openfn/language-http@latest",
        # enabled: true,
        workflow_id: openhie_workflow.id
      })

    {:ok, _success_upload} =
      Workflows.create_edge(%{
        workflow_id: openhie_workflow.id,
        condition: :on_job_success,
        target_job_id: notify_upload_successful.id,
        source_job_id: send_to_openhim.id,
        enabled: true
      })

    {:ok, notify_upload_failed} =
      Jobs.create_job(%{
        name: "Notify CHW upload failed",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(3, :second),
        body: """
        fn(state => state);
        """,
        adaptor: "@openfn/language-http@latest",
        # enabled: true,
        workflow_id: openhie_workflow.id
      })

    {:ok, _failed_upload} =
      Workflows.create_edge(%{
        workflow_id: openhie_workflow.id,
        condition: :on_job_failure,
        target_job_id: notify_upload_failed.id,
        source_job_id: send_to_openhim.id,
        enabled: true
      })

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

    output_dataclip_payload = %{
      body: %{data: http_body, references: []},
      project_id: openhie_project.id,
      type: :run_result
    }

    [output_dataclip_1, output_dataclip_2, output_dataclip_3] =
      Enum.map(1..3, fn _n -> create_dataclip(output_dataclip_payload) end)

    run_params = [
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
        started_at: DateTime.utc_now() |> DateTime.add(1, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(2, :second),
        input_dataclip_id: dataclip.id,
        output_dataclip_id: output_dataclip_1.id
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
        started_at: DateTime.utc_now() |> DateTime.add(3, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(4, :second),
        input_dataclip_id: output_dataclip_1.id,
        output_dataclip_id: output_dataclip_2.id
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
        started_at: DateTime.utc_now() |> DateTime.add(5, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(6, :second),
        input_dataclip_id: output_dataclip_2.id,
        output_dataclip_id: output_dataclip_3.id
      }
    ]

    {:ok, openhie_workorder} =
      create_workorder(
        openhie_workflow,
        openhie_trigger,
        dataclip,
        run_params
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
    {:ok, dhis2_project} =
      Projects.create_project(%{
        name: "dhis2-project",
        project_users: project_users
      })

    {:ok, dhis2_workflow} =
      Workflows.create_workflow(%{
        name: "DHIS2 to Sheets",
        project_id: dhis2_project.id
      })

    user_id = List.first(project_users).user_id
    dhis2_credential = create_dhis2_credential(dhis2_project, user_id)

    {:ok, get_dhis2_data} =
      Jobs.create_job(%{
        name: "Get DHIS2 data",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: NaiveDateTime.utc_now(),
        body: """
        get('trackedEntityInstances/PQfMcpmXeFE');
        """,
        adaptor: "@openfn/language-dhis2@latest",
        # enabled: true,
        workflow_id: dhis2_workflow.id,
        project_credential_id:
          List.first(dhis2_credential.project_credentials).id
      })

    {:ok, dhis_trigger} =
      Workflows.build_trigger(%{
        type: :cron,
        cron_expression: "0 * * * *",
        workflow_id: dhis2_workflow.id
      })

    {:ok, _root_edge} =
      Workflows.create_edge(%{
        workflow_id: dhis2_workflow.id,
        condition: :always,
        source_trigger: dhis_trigger,
        target_job: get_dhis2_data,
        enabled: true
      })

    {:ok, upload_to_google_sheet} =
      Jobs.create_job(%{
        name: "Upload to Google Sheet",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(1, :second),
        body: """
        fn(state => state);
        """,
        adaptor: "@openfn/language-http@latest",
        # enabled: true,
        workflow_id: dhis2_workflow.id
      })

    {:ok, _success_upload} =
      Workflows.create_edge(%{
        workflow_id: dhis2_workflow.id,
        condition: :on_job_success,
        target_job_id: upload_to_google_sheet.id,
        source_job_id: get_dhis2_data.id,
        enabled: true
      })

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
        project_id: dhis2_project.id,
        type: :http_request
      })

    output_dataclip =
      create_dataclip(%{
        body: %{
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
        },
        project_id: dhis2_project.id,
        type: :run_result
      })

    # Make it fail for demo purposes
    run_params = [
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
        started_at: DateTime.utc_now() |> DateTime.add(1, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(2, :second),
        input_dataclip_id: input_dataclip.id,
        output_dataclip_id: output_dataclip.id
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
          """),
        started_at: DateTime.utc_now() |> DateTime.add(3, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(4, :second),
        input_dataclip_id: output_dataclip.id
      }
    ]

    {:ok, failure_dhis2_workorder} =
      create_workorder(
        dhis2_workflow,
        dhis_trigger,
        input_dataclip,
        run_params
      )

    %{
      project: dhis2_project,
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
      Lightning.Attempt,
      Lightning.AttemptRun,
      Lightning.AuthProviders.AuthConfig,
      Lightning.Auditing.Model,
      Lightning.Projects.ProjectCredential,
      Lightning.WorkOrder,
      Lightning.Invocation.Run,
      Lightning.Invocation.LogLine,
      Lightning.Credentials.Credential,
      Lightning.Workflows.Job,
      Lightning.Workflows.Trigger,
      Lightning.Workflows.WebhookAuthMethod,
      Lightning.Workflows.Workflow,
      Lightning.Projects.ProjectUser,
      Lightning.Invocation.Dataclip,
      Lightning.Projects.Project
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
         run_params
       ) do
    attempt_finished_at =
      DateTime.utc_now()
      |> DateTime.add(length(run_params) * 2, :second)

    [%{exit_reason: final_run_exit_reason} | _rest] = Enum.reverse(run_params)

    Multi.new()
    |> Multi.insert(
      :workorder,
      WorkOrders.build_for(trigger, %{
        workflow: workflow,
        dataclip: input_dataclip,
        last_activity: attempt_finished_at
      })
    )
    |> Multi.update(:attempt, fn %{workorder: %{attempts: [attempt]}} ->
      runs =
        Enum.map(run_params, fn params ->
          log_lines =
            Enum.map(params.log_lines, fn line ->
              Map.merge(line, %{
                id: Ecto.UUID.generate(),
                attempt_id: attempt.id
              })
            end)

          params
          |> Map.merge(%{log_lines: log_lines})
          |> Run.new()
        end)

      attempt
      |> Repo.preload([:runs])
      |> Ecto.Changeset.change(%{
        state:
          if(final_run_exit_reason == "success", do: :success, else: :failed),
        claimed_at: DateTime.utc_now() |> DateTime.add(1, :second),
        started_at: DateTime.utc_now() |> DateTime.add(1, :second),
        finished_at: attempt_finished_at
      })
      |> Ecto.Changeset.put_assoc(:runs, runs)
    end)
    |> Multi.update(:workorder_status, fn %{
                                            workorder: workorder,
                                            attempt: attempt
                                          } ->
      Ecto.Changeset.change(workorder, %{
        state: attempt.state,
        last_activity: attempt_finished_at
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{workorder: workorder}} ->
        {:ok, workorder}

      {:error, _operation, failed_value, _changes} ->
        {:error, failed_value}
    end
  end

  defp create_dataclip(params) do
    {:ok, dataclip} = Lightning.Invocation.create_dataclip(params)

    dataclip
  end

  @doc """
  This is a helper function that can be used to aid instance administrators in
  migrating from v0.9.3 to v0.10.0.

  While the final state of an attempt is now handled by the worker, this script
  can be called once after migration (with no workers attached) to provide an
  approximate final state for attempts that were finished before the migration.
  """
  def approximate_state_for_attempts_and_workorders do
    # Set attempts state by exit_reason of their last run.
    Repo.query!("""
    UPDATE attempts
    SET state = (
      SELECT
        DISTINCT ON
        (a.id) CASE
          WHEN runs.exit_reason = 'success' THEN 'success'
          ELSE 'failed'
        END
      FROM
        runs
      JOIN attempt_runs ar ON
        ar.run_id = runs.id
      JOIN attempts a ON
        a.id = ar.attempt_id
      WHERE
        a.id = attempts.id
      ORDER BY
        a.id ASC,
        runs.finished_at DESC
    )
    WHERE attempts.state NOT IN ('available', 'claimed', 'started');
    """)

    # Set attempts finished_at by finished at of their last run.
    Repo.query!("""
    UPDATE attempts
    SET finished_at = (
      SELECT
        DISTINCT ON
        (a.id) runs.finished_at
      FROM
        runs
      JOIN attempt_runs ar ON
        ar.run_id = runs.id
      JOIN attempts a ON
        a.id = ar.attempt_id
      WHERE
        a.id = attempts.id
      ORDER BY
        a.id ASC,
        runs.finished_at DESC
    ) WHERE attempts.state NOT IN ('available', 'claimed', 'started');
    """)

    # Set attempts error type to a generic, pre v0.10.0 error.
    Repo.query!("""
    UPDATE attempts
    SET error_type = 'Error'
    WHERE error_type IS NULL
    AND state = 'failed';
    """)

    # Set runs error type to a generic, pre v0.10.0 error.
    Repo.query!("""
    UPDATE runs
    SET error_type = 'Error'
    WHERE error_type IS NULL
    AND exit_reason = 'fail';
    """)

    # Set state for workorders by the state from their last attempts.
    Repo.query!("""
    UPDATE work_orders
    SET state = (
      SELECT
        DISTINCT ON
        (a.work_order_id) a.state
      FROM
        attempts a
      WHERE
        a.work_order_id = work_orders.id
      ORDER BY
        a.work_order_id ASC,
        a.finished_at DESC
    )
    WHERE work_orders.state NOT IN ('available', 'claimed', 'started');
    """)

    # Set last activity for workorders by the last finished_at from attempts.
    Repo.query!("""
    UPDATE
      work_orders
    SET
      last_activity = (
      SELECT
        DISTINCT ON
        (a.work_order_id) a.finished_at
      FROM
        attempts a
      WHERE
        a.work_order_id = work_orders.id
      ORDER BY
        a.work_order_id ASC,
        a.finished_at DESC
      )
    WHERE work_orders.state NOT IN ('available', 'claimed', 'started');
    """)
  end
end
