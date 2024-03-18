defmodule Lightning.UsageTracking.ReportDataTest do
  use Lightning.DataCase

  alias Lightning.Projects.Project
  alias Lightning.Workflows.Workflow
  alias Lightning.UsageTracking.Configuration
  alias Lightning.UsageTracking.ReportData

  describe ".generate/2 - cleartext uuids disabled" do
    setup [:setup_config, :setup_cleartext_uuids_disabled]

    test "sets the time that the report was generated at",
         %{config: config, cleartext_enabled: enabled} do
      %{generated_at: generated_at} = ReportData.generate(config, enabled)

      assert DateTime.diff(DateTime.utc_now(), generated_at, :second) < 1
    end

    test "contains hashed uuid of reporting instance",
         %{config: config, cleartext_enabled: enabled} do
      %{instance_id: instance_id} = config

      %{instance: %{hashed_uuid: hashed_uuid}} =
        ReportData.generate(config, enabled)

      assert hashed_uuid == build_hash(instance_id)
    end

    test "cleartext uuid of reporting instance is nil",
         %{config: config, cleartext_enabled: enabled} do
      assert(
        %{instance: %{cleartext_uuid: nil}} =
          ReportData.generate(config, enabled)
      )
    end

    test "indicates the version of lightning present on the instance",
         %{config: config, cleartext_enabled: enabled} do
      # Temporarily water-down the test to address constraints imposed by CI.
      %{instance: %{version: version}} = ReportData.generate(config, enabled)

      assert String.match?(version, ~r/\A\d+\.\d+\.\d+\z/)
    end

    test "includes the total number of non-disabled users",
         %{config: config, cleartext_enabled: enabled} do
      _eligible_user_1 = insert(:user, disabled: false)
      _eligible_user_2 = insert(:user, disabled: false)
      _eligible_user_3 = insert(:user, disabled: false)
      _ineligible_user = insert(:user, disabled: true)

      assert(
        %{instance: %{no_of_users: 3}} =
          ReportData.generate(config, enabled)
      )
    end

    test "includes the operating system details",
         %{config: config, cleartext_enabled: enabled} do
      {_os_family, os_name_atom} = :os.type()

      os_name = os_name_atom |> Atom.to_string()

      assert String.match?(os_name, ~r/.{5,}/)

      assert(
        %{instance: %{operating_system: ^os_name}} =
          ReportData.generate(config, enabled)
      )
    end

    test "includes project details",
         %{config: config, cleartext_enabled: enabled} do
      project_1 = build_project(2)
      project_2 = build_project(3)

      %{projects: projects} = ReportData.generate(config, enabled)

      assert projects |> count() == 2

      projects |> assert_instrumented(project_1, enabled)
      projects |> assert_instrumented(project_2, enabled)
    end

    test "indicates the version of the report data structure in use",
         %{config: config, cleartext_enabled: enabled} do
      assert %{version: "1"} = ReportData.generate(config, enabled)
    end
  end

  describe ".generate/2 - cleartext uuids enabled" do
    setup [:setup_config, :setup_cleartext_uuids_enabled]

    test "sets the time that the report was generated at",
         %{config: config, cleartext_enabled: enabled} do
      %{generated_at: generated_at} = ReportData.generate(config, enabled)

      assert DateTime.diff(DateTime.utc_now(), generated_at, :second) < 1
    end

    test "contains hashed uuid of reporting instance",
         %{config: config, cleartext_enabled: enabled} do
      %{instance_id: instance_id} = config

      %{instance: %{hashed_uuid: hashed_uuid}} =
        ReportData.generate(config, enabled)

      assert hashed_uuid == build_hash(instance_id)
    end

    test "cleartext uuid of reporting instance is populated",
         %{config: config, cleartext_enabled: enabled} do
      %{instance_id: instance_id} = config

      assert(
        %{instance: %{cleartext_uuid: ^instance_id}} =
          ReportData.generate(config, enabled)
      )
    end

    test "indicates the version of lightning present on the instance",
         %{config: config, cleartext_enabled: enabled} do
      # Temporarily water-down the test to address constraints imposed by CI.
      %{instance: %{version: version}} = ReportData.generate(config, enabled)

      assert String.match?(version, ~r/\A\d+\.\d+\.\d+\z/)
    end

    test "includes the total number of non-disabled users",
         %{config: config, cleartext_enabled: enabled} do
      _eligible_user_1 = insert(:user, disabled: false)
      _eligible_user_2 = insert(:user, disabled: false)
      _eligible_user_3 = insert(:user, disabled: false)
      _ineligible_user = insert(:user, disabled: true)

      assert(
        %{instance: %{no_of_users: 3}} =
          ReportData.generate(config, enabled)
      )
    end

    test "includes the operating system details",
         %{config: config, cleartext_enabled: enabled} do
      {_os_family, os_name_atom} = :os.type()

      os_name = os_name_atom |> Atom.to_string()

      assert String.match?(os_name, ~r/.{5,}/)

      assert(
        %{instance: %{operating_system: ^os_name}} =
          ReportData.generate(config, enabled)
      )
    end

    test "includes project details",
         %{config: config, cleartext_enabled: enabled} do
      project_1 = build_project(2)
      project_2 = build_project(3)

      %{projects: projects} = ReportData.generate(config, enabled)

      assert projects |> count() == 2

      projects |> assert_instrumented(project_1, enabled)
      projects |> assert_instrumented(project_2, enabled)
    end

    test "indicates the version of the report data structure in use",
         %{config: config, cleartext_enabled: enabled} do
      assert %{version: "1"} = ReportData.generate(config, enabled)
    end
  end

  defp setup_config(context) do
    Map.merge(context, %{config: Repo.insert!(%Configuration{})})
  end

  defp setup_cleartext_uuids_disabled(context) do
    Map.merge(context, %{cleartext_enabled: false})
  end

  defp setup_cleartext_uuids_enabled(context) do
    Map.merge(context, %{cleartext_enabled: true})
  end

  defp build_hash(uuid), do: Base.encode16(:crypto.hash(:sha256, uuid))

  defp build_project(count) do
    project = insert(:project, project_users: build_project_users(count))

    workflows = insert_list(count, :workflow, project: project)

    for workflow <- workflows do
      [job | _] = insert_list(count, :job, workflow: workflow)
      work_orders = insert_list(count, :workorder, workflow: workflow)

      for work_order <- work_orders do
        insert_runs_with_steps(
          count: count,
          project: project,
          work_order: work_order,
          job: job
        )
      end
    end

    project
  end

  defp build_project_users(count) do
    build_list(count, :project_user, user: fn -> build(:user) end)
  end

  defp insert_runs_with_steps(options) do
    count = Keyword.get(options, :count)
    project = Keyword.get(options, :project)
    work_order = Keyword.get(options, :work_order)
    job = Keyword.get(options, :job)

    dataclip_builder = fn -> build(:dataclip, project: project) end

    insert_list(
      count,
      :run,
      work_order: work_order,
      dataclip: dataclip_builder,
      starting_job: job,
      steps: fn ->
        build_list(
          count,
          :step,
          input_dataclip: dataclip_builder,
          output_dataclip: dataclip_builder,
          job: job
        )
      end
    )
  end

  defp assert_instrumented(
         instrumented_projects,
         project = %Project{},
         cleartext_enabled
       ) do
    %Project{id: id, users: users, workflows: workflows} =
      project |> Repo.preload([:users, :workflows])

    instrumented_project = instrumented_projects |> find_instrumentation(id)

    instrumented_project |> assert_cleartext_uuid(id, cleartext_enabled)

    assert instrumented_project.no_of_users == users |> count()

    for w <- workflows do
      assert_instrumented(instrumented_project.workflows, w, cleartext_enabled)
    end
  end

  defp assert_instrumented(
         instrumented_workflows,
         workflow = %Workflow{},
         cleartext_enabled
       ) do
    %{id: id, jobs: jobs, runs: runs} =
      workflow |> Repo.preload([:jobs, runs: [:steps]])

    instrumented_workflow = instrumented_workflows |> find_instrumentation(id)

    instrumented_workflow |> assert_cleartext_uuid(id, cleartext_enabled)

    %{
      no_of_jobs: instrumented_no_of_jobs,
      no_of_runs: instrumented_no_of_runs,
      no_of_steps: instrumented_no_of_steps
    } = instrumented_workflow

    assert instrumented_no_of_jobs == jobs |> count()
    assert instrumented_no_of_runs == runs |> count()
    assert instrumented_no_of_steps == runs |> no_of_steps()
  end

  defp count(collection), do: collection |> Enum.count()

  defp find_instrumentation(instrumented_collection, identity) do
    hashed_uuid = build_hash(identity)

    instrumented_collection
    |> Enum.filter(fn record -> record.hashed_uuid == hashed_uuid end)
    |> hd()
  end

  defp assert_cleartext_uuid(instrumented_record, id, _enabled = true) do
    assert instrumented_record.cleartext_uuid == id
  end

  defp assert_cleartext_uuid(instrumented_record, _id, _enabled = false) do
    assert instrumented_record.cleartext_uuid == nil
  end

  defp no_of_steps(runs) do
    runs |> Enum.reduce(0, fn run, acc -> acc + (run.steps |> count()) end)
  end
end
