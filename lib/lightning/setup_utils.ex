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
        started_at: DateTime.utc_now() |> DateTime.add(10, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(15, :second)
      },
      %{
        job_id: job_3.id,
        exit_code: 0,
        started_at: DateTime.utc_now() |> DateTime.add(20, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(25, :second)
      }
    ]

    create_workorder(
      :webhook,
      job_1,
      ~s[{"age_in_months": 19, "name": "Genevieve Wimplemews"}],
      run_params
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

    {:ok, fhir_standard_data} =
      Jobs.create_job(%{
        name: "Transform data to FHIR standard",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http@latest",
        enabled: true,
        trigger: %{type: "webhook", id: "cae544ab-03dc-4ccc-a09c-fb4edb255d7a"},
        workflow_id: openhie_workflow.id
      })

    {:ok, send_to_openhim} =
      Jobs.create_job(%{
        name: "Send to OpenHIM to route to SHR",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http@latest",
        enabled: true,
        trigger: %{
          type: "on_job_success",
          upstream_job_id: fhir_standard_data.id
        },
        workflow_id: openhie_workflow.id
      })

    {:ok, notify_upload_successful} =
      Jobs.create_job(%{
        name: "Notify CHW upload successful",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http@latest",
        enabled: true,
        trigger: %{type: "on_job_success", upstream_job_id: send_to_openhim.id},
        workflow_id: openhie_workflow.id
      })

    {:ok, notify_upload_failed} =
      Jobs.create_job(%{
        name: "Notify CHW upload failed",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http@latest",
        enabled: true,
        trigger: %{type: "on_job_failure", upstream_job_id: send_to_openhim.id},
        workflow_id: openhie_workflow.id
      })

    run_params = [
      %{
        job_id: send_to_openhim.id,
        exit_code: 0,
        log_lines: [
          %{body: "[CLI] ℹ Versions:"},
          %{body: "        ▸ node.js                  18.12.0"},
          %{body: "        ▸ cli                      0.0.32"},
          %{body: "        ▸ runtime                  0.0.20"},
          %{body: "        ▸ compiler                 0.0.26"},
          %{body: "        ▸ @openfn/language-http    4.2.6"},
          %{
            body:
              "[CLI] ✔ Loaded state from /tmp/state-1686840746-126941-1hou2fm.json"
          },
          %{body: "[CLI] ℹ Loaded typedefs for @openfn/language-http@latest"},
          %{body: "[CLI] ℹ Loaded typedefs for @openfn/language-http@latest"},
          %{
            body: "[CMP] ℹ Added import statement for @openfn/language-http"
          },
          %{
            body: "[CMP] ℹ Added export * statement for @openfn/language-http"
          },
          %{
            body:
              "[CLI] ✔ Compiled job from /tmp/expression-1686840746-126941-1wuk06h.js"
          },
          %{
            body:
              "[R/T] ℹ Resolved adaptor @openfn/language-http to version 4.2.6"
          },
          %{
            body: "[R/T] ✔ Operation 1 complete in 0ms"
          },
          %{
            body:
              "[CLI] ✔ Writing output to /tmp/output-1686840746-126941-i2yb2g.json"
          },
          %{
            body: "[CLI] ✔ Done in 223ms! ✨"
          }
        ],
        started_at: DateTime.utc_now() |> DateTime.add(10, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(15, :second)
      },
      %{
        job_id: notify_upload_successful.id,
        exit_code: 0,
        log_lines: [
          %{body: "[CLI] ℹ Versions:"},
          %{body: "        ▸ node.js                  18.12.0"},
          %{body: "        ▸ cli                      0.0.32"},
          %{body: "        ▸ runtime                  0.0.20"},
          %{body: "        ▸ compiler                 0.0.26"},
          %{body: "        ▸ @openfn/language-http    4.2.6"},
          %{
            body:
              "[CLI] ✔ Loaded state from /tmp/state-1686840747-126941-n44hwo.json"
          },
          %{body: "[CLI] ℹ Loaded typedefs for @openfn/language-http@latest"},
          %{body: "[CMP] ℹ Added import statement for @openfn/language-http"},
          %{
            body: "[CMP] ℹ Added export * statement for @openfn/language-http"
          },
          %{
            body:
              "[CLI] ✔ Compiled job from /tmp/expression-1686840747-126941-1qi9xrb.js"
          },
          %{
            body:
              "[R/T] ℹ Resolved adaptor @openfn/language-http to version 4.2.6"
          },
          %{
            body: "[R/T] ✔ Operation 1 complete in 0ms"
          },
          %{
            body:
              "[CLI] ✔ Writing output to /tmp/output-1686840747-126941-16ewhef.json"
          },
          %{
            body: "[CLI] ✔ Done in 209ms! ✨"
          }
        ],
        started_at: DateTime.utc_now() |> DateTime.add(20, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(25, :second)
      }
    ]

    {:ok, openhie_workorder} =
      create_workorder(
        :webhook,
        fhir_standard_data,
        ~s[{}],
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
        body: "fn(state => state);",
        adaptor: "@openfn/language-dhis2@latest",
        enabled: true,
        trigger: %{type: "cron", cron_expression: "0 * * * *"},
        workflow_id: dhis2_workflow.id,
        project_credential_id:
          List.first(dhis2_credential.project_credentials).id
      })

    {:ok, upload_to_google_sheet} =
      Jobs.create_job(%{
        name: "Upload to Google Sheet",
        body: "fn(state => state);",
        adaptor: "@openfn/language-http@latest",
        enabled: true,
        trigger: %{type: "on_job_success", upstream_job_id: get_dhis2_data.id},
        workflow_id: dhis2_workflow.id
      })

    run_params = [
      %{
        job_id: upload_to_google_sheet.id,
        exit_code: 0,
        log_lines: [
          %{body: "[CLI] ℹ Versions:"},
          %{body: "        ▸ node.js                  18.12.0"},
          %{body: "        ▸ cli                      0.0.32"},
          %{body: "        ▸ runtime                  0.0.21"},
          %{body: "        ▸ compiler                 0.0.26"},
          %{body: "        ▸ @openfn/language-http    4.2.6"},
          %{
            body:
              "[CLI] ✔ Loaded state from /tmp/state-1686840343-126941-92qxs9.json"
          },
          %{body: "[CMP] ℹ Added import statement for @openfn/language-http"},
          %{body: "[CMP] ℹ Added export * statement for @openfn/language-http"},
          %{
            body:
              "[CLI] ✔ Compiled job from /tmp/expression-1686840343-126941-1pnt7u5.js"
          },
          %{
            body:
              "[R/T] ℹ Resolved adaptor @openfn/language-http to version 4.2.6"
          },
          %{
            body: "[R/T] ✔ Operation 1 complete in 0ms"
          },
          %{
            body:
              "[CLI] ✔ Writing output to /tmp/output-1686840343-126941-1hb3ve5.json"
          },
          %{
            body: "[CLI] ✔ Done in 216ms! ✨"
          }
        ],
        started_at: DateTime.utc_now() |> DateTime.add(10, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(15, :second)
      }
    ]

    {:ok, successful_dhis2_workorder} =
      create_workorder(
        :cron,
        get_dhis2_data,
        ~s[{}],
        run_params
      )

    # Make it fail for demo purposes
    run_params = [
      %{
        job_id: upload_to_google_sheet.id,
        exit_code: 1,
        log_lines: [
          %{body: "[CLI] ℹ Versions:"},
          %{body: "        ▸ @openfn/language-http    4.2.8"},
          %{body: "        ▸ compiler                 0.0.29"},
          %{body: "        ▸ runtime                  0.0.21"},
          %{body: "        ▸ cli                      0.0.35"},
          %{body: "        ▸ node.js                  18.12.0"},
          %{
            body:
              "[CLI] ✔ Loaded state from /var/folders/v9/rvycxf0j6kx8py3m2bw8d1gr0000gn/T/state-1686240004-30184-1qywkh4.json"
          },
          %{body: "[CLI] ℹ Added import statement for @openfn/language-http"},
          %{body: "[CLI] ℹ Added export * statement for @openfn/language-http"},
          %{
            body:
              "[CLI] ✔ Compiled job from /var/folders/v9/rvycxf0j6kx8py3m2bw8d1gr0000gn/T/expression-1686240004-30184-sd2j6r.js"
          },
          %{
            body:
              "[R/T] ℹ Resolved adaptor @openfn/language-http to version 4.2.8"
          },
          %{
            body:
              "[CLI] ✘ Error: 503 Service Unavailable, please try again later"
          },
          %{
            body: "[CLI] ✘ Took 1.634s."
          }
        ],
        started_at: DateTime.utc_now() |> DateTime.add(10, :second),
        finished_at: DateTime.utc_now() |> DateTime.add(15, :second)
      }
    ]

    {:ok, failure_dhis2_workorder} =
      create_workorder(
        :cron,
        get_dhis2_data,
        ~s[{}],
        run_params
      )

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

  defp create_workorder(trigger, job, dataclip, run_params) do
    WorkOrderService.multi_for(
      trigger,
      job,
      dataclip
      |> Jason.decode!()
    )
    |> add_and_update_runs(run_params)
    |> Repo.transaction()
  end

  def add_and_update_runs(multi, run_params) when is_list(run_params) do
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
          log_lines: %{
            "0" => %{
              body: "[CLI] ℹ Versions:"
            },
            "1" => %{
              body: "        ▸ node.js                   18.12.0"
            },
            "2" => %{
              body: "        ▸ cli                       0.0.32"
            },
            "3" => %{
              body: "        ▸ runtime                   0.0.20"
            },
            "4" => %{
              body: "        ▸ compiler                  0.0.26"
            },
            "5" => %{
              body: "        ▸ #{adaptor_for_log(run)}    3.2.11"
            },
            "6" => %{
              body:
                "[CLI] ✔ Loaded state from /tmp/state-1686836010-94749-17tka8f.json"
            },
            "7" => %{
              body: "[CLI] ℹ Loaded typedefs for #{adaptor_for_log(run)}"
            },
            "8" => %{
              body: "[CMP] ℹ Added import statement for #{adaptor_for_log(run)}"
            },
            "9" => %{
              body:
                "[CMP] ℹ Added export * statement for #{adaptor_for_log(run)}"
            },
            "10" => %{
              body:
                "[CLI] ✔ Compiled job from /tmp/expression-1686836010-94749-1cn5qct.js"
            },
            "11" => %{
              body:
                "[R/T] ℹ Resolved adaptor #{adaptor_for_log(run)} to version 3.2.11"
            },
            "12" => %{
              body: "[R/T] ✔ Operation 1 complete in 0ms"
            },
            "13" => %{
              body:
                "[CLI] ✔ Writing output to /tmp/output-1686836010-94749-1v3ppcw.json"
            },
            "14" => %{
              body: "[CLI] ✔ Done in 179ms! ✨"
            }
          },
          started_at: DateTime.utc_now() |> DateTime.add(0, :second),
          finished_at: DateTime.utc_now() |> DateTime.add(5, :second)
        })
      end)

    run_params
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {params, i}, multi ->
      multi
      |> Multi.insert("attempt_run_#{i}", fn %{
                                               attempt: attempt,
                                               dataclip: dataclip
                                             } ->
        run =
          Run.new(params)
          |> Ecto.Changeset.put_assoc(:input_dataclip, dataclip)

        AttemptRun.new(attempt, run)
      end)
    end)
  end

  defp adaptor_for_log(run) do
    run_with_job = Repo.preload(run, :job)
    run_with_job.job.adaptor
  end
end
