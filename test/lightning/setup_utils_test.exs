defmodule Lightning.SetupUtilsTest do
  alias Lightning.Invocation
  use Lightning.DataCase, async: true
  # use Mimic

  alias Lightning.{Accounts, Projects, Workflows, Jobs, SetupUtils}
  alias Lightning.Accounts.User

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
      User.valid_password?(super_user, "welcome123")

      user_token =
        Lightning.Repo.all(Lightning.Accounts.UserToken)
        |> List.first()

      assert user_token.user_id == super_user.id
      assert user_token.context == "api"
      assert user_token.token =~ "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"

      assert openhie_project.id == "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa"

      assert admin.email == "demo@openfn.org"
      User.valid_password?(admin, "welcome123")

      assert editor.email == "editor@openfn.org"
      User.valid_password?(editor, "welcome123")

      assert viewer.email == "viewer@openfn.org"
      User.valid_password?(viewer, "welcome123")

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
               e.condition == :always &&
                 e.target_job_id == fhir_standard_data.id
             end)

      assert Enum.find(loaded_flow.edges, fn e ->
               e.condition == :on_job_success &&
                 e.source_job_id == fhir_standard_data.id &&
                 e.target_job_id == send_to_openhim.id
             end)

      assert Enum.find(loaded_flow.edges, fn e ->
               e.condition == :on_job_success &&
                 e.source_job_id == fhir_standard_data.id &&
                 e.target_job_id == send_to_openhim.id
             end)

      assert Enum.find(loaded_flow.edges, fn e ->
               e.condition == :on_job_success &&
                 e.target_job_id == notify_upload_successful.id &&
                 e.source_job_id == send_to_openhim.id
             end)

      assert Enum.find(loaded_flow.edges, fn e ->
               e.condition == :on_job_failure &&
                 e.target_job_id == notify_upload_failed.id &&
                 e.source_job_id == send_to_openhim.id
             end)

      loaded_dhis_flow =
        Repo.get(Workflows.Workflow, dhis2_workflow.id)
        |> Repo.preload([:edges, :triggers])

      assert Enum.find(loaded_dhis_flow.edges, fn e ->
               e.condition == :always &&
                 e.target_job_id == get_dhis2_data.id
             end)

      assert Enum.find(loaded_dhis_flow.edges, fn e ->
               e.condition == :on_job_success &&
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
        workorder: workorder,
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
          ]
        )

      workflow = Repo.preload(workflow, [:edges, :jobs, :triggers, :project])

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

      runs =
        workorder |> get_runs_from_workorder()

      first_run =
        runs
        |> Enum.at(0)
        |> Repo.preload([:input_dataclip, :output_dataclip])

      last_run =
        runs
        |> Enum.at(1)
        |> Repo.preload([:input_dataclip, :output_dataclip])

      # first run is older than second run
      assert DateTime.diff(
               first_run.finished_at,
               last_run.finished_at,
               :second
             ) < 0

      assert first_run.exit_reason == "success"

      assert get_dataclip_body(first_run.input_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "age_in_months" => 19,
                   "name" => "Genevieve Wimplemews"
                 }
               }

      assert get_dataclip_body(first_run.output_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "age_in_months" => 19,
                   "name" => "Genevieve Wimplemews"
                 },
                 "names" => ["Genevieve", "Wimplemews"]
               }

      assert Invocation.assemble_logs_for_run(first_run) ==
               """
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
               """

      assert last_run.exit_reason == "success"

      assert get_dataclip_body(last_run.input_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "age_in_months" => 19,
                   "name" => "Genevieve Wimplemews"
                 },
                 "names" => ["Genevieve", "Wimplemews"]
               }

      assert get_dataclip_body(last_run.output_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "httpStatus" => "OK",
                   "httpStatusCode" => 200,
                   "message" => "Import was successful.",
                   "response" => %{
                     "importSummaries" => [
                       %{
                         "href" =>
                           "https://play.dhis2.org/dev/api/trackedEntityInstances/iqJrb85GmJb",
                         "reference" => "iqJrb85GmJb",
                         "responseType" => "ImportSummary",
                         "status" => "SUCCESS"
                       }
                     ],
                     "imported" => 1,
                     "responseType" => "ImportSummaries",
                     "status" => "SUCCESS",
                     "total" => 1,
                     "updated" => 0
                   },
                   "status" => "OK"
                 },
                 "names" => ["Genevieve", "Wimplemews"],
                 "references" => [
                   %{"age_in_months" => 19, "name" => "Genevieve Wimplemews"}
                 ]
               }

      assert Invocation.assemble_logs_for_run(last_run) ==
               """
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
               """

      assert last_run.exit_reason == "success"

      assert get_dataclip_body(last_run.input_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "age_in_months" => 19,
                   "name" => "Genevieve Wimplemews"
                 },
                 "names" => ["Genevieve", "Wimplemews"]
               }

      assert get_dataclip_body(last_run.output_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "httpStatus" => "OK",
                   "httpStatusCode" => 200,
                   "message" => "Import was successful.",
                   "response" => %{
                     "importSummaries" => [
                       %{
                         "href" =>
                           "https://play.dhis2.org/dev/api/trackedEntityInstances/iqJrb85GmJb",
                         "reference" => "iqJrb85GmJb",
                         "responseType" => "ImportSummary",
                         "status" => "SUCCESS"
                       }
                     ],
                     "imported" => 1,
                     "responseType" => "ImportSummaries",
                     "status" => "SUCCESS",
                     "total" => 1,
                     "updated" => 0
                   },
                   "status" => "OK"
                 },
                 "names" => ["Genevieve", "Wimplemews"],
                 "references" => [
                   %{"age_in_months" => 19, "name" => "Genevieve Wimplemews"}
                 ]
               }

      assert Invocation.assemble_logs_for_run(last_run) == """
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
             """
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
               editor: %User{first_name: "Esther"},
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

      runs =
        openhie_workorder |> get_runs_from_workorder()

      first_run =
        runs
        |> Enum.at(0)
        |> Repo.preload([:input_dataclip, :output_dataclip])

      second_run =
        runs
        |> Enum.at(1)
        |> Repo.preload([:input_dataclip, :output_dataclip])

      last_run =
        runs
        |> Enum.at(2)
        |> Repo.preload([:input_dataclip, :output_dataclip])

      # first run is older than second run
      assert DateTime.diff(
               first_run.finished_at,
               second_run.finished_at,
               :second
             ) < 0

      # second run is older than last run
      assert DateTime.diff(second_run.finished_at, last_run.finished_at, :second) <
               0

      assert first_run.exit_reason == "success"

      assert get_dataclip_body(first_run.input_dataclip.id) |> Jason.decode!() ==
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

      assert get_dataclip_body(first_run.output_dataclip.id) |> Jason.decode!() ==
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

      assert Invocation.assemble_logs_for_run(first_run) ==
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

      assert last_run.exit_reason == "success"

      assert get_dataclip_body(last_run.input_dataclip.id) |> Jason.decode!() ==
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

      assert get_dataclip_body(last_run.output_dataclip.id) |> Jason.decode!() ==
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

      assert Invocation.assemble_logs_for_run(last_run) ==
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

      assert second_run.exit_reason == "success"

      assert get_dataclip_body(second_run.input_dataclip.id) |> Jason.decode!() ==
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

      assert get_dataclip_body(second_run.output_dataclip.id) |> Jason.decode!() ==
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

      assert Invocation.assemble_logs_for_run(second_run) == """
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

      runs =
        failure_dhis2_workorder |> get_runs_from_workorder()

      failed_run =
        runs
        |> Enum.at(1)
        |> Repo.preload([:input_dataclip, :output_dataclip])

      assert failed_run.exit_reason == "fail"

      assert get_dataclip_body(failed_run.input_dataclip.id) |> Jason.decode!() ==
               %{
                 "data" => %{
                   "spreadsheetId" => "wv5ftwhte",
                   "tableRange" => "A3:D3",
                   "updates" => %{"updatedCells" => 4}
                 },
                 "references" => [%{}]
               }

      assert failed_run.output_dataclip == nil

      assert Invocation.assemble_logs_for_run(failed_run) ==
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
      assert Repo.all(Lightning.Invocation.Run) |> Enum.count() == 5

      assert Repo.all(Lightning.Invocation.LogLine)
             |> Enum.count() > 0

      Lightning.SetupUtils.tear_down(destroy_super: true)

      assert Lightning.Accounts.list_users() |> Enum.count() == 0
      assert Lightning.Projects.list_projects() |> Enum.count() == 0
      assert Lightning.Workflows.list_workflows() |> Enum.count() == 0
      assert Lightning.Jobs.list_jobs() |> Enum.count() == 0
      assert Repo.all(Lightning.Invocation.Run) |> Enum.count() == 0

      assert Repo.all(Lightning.Invocation.LogLine)
             |> Enum.count() == 0
    end

    test "all initial data gets wiped out of database except superusers" do
      assert Lightning.Accounts.list_users() |> Enum.count() > 1
      assert Lightning.Projects.list_projects() |> Enum.count() == 2
      assert Lightning.Workflows.list_workflows() |> Enum.count() == 2
      assert Lightning.Jobs.list_jobs() |> Enum.count() == 6
      assert Repo.all(Lightning.Invocation.Run) |> Enum.count() == 5

      assert Repo.all(Lightning.Invocation.LogLine)
             |> Enum.count() > 0

      Lightning.SetupUtils.tear_down(destroy_super: false)

      assert Lightning.Accounts.list_users() |> Enum.count() == 1
      assert Lightning.Projects.list_projects() |> Enum.count() == 0
      assert Lightning.Workflows.list_workflows() |> Enum.count() == 0
      assert Lightning.Jobs.list_jobs() |> Enum.count() == 0
      assert Repo.all(Lightning.Invocation.Run) |> Enum.count() == 0

      assert Repo.all(Lightning.Invocation.LogLine)
             |> Enum.count() == 0
    end
  end

  defp get_dataclip_body(dataclip_id) do
    from(d in Lightning.Invocation.Dataclip,
      select: type(d.body, :string),
      where: d.id == ^dataclip_id
    )
    |> Repo.one()
  end

  defp get_runs_from_workorder(workorder, attempt_idx \\ 0) do
    workorder
    |> Repo.preload(attempts: [:runs])
    |> Map.get(:attempts)
    |> Enum.at(attempt_idx)
    |> Map.get(:runs)
  end
end
