defmodule Lightning.UsageTracking.ReportDataTest do
  use Lightning.DataCase, async: false

  import Lightning.ApplicationHelpers, only: [put_temporary_env: 3]
  import Mock

  alias Lightning.UsageTracking
  alias Lightning.UsageTracking.GithubClient
  alias Lightning.UsageTracking.ProjectMetricsService
  alias Lightning.UsageTracking.ReportData

  describe ".generate/3 - cleartext uuids disabled" do
    setup_with_mocks [
      {GithubClient, [], [open_fn_commit?: fn _ -> true end]}
    ] do
      %{}
      |> setup_data_for_version_generation()
      |> setup_daily_report_config()
      |> setup_cleartext_uuids_disabled()
      |> setup_date()
    end

    test "sets the time that the report was generated at", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      %{generated_at: generated_at} =
        ReportData.generate(report_config, enabled, date)

      assert DateTime.diff(DateTime.utc_now(), generated_at, :second) < 1
    end

    test "contains hashed uuid of reporting instance", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      %{instance_id: instance_id} = report_config

      %{instance: %{hashed_uuid: hashed_uuid}} =
        ReportData.generate(report_config, enabled, date)

      assert hashed_uuid == build_hash(instance_id)
    end

    test "cleartext uuid of reporting instance is nil", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      assert %{
               instance: %{cleartext_uuid: nil}
             } = ReportData.generate(report_config, enabled, date)
    end

    test "indicates the version of lightning present on the instance", %{
      cleartext_enabled: enabled,
      commit: commit,
      config: report_config,
      date: date
    } do
      expected = "v#{Application.spec(:lightning, :vsn)}:edge:#{commit}"

      assert %{
               instance: %{
                 version: ^expected
               }
             } = ReportData.generate(report_config, enabled, date)
    end

    test "includes the total number of users", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      _user_1 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _user_2 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _user_3 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      assert %{
               instance: %{no_of_users: 3}
             } = ReportData.generate(report_config, enabled, date)
    end

    test "includes the total number of active users", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      within_threshold_date = Date.add(date, -89)

      {:ok, within_threshold_time, _offset} =
        DateTime.from_iso8601("#{within_threshold_date}T10:00:00Z")

      outside_threshold_date = Date.add(date, -90)

      {:ok, outside_threshold_time, _offset} =
        DateTime.from_iso8601("#{outside_threshold_date}T10:00:00Z")

      user_1 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _active_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: within_threshold_time,
          user: user_1
        )

      user_2 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _inactive_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: outside_threshold_time,
          user: user_2
        )

      assert %{
               instance: %{no_of_active_users: 1}
             } = ReportData.generate(report_config, enabled, date)
    end

    test "includes the operating system details", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      {_os_family, os_name_atom} = :os.type()

      os_name = os_name_atom |> Atom.to_string()

      assert String.match?(os_name, ~r/.{5,}/)

      assert %{instance: %{operating_system: ^os_name}} =
               ReportData.generate(report_config, enabled, date)
    end

    test "includes project details for projects created before date", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      after_date = Date.add(date, 1)

      project_1 = build_project(2, date)
      project_2 = build_project(5, after_date)
      project_3 = build_project(3, date)

      %{projects: projects} = ReportData.generate(report_config, enabled, date)

      # assert projects |> count() == 2

      projects
      |> assert_project_metrics(
        project: project_1,
        cleartext_enabled: enabled,
        date: date
      )

      projects
      |> assert_project_metrics(
        project: project_3,
        cleartext_enabled: enabled,
        date: date
      )

      projects |> assert_no_project_metrics(project_2)
    end

    test "indicates the version of the report data structure in use", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      assert %{version: "2"} = ReportData.generate(report_config, enabled, date)
    end

    test "indicates the applicable report date", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      assert %{report_date: ^date} =
               ReportData.generate(report_config, enabled, date)
    end
  end

  describe ".generate/3 - cleartext uuids enabled" do
    setup_with_mocks [
      {GithubClient, [], [open_fn_commit?: fn _ -> true end]}
    ] do
      %{}
      |> setup_data_for_version_generation()
      |> setup_daily_report_config()
      |> setup_cleartext_uuids_enabled()
      |> setup_date()
    end

    test "sets the time that the report was generated at", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      %{generated_at: generated_at} =
        ReportData.generate(report_config, enabled, date)

      assert DateTime.diff(DateTime.utc_now(), generated_at, :second) < 1
    end

    test "contains hashed uuid of reporting instance", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      %{instance_id: instance_id} = report_config

      %{instance: %{hashed_uuid: hashed_uuid}} =
        ReportData.generate(report_config, enabled, date)

      assert hashed_uuid == build_hash(instance_id)
    end

    test "cleartext uuid of reporting instance is populated", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      %{instance_id: instance_id} = report_config

      assert %{
               instance: %{cleartext_uuid: ^instance_id}
             } = ReportData.generate(report_config, enabled, date)
    end

    test "indicates the version of lightning present on the instance", %{
      cleartext_enabled: enabled,
      commit: commit,
      config: report_config,
      date: date
    } do
      expected = "v#{Application.spec(:lightning, :vsn)}:edge:#{commit}"

      assert %{
               instance: %{
                 version: ^expected
               }
             } = ReportData.generate(report_config, enabled, date)
    end

    test "includes the total number of users", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      _user_1 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _user_2 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _user_3 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      assert %{
               instance: %{no_of_users: 3}
             } = ReportData.generate(report_config, enabled, date)
    end

    test "includes the total number of active users", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      within_threshold_date = Date.add(date, -89)

      {:ok, within_threshold_time, _offset} =
        DateTime.from_iso8601("#{within_threshold_date}T10:00:00Z")

      outside_threshold_date = Date.add(date, -90)

      {:ok, outside_threshold_time, _offset} =
        DateTime.from_iso8601("#{outside_threshold_date}T10:00:00Z")

      user_1 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _active_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: within_threshold_time,
          user: user_1
        )

      user_2 =
        insert(
          :user,
          inserted_at: ~U[2024-02-04 01:00:00Z]
        )

      _inactive_token =
        insert(
          :user_token,
          context: "session",
          inserted_at: outside_threshold_time,
          user: user_2
        )

      assert %{
               instance: %{no_of_active_users: 1}
             } = ReportData.generate(report_config, enabled, date)
    end

    test "includes the operating system details", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      {_os_family, os_name_atom} = :os.type()

      os_name = os_name_atom |> Atom.to_string()

      assert String.match?(os_name, ~r/.{5,}/)

      assert %{instance: %{operating_system: ^os_name}} =
               ReportData.generate(report_config, enabled, date)
    end

    test "includes project details for projects created before date", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      after_date = Date.add(date, 1)

      project_1 = build_project(2, date)
      project_2 = build_project(5, after_date)
      project_3 = build_project(3, date)

      %{projects: projects} = ReportData.generate(report_config, enabled, date)

      # assert projects |> count() == 2

      projects
      |> assert_project_metrics(
        project: project_1,
        cleartext_enabled: enabled,
        date: date
      )

      projects
      |> assert_project_metrics(
        project: project_3,
        cleartext_enabled: enabled,
        date: date
      )

      projects |> assert_no_project_metrics(project_2)
    end

    test "indicates the version of the report data structure in use", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      assert %{version: "2"} = ReportData.generate(report_config, enabled, date)
    end

    test "indicates the applicable report date", %{
      cleartext_enabled: enabled,
      config: report_config,
      date: date
    } do
      assert %{report_date: ^date} =
               ReportData.generate(report_config, enabled, date)
    end
  end

  defp setup_data_for_version_generation(context) do
    commit = "abc123"

    put_temporary_env(:lightning, :image_info,
      branch: "foo-bar",
      commit: commit,
      image_tag: "edge"
    )

    context
    |> Map.merge(%{
      commit: commit
    })
  end

  defp setup_daily_report_config(context) do
    Map.merge(
      context,
      %{config: UsageTracking.enable_daily_report(DateTime.utc_now())}
    )
  end

  defp setup_cleartext_uuids_disabled(context) do
    Map.merge(context, %{cleartext_enabled: false})
  end

  defp setup_cleartext_uuids_enabled(context) do
    Map.merge(context, %{cleartext_enabled: true})
  end

  defp setup_date(context), do: Map.merge(context, %{date: ~D[2024-02-25]})

  defp build_hash(uuid), do: Base.encode16(:crypto.hash(:sha256, uuid))

  defp build_project(count, date) do
    {:ok, inserted_at, _offset} = DateTime.from_iso8601("#{date}T10:11:12Z")

    project =
      insert(
        :project,
        name: "proj-#{count}",
        inserted_at: inserted_at,
        project_users: build_project_users(count)
      )

    workflows = insert_list(1, :workflow, name: "wf-#{count}", project: project)

    for workflow <- workflows do
      [job | _] = insert_list(count, :job, workflow: workflow)
      work_orders = insert_list(count, :workorder, workflow: workflow)

      for work_order <- work_orders do
        insert_runs_with_steps(
          count: count,
          project: project,
          work_order: work_order,
          job: job,
          finished_at: inserted_at
        )
      end
    end

    project |> Repo.preload([:users, workflows: [:jobs, runs: [steps: [:job]]]])
  end

  defp build_project_users(count) do
    build_list(count, :project_user, user: fn -> build(:user) end)
  end

  defp insert_runs_with_steps(options) do
    count = Keyword.get(options, :count)
    project = Keyword.get(options, :project)
    work_order = Keyword.get(options, :work_order)
    job = Keyword.get(options, :job)
    finished_at = Keyword.get(options, :finished_at)

    dataclip_builder = fn -> build(:dataclip, project: project) end

    insert_list(
      count,
      :run,
      finished_at: finished_at,
      work_order: work_order,
      dataclip: dataclip_builder,
      starting_job: job,
      steps: fn ->
        build_list(
          count,
          :step,
          finished_at: finished_at,
          input_dataclip: dataclip_builder,
          output_dataclip: dataclip_builder,
          job: job
        )
      end
    )
  end

  defp find_instrumentation(instrumented_collection, identity) do
    hashed_uuid = build_hash(identity)

    instrumented_collection
    |> Enum.find(fn record -> record.hashed_uuid == hashed_uuid end)
  end

  defp assert_project_metrics(projects_metrics, opts) do
    project = opts |> Keyword.get(:project)
    cleartext_enabled = opts |> Keyword.get(:cleartext_enabled)
    date = opts |> Keyword.get(:date)

    project_metrics = projects_metrics |> find_instrumentation(project.id)

    expected_metrics =
      ProjectMetricsService.generate_metrics(project, cleartext_enabled, date)

    assert project_metrics == expected_metrics
  end

  defp assert_no_project_metrics(projects_metrics, project) do
    refute projects_metrics |> find_instrumentation(project.id)
  end
end
