defmodule Lightning.ProjectsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Invocation.Dataclip
  alias Lightning.Projects.ProjectUser
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Accounts.User

  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures
  import Lightning.CredentialsFixtures
  import Lightning.Factories
  import Swoosh.TestAssertions

  describe "projects" do
    @invalid_attrs %{name: nil}

    test "list_projects/0 returns all projects" do
      project = project_fixture() |> unload_relation(:project_users)
      assert Projects.list_projects() == [project]
    end

    test "list_project_credentials/1 returns all project_credentials for a project" do
      user = user_fixture()
      project = project_fixture(project_users: [%{user_id: user.id}])

      credential =
        credential_fixture(
          user_id: user.id,
          project_credentials: [%{project_id: project.id}]
        )

      assert Projects.list_project_credentials(project) ==
               credential.project_credentials |> Repo.preload(:credential)
    end

    test "get_project!/1 returns the project with given id" do
      project = project_fixture()
      assert Projects.get_project!(project.id) |> to_map() == project |> to_map()

      assert_raise Ecto.NoResultsError, fn ->
        Projects.get_project!(Ecto.UUID.generate())
      end
    end

    test "get_project/1 returns the project with given id" do
      assert Projects.get_project(Ecto.UUID.generate()) == nil

      project = project_fixture() |> unload_relation(:project_users)
      assert Projects.get_project(project.id) == project
    end

    test "get_project_with_users!/1 returns the project with given id" do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user_id: user.id, role: :editor}])
        |> Repo.preload(project_users: [:user])

      assert Projects.get_project_with_users!(project.id) == project
    end

    test "get_project_users!/1 returns the project users in order of first name" do
      user_a = user_fixture(first_name: "Anna")
      user_b = user_fixture(first_name: "Bob")

      project =
        project_fixture(
          project_users: [
            %{user_id: user_a.id},
            %{user_id: user_b.id}
          ]
        )

      assert [
               %ProjectUser{user: %User{first_name: "Anna"}},
               %ProjectUser{user: %User{first_name: "Bob"}}
             ] =
               Projects.get_project_users!(project.id)
    end

    test "get_project_user!/1 returns the project_user with given id" do
      project_user =
        insert(:project,
          project_users: [%{user_id: insert(:user).id, role: :editor}]
        ).project_users
        |> List.first()

      assert Projects.get_project_user!(project_user.id) == project_user

      assert_raise Ecto.NoResultsError, fn ->
        Projects.get_project_user!(Ecto.UUID.generate())
      end
    end

    test "get_project_user/1 returns the project_user with given id" do
      assert Projects.get_project_user(Ecto.UUID.generate()) == nil

      project_user =
        insert(:project,
          project_users: [%{user_id: insert(:user).id, role: :editor}]
        ).project_users
        |> List.first()

      assert Projects.get_project_user(project_user.id) == project_user
    end

    test "create_project/1 with valid data creates a project" do
      %{id: user_id} = insert(:user)

      valid_attrs = %{
        name: "some-name",
        project_users: [%{user_id: user_id, role: :owner}]
      }

      assert {:ok, %Project{id: project_id} = project} =
               Projects.create_project(valid_attrs)

      assert project.name == "some-name"

      assert [%{project_id: ^project_id, user_id: ^user_id, role: :owner}] =
               project.project_users
    end

    test "create_project/1 expects project to have exactly one owner" do
      user = insert(:user)

      # creates successfully if there's one
      assert {:ok, _project} =
               Projects.create_project(%{
                 name: "some-name",
                 project_users: [%{user_id: user.id, role: :owner}]
               })

      # errors out if there is none
      for role <- [:admin, :editor, :viewer] do
        assert {:error, %Ecto.Changeset{errors: errors}} =
                 Projects.create_project(%{
                   name: "some-name",
                   project_users: [%{user_id: user.id, role: role}]
                 })

        assert [
                 {:owner,
                  {"Every project must have exactly one owner. Please specify one below.",
                   []}}
               ] ==
                 errors
      end

      # errors out if there is more than one
      another_user = insert(:user)

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Projects.create_project(%{
                 name: "some-name",
                 project_users: [
                   %{user_id: user.id, role: :owner},
                   %{user_id: another_user.id, role: :owner}
                 ]
               })

      assert [{:owner, {"A project can have only one owner.", []}}] ==
               errors
    end

    test "create_project/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Projects.create_project(@invalid_attrs)

      assert {:error, %Ecto.Changeset{}} =
               Projects.create_project(%{"name" => "Can't have spaces!"})
    end

    test "update_project/2 with valid data updates the project" do
      project = project_fixture()
      update_attrs = %{name: "some-updated-name"}

      assert {:ok, %Project{} = project} =
               Projects.update_project(project, update_attrs)

      assert project.name == "some-updated-name"
    end

    test "update_project/2 updates the MFA requirement" do
      project = insert(:project)

      refute project.requires_mfa
      update_attrs = %{requires_mfa: true}

      assert {:ok, %Project{} = project} =
               Projects.update_project(project, update_attrs)

      assert project.requires_mfa
    end

    test "update_project/2 updates the data retention periods" do
      project =
        insert(:project,
          project_users:
            Enum.map(
              [
                :viewer,
                :editor,
                :admin,
                :owner
              ],
              fn role -> build(:project_user, user: build(:user), role: role) end
            )
        )

      update_attrs = %{
        history_retention_period: 14,
        dataclip_retention_period: 7
      }

      assert {:ok, %Project{} = updated_project} =
               Projects.update_project(project, update_attrs)

      # admins and owners receives an email
      admins =
        Enum.filter(project.project_users, fn %{role: role} ->
          role in [:admin, :owner]
        end)

      assert Enum.count(admins) == 2

      for %{user: user} <- admins do
        assert_email_sent(data_retention_change_email(user, updated_project))
      end

      # editors and viewers do not receive any email
      non_admins =
        Enum.filter(project.project_users, fn %{role: role} ->
          role in [:editor, :viewer]
        end)

      assert Enum.count(non_admins) == 2

      for %{user: user} <- non_admins do
        assert_email_not_sent(data_retention_change_email(user, updated_project))
      end

      # no email is sent when there's no change
      assert {:ok, updated_project} =
               Projects.update_project(updated_project, update_attrs)

      for %{user: user} <- project.project_users do
        assert_email_not_sent(data_retention_change_email(user, updated_project))
      end

      # no email is sent when there's an error in the changeset
      assert {:error, _changeset} =
               Projects.update_project(updated_project, %{
                 history_retention_period: "xyz",
                 dataclip_retention_period: 7
               })

      for %{user: user} <- project.project_users do
        assert_email_not_sent(data_retention_change_email(user, updated_project))
      end
    end

    test "update_project/2 with invalid data returns error changeset" do
      project = project_fixture() |> unload_relation(:project_users)

      assert {:error, %Ecto.Changeset{}} =
               Projects.update_project(project, @invalid_attrs)

      assert project == Projects.get_project!(project.id)
    end

    test "update_project_user/2 with valid data updates the project_user" do
      project =
        project_fixture(
          project_users: [
            %{
              user_id: user_fixture().id,
              role: :viewer,
              digest: :daily,
              failure_alert: false
            }
          ]
        )

      update_attrs = %{digest: "weekly"}

      assert {:ok, %ProjectUser{} = project_user} =
               Projects.update_project_user(
                 project.project_users |> List.first(),
                 update_attrs
               )

      assert project_user.digest == :weekly
      assert project_user.failure_alert == false
    end

    test "update_project_user/2 with invalid data returns error changeset" do
      project =
        project_fixture(
          project_users: [
            %{
              user_id: user_fixture().id,
              role: :viewer,
              digest: :monthly,
              failure_alert: true
            }
          ]
        )

      project_user = project.project_users |> List.first()

      update_attrs = %{digest: "bad_value"}

      assert {:error, %Ecto.Changeset{}} =
               Projects.update_project_user(project_user, update_attrs)

      assert project_user == Projects.get_project_user!(project_user.id)
    end

    test "delete_project/1 deletes the project" do
      %{project: p1, workflow_1_job: w1_job, workflow_1: w1} =
        full_project_fixture(
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      t1 = insert(:trigger, %{workflow: w1, type: :webhook})

      e1 =
        insert(:edge, %{
          workflow: w1,
          source_trigger: t1,
          target_job: w1_job
        })

      %{
        project: p2,
        workflow_2_job: w2_job,
        workflow_2: w2
      } = full_project_fixture()

      t2 = insert(:trigger, %{workflow: w2, type: :webhook})

      e2 =
        build(:edge, %{
          workflow: w2,
          source_trigger: t2,
          target_job: w2_job
        })
        |> insert()

      {:ok, p1_pu} = p1.project_users |> Enum.fetch(0)

      p1_user = Lightning.Accounts.get_user!(p1_pu.user_id)

      p1_dataclip = insert(:dataclip, body: %{foo: "bar"}, project: p1)

      p1_step_1 = insert(:step, input_dataclip: p1_dataclip, job: e1.target_job)
      p1_step_2 = insert(:step, input_dataclip: p1_dataclip, job: e1.target_job)

      insert(:workorder,
        trigger: t1,
        dataclip: p1_dataclip,
        workflow: w1,
        runs: [
          build(:run,
            starting_trigger: e1.source_trigger,
            dataclip: p1_dataclip,
            steps: [p1_step_1],
            log_lines: build_list(2, :log_line, step: p1_step_1)
          ),
          build(:run,
            starting_trigger: e1.source_trigger,
            dataclip: p1_dataclip,
            created_by: p1_user,
            steps: [p1_step_2],
            log_lines: build_list(2, :log_line, step: p1_step_1)
          )
        ]
      )

      p2_dataclip = insert(:dataclip, body: %{foo: "bar"}, project: p2)

      p2_step = insert(:step, input_dataclip: p2_dataclip, job: e2.target_job)

      p2_log_line = build(:log_line, step: p2_step)

      insert(:workorder,
        trigger: t2,
        workflow: w2,
        dataclip: p2_dataclip,
        runs:
          build_list(1, :run,
            starting_trigger: e2.source_trigger,
            dataclip: p2_dataclip,
            steps: [p2_step],
            log_lines: [p2_log_line]
          )
      )

      steps_query = Lightning.Projects.project_steps_query(p1)

      work_order_query = Lightning.Projects.project_workorders_query(p1)

      run_query = Lightning.Projects.project_runs_query(p1)

      run_step_query = Lightning.Projects.project_run_step_query(p1)

      pu_query = Lightning.Projects.project_users_query(p1)

      pc_query = Lightning.Projects.project_credentials_query(p1)

      workflows_query = Lightning.Projects.project_workflows_query(p1)

      jobs_query = Lightning.Projects.project_jobs_query(p1)

      assert steps_query |> Repo.aggregate(:count, :id) == 2

      assert work_order_query |> Repo.aggregate(:count, :id) == 1

      assert run_query |> Repo.aggregate(:count, :id) == 2

      assert run_step_query |> Repo.aggregate(:count, :id) == 2

      assert pu_query |> Repo.aggregate(:count, :id) == 1

      assert pc_query |> Repo.aggregate(:count, :id) == 1

      assert workflows_query |> Repo.aggregate(:count, :id) == 2,
             "There should be only two workflows"

      assert jobs_query |> Repo.aggregate(:count, :id) == 5,
             "There should be only five jobs"

      assert Repo.all(Lightning.Invocation.LogLine)
             |> Enum.count() == 5

      assert {:ok, %Project{}} = Projects.delete_project(p1)

      assert steps_query |> Repo.aggregate(:count, :id) == 0

      assert work_order_query |> Repo.aggregate(:count, :id) == 0

      assert run_query |> Repo.aggregate(:count, :id) == 0

      assert run_step_query |> Repo.aggregate(:count, :id) == 0

      assert pu_query |> Repo.aggregate(:count, :id) == 0

      assert pc_query |> Repo.aggregate(:count, :id) == 0

      assert workflows_query |> Repo.aggregate(:count, :id) == 0

      assert jobs_query |> Repo.aggregate(:count, :id) == 0

      assert only_record_for_type?(p2_log_line)

      assert_raise Ecto.NoResultsError, fn ->
        Projects.get_project!(p1.id)
      end

      assert p2.id == Projects.get_project!(p2.id).id

      assert Lightning.Projects.project_steps_query(p2)
             |> Repo.aggregate(:count, :id) == 1
    end

    test "change_project/1 returns a project changeset" do
      project = project_fixture()
      assert %Ecto.Changeset{} = Projects.change_project(project)
    end

    test "get_projects_for_user/1 won't get scheduled for deletion projects" do
      user = user_fixture()

      project_1 =
        project_fixture(project_users: [%{user_id: user.id}])
        |> Repo.reload()

      project_fixture(
        project_users: [%{user_id: user.id}],
        scheduled_deletion: Timex.now()
      )
      |> Repo.reload()

      assert [project_1] == Projects.get_projects_for_user(user)
    end

    test "get projects for a given user" do
      user = user_fixture()
      other_user = user_fixture()

      project_1 =
        project_fixture(
          project_users: [%{user_id: user.id}, %{user_id: other_user.id}]
        )
        |> Repo.reload()

      project_2 =
        project_fixture(project_users: [%{user_id: user.id}])
        |> Repo.reload()

      user_projects = Projects.get_projects_for_user(user)
      assert project_1 in user_projects
      assert project_2 in user_projects
      assert [project_1] == Projects.get_projects_for_user(other_user)
    end

    test "get_project_user_role/2" do
      user_1 = user_fixture()
      user_2 = user_fixture()

      project =
        project_fixture(
          project_users: [
            %{user_id: user_1.id, role: :admin},
            %{user_id: user_2.id, role: :editor}
          ]
        )
        |> Repo.reload()

      assert Projects.get_project_user_role(user_1, project) == :admin
      assert Projects.get_project_user_role(user_2, project) == :editor
    end

    test "export_project/2 as yaml works on project with no workflows" do
      project = project_fixture(name: "newly-created-project")

      expected_yaml =
        "name: newly-created-project\n# description:\n# credentials:\n# globals:\n# workflows:"

      {:ok, generated_yaml} = Projects.export_project(:yaml, project.id)

      assert generated_yaml == expected_yaml
    end

    test "export_project/2 as yaml" do
      %{project: project} =
        full_project_fixture(
          name: "a-test-project",
          description: "This is only a test"
        )

      expected_yaml =
        File.read!("test/fixtures/canonical_project.yaml") |> String.trim()

      {:ok, generated_yaml} = Projects.export_project(:yaml, project.id)

      assert generated_yaml == expected_yaml
    end

    test "schedule_project_deletion/1 schedules a project for deletion and notify all project users via email." do
      user_1 = user_fixture(email: "user_1@openfn.org", first_name: "user_1")
      user_2 = user_fixture(email: "user_2@openfn.org", first_name: "user_2")

      project =
        project_fixture(
          name: "project-to-delete",
          project_users: [%{user_id: user_1.id}, %{user_id: user_2.id}]
        )

      assert project.scheduled_deletion == nil

      Projects.schedule_project_deletion(project)

      project = Projects.get_project!(project.id)
      assert project.scheduled_deletion != nil

      admin_email = Lightning.Config.instance_admin_email()

      [user_2, user_1]
      |> Enum.each(fn user ->
        to = [{"", user.email}]

        text_body =
          "Hi #{user.first_name},\n\n#{project.name} project has been scheduled for deletion. All of the workflows in this project have been disabled,\nand the resources will be deleted in 7 day(s) from today at 02:00 UTC. If this doesn't sound right, please email\n#{admin_email} to cancel the deletion.\n"

        assert_receive {:email,
                        %Swoosh.Email{
                          subject: "Project scheduled for deletion",
                          to: ^to,
                          text_body: ^text_body
                        }}
      end)
    end

    test "schedule_project_deletion/1 schedules a project for deletion to now when purge_deleted_after_days is nil" do
      Mox.stub(Lightning.MockConfig, :purge_deleted_after_days, fn -> nil end)

      %{project: project} = full_project_fixture()

      {:ok, %{scheduled_deletion: scheduled_deletion}} =
        Projects.schedule_project_deletion(project)

      assert Timex.diff(scheduled_deletion, DateTime.utc_now(), :seconds) <= 10
    end

    test "schedule_project_deletion/1 schedules a project for deletion to purge_deleted_after_days days from now" do
      days = Lightning.Config.purge_deleted_after_days()

      %{project: project} = full_project_fixture()

      project_triggers = Projects.project_triggers_query(project) |> Repo.all()

      assert Enum.all?(project_triggers, & &1.enabled)

      assert project.scheduled_deletion == nil

      now = DateTime.utc_now() |> DateTime.add(-1, :second)
      {:ok, project} = Projects.schedule_project_deletion(project)

      project_triggers = Projects.project_triggers_query(project) |> Repo.all()

      assert Enum.all?(project_triggers, &(!&1.enabled))

      assert project.scheduled_deletion != nil
      assert Timex.diff(project.scheduled_deletion, now, :days) == days
    end

    test "cancel_scheduled_deletion/2" do
      project =
        project_fixture(
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert project.scheduled_deletion

      {:ok, project} = Projects.cancel_scheduled_deletion(project.id)

      refute project.scheduled_deletion
    end

    test "schedule deletion changeset" do
      project = project_fixture()

      errors =
        Project.deletion_changeset(project, %{
          "scheduled_deletion" => nil
        })
        |> errors_on()

      assert errors[:scheduled_deletion] == nil
    end
  end

  describe "list_projects_having_history_retention/0" do
    test "returns a list of projects having history_retention_period set" do
      project_1 = insert(:project, history_retention_period: 7)
      _project_2 = insert(:project, history_retention_period: nil)

      assert [project_1] == Projects.list_projects_having_history_retention()
    end
  end

  describe "list_project_admin_emails/1" do
    test "lists emails for users with admin or owner roles in the project" do
      project = insert(:project)

      owner =
        insert(:project_user, project: project, role: :owner, user: build(:user))

      admin =
        insert(:project_user, project: project, role: :admin, user: build(:user))

      editor =
        insert(:project_user,
          project: project,
          role: :editor,
          user: build(:user)
        )

      viewer =
        insert(:project_user,
          project: project,
          role: :viewer,
          user: build(:user)
        )

      emails = Projects.list_project_admin_emails(project.id)

      assert owner.user.email in emails
      assert admin.user.email in emails

      refute editor.user.email in emails
      refute viewer.user.email in emails
    end
  end

  describe "The default Oban function Projects.perform/1" do
    test "removes all projects past deletion date when called with type 'purge_deleted'" do
      project_to_delete =
        project_fixture(
          scheduled_deletion: DateTime.utc_now() |> Timex.shift(seconds: -10)
        )

      project_fixture(
        scheduled_deletion: DateTime.utc_now() |> Timex.shift(seconds: 10)
      )

      count_before = Repo.all(Project) |> Enum.count()

      {:ok, %{projects_deleted: projects_deleted}} =
        Projects.perform(%Oban.Job{args: %{"type" => "purge_deleted"}})

      assert count_before - 1 == Repo.all(Project) |> Enum.count()
      assert 1 == projects_deleted |> Enum.count()

      assert project_to_delete.id ==
               projects_deleted |> Enum.at(0) |> Map.get(:id)
    end
  end

  describe "Projects.perform/1 for data retention periods" do
    test "deletes history for workorders based on last_activity" do
      project = insert(:project, history_retention_period: 7)

      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project)

      now = DateTime.utc_now()

      workorder_to_delete =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -7),
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            build(:run,
              starting_trigger: trigger,
              dataclip: build(:dataclip),
              log_lines: [build(:log_line)],
              steps: [build(:step, job: job)]
            )
          ]
        )

      workorder_to_remain =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -6),
          trigger: trigger,
          dataclip: build(:dataclip),
          runs: [
            build(:run,
              starting_trigger: trigger,
              dataclip: build(:dataclip),
              log_lines: [build(:log_line)],
              steps: [build(:step, job: job)]
            )
          ]
        )

      assert :ok =
               Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      # deleted history
      refute Lightning.Repo.get(Lightning.WorkOrder, workorder_to_delete.id)
      run_to_delete = hd(workorder_to_delete.runs)
      refute Lightning.Repo.get(Lightning.Run, run_to_delete.id)
      step_to_delete = hd(run_to_delete.steps)
      refute Lightning.Repo.get(Lightning.Invocation.Step, step_to_delete.id)
      log_line_to_delete = hd(run_to_delete.log_lines)

      refute Lightning.Repo.get_by(
               Lightning.Invocation.LogLine,
               id: log_line_to_delete.id
             )

      # remaining history
      assert Lightning.Repo.get(Lightning.WorkOrder, workorder_to_remain.id)
      run_to_remain = hd(workorder_to_remain.runs)
      assert Lightning.Repo.get(Lightning.Run, run_to_remain.id)
      step_to_remain = hd(run_to_remain.steps)
      assert Lightning.Repo.get(Lightning.Invocation.Step, step_to_remain.id)
      log_line_to_remain = hd(run_to_remain.log_lines)

      assert Lightning.Repo.get_by(
               Lightning.Invocation.LogLine,
               id: log_line_to_remain.id
             )

      # extra checks. Jobs, Triggers, Workflows are not deleted
      assert Repo.get(Lightning.Workflows.Job, job.id)
      assert Repo.get(Lightning.Workflows.Trigger, trigger.id)
      assert Repo.get(Lightning.Workflows.Workflow, workflow.id)
    end

    test "deletes project dataclips not associated to any work order correctly" do
      project = insert(:project, history_retention_period: 7)
      workflow = insert(:simple_workflow, project: project)
      now = DateTime.utc_now()

      # pre_retention means it exists earlier than the retention cut off time
      # post_retention means it exists later than the retention cut off time

      pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # opharn to mean not associated to any workorder
      opharn_pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      opharn_post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # to delete
      workorder_to_delete_1 =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -8),
          dataclip: post_retention_dataclip
        )

      # note that we've used pre_retention_dataclip for these 2 workorders.
      # to delete
      workorder_to_delete_2 =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -8),
          dataclip: pre_retention_dataclip
        )

      # will remain
      workorder_to_remain =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -6),
          dataclip: pre_retention_dataclip
        )

      assert :ok =
               Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      # the workorders are deleted correctly
      refute Lightning.Repo.get(Lightning.WorkOrder, workorder_to_delete_1.id)
      refute Lightning.Repo.get(Lightning.WorkOrder, workorder_to_delete_2.id)
      assert Lightning.Repo.get(Lightning.WorkOrder, workorder_to_remain.id)

      # pre_retention_dataclip is not deleted because it is still linked to workorder_to_remain which was not deleted
      assert workorder_to_delete_2.dataclip_id == pre_retention_dataclip.id
      assert workorder_to_remain.dataclip_id == pre_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, pre_retention_dataclip.id)

      # post_retention_dataclip is not deleted because it exists later than the cut off time
      # the workorder it was attached to was deleted
      assert workorder_to_delete_1.dataclip_id == post_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, post_retention_dataclip.id)

      # opharn_post_retention_dataclip is not deleted because it exists later than the cut off time
      # this dataclip was never attached to any workorder
      assert Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_post_retention_dataclip.id
             )

      # opharn_pre_retention_dataclip is deleted because it exists earlier than the cut off time
      # this dataclip was never attached to any workorder
      refute Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_pre_retention_dataclip.id
             )
    end

    test "deletes project dataclips not associated to any run correctly" do
      project = insert(:project, history_retention_period: 7)

      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow, project: project)

      now = DateTime.utc_now()

      # pre_retention means it exists earlier than the retention cut off time
      # post_retention means it exists later than the retention cut off time

      pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # opharn to mean not associated to any run
      opharn_pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      opharn_post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # to delete
      workorder_to_delete_1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          last_activity: Timex.shift(now, days: -8)
        )

      run_to_delete_1 =
        insert(:run,
          work_order: workorder_to_delete_1,
          starting_trigger: trigger,
          dataclip: post_retention_dataclip
        )

      # note that we've used pre_retention_dataclip for these 2 runs.
      # to delete
      run_to_delete_2 =
        insert(:run,
          work_order: workorder_to_delete_1,
          starting_trigger: trigger,
          dataclip: pre_retention_dataclip
        )

      # will remain
      workorder_to_remain =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -6)
        )

      run_to_remain =
        insert(:run,
          work_order: workorder_to_remain,
          starting_trigger: trigger,
          dataclip: pre_retention_dataclip
        )

      assert :ok =
               Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      # the runs are deleted correctly
      refute Lightning.Repo.get(Lightning.Run, run_to_delete_1.id)
      refute Lightning.Repo.get(Lightning.Run, run_to_delete_2.id)
      assert Lightning.Repo.get(Lightning.Run, run_to_remain.id)

      # pre_retention_dataclip is not deleted because it is still linked to run_to_remain which was not deleted
      assert run_to_delete_2.dataclip_id == pre_retention_dataclip.id
      assert run_to_remain.dataclip_id == pre_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, pre_retention_dataclip.id)

      # post_retention_dataclip is not deleted because it exists later than the cut off time
      # the run it was attached to was deleted
      assert run_to_delete_1.dataclip_id == post_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, post_retention_dataclip.id)

      # opharn_post_retention_dataclip is not deleted because it exists later than the cut off time
      # this dataclip was never attached to any run
      assert Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_post_retention_dataclip.id
             )

      # opharn_pre_retention_dataclip is deleted because it exists earlier than the cut off time
      # this dataclip was never attached to any run
      refute Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_pre_retention_dataclip.id
             )
    end

    test "deletes project dataclips not associated to any step input_dataclip correctly" do
      project = insert(:project, history_retention_period: 7)

      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project)

      now = DateTime.utc_now()

      # pre_retention means it exists earlier than the retention cut off time
      # post_retention means it exists later than the retention cut off time

      pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # opharn to mean not associated to any step
      opharn_pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      opharn_post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # to delete
      workorder_to_delete_1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          last_activity: Timex.shift(now, days: -8)
        )

      run_to_delete_1 =
        insert(:run,
          work_order: workorder_to_delete_1,
          starting_trigger: trigger,
          dataclip: build(:dataclip)
        )

      step_to_delete_1 =
        insert(:step,
          runs: [run_to_delete_1],
          job: job,
          input_dataclip: post_retention_dataclip
        )

      # note that we've used pre_retention_dataclip for these 2 steps.
      # to delete
      run_to_delete_2 =
        insert(:run,
          work_order: workorder_to_delete_1,
          starting_trigger: trigger,
          dataclip: build(:dataclip)
        )

      step_to_delete_2 =
        insert(:step,
          runs: [run_to_delete_2],
          job: job,
          input_dataclip: pre_retention_dataclip
        )

      # will remain
      workorder_to_remain =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -6)
        )

      run_to_remain =
        insert(:run,
          work_order: workorder_to_remain,
          starting_trigger: trigger,
          dataclip: build(:dataclip)
        )

      step_to_remain =
        insert(:step,
          runs: [run_to_remain],
          job: job,
          input_dataclip: pre_retention_dataclip
        )

      assert :ok =
               Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      # the steps are deleted correctly
      refute Lightning.Repo.get(Lightning.Invocation.Step, step_to_delete_1.id)
      refute Lightning.Repo.get(Lightning.Invocation.Step, step_to_delete_2.id)
      assert Lightning.Repo.get(Lightning.Invocation.Step, step_to_remain.id)

      # pre_retention_dataclip is NOT deleted because it is still linked to step_to_remain which was not deleted
      assert step_to_delete_2.input_dataclip_id == pre_retention_dataclip.id
      assert step_to_remain.input_dataclip_id == pre_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, pre_retention_dataclip.id)

      # post_retention_dataclip is NOT deleted because it exists later than the cut off time
      # the step it was attached to was deleted
      assert step_to_delete_1.input_dataclip_id == post_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, post_retention_dataclip.id)

      # opharn_post_retention_dataclip is NOT deleted because it exists later than the cut off time
      # this dataclip was never attached to any step
      assert Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_post_retention_dataclip.id
             )

      # opharn_pre_retention_dataclip is deleted because it exists earlier than the cut off time
      # this dataclip was never attached to any step
      refute Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_pre_retention_dataclip.id
             )
    end

    test "deletes project dataclips not associated to any step output_dataclip correctly" do
      project = insert(:project, history_retention_period: 7)

      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project)

      now = DateTime.utc_now()

      # pre_retention means it exists earlier than the retention cut off time
      # post_retention means it exists later than the retention cut off time

      pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # opharn to mean not associated to any workorder
      opharn_pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      opharn_post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # to delete
      workorder_to_delete_1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          last_activity: Timex.shift(now, days: -8)
        )

      run_to_delete_1 =
        insert(:run,
          work_order: workorder_to_delete_1,
          starting_trigger: trigger,
          dataclip: build(:dataclip)
        )

      step_to_delete_1 =
        insert(:step,
          runs: [run_to_delete_1],
          job: job,
          output_dataclip: post_retention_dataclip
        )

      # note that we've used pre_retention_dataclip for these 2 steps.
      # to delete
      run_to_delete_2 =
        insert(:run,
          work_order: workorder_to_delete_1,
          starting_trigger: trigger,
          dataclip: build(:dataclip)
        )

      step_to_delete_2 =
        insert(:step,
          runs: [run_to_delete_2],
          job: job,
          output_dataclip: pre_retention_dataclip
        )

      # will remain
      workorder_to_remain =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -6)
        )

      run_to_remain =
        insert(:run,
          work_order: workorder_to_remain,
          starting_trigger: trigger,
          dataclip: build(:dataclip)
        )

      step_to_remain =
        insert(:step,
          runs: [run_to_remain],
          job: job,
          output_dataclip: pre_retention_dataclip
        )

      assert :ok =
               Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      # the steps are deleted correctly
      refute Lightning.Repo.get(Lightning.Invocation.Step, step_to_delete_1.id)
      refute Lightning.Repo.get(Lightning.Invocation.Step, step_to_delete_2.id)
      assert Lightning.Repo.get(Lightning.Invocation.Step, step_to_remain.id)

      # pre_retention_dataclip is NOT deleted because it is still linked to step_to_remain which was not deleted
      assert step_to_delete_2.output_dataclip_id == pre_retention_dataclip.id
      assert step_to_remain.output_dataclip_id == pre_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, pre_retention_dataclip.id)

      # post_retention_dataclip is NOT deleted because it exists later than the cut off time
      # the step it was attached to was deleted
      assert step_to_delete_1.output_dataclip_id == post_retention_dataclip.id
      assert Repo.get(Lightning.Invocation.Dataclip, post_retention_dataclip.id)

      # opharn_post_retention_dataclip is NOT deleted because it exists later than the cut off time
      # this dataclip was never attached to any step
      assert Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_post_retention_dataclip.id
             )

      # opharn_pre_retention_dataclip is deleted because it exists earlier than the cut off time
      # this dataclip was never attached to any step
      refute Repo.get(
               Lightning.Invocation.Dataclip,
               opharn_pre_retention_dataclip.id
             )
    end

    test "does not wipe dataclips if history_retention_period is not set" do
      project =
        insert(:project,
          history_retention_period: nil,
          dataclip_retention_period: 10
        )

      dataclip =
        insert(:dataclip,
          project: project,
          request: %{star: "sadio mane"},
          type: :http_request,
          body: %{team: "senegal"},
          inserted_at: Timex.now() |> Timex.shift(days: -12)
        )

      :ok = Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      dataclip = dataclip_with_body_and_request(dataclip)

      assert dataclip.request === %{"star" => "sadio mane"}
      assert dataclip.body === %{"team" => "senegal"}
      assert dataclip.wiped_at == nil
    end

    test "does not wipe dataclips within the retention period" do
      project =
        insert(:project,
          history_retention_period: 14,
          dataclip_retention_period: 10
        )

      dataclip_1 =
        insert(:dataclip,
          project: project,
          request: %{star: "sadio mane"},
          type: :http_request,
          body: %{team: "senegal"},
          inserted_at: Timex.now() |> Timex.shift(days: -9)
        )

      :ok = Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      dataclip_1 = dataclip_with_body_and_request(dataclip_1)

      assert dataclip_1.request === %{"star" => "sadio mane"}
      assert dataclip_1.body === %{"team" => "senegal"}
      assert dataclip_1.wiped_at == nil
    end

    test "wipes dataclips past the retention period" do
      project =
        insert(:project,
          history_retention_period: 14,
          dataclip_retention_period: 10
        )

      dataclip =
        insert(:dataclip,
          project: project,
          request: %{star: "sadio mane"},
          type: :step_result,
          body: %{team: "senegal"},
          inserted_at: Timex.now() |> Timex.shift(days: -11)
        )

      :ok = Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      dataclip = dataclip_with_body_and_request(dataclip)

      refute dataclip.request
      refute dataclip.body
      refute is_nil(dataclip.wiped_at)
    end

    test "does not wipe dataclips without a set retention period" do
      project = insert(:project)

      dataclip =
        insert(:dataclip,
          project: project,
          request: %{star: "sadio mane"},
          type: :saved_input,
          body: %{team: "senegal"}
        )

      :ok = Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      dataclip = dataclip_with_body_and_request(dataclip)

      assert dataclip.request == %{"star" => "sadio mane"}
      assert dataclip.body == %{"team" => "senegal"}
      assert is_nil(dataclip.wiped_at)
    end

    test "does not wipe global dataclips" do
      project =
        insert(:project,
          history_retention_period: 14,
          dataclip_retention_period: 5
        )

      dataclip =
        insert(:dataclip,
          project: project,
          request: %{star: "sadio mane"},
          type: :global,
          body: %{team: "senegal"},
          inserted_at: Timex.now() |> Timex.shift(days: -6)
        )

      :ok = Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      dataclip = dataclip_with_body_and_request(dataclip)

      assert dataclip.request === %{"star" => "sadio mane"}
      assert dataclip.body === %{"team" => "senegal"}
      assert is_nil(dataclip.wiped_at)
    end
  end

  @spec full_project_fixture(attrs :: Keyword.t()) :: %{optional(any) => any}
  def full_project_fixture(attrs \\ []) when is_list(attrs) do
    %{workflows: [workflow_1, workflow_2]} =
      project = canonical_project_fixture(attrs)

    insert(:job,
      name: "unrelated job"
    )

    %{
      project: project,
      workflow_1: workflow_1,
      workflow_2: workflow_2,
      workflow_1_job: hd(workflow_1.jobs),
      workflow_2_job: hd(workflow_2.jobs)
    }
  end

  defp data_retention_change_email(user, project) do
    body = """
    Hi #{user.first_name},

    We'd like to inform you that the data retention policy for your project, #{project.name}, was recently updated.
    If you haven't approved this change, we recommend that you log in into your OpenFn account to reset the policy.

    Should you require assistance with your account, feel free to contact #{Lightning.Config.instance_admin_email()}.

    Best regards,
    The OpenFn Team
    """

    Swoosh.Email.new()
    |> Swoosh.Email.to(user.email)
    |> Swoosh.Email.from(
      {Lightning.Config.email_sender_name(),
       Lightning.Config.instance_admin_email()}
    )
    |> Swoosh.Email.subject("An update to your #{project.name} retention policy")
    |> Swoosh.Email.text_body(body)
  end

  defp dataclip_with_body_and_request(dataclip) do
    reloaded_dataclip = Repo.get(Dataclip, dataclip.id)

    from(Dataclip, select: [:wiped_at, :body, :request])
    |> Lightning.Repo.get(reloaded_dataclip.id)
  end
end
