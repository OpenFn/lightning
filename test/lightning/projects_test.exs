defmodule Lightning.ProjectsTest do
  use Lightning.DataCase, async: true

  import Lightning.AccountsFixtures
  import Lightning.Factories
  import Lightning.ProjectsFixtures
  import Mox
  import Swoosh.TestAssertions

  alias Lightning.Auditing.Audit
  alias Lightning.Accounts.User
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.LogLine
  alias Lightning.Invocation.Step
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectOverviewRow
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.Workflows.Snapshot
  alias Lightning.WorkOrder

  alias Swoosh.Email

  require Phoenix.VerifiedRoutes

  describe "projects" do
    @invalid_attrs %{name: nil}

    test "list_projects/0 returns all projects" do
      project = project_fixture() |> unload_relation(:project_users)
      assert Projects.list_projects() == [project]
    end

    test "list_project_credentials/1 returns all project_credentials for a project" do
      user = insert(:user)
      project = insert(:project, project_users: [%{user_id: user.id}])

      credential =
        insert(:credential,
          user_id: user.id,
          project_credentials: [%{project_id: project.id}]
        )

      assert Projects.list_project_credentials(project) ==
               credential.project_credentials
               |> Repo.preload(credential: [:user, :oauth_client])
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
      assert Projects.get_project(project.id) == Repo.preload(project, :parent)
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
          scheduled_deletion:
            Lightning.current_time() |> DateTime.truncate(:second),
          collections: [build(:collection, project: nil)]
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

    test "schedule_project_deletion/1 schedules a project for deletion and notify all project users via email." do
      user_1 = insert(:user, email: "user_1@openfn.org", first_name: "user_1")
      user_2 = insert(:user, email: "user_2@openfn.org", first_name: "user_2")

      project =
        insert(:project,
          name: "project-to-delete",
          project_users: [%{user: user_1}, %{user: user_2}]
        )

      assert project.scheduled_deletion == nil

      Projects.schedule_project_deletion(project)

      admin_email = Lightning.Config.instance_admin_email()

      actual_deletion_date =
        Lightning.Config.purge_deleted_after_days()
        |> Lightning.Helpers.actual_deletion_date()
        |> Lightning.Helpers.format_date("%F at %T")

      for user <- [user_1, user_2] do
        email = %Email{
          subject: "Project scheduled for deletion",
          to: [Swoosh.Email.Recipient.format(user)],
          from:
            {Lightning.Config.email_sender_name(),
             Lightning.Config.instance_admin_email()},
          text_body: """
          Hi #{user.first_name},

          Your OpenFn project "#{project.name}" has been scheduled for deletion.

          All of the workflows in this project have been disabled, and it's associated resources will be deleted on #{actual_deletion_date}.

          If you don't want this project deleted, please email #{admin_email} as soon as possible.

          OpenFn
          """
        }

        assert_email_sent(email)
      end

      project = Repo.reload!(project)
      assert project.scheduled_deletion != nil
    end

    test "schedule_project_deletion/1 schedules a project for deletion to now when purge_deleted_after_days is nil" do
      Mox.stub(Lightning.MockConfig, :purge_deleted_after_days, fn -> nil end)

      %{project: project} = full_project_fixture()

      {:ok, %{scheduled_deletion: scheduled_deletion}} =
        Projects.schedule_project_deletion(project)

      assert Timex.diff(scheduled_deletion, Lightning.current_time(), :seconds) <=
               10
    end

    test "schedule_project_deletion/1 schedules a project for deletion to purge_deleted_after_days days from now" do
      days = Lightning.Config.purge_deleted_after_days()

      %{project: project} = full_project_fixture()

      project_triggers = Projects.project_triggers_query(project) |> Repo.all()

      assert Enum.all?(project_triggers, & &1.enabled)

      assert project.scheduled_deletion == nil

      now = Lightning.current_time() |> DateTime.add(-1, :second)
      {:ok, project} = Projects.schedule_project_deletion(project)

      project_triggers = Projects.project_triggers_query(project) |> Repo.all()

      assert Enum.all?(project_triggers, &(!&1.enabled))

      assert project.scheduled_deletion != nil
      assert Timex.diff(project.scheduled_deletion, now, :days) == days
    end

    test "cancel_scheduled_deletion/2" do
      project =
        project_fixture(
          scheduled_deletion:
            Lightning.current_time() |> DateTime.truncate(:second)
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

  describe "export_project/2 as yaml:" do
    test "works on project with no workflows" do
      project = project_fixture(name: "newly-created-project")

      expected_yaml =
        "name: newly-created-project\ndescription: null\ncollections: null\ncredentials: null\nworkflows: null"

      {:ok, generated_yaml} = Projects.export_project(:yaml, project.id)

      assert generated_yaml == expected_yaml
    end

    test "adds quotes to values with special charaters" do
      project = insert(:project, name: "project: 1")

      workflow_with_bad_name =
        insert(:simple_workflow, project: project, name: "workflow: 1")

      workflow_with_good_name =
        insert(:simple_workflow, project: project, name: "workflow 2")

      assert {:ok, generated_yaml} = Projects.export_project(:yaml, project.id)

      assert generated_yaml =~ ~s(name: '#{project.name}')
      assert generated_yaml =~ ~s(name: '#{workflow_with_bad_name.name}')
      # key is quoted
      assert generated_yaml =~
               ~s("#{String.replace(workflow_with_bad_name.name, " ", "-")}")

      refute generated_yaml =~ ~s(name: '#{workflow_with_good_name.name}')
      assert generated_yaml =~ "name: #{workflow_with_good_name.name}"

      # key is not quoted
      refute generated_yaml =~
               ~s("#{String.replace(workflow_with_good_name.name, " ", "-")}")
    end

    test "js_expressions edge conditions are made multiline" do
      project = insert(:project, name: "project 1")

      trigger =
        build(:trigger,
          type: :webhook,
          enabled: true
        )

      job =
        build(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      js_expression = "!state.data && !state.data"

      build(:workflow, name: "workflow 1", project: project)
      |> with_trigger(trigger)
      |> with_job(job)
      |> with_edge({trigger, job},
        condition_type: :js_expression,
        condition_expression: js_expression
      )
      |> insert()

      assert {:ok, generated_yaml} = Projects.export_project(:yaml, project.id)

      assert generated_yaml =~
               "condition_expression: |\n          #{js_expression}"
    end

    test "project descriptions with multiline and special characters are correctly represented" do
      project =
        insert(:project,
          name: "project_multiline_special",
          description: """
          This is a multiline description.
          It includes special characters: :, #, &, *, ?, |, -, <, >, =, !, %, @, *, &, ?.
          Also, YAML indicators: *alias, &anchor, ?key, !tag.
          Line breaks and special characters should be preserved.
          """
        )

      assert {:ok, generated_yaml} = Projects.export_project(:yaml, project.id)

      expected_yaml = """
      name: project_multiline_special
      description: |
        This is a multiline description.
        It includes special characters: :, #, &, *, ?, |, -, <, >, =, !, %, @, *, &, ?.
        Also, YAML indicators: *alias, &anchor, ?key, !tag.
        Line breaks and special characters should be preserved.
      """

      assert generated_yaml =~ expected_yaml
    end

    test "projects with empty and nil descriptions are correctly represented" do
      project_empty =
        insert(:project, name: "project_empty_description", description: "")

      assert {:ok, generated_yaml} =
               Projects.export_project(:yaml, project_empty.id)

      expected_yaml = """
      name: project_empty_description
      description: |
      """

      assert generated_yaml =~ expected_yaml

      project_nil =
        insert(:project, name: "project_nil_description", description: nil)

      assert {:ok, generated_yaml} =
               Projects.export_project(:yaml, project_nil.id)

      expected_yaml = """
      name: project_nil_description
      description: null
      """

      assert generated_yaml =~ expected_yaml
    end

    test "kafka triggers are included in the export" do
      project = insert(:project, name: "project 1")

      trigger =
        build(:trigger,
          type: :kafka,
          kafka_configuration: %{
            hosts: [["localhost", "9092"]],
            topics: ["dummy"],
            initial_offset_reset_policy: "earliest"
          }
        )

      job =
        build(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      build(:workflow, name: "workflow 1", project: project)
      |> with_trigger(trigger)
      |> with_job(job)
      |> with_edge({trigger, job}, condition_type: :always)
      |> insert()

      expected_yaml_trigger = """
          triggers:
            kafka:
              type: kafka
              enabled: true
              kafka_configuration:
                hosts:
                  - 'localhost:9092'
                topics:
                  - dummy
                initial_offset_reset_policy: earliest
                connect_timeout: 30
      """

      assert {:ok, generated_yaml} = Projects.export_project(:yaml, project.id)

      assert generated_yaml =~ expected_yaml_trigger
    end

    test "exports canonical project" do
      project =
        canonical_project_fixture(
          name: "a-test-project",
          description: "This is only a test"
        )

      expected_yaml =
        File.read!("test/fixtures/canonical_project.yaml") |> String.trim()

      {:ok, generated_yaml} = Projects.export_project(:yaml, project.id)

      assert generated_yaml == expected_yaml
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
          scheduled_deletion:
            Lightning.current_time() |> Timex.shift(seconds: -10)
        )

      not_to_delete =
        project_fixture(
          scheduled_deletion:
            Lightning.current_time() |> Timex.shift(seconds: 10)
        )

      count_before = Repo.all(Project) |> Enum.count()

      :ok = Projects.perform(%Oban.Job{args: %{"type" => "purge_deleted"}})

      assert Repo.aggregate(Project, :count) == count_before - 1

      refute Repo.get(Project, project_to_delete.id)
      assert Repo.get(Project, not_to_delete.id)
    end
  end

  describe "Projects.perform/1 for data retention periods" do
    test "deletes history for workorders based on last_activity" do
      project = insert(:project, history_retention_period: 7)

      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project, lock_version: 3)

      now = Lightning.current_time()

      snapshot_to_delete = insert(:snapshot, workflow: workflow, lock_version: 1)
      snapshot_to_keep = insert(:snapshot, workflow: workflow, lock_version: 2)
      latest_snapshot = insert(:snapshot, workflow: workflow, lock_version: 3)

      all_snapshots = [snapshot_to_delete, snapshot_to_keep, latest_snapshot]

      workorders_to_delete =
        Enum.map(1..12, fn i ->
          # this returns 0, 1 or 2
          snapshot_index = rem(i, 3)
          snapshot = Enum.at(all_snapshots, snapshot_index)

          insert(:workorder,
            workflow: workflow,
            last_activity: Timex.shift(now, days: -7),
            trigger: trigger,
            dataclip: build(:dataclip),
            snapshot: snapshot,
            runs: [
              build(:run,
                starting_trigger: trigger,
                dataclip: build(:dataclip),
                log_lines: [build(:log_line)],
                steps: [build(:step, job: job)]
              )
            ]
          )
        end)

      workorder_to_remain =
        insert(:workorder,
          workflow: workflow,
          last_activity: Timex.shift(now, days: -6),
          trigger: trigger,
          dataclip: build(:dataclip),
          snapshot: snapshot_to_keep,
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

      refute Repo.get(Snapshot, snapshot_to_delete.id)

      Enum.each(workorders_to_delete, fn workorder ->
        refute Repo.get(WorkOrder, workorder.id)
        run_to_delete = hd(workorder.runs)
        refute Repo.get(Run, run_to_delete.id)
        step_to_delete = hd(run_to_delete.steps)
        refute Repo.get(Step, step_to_delete.id)
        log_line_to_delete = hd(run_to_delete.log_lines)

        refute Repo.get_by(LogLine, id: log_line_to_delete.id)
      end)

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

      # snapshot that is still in use
      assert workorder_to_remain.snapshot_id == snapshot_to_keep.id
      assert Repo.get(Snapshot, snapshot_to_keep.id)

      # latest snapshot is not deleted
      refute Repo.get_by(WorkOrder, snapshot_id: latest_snapshot.id)
      assert Repo.get(Snapshot, latest_snapshot.id)

      # extra checks. Jobs, Triggers, Workflows are not deleted
      assert Repo.get(Lightning.Workflows.Job, job.id)
      assert Repo.get(Lightning.Workflows.Trigger, trigger.id)
      assert Repo.get(Lightning.Workflows.Workflow, workflow.id)
    end

    test "does not incorrectly delete runs that reference older snapshots" do
      project = insert(:project, history_retention_period: 7)

      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project, lock_version: 3)

      now = Lightning.current_time()

      # Create multiple snapshots for the workflow
      older_snapshot = insert(:snapshot, workflow: workflow, lock_version: 1)
      unused_snapshot = insert(:snapshot, workflow: workflow, lock_version: 2)
      middle_snapshot = insert(:snapshot, workflow: workflow, lock_version: 3)
      current_snapshot = insert(:snapshot, workflow: workflow, lock_version: 4)

      # Create a workorder that should NOT be deleted (recent activity)
      # This workorder references the current snapshot
      workorder_to_keep =
        insert(:workorder,
          workflow: workflow,
          # Within retention period
          last_activity: Timex.shift(now, days: -5),
          trigger: trigger,
          dataclip: build(:dataclip),
          snapshot: current_snapshot,
          runs: []
        )

      # Create runs that reference older snapshots but belong to the workorder that should be kept
      # These runs should NOT be deleted because they are still accessible and referenced
      run_with_older_snapshot =
        insert(:run,
          work_order: workorder_to_keep,
          starting_trigger: trigger,
          dataclip: build(:dataclip),
          # References older snapshot!
          snapshot: older_snapshot,
          # Step also references older snapshot
          steps: [build(:step, job: job, snapshot: older_snapshot)]
        )

      run_with_middle_snapshot =
        insert(:run,
          work_order: workorder_to_keep,
          starting_trigger: trigger,
          dataclip: build(:dataclip),
          # References middle snapshot!
          snapshot: middle_snapshot,
          # Step also references middle snapshot
          steps: [build(:step, job: job, snapshot: middle_snapshot)]
        )

      # Run the data retention job
      assert :ok =
               Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      # The workorder should still exist (it has recent activity)
      assert Repo.get(WorkOrder, workorder_to_keep.id)

      # BUG: Currently these runs get deleted because their snapshots are considered "unused"
      # But they should still exist because they are part of an active workorder
      assert Repo.get(Run, run_with_older_snapshot.id),
             "Run referencing older snapshot should not be deleted via cascade deletion"

      assert Repo.get(Run, run_with_middle_snapshot.id),
             "Run referencing middle snapshot should not be deleted via cascade deletion"

      # The steps should also still exist
      step_with_older_snapshot = hd(run_with_older_snapshot.steps)
      step_with_middle_snapshot = hd(run_with_middle_snapshot.steps)

      assert Repo.get(Step, step_with_older_snapshot.id),
             "Step referencing older snapshot should not be deleted via cascade deletion"

      assert Repo.get(Step, step_with_middle_snapshot.id),
             "Step referencing middle snapshot should not be deleted via cascade deletion"

      # We should only have 3 snapshots left, despite creating 4
      assert Repo.all(Snapshot) |> Enum.count() == 3

      # The snapshots should also still exist because they are referenced by runs/steps
      assert Repo.get(Snapshot, older_snapshot.id),
             "Older snapshot should not be deleted because it's referenced by active runs"

      middle_snapshot = Repo.get(Snapshot, middle_snapshot.id)

      assert middle_snapshot,
             "Middle snapshot should not be deleted because it's referenced by active runs"

      error =
        assert_raise Ecto.ConstraintError, fn ->
          Repo.delete(middle_snapshot)
        end

      assert error.constraint == "runs_snapshot_id_fkey"
      assert error.message =~ "constraint error when attempting to delete"

      # The snapshot that was never used in a run and is not the latest should be deleted
      refute Repo.get(Snapshot, unused_snapshot.id)

      # The current snapshot should definitely still exist
      assert Repo.get(Snapshot, current_snapshot.id)
    end

    test "deletes orphaned dataclips correctly (comprehensive test for all association types)" do
      project = insert(:project, history_retention_period: 7)

      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project)

      now = Lightning.current_time()

      # Test comprehensive dataclip deletion based on all association types:
      # workorder, run, step input_dataclip, step output_dataclip

      # Create dataclips at different time periods
      pre_retention_dataclip_1 =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      pre_retention_dataclip_2 =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      pre_retention_dataclip_3 =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      pre_retention_dataclip_4 =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      post_retention_dataclip_1 =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      post_retention_dataclip_2 =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      post_retention_dataclip_3 =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      post_retention_dataclip_4 =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # Orphaned dataclips (not associated to anything)
      orphan_pre_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      orphan_pre_retention_dataclip_having_name =
        insert(:dataclip,
          name: "some-name",
          project: project,
          inserted_at: Timex.shift(now, days: -8)
        )

      orphan_post_retention_dataclip =
        insert(:dataclip,
          project: project,
          inserted_at: Timex.shift(now, days: -6)
        )

      # Create old workorder that will be deleted
      workorder_to_delete =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          last_activity: Timex.shift(now, days: -8),
          # Test workorder association
          dataclip: post_retention_dataclip_1
        )

      run_to_delete =
        insert(:run,
          work_order: workorder_to_delete,
          starting_trigger: trigger,
          # Test run association
          dataclip: post_retention_dataclip_2
        )

      step_to_delete =
        insert(:step,
          runs: [run_to_delete],
          job: job,
          # Test step input association
          input_dataclip: post_retention_dataclip_3,
          # Test step output association
          output_dataclip: post_retention_dataclip_4
        )

      # Create recent workorder that will remain
      workorder_to_remain =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          last_activity: Timex.shift(now, days: -6),
          # This should protect the dataclip
          dataclip: pre_retention_dataclip_1
        )

      run_to_remain =
        insert(:run,
          work_order: workorder_to_remain,
          starting_trigger: trigger,
          # This should protect the dataclip
          dataclip: pre_retention_dataclip_2
        )

      step_to_remain =
        insert(:step,
          runs: [run_to_remain],
          job: job,
          # This should protect the dataclip
          input_dataclip: pre_retention_dataclip_3,
          # This should protect the dataclip
          output_dataclip: pre_retention_dataclip_4
        )

      assert :ok =
               Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      # Verify workorders/runs/steps deletion
      refute Repo.get(WorkOrder, workorder_to_delete.id)
      refute Repo.get(Run, run_to_delete.id)
      refute Repo.get(Step, step_to_delete.id)

      assert Repo.get(WorkOrder, workorder_to_remain.id)
      assert Repo.get(Run, run_to_remain.id)
      assert Repo.get(Step, step_to_remain.id)

      # Test 1: Workorder association protection
      # pre_retention_dataclip_1 should NOT be deleted (protected by workorder_to_remain)
      assert Repo.get(Dataclip, pre_retention_dataclip_1.id)

      # post_retention_dataclip_1 should NOT be deleted (recent timestamp, despite workorder deletion)
      assert Repo.get(Dataclip, post_retention_dataclip_1.id)

      # Test 2: Run association protection
      # pre_retention_dataclip_2 should NOT be deleted (protected by run_to_remain)
      assert Repo.get(Dataclip, pre_retention_dataclip_2.id)

      # post_retention_dataclip_2 should NOT be deleted (recent timestamp, despite run deletion)
      assert Repo.get(Dataclip, post_retention_dataclip_2.id)

      # Test 3: Step input association protection
      # pre_retention_dataclip_3 should NOT be deleted (protected by step_to_remain input)
      assert Repo.get(Dataclip, pre_retention_dataclip_3.id)

      # post_retention_dataclip_3 should NOT be deleted (recent timestamp, despite step deletion)
      assert Repo.get(Dataclip, post_retention_dataclip_3.id)

      # Test 4: Step output association protection
      # pre_retention_dataclip_4 should NOT be deleted (protected by step_to_remain output)
      assert Repo.get(Dataclip, pre_retention_dataclip_4.id)

      # post_retention_dataclip_4 should NOT be deleted (recent timestamp, despite step deletion)
      assert Repo.get(Dataclip, post_retention_dataclip_4.id)

      # Test 5: Orphaned dataclip cleanup
      # orphan_pre_retention_dataclip_having_name SHOULD NOT be deleted (despite being old it has a name)
      assert Repo.get(Dataclip, orphan_pre_retention_dataclip_having_name.id)
      # orphan_pre_retention_dataclip SHOULD be deleted (old and not referenced)
      refute Repo.get(Dataclip, orphan_pre_retention_dataclip.id)
      # orphan_post_retention_dataclip should NOT be deleted (recent timestamp)
      assert Repo.get(Dataclip, orphan_post_retention_dataclip.id)
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

    test "does not wipe dataclips having names" do
      project =
        insert(:project,
          history_retention_period: 14,
          dataclip_retention_period: 10
        )

      dataclip =
        insert(:dataclip,
          name: "some-name",
          project: project,
          request: %{star: "sadio mane"},
          type: :step_result,
          body: %{team: "senegal"},
          inserted_at: Timex.now() |> Timex.shift(days: -11)
        )

      :ok = Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      dataclip = dataclip_with_body_and_request(dataclip)

      assert dataclip.request === %{"star" => "sadio mane"}
      assert dataclip.body === %{"team" => "senegal"}
      assert dataclip.wiped_at == nil
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

    test "deletes project files past the retention period" do
      project =
        insert(:project, history_retention_period: 7)

      more_days_ago = Date.utc_today() |> Date.add(-8)

      File.write!("ficheiro", "some-content")
      on_exit(fn -> File.rm!("ficheiro") end)

      {:ok, path} =
        Lightning.Storage.store("ficheiro", "/bucket_subdir/ficheiro")

      project_file1 =
        insert(:project_file,
          project: project,
          path: path,
          inserted_at: DateTime.new!(more_days_ago, ~T[00:00:00])
        )

      project_file2 =
        insert(:project_file, project: project)

      :ok = Projects.perform(%Oban.Job{args: %{"type" => "data_retention"}})

      refute Repo.get(Projects.File, project_file1.id)
      assert Repo.get(Projects.File, project_file2.id)
    end
  end

  describe "invite_collaborators/3" do
    setup :verify_on_exit!

    test "calls the AccountHook service for user registration" do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      collaborators_count = 5

      collaborators =
        Enum.map(1..collaborators_count, fn n ->
          %{
            email: "myemailtest#{n}@test#{n}ing.com",
            first_name: "Anna",
            last_name: "Smith",
            role: "editor"
          }
        end)

      # expect the AccountHook service to be called for each collaborator
      expect(
        Lightning.Extensions.MockAccountHook,
        :handle_register_user,
        collaborators_count,
        fn attrs ->
          Lightning.Extensions.AccountHook.handle_register_user(attrs)
        end
      )

      assert {:ok, _} =
               Projects.invite_collaborators(project, collaborators, user)
    end

    test "project collaborators digest emails are by default turned off" do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user_id: user.id}])

      assert project.project_users
             |> Enum.map(& &1.digest)
             |> Enum.all?(&(&1 == :never))
    end
  end

  describe ".find_users_to_notify_of_trigger_failure/1" do
    setup do
      other_project = insert(:project)
      project = insert(:project)

      superuser_1 = insert(:user, email: "super1@test.com", role: :superuser)
      superuser_2 = insert(:user, email: "super2@test.com", role: :superuser)

      other_project_superuser =
        insert(:user, email: "other@test.com", role: :superuser)

      admin_user = insert(:user, email: "admin@test.com", role: :user)
      owner_user = insert(:user, email: "owner@test.com", role: :user)
      user = insert(:user, email: "user@test.com", role: :user)

      insert(
        :project_user,
        project: other_project,
        user: other_project_superuser,
        role: :viewer
      )

      insert(
        :project_user,
        project: project,
        user: user,
        role: :viewer
      )

      insert(
        :project_user,
        project: project,
        user: superuser_1,
        role: :viewer
      )

      insert(
        :project_user,
        project: project,
        user: superuser_2,
        role: :admin
      )

      insert(
        :project_user,
        project: project,
        user: admin_user,
        role: :admin
      )

      insert(
        :project_user,
        project: project,
        user: owner_user,
        role: :owner
      )

      %{
        admin_user: admin_user,
        other_project_superuser: other_project_superuser,
        owner_user: owner_user,
        project: project,
        superuser_1: superuser_1,
        superuser_2: superuser_2,
        user: user
      }
    end

    test "returns associated superusers or users with admin/owner role", %{
      admin_user: admin_user,
      owner_user: owner_user,
      project: project,
      superuser_1: superuser_1,
      superuser_2: superuser_2
    } do
      expected_emails =
        [admin_user, owner_user, superuser_1, superuser_2]
        |> Enum.map(& &1.email)
        |> Enum.sort()

      actual_emails =
        project.id
        |> Projects.find_users_to_notify_of_trigger_failure()
        |> Enum.map(& &1.email)
        |> Enum.sort()

      assert actual_emails == expected_emails
    end
  end

  describe "get_projects_overview/2" do
    test "returns an empty list when the user has no projects" do
      user = insert(:user)

      assert Projects.get_projects_overview(user) == []
    end

    test "returns projects overview with workflows and collaborators count" do
      user = insert(:user)
      other_user = insert(:user)

      project =
        %{id: project_id} =
        insert(:project, name: "Project A", project_users: [%{user_id: user.id}])

      insert(:simple_workflow, project: project)
      insert(:simple_workflow, project: project)

      insert(:project,
        name: "Project B",
        project_users: [%{user_id: other_user.id}]
      )

      result = Projects.get_projects_overview(user)

      assert length(result) == 1

      [
        %ProjectOverviewRow{
          id: ^project_id,
          name: "Project A",
          workflows_count: 2,
          collaborators_count: 1
        }
      ] = result
    end

    test "orders projects by name ascending by default" do
      user = insert(:user)

      %{id: project_a_id} =
        insert(:project, name: "Project A", project_users: [%{user_id: user.id}])

      %{id: project_b_id} =
        insert(:project, name: "Project B", project_users: [%{user_id: user.id}])

      result = Projects.get_projects_overview(user)

      assert [
               %ProjectOverviewRow{id: ^project_a_id, name: "Project A"},
               %ProjectOverviewRow{id: ^project_b_id, name: "Project B"}
             ] = result
    end

    test "orders projects by last_updated_at (updated_at of workflows) descending when specified" do
      user = insert(:user)

      project_a =
        %{id: project_a_id} =
        insert(:project, name: "Project A", project_users: [%{user_id: user.id}])

      project_b =
        %{id: project_b_id} =
        insert(:project, name: "Project B", project_users: [%{user_id: user.id}])

      insert(:simple_workflow,
        project: project_a,
        updated_at: ~N[2023-10-05 00:00:00]
      )

      insert(:simple_workflow,
        project: project_b,
        updated_at: ~N[2023-10-10 00:00:00]
      )

      result =
        Projects.get_projects_overview(user,
          order_by: {:last_updated_at, :desc}
        )

      assert [
               %ProjectOverviewRow{id: ^project_b_id, name: "Project B"},
               %ProjectOverviewRow{id: ^project_a_id, name: "Project A"}
             ] = result
    end

    test "orders projects by last_updated_at ascending when specified" do
      user = insert(:user)

      project_a =
        %{id: project_a_id} =
        insert(:project, name: "Project A", project_users: [%{user_id: user.id}])

      project_b =
        %{id: project_b_id} =
        insert(:project, name: "Project B", project_users: [%{user_id: user.id}])

      insert(:simple_workflow,
        project: project_a,
        updated_at: ~N[2023-10-05 00:00:00]
      )

      insert(:simple_workflow,
        project: project_b,
        updated_at: ~N[2023-10-10 00:00:00]
      )

      result =
        Projects.get_projects_overview(user,
          order_by: {:last_updated_at, :asc}
        )

      assert [
               %ProjectOverviewRow{id: ^project_a_id, name: "Project A"},
               %ProjectOverviewRow{id: ^project_b_id, name: "Project B"}
             ] = result
    end

    test "returns project with no workflows or last activity" do
      user = insert(:user)

      %{id: project_id} =
        insert(:project,
          name: "Project No Workflow",
          project_users: [%{user_id: user.id}]
        )

      result = Projects.get_projects_overview(user)

      assert [
               %ProjectOverviewRow{
                 id: ^project_id,
                 name: "Project No Workflow",
                 workflows_count: 0,
                 last_updated_at: nil
               }
             ] = result
    end

    test "returns correct collaborators count with multiple collaborators" do
      user = insert(:user)
      other_user = insert(:user)
      third_user = insert(:user)

      project =
        insert(:project, name: "Project A", project_users: [%{user_id: user.id}])

      insert(:project_user, project: project, user: other_user)
      insert(:project_user, project: project, user: third_user)

      result = Projects.get_projects_overview(user)

      assert [
               %ProjectOverviewRow{
                 collaborators_count: 3
               }
             ] = result
    end

    test "returns correct role for the user" do
      user = insert(:user)
      other_user = insert(:user)

      project =
        insert(:project,
          name: "Project A",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      insert(:project_user, project: project, user: other_user, role: :admin)

      result = Projects.get_projects_overview(user)

      assert [
               %ProjectOverviewRow{
                 role: :owner
               }
             ] = result
    end

    test "returns correct collaborators count with only one collaborator" do
      user = insert(:user)

      insert(:project,
        name: "Solo Project",
        project_users: [%{user_id: user.id}]
      )

      result = Projects.get_projects_overview(user)

      assert [
               %ProjectOverviewRow{
                 collaborators_count: 1
               }
             ] = result
    end
  end

  describe ".update_project/3" do
    setup do
      %{user: insert(:user)}
    end

    test "update_project/3 with valid data updates the project" do
      project = project_fixture()
      update_attrs = %{name: "some-updated-name"}

      assert {:ok, %Project{} = project} =
               Projects.update_project(project, update_attrs)

      assert project.name == "some-updated-name"
    end

    test "update_project/3 updates the MFA requirement" do
      project = insert(:project)

      refute project.requires_mfa
      update_attrs = %{requires_mfa: true}

      assert {:ok, %Project{} = project} =
               Projects.update_project(project, update_attrs)

      assert project.requires_mfa
    end

    test "update_project/3 updates the data retention periods" do
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

      %{subject: subject, body: body} = data_retention_email(updated_project)

      for %{user: user} <- admins do
        email = Swoosh.Email.Recipient.format(user)

        assert_receive {:email,
                        %Swoosh.Email{
                          subject: ^subject,
                          to: [^email],
                          text_body: ^body
                        }}
      end

      # editors and viewers do not receive any email
      non_admins =
        Enum.filter(project.project_users, fn %{role: role} ->
          role in [:editor, :viewer]
        end)

      assert Enum.count(non_admins) == 2

      for %{user: %{email: email}} <- non_admins do
        refute_receive {:email,
                        %Swoosh.Email{
                          subject: ^subject,
                          to: [{"", ^email}],
                          text_body: ^body
                        }}

        # data_retention_email(user, updated_project) |> assert_email_not_sent()
      end

      # no email is sent when there's no change
      assert {:ok, updated_project} =
               Projects.update_project(updated_project, update_attrs)

      for %{user: %{email: email}} <- project.project_users do
        refute_receive {:email,
                        %Swoosh.Email{
                          subject: ^subject,
                          to: [{"", ^email}],
                          text_body: ^body
                        }}
      end

      # no email is sent when there's an error in the changeset
      assert {:error, _changeset} =
               Projects.update_project(updated_project, %{
                 history_retention_period: "xyz",
                 dataclip_retention_period: 7
               })

      for %{user: %{email: email}} <- project.project_users do
        refute_receive {:email,
                        %Swoosh.Email{
                          subject: ^subject,
                          to: [{"", ^email}],
                          text_body: ^body
                        }}
      end
    end

    test "update_project/3 with invalid data returns error changeset" do
      project = project_fixture() |> unload_relation(:project_users)

      assert {:error, %Ecto.Changeset{}} =
               Projects.update_project(project, @invalid_attrs)

      assert Repo.preload(project, :parent) == Projects.get_project!(project.id)
    end

    test "update_project/2 calls the validate_changeset hook" do
      verify_on_exit!()

      project =
        insert(:project,
          name: "test",
          project_users: [
            build(:project_user, user: build(:user), role: :owner)
          ]
        )

      error_msg = "Hello world"

      expect(
        Lightning.Extensions.MockProjectHook,
        :handle_project_validation,
        fn changeset ->
          Ecto.Changeset.add_error(changeset, :name, error_msg)
        end
      )

      assert {:error, changeset} =
               Projects.update_project(project, %{
                 name: "new-name"
               })

      assert errors_on(changeset) == %{name: [error_msg]}
    end

    test "creates audit events if retention periods are updated", %{
      user: %{id: user_id} = user
    } do
      %{id: project_id} =
        project =
        insert(
          :project,
          dataclip_retention_period: 7,
          history_retention_period: 30,
          retention_policy: :retain_all
        )

      update_attrs = %{
        dataclip_retention_period: 14,
        history_retention_period: 90,
        retention_policy: :retain_with_errors
      }

      Projects.update_project(project, update_attrs, user)

      query =
        from a in Audit, where: a.event == "history_retention_period_updated"

      history_audit_event = Repo.one!(query)

      assert %{
               item_type: "project",
               item_id: ^project_id,
               actor_id: ^user_id,
               changes: changes
             } = history_audit_event

      assert changes == %Audit.Changes{
               before: %{"history_retention_period" => 30},
               after: %{"history_retention_period" => 90}
             }

      query =
        from a in Audit, where: a.event == "dataclip_retention_period_updated"

      dataclip_audit_event = Repo.one!(query)

      assert %{
               item_type: "project",
               item_id: ^project_id,
               actor_id: ^user_id,
               changes: changes
             } = dataclip_audit_event

      assert changes == %Audit.Changes{
               before: %{"dataclip_retention_period" => 7},
               after: %{"dataclip_retention_period" => 14}
             }
    end

    test "creates audit events when toggling the support user grant", %{
      user: %{id: user_id} = user
    } do
      %{id: project_id} =
        project = insert(:project, allow_support_access: false)

      Projects.update_project(project, %{allow_support_access: true}, user)

      changes = %Lightning.Auditing.Audit.Changes{
        after: %{"allow_support_access" => true},
        before: %{"allow_support_access" => false}
      }

      assert %{
               item_type: "project",
               item_id: ^project_id,
               actor_id: ^user_id,
               changes: ^changes
             } = Repo.get_by!(Audit, event: "allow_support_access_updated")
    end

    test "creates audit events when toggling MFA", %{
      user: %{id: user_id} = user
    } do
      %{id: project_id} =
        project = insert(:project, requires_mfa: false)

      Projects.update_project(project, %{requires_mfa: true}, user)

      changes = %Lightning.Auditing.Audit.Changes{
        after: %{"requires_mfa" => true},
        before: %{"requires_mfa" => false}
      }

      assert %{
               item_type: "project",
               item_id: ^project_id,
               actor_id: ^user_id,
               changes: ^changes
             } = Repo.get_by!(Audit, event: "requires_mfa_updated")
    end

    test "does not create events if no user was provided" do
      project =
        insert(
          :project,
          dataclip_retention_period: 7,
          history_retention_period: 30,
          retention_policy: :retain_all
        )

      update_attrs = %{
        dataclip_retention_period: 14,
        history_retention_period: 90,
        retention_policy: :retain_with_errors
      }

      Projects.update_project(project, update_attrs)

      assert Audit |> Repo.all() |> Enum.empty?()
    end

    test "does not create events if the project change fails", %{
      user: user
    } do
      project =
        insert(
          :project,
          dataclip_retention_period: 7,
          history_retention_period: 30,
          retention_policy: :retain_all
        )

      update_attrs = %{
        dataclip_retention_period: 14,
        history_retention_period: 90,
        retention_policy: :no_such_value
      }

      Projects.update_project(project, update_attrs, user)

      assert Audit |> Repo.all() |> Enum.empty?()
    end
  end

  describe "delete_project_user!/1" do
    test "deletes the project user and removes their credentials from the project" do
      user1 = insert(:user)
      user2 = insert(:user)

      project =
        insert(:project,
          project_users: [
            %{user_id: user1.id, role: :owner},
            %{user_id: user2.id, role: :editor}
          ]
        )

      project_user =
        Enum.find(project.project_users, fn pu -> pu.user_id == user2.id end)

      credential1 =
        insert(:credential,
          user: user1,
          project_credentials: [%{project_id: project.id}]
        )

      credential2 =
        insert(:credential,
          user: user2,
          project_credentials: [%{project_id: project.id}]
        )

      other_project = insert(:project)

      credential3 =
        insert(:credential,
          user: user2,
          project_credentials: [%{project_id: other_project.id}]
        )

      deleted_project_user = Projects.delete_project_user!(project_user)

      assert deleted_project_user.id == project_user.id
      refute Repo.get(Lightning.Projects.ProjectUser, project_user.id)

      pc1 =
        Repo.get_by(Lightning.Projects.ProjectCredential,
          project_id: project.id,
          credential_id: credential1.id
        )

      assert pc1 != nil

      pc2 =
        Repo.get_by(Lightning.Projects.ProjectCredential,
          project_id: project.id,
          credential_id: credential2.id
        )

      assert pc2 == nil

      pc3 =
        Repo.get_by(Lightning.Projects.ProjectCredential,
          project_id: other_project.id,
          credential_id: credential3.id
        )

      assert pc3 != nil

      assert Repo.get(Lightning.Credentials.Credential, credential1.id)
      assert Repo.get(Lightning.Credentials.Credential, credential2.id)
      assert Repo.get(Lightning.Credentials.Credential, credential3.id)
    end

    test "works when user has no credentials in the project" do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user_id: user.id, role: :editor}])

      project_user = List.first(project.project_users)

      deleted_project_user = Projects.delete_project_user!(project_user)

      assert deleted_project_user.id == project_user.id
      refute Repo.get(Lightning.Projects.ProjectUser, project_user.id)
    end
  end

  describe "sandboxes (list/create/workspace)" do
    test "list_sandboxes/1 returns only direct children ordered by name" do
      parent = insert(:project, name: "parent")

      _other_parent = insert(:project, name: "another-root")

      # children (unordered names to prove sorting)
      _c2 = insert(:project, name: "B-child", parent: parent)
      _c1 = insert(:project, name: "A-child", parent: parent)
      _c3 = insert(:project, name: "Z-child", parent: parent)

      got = Projects.list_sandboxes(parent.id)
      assert Enum.map(got, & &1.name) == ["A-child", "B-child", "Z-child"]
      assert Enum.uniq(Enum.map(got, & &1.parent_id)) == [parent.id]
    end

    test "create_sandbox/3 sets parent and creates a normal project (emails off by default)" do
      owner = insert(:user)

      parent =
        insert(:project, project_users: [%{user_id: owner.id, role: :owner}])

      attrs = %{
        name: "sandbox-1",
        project_users: [%{user_id: owner.id, role: :owner}]
      }

      assert {:ok, sandbox} = Projects.create_sandbox(parent, attrs)
      assert sandbox.parent_id == parent.id
      assert sandbox.name == "sandbox-1"
    end

    test "list_workspace_project/1 returns parent + its direct sandboxes (unique set)" do
      parent = insert(:project, name: "root")
      c1 = insert(:project, name: "s-a", parent: parent)
      c2 = insert(:project, name: "s-b", parent: parent)
      _unrelated = insert(:project, name: "someone-else")

      %{root: root_project, descendants: sandboxes} =
        Projects.list_workspace_projects(parent)

      # Ensure it contains exactly parent + children (order is not guaranteed)
      expected_sandboxes_ids = MapSet.new([c1.id, c2.id])
      assert MapSet.new(Enum.map(sandboxes, & &1.id)) == expected_sandboxes_ids
      assert root_project.id == parent.id
    end

    test "returns root and all descendants sorted by name ascending by default" do
      root = insert(:project, name: "root")

      # Level 1 children (unordered names to test sorting)
      c2 = insert(:project, name: "Z-child", parent: root)
      c1 = insert(:project, name: "A-child", parent: root)
      c3 = insert(:project, name: "M-child", parent: root)

      # Level 2 children (grandchildren)
      gc1 = insert(:project, name: "B-grandchild", parent: c1)
      gc2 = insert(:project, name: "Y-grandchild", parent: c2)

      # Unrelated project in different workspace
      _other_root = insert(:project, name: "other-root")

      %{root: returned_root, descendants: descendants} =
        Projects.list_workspace_projects(root.id)

      # Check root is correct
      assert returned_root.id == root.id

      # Check all descendants are included and sorted alphabetically
      expected_names = [
        "A-child",
        "B-grandchild",
        "M-child",
        "Y-grandchild",
        "Z-child"
      ]

      assert Enum.map(descendants, & &1.name) == expected_names

      # Verify correct IDs are returned
      expected_ids = [c1.id, gc1.id, c3.id, gc2.id, c2.id]
      assert Enum.map(descendants, & &1.id) == expected_ids
    end

    test "accepts Project struct and delegates to binary version" do
      root = insert(:project, name: "root")
      _c1 = insert(:project, name: "child-A", parent: root)

      # Call with struct
      %{root: returned_root, descendants: descendants} =
        Projects.list_workspace_projects(root)

      assert returned_root.id == root.id
      assert Enum.map(descendants, & &1.name) == ["child-A"]
    end

    test "works when called with child project - finds correct root" do
      root = insert(:project, name: "root")
      child = insert(:project, name: "child", parent: root)
      grandchild = insert(:project, name: "grandchild", parent: child)

      # Call with grandchild - should find root and return entire workspace
      %{root: returned_root, descendants: descendants} =
        Projects.list_workspace_projects(grandchild.id)

      assert returned_root.id == root.id
      assert Enum.map(descendants, & &1.name) == ["child", "grandchild"]
    end

    test "returns empty descendants list when root has no children" do
      root = insert(:project, name: "lonely-root")

      %{root: returned_root, descendants: descendants} =
        Projects.list_workspace_projects(root.id)

      assert returned_root.id == root.id
      assert descendants == []
    end

    test "sort_by: :name, sort_order: :desc sorts names descending" do
      root = insert(:project, name: "root")
      insert(:project, name: "Alpha", parent: root)
      insert(:project, name: "Zeta", parent: root)
      insert(:project, name: "Beta", parent: root)

      %{descendants: descendants} =
        Projects.list_workspace_projects(root.id,
          sort_by: :name,
          sort_order: :desc
        )

      assert Enum.map(descendants, & &1.name) == ["Zeta", "Beta", "Alpha"]
    end

    test "sort_by: :inserted_at sorts by creation time" do
      root = insert(:project, name: "root")

      # Insert with specific timestamps to control order
      _old_child =
        insert(:project,
          name: "old",
          parent: root,
          inserted_at: ~N[2023-01-01 10:00:00]
        )

      _new_child =
        insert(:project,
          name: "new",
          parent: root,
          inserted_at: ~N[2023-01-01 12:00:00]
        )

      _mid_child =
        insert(:project,
          name: "mid",
          parent: root,
          inserted_at: ~N[2023-01-01 11:00:00]
        )

      # Sort by inserted_at ascending
      %{descendants: descendants} =
        Projects.list_workspace_projects(root.id,
          sort_by: :inserted_at,
          sort_order: :asc
        )

      assert Enum.map(descendants, & &1.name) == ["old", "mid", "new"]

      # Sort by inserted_at descending
      %{descendants: descendants} =
        Projects.list_workspace_projects(root.id,
          sort_by: :inserted_at,
          sort_order: :desc
        )

      assert Enum.map(descendants, & &1.name) == ["new", "mid", "old"]
    end

    test "sort_by: :updated_at sorts by update time" do
      root = insert(:project, name: "root")

      old_time = ~N[2023-01-01 10:00:00]
      new_time = ~N[2023-01-01 11:00:00]

      _child1 =
        insert(:project,
          name: "child1-updated",
          parent: root,
          updated_at: old_time
        )

      _child2 =
        insert(:project,
          name: "child2-updated",
          parent: root,
          updated_at: new_time
        )

      %{descendants: descendants} =
        Projects.list_workspace_projects(root.id,
          sort_by: :updated_at,
          sort_order: :desc
        )

      assert Enum.map(descendants, & &1.name) == [
               "child2-updated",
               "child1-updated"
             ]
    end

    test "raises ArgumentError for invalid sort_by option" do
      root = insert(:project, name: "root")

      assert_raise ArgumentError,
                   ~r/Invalid sort_by option: invalid_field/,
                   fn ->
                     Projects.list_workspace_projects(root.id,
                       sort_by: :invalid_field
                     )
                   end
    end

    test "raises ArgumentError for invalid sort_order option" do
      root = insert(:project, name: "root")

      assert_raise ArgumentError,
                   ~r/Invalid sort_order option: invalid_order/,
                   fn ->
                     Projects.list_workspace_projects(root.id,
                       sort_order: :invalid_order
                     )
                   end
    end

    test "excludes projects from other workspaces" do
      # Workspace 1
      root1 = insert(:project, name: "root1")
      _child1 = insert(:project, name: "workspace1-child", parent: root1)

      # Workspace 2
      root2 = insert(:project, name: "root2")
      child2 = insert(:project, name: "workspace2-child", parent: root2)

      # Get workspace 1 projects
      %{root: returned_root, descendants: descendants} =
        Projects.list_workspace_projects(root1.id)

      assert returned_root.id == root1.id
      assert Enum.map(descendants, & &1.name) == ["workspace1-child"]

      # Ensure workspace 2 projects are not included
      descendant_ids = Enum.map(descendants, & &1.id)
      refute child2.id in descendant_ids
      refute root2.id in descendant_ids
    end

    test "handles deep nesting correctly" do
      root = insert(:project, name: "root")
      l1 = insert(:project, name: "level1", parent: root)
      l2 = insert(:project, name: "level2", parent: l1)
      l3 = insert(:project, name: "level3", parent: l2)
      _l4 = insert(:project, name: "level4", parent: l3)

      %{root: returned_root, descendants: descendants} =
        Projects.list_workspace_projects(root.id)

      assert returned_root.id == root.id

      assert Enum.map(descendants, & &1.name) == [
               "level1",
               "level2",
               "level3",
               "level4"
             ]
    end

    test "preloads parent associations" do
      root = insert(:project, name: "root")
      child = insert(:project, name: "child", parent: root)
      grandchild = insert(:project, name: "grandchild", parent: child)

      %{descendants: descendants} =
        Projects.list_workspace_projects(root.id)

      # Find the grandchild in results
      grandchild_result = Enum.find(descendants, &(&1.id == grandchild.id))

      # Parent should be preloaded
      assert grandchild_result.parent.id == child.id
      assert grandchild_result.parent.name == "child"
    end

    test "same names at different levels sort correctly" do
      root = insert(:project, name: "root")
      _child1 = insert(:project, name: "duplicate", parent: root)
      child2 = insert(:project, name: "other", parent: root)
      _grandchild = insert(:project, name: "duplicate", parent: child2)

      %{descendants: descendants} =
        Projects.list_workspace_projects(root.id)

      # Should get both "duplicate" projects in alphabetical order
      names = Enum.map(descendants, & &1.name)
      assert names == ["duplicate", "duplicate", "other"]
    end

    test "raises when project doesn't exist" do
      fake_id = Ecto.UUID.generate()

      assert_raise Ecto.NoResultsError, fn ->
        Projects.list_workspace_projects(fake_id)
      end
    end

    test "sandbox_name_exists?/3 returns true when sandbox with name exists" do
      parent = insert(:project, name: "parent")
      _existing = insert(:sandbox, parent: parent, name: "test-sandbox")

      assert Projects.sandbox_name_exists?(parent.id, "test-sandbox") == true
    end

    test "sandbox_name_exists?/3 returns false when no sandbox with name exists" do
      parent = insert(:project, name: "parent")
      _existing = insert(:sandbox, parent: parent, name: "test-sandbox")

      assert Projects.sandbox_name_exists?(parent.id, "other-name") == false
    end

    test "sandbox_name_exists?/3 excludes specific sandbox ID when provided" do
      parent = insert(:project, name: "parent")
      existing = insert(:sandbox, parent: parent, name: "test-sandbox")

      # Should return false when checking if the same sandbox's name exists
      # (useful for edit operations where we want to allow keeping the same name)
      assert Projects.sandbox_name_exists?(
               parent.id,
               "test-sandbox",
               existing.id
             ) == false
    end

    test "sandbox_name_exists?/3 returns true when different sandbox has same name (edit case)" do
      parent = insert(:project, name: "parent")
      existing1 = insert(:sandbox, parent: parent, name: "test-sandbox")
      _existing2 = insert(:sandbox, parent: parent, name: "other-sandbox")

      # Should return true when trying to rename existing1 to "other-sandbox"
      assert Projects.sandbox_name_exists?(
               parent.id,
               "other-sandbox",
               existing1.id
             ) == true
    end
  end

  describe "project head hash + version history helpers" do
    test "compute_project_head_hash/1 uses latest per workflow and is deterministic" do
      project = insert(:project)

      # Two workflows in this project
      w1 = insert(:simple_workflow, project: project)
      w2 = insert(:simple_workflow, project: project)

      # Insert workflow_versions with controlled inserted_at so ordering is deterministic
      now = DateTime.utc_now(:microsecond)
      later = DateTime.add(now, 1, :microsecond)
      latest = DateTime.add(now, 2, :microsecond)

      rows = [
        %{
          id: Ecto.UUID.generate(),
          workflow_id: w1.id,
          hash: "aaaaaaaaaaaa",
          source: "app",
          inserted_at: now
        },
        %{
          id: Ecto.UUID.generate(),
          workflow_id: w1.id,
          hash: "bbbbbbbbbbbb",
          source: "cli",
          inserted_at: later
        },
        %{
          id: Ecto.UUID.generate(),
          workflow_id: w2.id,
          hash: "cccccccccccc",
          source: "app",
          inserted_at: latest
        }
      ]

      Repo.insert_all(Lightning.Workflows.WorkflowVersion, rows)

      # Build expected digest the same way as the implementation
      pairs =
        [
          {w1.id, "bbbbbbbbbbbb"},
          {w2.id, "cccccccccccc"}
        ]
        |> Enum.sort_by(fn {wid, _} -> to_string(wid) end)
        |> Enum.map(fn {wid, h} -> [to_string(wid), h] end)

      expected =
        pairs
        |> Jason.encode!()
        |> then(fn data -> :crypto.hash(:sha256, data) end)
        |> Base.encode16(case: :lower)
        |> binary_part(0, 12)

      assert Projects.compute_project_head_hash(project.id) == expected
    end

    test "append_project_head/2 appends once and validates format" do
      project = insert(:project, version_history: [])

      # Valid 12-hex hash
      h1 = "deadbeefcafe"
      assert {:ok, p1} = Projects.append_project_head(project, h1)
      assert p1.version_history == [h1]

      # Appending the same hash again is a no-op
      assert {:ok, p2} = Projects.append_project_head(p1, h1)
      assert p2.version_history == [h1]

      # Invalid hash returns {:error, :bad_hash}
      assert {:error, :bad_hash} = Projects.append_project_head(p2, "not-hex")
    end

    test "append_project_head!/2 raises on bad hash and returns updated project on success" do
      project = insert(:project, version_history: [])

      good = "0123456789ab"
      bad = "oops"

      # Success path
      updated = Projects.append_project_head!(project, good)
      assert updated.version_history == [good]

      # Error path
      assert_raise ArgumentError,
                   "head_hash must be 12 lowercase hex chars",
                   fn ->
                     Projects.append_project_head!(updated, bad)
                   end
    end

    test "rejects uppercase even if otherwise valid" do
      p = insert(:project)

      assert {:error, :bad_hash} =
               Projects.append_project_head(p, "ABCDEF123456")
    end

    test "concurrent appends of the same hash result in a single entry" do
      p = insert(:project)

      fun = fn -> Projects.append_project_head!(p, "abcdef123456") end
      tasks = for _ <- 1..10, do: Task.async(fun)
      _ = Enum.map(tasks, &Task.await/1)

      p = Repo.get!(Lightning.Projects.Project, p.id)
      assert p.version_history == ["abcdef123456"]
    end

    test "concurrent appends of different hashes keep both (order unspecified)" do
      p = insert(:project)

      t1 = Task.async(fn -> Projects.append_project_head!(p, "aaaaaaaaaaaa") end)
      t2 = Task.async(fn -> Projects.append_project_head!(p, "bbbbbbbbbbbb") end)
      _ = Task.await(t1)
      _ = Task.await(t2)

      p = Repo.get!(Lightning.Projects.Project, p.id)

      assert Enum.sort(p.version_history) ==
               Enum.sort(["aaaaaaaaaaaa", "bbbbbbbbbbbb"])
    end

    test "version_history attrs are ignored by changeset (append-only via context)" do
      {:ok, p} =
        %Project{}
        |> Project.changeset(%{name: "p", version_history: ["abcdef123456"]})
        |> Repo.insert()

      assert p.version_history == []

      {:ok, p2} =
        p
        |> Project.changeset(%{version_history: ["bbbbbbbbbbbb"]})
        |> Repo.update()

      assert p2.version_history == []
    end

    test "compute_project_head_hash/1 returns stable digest for projects with no workflow versions" do
      p = insert(:project)

      expected =
        []
        |> Jason.encode!()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)
        |> binary_part(0, 12)

      assert Projects.compute_project_head_hash(p.id) == expected
    end
  end

  describe "sandbox facade delegates" do
    test "provision_sandbox/3 creates a child project and sets parent_id" do
      owner = insert(:user)

      parent =
        insert(:project, project_users: [%{user_id: owner.id, role: :owner}])

      {:ok, sandbox} =
        Projects.provision_sandbox(parent, owner, %{name: "sb-1"})

      assert sandbox.parent_id == parent.id
      assert sandbox.name == "sb-1"
      assert is_list(sandbox.version_history)
    end

    test "update_sandbox/3 updates basic fields on the sandbox" do
      owner = insert(:user)

      parent =
        insert(:project, project_users: [%{user_id: owner.id, role: :owner}])

      {:ok, sandbox} = Projects.provision_sandbox(parent, owner, %{name: "old"})

      {:ok, updated} =
        Projects.update_sandbox(sandbox, owner, %{name: "new"})

      assert updated.name == "new"
    end

    test "delete_sandbox/2 removes the child project" do
      owner = insert(:user)

      parent =
        insert(:project, project_users: [%{user_id: owner.id, role: :owner}])

      {:ok, sandbox} =
        Projects.provision_sandbox(parent, owner, %{name: "to-delete"})

      assert {:ok, %Lightning.Projects.Project{}} =
               Projects.delete_sandbox(sandbox, owner)

      refute Repo.get(Lightning.Projects.Project, sandbox.id)
    end
  end

  describe "descendant_of?/3" do
    test "returns true when child is direct descendant of parent" do
      parent = insert(:project, name: "parent")
      child = insert(:project, name: "child", parent: parent)

      # Preload the parent association for the child
      child_with_parent = Repo.preload(child, :parent)

      assert Projects.descendant_of?(child_with_parent, parent)
    end

    test "returns false when projects are siblings (same parent)" do
      parent = insert(:project, name: "parent")
      sibling1 = insert(:project, name: "sibling1", parent: parent)
      sibling2 = insert(:project, name: "sibling2", parent: parent)

      # Preload parent associations
      sibling1_with_parent = Repo.preload(sibling1, :parent)
      sibling2_with_parent = Repo.preload(sibling2, :parent)

      refute Projects.descendant_of?(sibling1_with_parent, sibling2_with_parent)
      refute Projects.descendant_of?(sibling2_with_parent, sibling1_with_parent)
    end

    test "returns true for multi-level descendants (grandchild, great-grandchild, etc.)" do
      root = insert(:project, name: "root")
      child = insert(:project, name: "child", parent: root)
      grandchild = insert(:project, name: "grandchild", parent: child)

      great_grandchild =
        insert(:project, name: "great_grandchild", parent: grandchild)

      # Build the chain with preloaded parents
      great_grandchild = Repo.preload(great_grandchild, :parent)
      grandchild = Repo.preload(grandchild, :parent)
      child = Repo.preload(child, :parent)

      # Update the preloaded associations to form the complete chain
      great_grandchild = %{great_grandchild | parent: grandchild}
      grandchild = %{grandchild | parent: child}
      child = %{child | parent: root}

      great_grandchild = %{
        great_grandchild
        | parent: %{grandchild | parent: child}
      }

      assert Projects.descendant_of?(great_grandchild, root)
      assert Projects.descendant_of?(great_grandchild, child)
      assert Projects.descendant_of?(great_grandchild, grandchild)
      assert Projects.descendant_of?(grandchild, root)
      assert Projects.descendant_of?(grandchild, child)
      assert Projects.descendant_of?(child, root)
    end

    test "returns false when child is the root (no parent)" do
      root = insert(:project, name: "root")
      other_root = insert(:project, name: "other_root")

      # Preload to ensure parent is nil
      root_with_parent = Repo.preload(root, :parent)
      other_root_with_parent = Repo.preload(other_root, :parent)

      refute Projects.descendant_of?(root_with_parent, other_root_with_parent)
      refute Projects.descendant_of?(other_root_with_parent, root_with_parent)
    end

    test "returns false when child has reached the root in the recursive walk" do
      root = insert(:project, name: "root")
      other_root = insert(:project, name: "other_root")

      child_of_other =
        insert(:project, name: "child_of_other", parent: other_root)

      # Preload associations properly
      child_with_parent = Repo.preload(child_of_other, :parent)

      refute Projects.descendant_of?(child_with_parent, root)
    end

    test "returns false when child's parent_id equals root_project.id (stops recursion)" do
      root = insert(:project, name: "root")
      direct_child = insert(:project, name: "direct_child", parent: root)
      other_project = insert(:project, name: "other_project")

      # Preload the parent association
      child_with_parent = Repo.preload(direct_child, :parent)

      # When the child's parent is the root, it should not be considered a descendant of other_project
      refute Projects.descendant_of?(child_with_parent, other_project, root)
    end

    test "handles nil parent_id correctly (stops recursion)" do
      # This has nil parent_id
      root = insert(:project, name: "root")
      other_project = insert(:project, name: "other_project")

      # Preload to ensure parent is nil
      root_with_parent = Repo.preload(root, :parent)

      refute Projects.descendant_of?(root_with_parent, other_project)
    end

    test "uses provided root_project parameter correctly" do
      workspace_root = insert(:project, name: "workspace_root")
      child = insert(:project, name: "child", parent: workspace_root)
      grandchild = insert(:project, name: "grandchild", parent: child)

      # Different workspace
      other_root = insert(:project, name: "other_root")

      # Build proper parent chain
      grandchild = Repo.preload(grandchild, :parent)
      child = Repo.preload(child, :parent)
      grandchild = %{grandchild | parent: %{child | parent: workspace_root}}

      # When root_project is provided, recursion should stop at that root
      assert Projects.descendant_of?(grandchild, child, workspace_root)

      # Should return false when checking against different root
      refute Projects.descendant_of?(grandchild, other_root, workspace_root)
    end

    test "auto-discovers root when root_project parameter is nil" do
      root = insert(:project, name: "auto_discovered_root")
      child = insert(:project, name: "child", parent: root)
      grandchild = insert(:project, name: "grandchild", parent: child)

      # Build parent chain
      grandchild = Repo.preload(grandchild, :parent)
      child = Repo.preload(child, :parent)
      grandchild = %{grandchild | parent: %{child | parent: root}}

      # Should auto-discover root and work correctly
      assert Projects.descendant_of?(grandchild, child, nil)
      assert Projects.descendant_of?(grandchild, root, nil)
    end

    test "complex hierarchy with multiple branches" do
      # Create a complex tree structure
      root = insert(:project, name: "root")

      # Branch 1
      branch1 = insert(:project, name: "branch1", parent: root)
      branch1_child = insert(:project, name: "branch1_child", parent: branch1)

      # Branch 2
      branch2 = insert(:project, name: "branch2", parent: root)
      branch2_child = insert(:project, name: "branch2_child", parent: branch2)

      # Build proper parent chains
      branch1_child = Repo.preload(branch1_child, :parent)
      branch1 = Repo.preload(branch1, :parent)
      branch1_child = %{branch1_child | parent: %{branch1 | parent: root}}

      branch2_child = Repo.preload(branch2_child, :parent)
      branch2 = Repo.preload(branch2, :parent)
      branch2_child = %{branch2_child | parent: %{branch2 | parent: root}}

      # Test relationships within branches
      assert Projects.descendant_of?(branch1_child, branch1)
      assert Projects.descendant_of?(branch1_child, root)
      assert Projects.descendant_of?(branch2_child, branch2)
      assert Projects.descendant_of?(branch2_child, root)

      # Test cross-branch relationships (should be false)
      refute Projects.descendant_of?(branch1_child, branch2)
      refute Projects.descendant_of?(branch2_child, branch1)
      refute Projects.descendant_of?(branch1_child, branch2_child)
    end

    test "edge case: project compared to itself" do
      project = insert(:project, name: "self")
      project_with_parent = Repo.preload(project, :parent)

      # A project is not considered a descendant of itself
      refute Projects.descendant_of?(project_with_parent, project_with_parent)
    end

    test "edge case: deeply nested hierarchy performance" do
      # Test with a very deep hierarchy to ensure it doesn't hit stack overflow
      root = insert(:project, name: "deep_root")

      # Create a chain of 10 levels deep
      deepest =
        Enum.reduce(1..10, root, fn level, parent ->
          insert(:project, name: "level_#{level}", parent: parent)
        end)

      # Build the complete parent chain by preloading recursively
      current = Repo.preload(deepest, :parent)

      # Walk up the chain to build proper associations
      current = build_parent_chain(current)

      assert Projects.descendant_of?(current, root)
    end
  end

  defp build_parent_chain(project) do
    case project.parent do
      nil ->
        project

      parent ->
        parent_with_chain = build_parent_chain(Repo.preload(parent, :parent))
        %{project | parent: parent_with_chain}
    end
  end

  @spec full_project_fixture(attrs :: Keyword.t()) :: %{optional(any) => any}
  def full_project_fixture(attrs \\ []) when is_list(attrs) do
    %{workflows: [workflow_1, workflow_2]} =
      project = build_full_project(attrs)

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

  defp data_retention_email(updated_project) do
    %{
      subject:
        "The data retention policy for #{updated_project.name} has been modified",
      body: """
      Hi anna,

      The data retention policy for your project, #{updated_project.name}, has been updated. Here are the new details:

      - 14 days history retention
      - input/output (I/O) data is saved for reprocessing
      - 7 days I/O data retention

      This policy can be changed by owners and administrators. If you haven't approved this change, please reset the policy by visiting the URL below:

      #{LightningWeb.Endpoint.url() <> "/projects/#{updated_project.id}/settings#data-storage"}

      OpenFn
      """
    }
  end

  defp dataclip_with_body_and_request(dataclip) do
    reloaded_dataclip = Repo.get(Dataclip, dataclip.id)

    from(Dataclip, select: [:wiped_at, :body, :request])
    |> Lightning.Repo.get(reloaded_dataclip.id)
  end
end
