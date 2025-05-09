defmodule Lightning.SetupUtilsTest do
  alias Lightning.Invocation
  use Lightning.DataCase, async: true
  import Swoosh.TestAssertions

  alias Lightning.{Accounts, Projects, Workflows, Jobs, SetupUtils}
  alias Lightning.Projects
  alias Lightning.Accounts.{User, UserToken}
  alias Lightning.Credentials.{Credential}

  describe "Setup demo site seed data" do
    setup do
      Lightning.SetupUtils.setup_demo(create_super: true)
    end

    test "all initial data is present in database", %{
      users: [super_user, admin, editor, viewer] = users,
      projects: [openhie_project, dhis2_project] = projects,
      workflows: [openhie_workflow, dhis2_workflow] = workflows,
      jobs:
        [
          fhir_standard_data,
          send_to_openhim,
          notify_upload_successful,
          notify_upload_failed,
          get_dhis2_data,
          upload_to_google_sheet
        ] = jobs
    } do
      assert users |> Enum.count() == 4
      assert projects |> Enum.count() == 2
      assert workflows |> Enum.count() == 2
      assert jobs |> Enum.count() == 6

      assert super_user.email == "super@openfn.org"
      User.valid_password?(super_user, "welcome12345")

      user_token =
        Lightning.Repo.all(UserToken)
        |> List.first()

      assert user_token.user_id == super_user.id
      assert user_token.context == "api"
      assert user_token.token =~ "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"

      assert openhie_project.id == "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa"

      assert admin.email == "demo@openfn.org"
      User.valid_password?(admin, "welcome12345")

      assert editor.email == "editor@openfn.org"
      User.valid_password?(editor, "welcome12345")

      assert viewer.email == "viewer@openfn.org"
      User.valid_password?(viewer, "welcome12345")

      assert Enum.map(
               openhie_project.project_users,
               fn project_user -> project_user.user_id end
             ) == [super_user.id, admin.id, editor.id, viewer.id]

      assert Enum.map(
               dhis2_project.project_users,
               fn project_user -> project_user.user_id end
             ) == [admin.id]

      assert fhir_standard_data.workflow_id == openhie_workflow.id
      assert send_to_openhim.workflow_id == openhie_workflow.id
      assert notify_upload_successful.workflow_id == openhie_workflow.id
      assert notify_upload_failed.workflow_id == openhie_workflow.id
      assert get_dhis2_data.workflow_id == dhis2_workflow.id
      assert upload_to_google_sheet.workflow_id == dhis2_workflow.id

      loaded_flow =
        Repo.get(Workflows.Workflow, openhie_workflow.id)
        |> Repo.preload([:edges, :triggers])

      assert Enum.find(loaded_flow.triggers, fn t ->
               t.type == :webhook
             end)

      assert Enum.find(loaded_flow.edges, fn e ->
               e.condition_type == :always &&
                 e.target_job_id == fhir_standard_data.id
             end)

      assert Enum.find(loaded_flow.edges, fn e ->
               e.condition_type == :on_job_success &&
                 e.source_job_id == fhir_standard_data.id &&
                 e.target_job_id == send_to_openhim.id
             end)

      assert Enum.find(loaded_flow.edges, fn e ->
               e.condition_type == :on_job_success &&
                 e.source_job_id == fhir_standard_data.id &&
                 e.target_job_id == send_to_openhim.id
             end)

      assert Enum.find(loaded_flow.edges, fn e ->
               e.condition_type == :on_job_success &&
                 e.target_job_id == notify_upload_successful.id &&
                 e.source_job_id == send_to_openhim.id
             end)

      assert Enum.find(loaded_flow.edges, fn e ->
               e.condition_type == :on_job_failure &&
                 e.target_job_id == notify_upload_failed.id &&
                 e.source_job_id == send_to_openhim.id
             end)

      loaded_dhis_flow =
        Repo.get(Workflows.Workflow, dhis2_workflow.id)
        |> Repo.preload([:edges, :triggers])

      assert Enum.find(loaded_dhis_flow.edges, fn e ->
               e.condition_type == :always &&
                 e.target_job_id == get_dhis2_data.id
             end)

      assert Enum.find(loaded_dhis_flow.edges, fn e ->
               e.condition_type == :on_job_success &&
                 e.source_job_id == get_dhis2_data.id &&
                 e.target_job_id == upload_to_google_sheet.id
             end)

      assert Enum.find(loaded_dhis_flow.triggers, fn t ->
               t.cron_expression == "0 * * * *"
             end)

      assert (Enum.map(users, fn user -> user.id end) --
                Enum.map(Accounts.list_users(), fn user -> user.id end))
             |> Enum.empty?()

      assert (Enum.map(projects, fn project -> project.id end) --
                Enum.map(Projects.list_projects(), fn project -> project.id end))
             |> Enum.empty?()

      assert (Enum.map(workflows, fn workflow -> workflow.id end) --
                Enum.map(Workflows.list_workflows(), fn workflow ->
                  workflow.id
                end))
             |> Enum.empty?()

      assert (Enum.map(jobs, fn job -> job.id end) --
                Enum.map(Jobs.list_jobs(), fn job -> job.id end))
             |> Enum.empty?()
    end

    test "create_starter_project/2", %{
      users: [super_user, admin, editor, viewer]
    } do
      %{
        project: project,
        workflow: workflow,
        jobs: [job_1, job_2, job_3] = jobs
      } =
        Lightning.SetupUtils.create_starter_project(
          "starter-project",
          [
            %{user_id: super_user.id, role: :owner},
            %{user_id: admin.id, role: :admin},
            %{user_id: editor.id, role: :editor},
            %{user_id: viewer.id, role: :viewer}
          ],
          with_workflow: true
        )

      workflow =
        Repo.preload(workflow, [:edges, :triggers, :project, jobs: [:credential]])

      assert workflow.jobs
             |> Enum.find(&(&1.name =~ "Job 3"))
             |> Map.get(:credential),
             "Job 3 should have a credential"

      assert workflow.project.id == project.id

      assert workflow.jobs |> Enum.map(fn job -> job.id end) |> Enum.sort() ==
               jobs |> Enum.map(fn job -> job.id end) |> Enum.sort()

      assert length(workflow.edges) == length(jobs)
      assert List.first(workflow.triggers).type == :webhook

      assert job_1.name == "Job 1 - Check if age is over 18 months"

      assert job_1.body == """
               fn(state => {
                 if (state.data.age_in_months > 18) {
                   console.log('Eligible for program.');
                   return state;
                 }
                 else { throw 'Error, patient ineligible.' }
               });
             """

      assert job_1.adaptor == "@openfn/language-common@latest"

      assert job_2.name == "Job 2 - Convert data to DHIS2 format"

      assert job_2.body == """
               fn(state => {
                 const names = state.data.name.split(' ');
                 return { ...state, names };
               });
             """

      assert job_2.adaptor == "@openfn/language-common@latest"

      assert job_3.name == "Job 3 - Upload to DHIS2"

      assert job_3.body == """
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
             """

      assert job_3.adaptor == "@openfn/language-dhis2@latest"

      assert_no_email_sent()
    end
  end

  describe "User setup" do
    test "create_users with `create_super: true` returns 4 valid users" do
      users = SetupUtils.create_users(create_super: true)

      assert %{
               super_user: %User{first_name: "Sizwe"},
               admin: %User{first_name: "Amy"},
               editor: %User{first_name: "Esther"},
               viewer: %User{first_name: "Vikram"}
             } =
               users
    end

    test "create_users with `create_super: false` returns nil for super_user" do
      users = SetupUtils.create_users(create_super: false)

      assert %{
               super_user: nil,
               admin: %User{first_name: "Amy"},
               editor: %User{first_name: "Esther", email: "editor@openfn.org"},
               viewer: %User{first_name: "Vikram"}
             } =
               users
    end
  end

  describe "Demo project creation" do
    setup do
      Lightning.SetupUtils.create_users(create_super: true)
    end

    test "create_openhie_project/1", %{
      super_user: super_user,
      admin: admin,
      editor: editor,
      viewer: viewer
    } do
      %{
        project: openhie_project,
        workflow: openhie_workflow,
        workorder: openhie_workorder,
        jobs:
          [
            fhir_standard_data,
            send_to_openhim,
            notify_upload_successful,
            notify_upload_failed
          ] = jobs
      } =
        Lightning.SetupUtils.create_openhie_project([
          %{user_id: super_user.id, role: :owner},
          %{user_id: admin.id, role: :admin},
          %{user_id: editor.id, role: :editor},
          %{user_id: viewer.id, role: :viewer}
        ])

      openhie_workflow =
        Repo.preload(openhie_workflow, [:edges, :jobs, :triggers, :project])

      assert openhie_workflow.project.id == openhie_project.id

      assert openhie_workflow.jobs
             |> Enum.map(fn job -> job.id end)
             |> Enum.sort() ==
               jobs |> Enum.map(fn job -> job.id end) |> Enum.sort()

      assert length(openhie_workflow.edges) == length(jobs)

      [trigger | _] = openhie_workflow.triggers
      assert trigger.type == :webhook
      assert trigger.id == "cae544ab-03dc-4ccc-a09c-fb4edb255d7a"

      assert fhir_standard_data.name == "Transform data to FHIR standard"

      assert fhir_standard_data.body == """
             fn(state => state);
             """

      assert fhir_standard_data.adaptor == "@openfn/language-http@latest"

      assert send_to_openhim.name == "Send to OpenHIM to route to SHR"

      assert send_to_openhim.body == """
             fn(state => state);
             """

      assert send_to_openhim.adaptor == "@openfn/language-http@latest"

      assert notify_upload_successful.name == "Notify CHW upload successful"

      assert notify_upload_successful.body == """
             fn(state => state);
             """

      assert notify_upload_successful.adaptor == "@openfn/language-http@latest"

      assert notify_upload_failed.name == "Notify CHW upload failed"

      assert notify_upload_failed.body == """
             fn(state => state);
             """

      assert notify_upload_failed.adaptor == "@openfn/language-http@latest"

      steps =
        openhie_workorder |> get_steps_from_workorder()

      first_step =
        steps
        |> Enum.at(0)
        |> Repo.preload([:input_dataclip, :output_dataclip])

      second_step =
        steps
        |> Enum.at(1)
        |> Repo.preload([:input_dataclip, :output_dataclip])

      last_step =
        steps
        |> Enum.at(2)
        |> Repo.preload([:input_dataclip, :output_dataclip])

      # first step is older than second step
      assert DateTime.diff(
               first_step.finished_at,
               second_step.finished_at,
               :millisecond
             ) < 0

      # second step is older than last step
      assert DateTime.diff(
               second_step.finished_at,
               last_step.finished_at,
               :millisecond
             ) <
               0

      assert first_step.exit_reason == "success"

      assert get_dataclip_body(first_step.input_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "formId" => "early_enrollment",
                   "patientId" => 1234,
                   "patientData" => %{
                     "name" => "Wally",
                     "surname" => "Robertson"
                   }
                 }
               }

      assert get_dataclip_body(first_step.output_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "formId" => "early_enrollment",
                   "patientId" => 1234,
                   "patientData" => %{
                     "name" => "Wally",
                     "surname" => "Robertson"
                   }
                 },
                 "references" => []
               }

      assert Invocation.assemble_logs_for_step(first_step) ==
               """
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
               """

      assert last_step.exit_reason == "success"

      assert get_dataclip_body(last_step.input_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "formId" => "early_enrollment",
                   "patientId" => 1234,
                   "patientData" => %{
                     "name" => "Wally",
                     "surname" => "Robertson"
                   }
                 },
                 "references" => []
               }

      assert get_dataclip_body(last_step.output_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "formId" => "early_enrollment",
                   "patientData" => %{
                     "name" => "Wally",
                     "surname" => "Robertson"
                   },
                   "patientId" => 1234
                 },
                 "references" => []
               }

      assert Invocation.assemble_logs_for_step(last_step) ==
               """
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
               """

      assert second_step.exit_reason == "success"

      assert get_dataclip_body(second_step.input_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "formId" => "early_enrollment",
                   "patientData" => %{
                     "name" => "Wally",
                     "surname" => "Robertson"
                   },
                   "patientId" => 1234
                 },
                 "references" => []
               }

      assert get_dataclip_body(second_step.output_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "formId" => "early_enrollment",
                   "patientData" => %{
                     "name" => "Wally",
                     "surname" => "Robertson"
                   },
                   "patientId" => 1234
                 },
                 "references" => []
               }

      assert Invocation.assemble_logs_for_step(second_step) ==
               """
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
               """
    end

    test "create_dhis2_project/1", %{
      super_user: super_user,
      admin: admin,
      editor: editor,
      viewer: viewer
    } do
      %{
        project: dhis2_project,
        workflow: dhis2_workflow,
        workorders: [failure_dhis2_workorder],
        jobs: [get_dhis2_data, upload_to_google_sheet] = jobs
      } =
        Lightning.SetupUtils.create_dhis2_project([
          %{user_id: super_user.id, role: :owner},
          %{user_id: admin.id, role: :admin},
          %{user_id: editor.id, role: :editor},
          %{user_id: viewer.id, role: :viewer}
        ])

      dhis2_workflow =
        Repo.preload(dhis2_workflow, [:edges, :jobs, :triggers, :project])

      assert dhis2_workflow.project.id == dhis2_project.id

      assert dhis2_workflow.jobs |> Enum.map(fn job -> job.id end) |> Enum.sort() ==
               jobs |> Enum.map(fn job -> job.id end) |> Enum.sort()

      assert length(dhis2_workflow.edges) == length(jobs)
      assert List.first(dhis2_workflow.triggers).type == :cron

      assert get_dhis2_data.name == "Get DHIS2 data"

      assert get_dhis2_data.body == """
             get('trackedEntityInstances/PQfMcpmXeFE');
             """

      assert get_dhis2_data.adaptor == "@openfn/language-dhis2@latest"

      assert upload_to_google_sheet.name == "Upload to Google Sheet"

      assert upload_to_google_sheet.body == """
             fn(state => state);
             """

      assert upload_to_google_sheet.adaptor == "@openfn/language-http@latest"

      steps =
        failure_dhis2_workorder |> get_steps_from_workorder()

      failed_step =
        steps
        |> Enum.at(1)
        |> Repo.preload([:input_dataclip, :output_dataclip])

      assert failed_step.exit_reason == "fail"

      assert get_dataclip_body(failed_step.input_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "spreadsheetId" => "wv5ftwhte",
                   "tableRange" => "A3:D3",
                   "updates" => %{"updatedCells" => 4}
                 },
                 "references" => [%{}]
               }

      assert failed_step.output_dataclip == nil

      assert Invocation.assemble_logs_for_step(failed_step) ==
               """
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
               """
    end
  end

  describe "Tear down demo data" do
    setup do
      Lightning.SetupUtils.setup_demo(create_super: true)
    end

    test "all initial data gets wiped out of database" do
      assert Lightning.Accounts.list_users() |> Enum.count() > 0
      assert Lightning.Projects.list_projects() |> Enum.count() == 2
      assert Lightning.Workflows.list_workflows() |> Enum.count() == 2
      assert Lightning.Jobs.list_jobs() |> Enum.count() == 6
      assert Repo.all(Lightning.Invocation.Step) |> Enum.count() == 5

      assert Repo.all(Lightning.Invocation.LogLine)
             |> Enum.count() > 0

      Lightning.SetupUtils.tear_down(destroy_super: true)

      assert Lightning.Accounts.list_users() |> Enum.count() == 0
      assert Lightning.Projects.list_projects() |> Enum.count() == 0
      assert Lightning.Workflows.list_workflows() |> Enum.count() == 0
      assert Lightning.Jobs.list_jobs() |> Enum.count() == 0
      assert Repo.all(Lightning.Invocation.Step) |> Enum.count() == 0

      assert Repo.all(Lightning.Invocation.LogLine)
             |> Enum.count() == 0
    end

    test "all initial data gets wiped out of database except superusers" do
      assert Lightning.Accounts.list_users() |> Enum.count() > 1
      assert Lightning.Projects.list_projects() |> Enum.count() == 2
      assert Lightning.Workflows.list_workflows() |> Enum.count() == 2
      assert Lightning.Jobs.list_jobs() |> Enum.count() == 6
      assert Repo.all(Lightning.Invocation.Step) |> Enum.count() == 5

      assert Repo.all(Lightning.Invocation.LogLine)
             |> Enum.count() > 0

      Lightning.SetupUtils.tear_down(destroy_super: false)

      assert Lightning.Accounts.list_users() |> Enum.count() == 1
      assert Lightning.Projects.list_projects() |> Enum.count() == 0
      assert Lightning.Workflows.list_workflows() |> Enum.count() == 0
      assert Lightning.Jobs.list_jobs() |> Enum.count() == 0
      assert Repo.all(Lightning.Invocation.Step) |> Enum.count() == 0

      assert Repo.all(Lightning.Invocation.LogLine)
             |> Enum.count() == 0
    end
  end

  describe "setup_user/3" do
    test "creates a user, an api token, and credentials" do
      assert {:ok, :ok} ==
               Lightning.SetupUtils.setup_user(
                 %{
                   first_name: "Taylor",
                   last_name: "Downs",
                   email: "contact@openfn.org",
                   password: "shh12345678!"
                 },
                 "abc123supersecret",
                 [
                   %{
                     name: "openmrs",
                     schema: "raw",
                     body: %{"a" => "secret"}
                   },
                   %{
                     name: "dhis2",
                     schema: "raw",
                     body: %{"b" => "safe"}
                   }
                 ]
               )

      # check that the user has been created
      assert %User{id: user_id} = Repo.get_by(User, email: "contact@openfn.org")

      # check that the apiToken has been created
      assert %UserToken{} = Repo.get_by(UserToken, token: "abc123supersecret")

      # check that the credentials have been created
      assert [
               %Credential{name: "openmrs", user_id: ^user_id},
               %Credential{name: "dhis2", user_id: ^user_id}
             ] = Repo.all(Credential)
    end

    test "can be used to set up a superuser" do
      assert {:ok, :ok} ==
               Lightning.SetupUtils.setup_user(
                 %{
                   role: :superuser,
                   first_name: "Super",
                   last_name: "Hero",
                   email: "super@openfn.org",
                   password: "easyAsCake123!"
                 },
                 "abc"
               )

      # check that the user has been created
      assert %User{id: _user_id, role: :superuser} =
               Repo.get_by(User, email: "super@openfn.org")
    end
  end

  defp get_dataclip_body(dataclip_id) do
    from(d in Lightning.Invocation.Dataclip,
      select: type(d.body, :string),
      where: d.id == ^dataclip_id
    )
    |> Repo.one()
  end

  defp get_steps_from_workorder(workorder, run_idx \\ 0) do
    run_query =
      Ecto.assoc(workorder, :runs)
      |> offset(^run_idx)
      |> limit(1)

    from(a in run_query, preload: [:steps])
    |> Repo.one()
    |> Map.get(:steps)
  end
end
