defmodule Lightning.ProjectsTest do
  use Lightning.DataCase, async: false

  alias Lightning.Projects.ProjectUser
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Accounts.User

  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures
  import Lightning.CredentialsFixtures
  import Lightning.Factories

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
      user = user_fixture()

      project =
        project_fixture(project_users: [%{user_id: user.id}])
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
        project_fixture(project_users: [%{user_id: user_fixture().id}]).project_users
        |> List.first()

      assert Projects.get_project_user!(project_user.id) == project_user

      assert_raise Ecto.NoResultsError, fn ->
        Projects.get_project_user!(Ecto.UUID.generate())
      end
    end

    test "get_project_user/1 returns the project_user with given id" do
      assert Projects.get_project_user(Ecto.UUID.generate()) == nil

      project_user =
        project_fixture(project_users: [%{user_id: user_fixture().id}]).project_users
        |> List.first()

      assert Projects.get_project_user(project_user.id) == project_user
    end

    test "create_project/1 with valid data creates a project" do
      %{id: user_id} = user_fixture()
      valid_attrs = %{name: "some-name", project_users: [%{user_id: user_id}]}

      assert {:ok, %Project{id: project_id} = project} =
               Projects.create_project(valid_attrs)

      assert project.name == "some-name"

      assert [%{project_id: ^project_id, user_id: ^user_id}] =
               project.project_users
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

      p1_run_1 = insert(:run, input_dataclip: p1_dataclip, job: e1.target_job)
      p1_run_2 = insert(:run, input_dataclip: p1_dataclip, job: e1.target_job)

      insert(:workorder,
        trigger: t1,
        dataclip: p1_dataclip,
        workflow: w1,
        attempts: [
          build(:attempt,
            starting_trigger: e1.source_trigger,
            dataclip: p1_dataclip,
            runs: [p1_run_1],
            log_lines: build_list(2, :log_line, run: p1_run_1)
          ),
          build(:attempt,
            starting_trigger: e1.source_trigger,
            dataclip: p1_dataclip,
            created_by: p1_user,
            runs: [p1_run_2],
            log_lines: build_list(2, :log_line, run: p1_run_1)
          )
        ]
      )

      p2_dataclip = insert(:dataclip, body: %{foo: "bar"}, project: p2)

      p2_run = insert(:run, input_dataclip: p2_dataclip, job: e2.target_job)

      p2_log_line = build(:log_line, run: p2_run)

      insert(:workorder,
        trigger: t2,
        workflow: w2,
        dataclip: p2_dataclip,
        attempts:
          build_list(1, :attempt,
            starting_trigger: e2.source_trigger,
            dataclip: p2_dataclip,
            runs: [p2_run],
            log_lines: [p2_log_line]
          )
      )

      p2_attempt_run = Repo.get_by(Lightning.AttemptRun, run_id: p2_run.id)

      runs_query = Lightning.Projects.project_runs_query(p1)

      work_order_query = Lightning.Projects.project_workorders_query(p1)

      attempt_query = Lightning.Projects.project_attempts_query(p1)

      attempt_run_query = Lightning.Projects.project_attempt_run_query(p1)

      pu_query = Lightning.Projects.project_users_query(p1)

      pc_query = Lightning.Projects.project_credentials_query(p1)

      workflows_query = Lightning.Projects.project_workflows_query(p1)

      jobs_query = Lightning.Projects.project_jobs_query(p1)

      assert runs_query |> Repo.aggregate(:count, :id) == 2

      assert work_order_query |> Repo.aggregate(:count, :id) == 1

      assert attempt_query |> Repo.aggregate(:count, :id) == 2

      assert attempt_run_query |> Repo.aggregate(:count, :id) == 2

      assert pu_query |> Repo.aggregate(:count, :id) == 1

      assert pc_query |> Repo.aggregate(:count, :id) == 1

      assert workflows_query |> Repo.aggregate(:count, :id) == 2,
             "There should be only two workflows"

      assert jobs_query |> Repo.aggregate(:count, :id) == 5,
             "There should be only five jobs"

      assert Repo.all(Lightning.Invocation.LogLine)
             |> Enum.count() == 5

      assert {:ok, %Project{}} = Projects.delete_project(p1)

      assert runs_query |> Repo.aggregate(:count, :id) == 0

      assert work_order_query |> Repo.aggregate(:count, :id) == 0

      assert attempt_query |> Repo.aggregate(:count, :id) == 0

      assert only_record_for_type?(p2_attempt_run)

      assert pu_query |> Repo.aggregate(:count, :id) == 0

      assert pc_query |> Repo.aggregate(:count, :id) == 0

      assert workflows_query |> Repo.aggregate(:count, :id) == 0

      assert jobs_query |> Repo.aggregate(:count, :id) == 0

      assert only_record_for_type?(p2_log_line)

      assert_raise Ecto.NoResultsError, fn ->
        Projects.get_project!(p1.id)
      end

      assert p2.id == Projects.get_project!(p2.id).id

      assert Lightning.Projects.project_runs_query(p2)
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

      admin_email =
        Application.get_env(:lightning, :email_addresses) |> Keyword.get(:admin)

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
      prev_purge_deleted_after_days =
        Application.get_env(:lightning, :purge_deleted_after_days)

      Application.put_env(:lightning, :purge_deleted_after_days, nil)

      %{project: project} = full_project_fixture()

      {:ok, %{scheduled_deletion: scheduled_deletion}} =
        Projects.schedule_project_deletion(project)

      assert Timex.diff(scheduled_deletion, DateTime.utc_now(), :seconds) <= 10

      Application.put_env(
        :lightning,
        :purge_deleted_after_days,
        prev_purge_deleted_after_days
      )
    end

    test "schedule_project_deletion/1 schedules a project for deletion to purge_deleted_after_days days from now" do
      days = Application.get_env(:lightning, :purge_deleted_after_days)

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

  @spec full_project_fixture(attrs :: Keyword.t()) :: %{optional(any) => any}
  def full_project_fixture(attrs \\ []) when is_list(attrs) do
    user = insert(:user)

    project =
      build(:project, project_users: [%{user: user}])
      |> ExMachina.merge_attributes(attrs)
      |> insert()

    workflow_1 = insert(:workflow, project: project, name: "workflow 1")

    workflow_2 = insert(:workflow, project: project, name: "workflow 2")

    credential =
      insert(:credential,
        user_id: user.id,
        name: "new credential",
        body: %{"foo" => "super-secret"},
        projects: [project]
      )

    workflow_1_job =
      insert(:job,
        name: "webhook job",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: NaiveDateTime.utc_now() |> Timex.shift(seconds: 0),
        project: project,
        workflow: workflow_1,
        project_credential: %{credential: credential, project: project},
        body: "console.log('webhook job')\nfn(state => state)"
      )

    insert(:edge,
      workflow: workflow_1,
      source_trigger: build(:trigger, workflow: workflow_1),
      target_job: workflow_1_job,
      condition: :always
    )

    insert(:edge,
      workflow: workflow_1,
      source_job: workflow_1_job,
      condition: :on_job_failure,
      target_job:
        insert(:job,
          name: "on fail",
          # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
          inserted_at: NaiveDateTime.utc_now() |> Timex.shift(seconds: 1),
          workflow: workflow_1,
          body: "console.log('on fail')\nfn(state => state)"
        )
    )

    insert(:edge,
      workflow: workflow_1,
      source_job: workflow_1_job,
      condition: :on_job_success,
      target_job:
        insert(:job,
          name: "on success",
          # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
          inserted_at: NaiveDateTime.utc_now() |> Timex.shift(seconds: 2),
          workflow: workflow_1
        )
    )

    workflow_2_job =
      insert(:job,
        name: "some cronjob",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: NaiveDateTime.utc_now() |> Timex.shift(seconds: 3),
        workflow: workflow_2
      )

    insert(:edge,
      workflow: workflow_2,
      source_trigger:
        build(:trigger,
          workflow: workflow_2,
          type: :cron,
          cron_expression: "0 23 * * *"
        ),
      target_job: workflow_2_job,
      condition: :always
    )

    insert(:edge,
      workflow: workflow_2,
      source_job: workflow_2_job,
      condition: :on_job_success,
      target_job:
        insert(:job,
          name: "on cron failure",
          # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
          inserted_at: NaiveDateTime.utc_now() |> Timex.shift(seconds: 4),
          workflow: workflow_2
        )
    )

    insert(:job,
      name: "unrelated job"
    )

    %{
      project: project,
      workflow_1: workflow_1,
      workflow_2: workflow_2,
      workflow_1_job: workflow_1_job,
      workflow_2_job: workflow_2_job
    }
  end
end
