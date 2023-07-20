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
    AttemptRun
  }

  alias Lightning.WorkOrderService
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
    {:ok, super_user} =
      if opts[:create_super] do
        Accounts.register_superuser(%{
          first_name: "Sizwe",
          last_name: "Super",
          email: "super@openfn.org",
          password: "welcome123"
        })
      else
        {:ok, nil}
      end

    Lightning.Repo.insert!(%Lightning.Accounts.UserToken{
      user_id: super_user.id,
      context: "api",
      token:
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJKb2tlbiIsImlhdCI6MTY4
        ODAzNzE4NSwiaXNzIjoiSm9rZW4iLCJqdGkiOiIydG1ocG8zYm0xdmR0MDZvZDgwMDAwdTEiLCJuY
        mYiOjE2ODgwMzcxODUsInVzZXJfaWQiOiIzZjM3OGU2Yy02NjBhLTRiOTUtYWI5Ni02YmQwZGMyNj
        NkMzMifQ.J1FnACGpqtQbmXNvyUCwCY4mS5S6CohRU3Ey-N0prP4"
    })

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

    %{
      project: openhie_project,
      workflow: openhie_workflow,
      jobs: openhie_jobs,
      workorder: openhie_workorder
    } =
      create_openhie_project([
        %{user_id: admin.id, role: :admin},
        %{user_id: editor.id, role: :editor},
        %{user_id: viewer.id, role: :viewer}
      ])

    %{
      project: dhis2_project,
      workflow: dhis2_workflow,
      jobs: dhis2_jobs,
      workorders: [successful_dhis2_workorder, failure_dhis2_workorder]
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
        successful_dhis2_workorder,
        failure_dhis2_workorder
      ]
    }
  end

  defp to_log_lines(log) do
    log
    |> String.split("\n")
    |> Enum.map(fn log -> %{body: log} end)
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
        body: "fn(state => {
  if (state.data.age_in_months > 18) {
    console.log('Eligible for program.');
    return state;
  }
  else { throw 'Error, patient ineligible.' }
});",
        adaptor: "@openfn/language-common@latest",
        trigger: %{type: "webhook"},
        enabled: true,
        workflow_id: workflow.id
      })

    {:ok, job_2} =
      Jobs.create_job(%{
        name: "Job 2 - Convert data to DHIS2 format",
        body: "fn(state => {
  const names = state.data.name.split(' ');
  return { ...state, names };
});",
        adaptor: "@openfn/language-common@latest",
        trigger: %{type: "on_job_success", upstream_job_id: job_1.id},
        enabled: true,
        workflow_id: workflow.id
      })

    user_id = List.first(project_users).user_id

    dhis2_credential = create_dhis2_credential(project, user_id)

    {:ok, job_3} =
      Jobs.create_job(%{
        name: "Job 3 - Upload to DHIS2",
        body: "create('trackedEntityInstances', {
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
});",
        adaptor: "@openfn/language-dhis2@latest",
        trigger: %{type: "on_job_success", upstream_job_id: job_2.id},
        enabled: true,
        workflow_id: workflow.id,
        project_credential_id:
          List.first(dhis2_credential.project_credentials).id
      })

    run_params = [
      %{
        job_id: job_2.id,
        exit_code: 0,
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
        started_at: DateTime.utc_now() |> DateTime.add(10, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(15, :second),
        input_dataclip_id:
          create_dataclip(%{
            body: %{
              data: %{
                age_in_months: 19,
                name: "Genevieve Wimplemews"
              }
            },
            project_id: project.id,
            type: :http_request
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
            type: :http_request
          }).id
      },
      %{
        job_id: job_3.id,
        exit_code: 0,
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
        started_at: DateTime.utc_now() |> DateTime.add(20, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(25, :second),
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
            type: :http_request
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
            type: :http_request
          }).id
      }
    ]

    output_dataclip_id =
      create_dataclip(%{
        body: %{
          data: %{
            age_in_months: 19,
            name: "Genevieve Wimplemews"
          }
        },
        project_id: project.id,
        type: :http_request
      }).id

    create_workorder(
      :webhook,
      job_1,
      ~s[{"age_in_months": 19, "name": "Genevieve Wimplemews"}],
      run_params,
      output_dataclip_id
    )

    %{
      project: project,
      workflow: workflow,
      jobs: [job_1, job_2, job_3]
    }
  end

  def create_openhie_project(project_users) do
    {:ok, openhie_project} =
      Projects.create_project(%{
        name: "openhie-project",
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
        id: "cae544ab-03dc-4ccc-a09c-fb4edb255d7a",
        workflow_id: openhie_workflow.id
      })

    {:ok, fhir_standard_data} =
      Jobs.create_job(%{
        name: "Transform data to FHIR standard",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http@latest",
        enabled: true,
        workflow_id: openhie_workflow.id
      })

    {:ok, _openhie_root_edge} =
      Workflows.create_edge(%{
        workflow_id: openhie_workflow.id,
        condition: :always,
        source_trigger_id: openhie_trigger.id,
        target_job_id: fhir_standard_data.id
      })

    {:ok, send_to_openhim} =
      Jobs.create_job(%{
        name: "Send to OpenHIM to route to SHR",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http@latest",
        enabled: true,
        workflow_id: openhie_workflow.id
      })

    {:ok, _send_to_openhim_edge} =
      Workflows.create_edge(%{
        workflow_id: openhie_workflow.id,
        condition: :on_job_success,
        target_job_id: send_to_openhim.id,
        source_job_id: fhir_standard_data.id
      })

    {:ok, notify_upload_successful} =
      Jobs.create_job(%{
        name: "Notify CHW upload successful",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http@latest",
        enabled: true,
        workflow_id: openhie_workflow.id
      })

    {:ok, _success_upload} =
      Workflows.create_edge(%{
        workflow_id: openhie_workflow.id,
        condition: :on_job_success,
        target_job_id: notify_upload_successful.id,
        source_job_id: send_to_openhim.id
      })

    {:ok, notify_upload_failed} =
      Jobs.create_job(%{
        name: "Notify CHW upload failed",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http@latest",
        enabled: true,
        workflow_id: openhie_workflow.id
      })

    dataclip =
      create_dataclip(%{
        body: %{data: %{}, references: []},
        project_id: openhie_project.id,
        type: :http_request
      })

    run_params = [
      %{
        job_id: send_to_openhim.id,
        exit_code: 0,
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
        started_at: DateTime.utc_now() |> DateTime.add(10, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(15, :second),
        input_dataclip_id: dataclip.id,
        output_dataclip_id: dataclip.id
      },
      %{
        job_id: notify_upload_successful.id,
        exit_code: 0,
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
        started_at: DateTime.utc_now() |> DateTime.add(20, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(25, :second),
        input_dataclip_id: dataclip.id,
        output_dataclip_id: dataclip.id
      }
    ]

    output_dataclip_id =
      create_dataclip(%{
        body: %{data: %{}, references: []},
        project_id: openhie_project.id,
        type: :http_request
      }).id

    {:ok, openhie_workorder} =
      create_workorder(
        :webhook,
        fhir_standard_data,
        ~s[{}],
        run_params,
        output_dataclip_id
      )

    {:ok, _failed_upload} =
      Workflows.create_edge(%{
        workflow_id: openhie_workflow.id,
        condition: :on_job_failure,
        target_job_id: notify_upload_failed.id,
        source_job_id: send_to_openhim.id
      })

    %{
      project: openhie_project,
      workflow: openhie_workflow,
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
        body: "get('trackedEntityInstances/PQfMcpmXeFE');",
        adaptor: "@openfn/language-dhis2@latest",
        enabled: true,
        project_credential_id:
          List.first(dhis2_credential.project_credentials).id,
        workflow_id: dhis2_workflow.id
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
        source_trigger_id: dhis_trigger.id,
        target_job_id: get_dhis2_data.id
      })

    {:ok, upload_to_google_sheet} =
      Jobs.create_job(%{
        name: "Upload to Google Sheet",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http@latest",
        enabled: true,
        workflow_id: dhis2_workflow.id
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
        type: :http_request
      })

    run_params = [
      %{
        job_id: upload_to_google_sheet.id,
        exit_code: 0,
        log_lines:
          to_log_lines("""
          -- THIS IS ONLY A SAMPLE --
          [CLI] ℹ Versions:
               ▸ node.js                  18.12.0
               ▸ cli                      0.0.32
               ▸ runtime                  0.0.21
               ▸ compiler                 0.0.26
               ▸ @openfn/language-http    4.2.6
          [CLI] ✔ Loaded state from /tmp/state-1686840343-126941-92qxs9.json
          [CMP] ℹ Added import statement for @openfn/language-http
          [CMP] ℹ Added export * statement for @openfn/language-http
          [CLI] ✔ Compiled job from /tmp/expression-1686840343-126941-1pnt7u5.js
          [R/T] ℹ Resolved adaptor @openfn/language-http to version 4.2.6
          [R/T] ✔ Operation 1 complete in 0ms
          [CLI] ✔ Writing output to /tmp/output-1686840343-126941-1hb3ve5.json
          [CLI] ✔ Done in 216ms! ✨
          """),
        started_at: DateTime.utc_now() |> DateTime.add(10, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(15, :second),
        input_dataclip_id: input_dataclip.id,
        output_dataclip_id: output_dataclip.id
      }
    ]

    output_dataclip_id =
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
      }).id

    {:ok, successful_dhis2_workorder} =
      create_workorder(
        :cron,
        get_dhis2_data,
        ~s[{"data": {}, "references": \[\]}],
        run_params,
        output_dataclip_id
      )

    # Make it fail for demo purposes
    run_params = [
      %{
        job_id: upload_to_google_sheet.id,
        exit_code: 1,
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
        started_at: DateTime.utc_now() |> DateTime.add(10, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(15, :second),
        input_dataclip_id: input_dataclip.id
      }
    ]

    {:ok, failure_dhis2_workorder} =
      create_workorder(
        :cron,
        get_dhis2_data,
        ~s[{"data": {}, "references": \[\]}],
        run_params,
        output_dataclip_id
      )
    {:ok, _success_upload} =
      Workflows.create_edge(%{
        workflow_id: dhis2_workflow.id,
        condition: :on_job_success,
        target_job_id: upload_to_google_sheet.id,
        source_job_id: get_dhis2_data.id
      })

    %{
      project: dhis2_project,
      workflow: dhis2_workflow,
      workorders: [successful_dhis2_workorder, failure_dhis2_workorder],
      jobs: [get_dhis2_data, upload_to_google_sheet]
    }
  end

  def tear_down(opts \\ [destroy_super: false]) do
    delete_all_entities([
      Lightning.Attempt,
      Lightning.AttemptRun,
      Lightning.AuthProviders.AuthConfig,
      Lightning.Credentials.Audit,
      Lightning.Projects.ProjectCredential,
      Lightning.WorkOrder,
      Lightning.InvocationReason,
      Lightning.Invocation.Run,
      Lightning.Credentials.Credential,
      Lightning.Jobs.Job,
      Lightning.Jobs.Trigger,
      Lightning.Workflows.Workflow,
      Lightning.Projects.ProjectUser,
      Lightning.Invocation.Dataclip,
      Lightning.Projects.Project
    ])

    delete_other_tables(["oban_jobs", "oban_peers"])

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

  defp create_workorder(trigger, job, dataclip, run_params, output_dataclip_id) do
    WorkOrderService.multi_for(
      trigger,
      job,
      dataclip
      |> Jason.decode!()
    )
    |> add_and_update_runs(run_params, output_dataclip_id)
    |> Repo.transaction()
  end

  def add_and_update_runs(multi, run_params, output_dataclip_id)
      when is_list(run_params) do
    multi =
      multi
      |> Multi.run(:run, fn repo, %{attempt_run: attempt_run} ->
        {:ok, Ecto.assoc(attempt_run, :run) |> repo.one!()}
      end)
      |> Multi.update("update_run", fn %{run: run} ->
        # Change the timestamps, logs, exit_code etc
        run
        |> Repo.preload(:log_lines)
        |> Run.changeset(%{
          exit_code: 0,
          log_lines:
            to_log_lines("""
            -- THIS IS ONLY A SAMPLE --
            [CLI] ℹ Versions:
                 ▸ node.js                   18.12.0
                 ▸ cli                       0.0.32
                 ▸ runtime                   0.0.20
                 ▸ compiler                  0.0.26
                 ▸ #{adaptor_for_log(run)}            3.2.11
            [CLI] ✔ Loaded state from /tmp/state-1686836010-94749-17tka8f.json
            [CLI] ℹ Loaded typedefs for #{adaptor_for_log(run)}
            [CMP] ℹ Added import statement for #{adaptor_for_log(run)}
            [CMP] ℹ Added export * statement for #{adaptor_for_log(run)}
            [CLI] ✔ Compiled job from /tmp/expression-1686836010-94749-1cn5qct.js
            [R/T] ℹ Resolved adaptor #{adaptor_for_log(run)} to version 3.2.11
            [R/T] ✔ Operation 1 complete in 0ms
            [CLI] ✔ Writing output to /tmp/output-1686836010-94749-1v3ppcw.json
            [CLI] ✔ Done in 179ms! ✨
            """)
            |> Enum.with_index()
            |> Enum.map(fn {log, index} -> {index, log} end)
            |> Enum.into(%{}),
          started_at: DateTime.utc_now() |> DateTime.add(0, :second),
          finished_at: DateTime.utc_now() |> DateTime.add(5, :second),
          output_dataclip_id: output_dataclip_id
        })
      end)

    run_params
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {params, i}, multi ->
      multi
      |> Multi.insert("attempt_run_#{i}", fn %{
                                               attempt: attempt,
                                               dataclip: _dataclip
                                             } ->
        run = Run.new(params)
        AttemptRun.new(attempt, run)
      end)
    end)
  end

  defp create_dataclip(params) do
    {:ok, dataclip} = Lightning.Invocation.create_dataclip(params)

    dataclip
  end

  defp adaptor_for_log(run) do
    run_with_job = Repo.preload(run, :job)
    run_with_job.job.adaptor
  end
end
