defmodule Lightning.ProjectsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.ProjectUser
  alias Lightning.Projects
  alias Lightning.Projects.Project

  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures
  import Lightning.CredentialsFixtures

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
      project = project_fixture() |> unload_relation(:project_users)
      assert Projects.get_project!(project.id) == project

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
      %{
        project: project,
        w1: w1,
        w1_job: w1_job,
        project1: project1,
        # p1_w1: p1_w1,
        p1_w1_job: p1_w1_job
      } = full_project_fixture()

      user =
        from(u in Lightning.Accounts.User,
          join: p in assoc(u, :project_users),
          where: p.project_id == ^project.id
        )
        |> Repo.one()

      {:ok, workorder_multi} =
        Lightning.WorkOrderService.multi_for(
          :webhook,
          w1_job,
          ~s[{"foo": "bar"}] |> Jason.decode!()
        )
        |> Repo.transaction()

      Lightning.WorkOrderService.multi_for(
        :webhook,
        p1_w1_job,
        ~s[{"foo": "bar"}] |> Jason.decode!()
      )
      |> Repo.transaction()

      Lightning.WorkOrderService.retry_attempt_run(
        workorder_multi.attempt_run,
        user
      )

      assert from(w in Lightning.WorkOrder,
               where: w.workflow_id == ^w1.id,
               select: count(w.id)
             )
             |> Repo.one() == 1,
             "There should be only one workorder"

      assert from(a in Lightning.Attempt,
               where: a.id == ^workorder_multi.attempt.id,
               select: count(a.id)
             )
             |> Repo.one() == 1,
             "There should be only one attempt"

      assert from(ar in Lightning.AttemptRun,
               where: ar.id == ^workorder_multi.attempt_run.id,
               select: count(ar.id)
             )
             |> Repo.one() == 1,
             "There should be only one attempt run"

      assert from(ir in Lightning.InvocationReason,
               join: t in assoc(ir, :trigger),
               where: t.workflow_id == ^w1.id,
               select: count(ir.id)
             )
             |> Repo.one() == 1,
             "There should be only one invocation reason for a trigger"

      assert from(ir in Lightning.InvocationReason,
               join: r in assoc(ir, :run),
               where: r.job_id == ^w1_job.id,
               select: count(ir.id)
             )
             |> Repo.one() == 1,
             "There should be only one invocation reason for a run."

      assert from(ir in Lightning.InvocationReason,
               join: d in assoc(ir, :dataclip),
               where: d.project_id == ^project.id,
               select: count(ir.id)
             )
             |> Repo.one() == 1,
             "There should be only one invocation reason for dataclip"

      assert from(pu in Ecto.assoc(project, :project_users), select: count(pu.id))
             |> Repo.one() == 1,
             "There should be only one project user"

      assert from(pc in Ecto.assoc(project, :project_credentials),
               select: count(pc.id)
             )
             |> Repo.one() == 1,
             "There should be only one project credential"

      assert from(w in Ecto.assoc(project, :workflows), select: count(w.id))
             |> Repo.one() == 2,
             "There should be only two workflows"

      assert from(jo in Ecto.assoc(project, :jobs), select: count(jo.id))
             |> Repo.one() == 5,
             "There should be only five jobs"

      assert {:ok, %Project{}} = Projects.delete_project(project)

      assert from(pu in Ecto.assoc(project, :project_users), select: count(pu.id))
             |> Repo.one() == 0,
             "Should be no project users left after deletion"

      assert from(pc in Ecto.assoc(project, :project_credentials),
               select: count(pc.id)
             )
             |> Repo.one() == 0,
             "Should be no project credential left after deletion"

      assert from(w in Ecto.assoc(project, :workflows), select: count(w.id))
             |> Repo.one() == 0,
             "Should be no workflows left after deletion"

      assert from(jo in Ecto.assoc(project, :jobs), select: count(jo.id))
             |> Repo.one() == 0,
             "Should be no jobs left after deletion"

      assert from(a in Lightning.Attempt,
               where: a.id == ^workorder_multi.attempt.id,
               select: count(a.id)
             )
             |> Repo.one() == 0,
             "Should be no attempts left after deletion"

      assert from(ar in Lightning.AttemptRun,
               where: ar.id == ^workorder_multi.attempt_run.id,
               select: count(ar.id)
             )
             |> Repo.one() == 0,
             "Should be no attempts run left after deletion"

      assert from(w in Lightning.WorkOrder,
               where: w.workflow_id == ^w1.id,
               select: count(w.id)
             )
             |> Repo.one() == 0,
             "Should be no workorder left after deletion"

      assert from(ir in Lightning.InvocationReason,
               join: t in assoc(ir, :trigger),
               where: t.workflow_id == ^w1.id,
               select: count(ir.id)
             )
             |> Repo.one() == 0,
             "Should be no invocation reasons left for the trigger after deletion."

      assert from(ir in Lightning.InvocationReason,
               join: r in assoc(ir, :run),
               where: r.job_id == ^w1_job.id,
               select: count(ir.id)
             )
             |> Repo.one() == 0,
             "Should be no invocation reasons left for the job run after deletion."

      assert from(ir in Lightning.InvocationReason,
               join: d in assoc(ir, :dataclip),
               where: d.project_id == ^project.id,
               select: count(ir.id)
             )
             |> Repo.one() == 0,
             "Should be no invocation reasons left for the dataclip after deletion."

      assert_raise Ecto.NoResultsError, fn ->
        Projects.get_project!(project.id)
      end

      assert project1.id == Projects.get_project!(project1.id).id,
             "Should be one project1"

      assert from(r in Lightning.Invocation.Run,
               join: j in assoc(r, :job),
               join: w in assoc(j, :workflow),
               where: w.project_id == ^project1.id,
               select: count(r.id)
             )
             |> Repo.one() == 1,
             "Should be one run activity for project1"
    end

    test "change_project/1 returns a project changeset" do
      project = project_fixture()
      assert %Ecto.Changeset{} = Projects.change_project(project)
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

      assert [project_1, project_2] == Projects.get_projects_for_user(user)
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
      %{project: project} = full_project_fixture()
      expected_yaml = File.read!("test/fixtures/canonical_project.yaml")
      {:ok, generated_yaml} = Projects.export_project(:yaml, project.id)

      assert generated_yaml == expected_yaml
    end
  end
end
