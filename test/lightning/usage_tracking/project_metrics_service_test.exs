defmodule Lightning.UsageTracking.ProjectMetricsServiceTest do
  use Lightning.DataCase

  alias Lightning.UsageTracking.ProjectMetricsService
  alias Lightning.UsageTracking.WorkflowMetricsService

  setup do
    project_id = "3cfb674b-e878-470d-b7c0-cfa8f7e003ae"

    active_user_count = 2

    project =
      build_project(
        active_user_count,
        project_id,
        active_user_threshold_time: ~U[2023-11-08 00:00:00Z],
        report_time: ~U[2024-02-05 23:59:59Z]
      )

    _other_project =
      build_project(
        3,
        Ecto.UUID.generate(),
        active_user_threshold_time: ~U[2023-11-08 00:00:00Z],
        report_time: ~U[2024-02-05 23:59:59Z]
      )

    %{
      active_user_count: active_user_count,
      date: ~D[2024-02-05],
      hashed_id:
        "EECF8CFDD120E8DF8D9A12CA92AC3E815908223F95CFB11F19261A3C0EB34AEC",
      project: project,
      project_id: project_id
    }
  end

  describe ".find_eligible_projects" do
    setup do
      %{date: ~D[2024-02-05]}
    end

    test "returns all projects created before the date", %{date: date} do
      eligible_project_1 =
        insert(:project, inserted_at: ~U[2024-02-05 23:59:58Z])
      eligible_project_2 =
        insert(:project, inserted_at: ~U[2024-02-04 23:59:59Z])
      ineligible_project_1 =
        insert(:project, inserted_at: ~U[2024-02-06 00:00:00Z])
      ineligible_project_2 =
        insert(:project, inserted_at: ~U[2024-02-06 00:00:01Z])

      result = ProjectMetricsService.find_eligible_projects(date)

      assert result |> contains?(eligible_project_1)
      assert result |> contains?(eligible_project_2)
      refute result |> contains?(ineligible_project_1)
      refute result |> contains?(ineligible_project_2)
    end

  end

  describe ".generate_metrics/3 - cleartext disabled" do
    setup context do
      context |> Map.merge(%{enabled: false})
    end

    test "includes the hashed project id", %{
      date: date,
      enabled: enabled,
      hashed_id: hashed_id,
      project: project
    } do
      assert %{
               hashed_uuid: ^hashed_id
             } = ProjectMetricsService.generate_metrics(project, enabled, date)
    end

    test "excludes the cleartext uuid", %{
      date: date,
      enabled: enabled,
      project: project
    } do
      assert %{
               cleartext_uuid: nil
             } = ProjectMetricsService.generate_metrics(project, enabled, date)
    end

    test "includes the number of enabled users", %{
      active_user_count: active_user_count,
      date: date,
      enabled: enabled,
      project: project
    } do
      enabled_user_count = active_user_count + 1

      assert %{
               no_of_users: ^enabled_user_count
             } = ProjectMetricsService.generate_metrics(project, enabled, date)
    end

    test "includes the number of active users", %{
      active_user_count: active_user_count,
      date: date,
      enabled: enabled,
      project: project
    } do
      assert %{
               no_of_active_users: ^active_user_count
             } = ProjectMetricsService.generate_metrics(project, enabled, date)
    end

    test "includes data for associated workflows", %{
      date: date,
      enabled: enabled,
      project: project
    } do
      [workflow_1, workflow_2] = project.workflows

      %{workflows: workflows} =
        ProjectMetricsService.generate_metrics(project, enabled, date)

      workflows
      |> assert_workflow_metrics(
        workflow: workflow_1,
        cleartext_enabled: enabled,
        date: date
      )

      workflows
      |> assert_workflow_metrics(
        workflow: workflow_2,
        cleartext_enabled: enabled,
        date: date
      )
    end
  end

  describe ".generate_metrics/3 - cleartext enabled" do
    setup context do
      context |> Map.merge(%{enabled: true})
    end

    test "includes the hashed project id", %{
      date: date,
      enabled: enabled,
      hashed_id: hashed_id,
      project: project
    } do
      assert %{
               hashed_uuid: ^hashed_id
             } = ProjectMetricsService.generate_metrics(project, enabled, date)
    end

    test "includes the cleartext uuid", %{
      date: date,
      enabled: enabled,
      project: project
    } do
      project_id = project.id

      assert %{
               cleartext_uuid: ^project_id
             } = ProjectMetricsService.generate_metrics(project, enabled, date)
    end

    test "includes the number of enabled users", %{
      active_user_count: active_user_count,
      date: date,
      enabled: enabled,
      project: project
    } do
      enabled_user_count = active_user_count + 1

      assert %{
               no_of_users: ^enabled_user_count
             } = ProjectMetricsService.generate_metrics(project, enabled, date)
    end

    test "includes the number of active users", %{
      active_user_count: active_user_count,
      date: date,
      enabled: enabled,
      project: project
    } do
      assert %{
               no_of_active_users: ^active_user_count
             } = ProjectMetricsService.generate_metrics(project, enabled, date)
    end

    test "includes data for associated workflows", %{
      date: date,
      enabled: enabled,
      project: project
    } do
      [workflow_1, workflow_2] = project.workflows

      %{workflows: workflows} =
        ProjectMetricsService.generate_metrics(project, enabled, date)

      workflows
      |> assert_workflow_metrics(
        workflow: workflow_1,
        cleartext_enabled: enabled,
        date: date
      )

      workflows
      |> assert_workflow_metrics(
        workflow: workflow_2,
        cleartext_enabled: enabled,
        date: date
      )
    end
  end

  defp build_project(count, project_id, opts) do
    active_user_threshold_time = opts |> Keyword.get(:active_user_threshold_time)
    report_time = opts |> Keyword.get(:report_time)

    project =
      insert(
        :project,
        id: project_id,
        project_users:
          build_project_users(
            count,
            active_user_threshold_time,
            report_time
          )
      )

    insert_list(count, :workflow, project: project)

    project |> Repo.preload([:users, workflows: [:jobs, :runs]])
  end

  defp build_project_users(count, active_user_threshold_time, report_time) do
    active_users =
      build_list(
        count,
        :project_user,
        user: fn ->
          insert_active_user(active_user_threshold_time, report_time)
        end
      )

    enabled_user =
      build(
        :project_user,
        user: fn ->
          insert_enabled_user(active_user_threshold_time, report_time)
        end
      )

    disabled_user =
      build(
        :project_user,
        user: fn ->
          insert_disabled_user(report_time)
        end
      )

    [disabled_user | [enabled_user | active_users]]
  end

  defp insert_active_user(active_user_threshold_time, report_time) do
    user = insert_enabled_user(active_user_threshold_time, report_time)

    insert(
      :user_token,
      context: "session",
      user: user,
      inserted_at: active_user_threshold_time
    )

    user
  end

  defp insert_enabled_user(active_user_threshold_time, report_time) do
    user = insert(:user, disabled: false, inserted_at: report_time)

    precedes_active_threshold =
      active_user_threshold_time
      |> DateTime.add(-1, :second)

    insert(
      :user_token,
      context: "session",
      user: user,
      inserted_at: precedes_active_threshold
    )

    user
  end

  defp insert_disabled_user(report_time) do
    activated_after_report = report_time |> DateTime.add(1, :second)

    insert(:user, disabled: false, inserted_at: activated_after_report)
  end

  defp assert_workflow_metrics(workflows_metrics, opts) do
    workflow = opts |> Keyword.get(:workflow)
    cleartext_enabled = opts |> Keyword.get(:cleartext_enabled)
    date = opts |> Keyword.get(:date)

    workflow_metrics = workflows_metrics |> find_instrumentation(workflow.id)

    expected_metrics =
      WorkflowMetricsService.generate_metrics(workflow, cleartext_enabled, date)

    assert workflow_metrics == expected_metrics
  end

  defp find_instrumentation(instrumented_collection, identity) do
    hashed_uuid = build_hash(identity)

    instrumented_collection
    |> Enum.find(fn record -> record.hashed_uuid == hashed_uuid end)
  end

  defp build_hash(uuid), do: Base.encode16(:crypto.hash(:sha256, uuid))

  defp contains?(result, desired_project) do
    result |> Enum.find(fn project -> project.id == desired_project.id end)
  end
end
