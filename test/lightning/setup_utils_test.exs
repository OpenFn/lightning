defmodule Lightning.SetupUtilsTest do
  use Lightning.DataCase, async: true
  # use Mimic

  alias Lightning.Accounts
  alias Lightning.Projects
  alias Lightning.Workflows
  alias Lightning.Jobs
  alias Lightning.Accounts.User

  describe "Setup demo site seed data" do
    setup do
      # stub(Lightning.WorkOrderService, :create_webhook_workorder, fn _job,
      #                                                                _dataclip_body ->
      #   {:ok, %{}}
      # end)

      # stub(Lightning.WorkOrderService, :create_manual_workorder, fn _job,
      #                                                               _dataclip_body,
      #                                                               _user ->
      #   {:ok, %{}}
      # end)

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

      assert admin.email == "demo@openfn.org"
      User.valid_password?(admin, "welcome123")

      assert editor.email == "editor@openfn.org"
      User.valid_password?(editor, "welcome123")

      assert viewer.email == "viewer@openfn.org"
      User.valid_password?(viewer, "welcome123")

      assert Enum.map(
               openhie_project.project_users,
               fn project_user -> project_user.user_id end
             ) == [admin.id, editor.id, viewer.id]

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
  end

  describe "Tear down demo data" do
    setup do
      Lightning.SetupUtils.setup_demo(create_super: true)
    end

    test "all initial data gets wiped out of database" do
      assert Lightning.Accounts.list_users() |> Enum.count() == 4
      assert Lightning.Projects.list_projects() |> Enum.count() == 2
      assert Lightning.Workflows.list_workflows() |> Enum.count() == 2
      assert Lightning.Jobs.list_jobs() |> Enum.count() == 6

      Lightning.SetupUtils.tear_down(destroy_super: true)

      assert Lightning.Accounts.list_users() |> Enum.count() == 0
      assert Lightning.Projects.list_projects() |> Enum.count() == 0
      assert Lightning.Workflows.list_workflows() |> Enum.count() == 0
      assert Lightning.Jobs.list_jobs() |> Enum.count() == 0
    end

    test "all initial data gets wiped out of database except superusers" do
      assert Lightning.Accounts.list_users() |> Enum.count() == 4
      assert Lightning.Projects.list_projects() |> Enum.count() == 2
      assert Lightning.Workflows.list_workflows() |> Enum.count() == 2
      assert Lightning.Jobs.list_jobs() |> Enum.count() == 6

      Lightning.SetupUtils.tear_down(destroy_super: false)

      assert Lightning.Accounts.list_users() |> Enum.count() == 1
      assert Lightning.Projects.list_projects() |> Enum.count() == 0
      assert Lightning.Workflows.list_workflows() |> Enum.count() == 0
      assert Lightning.Jobs.list_jobs() |> Enum.count() == 0
    end
  end
end
