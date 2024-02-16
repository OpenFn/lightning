# This module will be re-introduced in https://github.com/OpenFn/Lightning/issues/1143
defmodule Lightning.CliDeployTest do
  use LightningWeb.ConnCase, async: false

  require Logger

  import Lightning.Factories

  alias Lightning.Accounts

  @cli_path Application.app_dir(:lightning, "priv/openfn/bin/openfn")

  @moduletag :tmp_dir

  describe "The openfn CLI can be used to" do
    setup %{tmp_dir: tmp_dir} do
      url = LightningWeb.Endpoint.url()
      user = insert(:user)
      token = Accounts.generate_api_token(user)
      project = Lightning.ProjectsFixtures.canonical_project_fixture()
      insert(:project_user, project: project, user: user, role: :admin)

      config = %{
        endpoint: url,
        apiKey: token,
        specPath: Path.join(tmp_dir, "testProjectSpec.yaml"),
        statePath: Path.join(tmp_dir, "testProjectState.json")
      }

      config_path = Path.join(tmp_dir, "testConfig.json")

      %{user: user, config: config, config_path: config_path, project: project}
    end

    test "pull a valid project from a Lightning server", %{
      project: project,
      config: config,
      config_path: config_path
    } do
      File.write(config_path, Jason.encode!(config))
      # Try to pull
      System.cmd(
        @cli_path,
        ["pull", project.id, "-c", config_path]
      )

      # Check result
      expected_state = expected_project_state(project)

      actual_state = config.statePath |> File.read!() |> Jason.decode!()

      # encoding and decoding in order to transform values like dates into string
      assert actual_state == expected_state |> Jason.encode!() |> Jason.decode!()

      expected_yaml =
        File.read!("test/fixtures/canonical_project.yaml") |> String.trim()

      actual_yaml = File.read!(config.specPath)

      assert actual_yaml == expected_yaml
    end

    test "deploy a new project to a Lightning server", %{user: _user} do
      # System.cmd(
      #   "openfn",
      #   ["deploy", "-c", "./tmp/testConfig.json"],
      #   into: IO.stream()
      # )
    end

    test "deploy updates to an existing project on a Lightning server", %{
      project:
        %{workflows: [%{jobs: [job_to_update | _rest]} = workflow_1 | _]} =
          project,
      config: config,
      config_path: config_path
    } do
      # Lets Pull to get the intial state and spec
      File.write(config_path, Jason.encode!(config))

      System.cmd(
        @cli_path,
        ["pull", project.id, "-c", config_path]
      )

      # Lets use the updated spec
      specPath = Path.expand("test/fixtures/canonical_update_project.yaml")

      config = %{config | specPath: specPath}
      File.write(config_path, Jason.encode!(config))

      assert project.description == "This is only a test"
      assert workflow_1.name == "workflow 1"
      assert job_to_update.name == "webhook job"

      assert job_to_update.body ==
               "console.log('webhook job')\nfn(state => state)"

      System.cmd(
        @cli_path,
        ["deploy", project.id, "-c", config_path, "--no-confirm"]
      )

      updated_project = Lightning.Repo.reload(project)
      assert updated_project.description == "This is an update"
      updated_workflow_1 = Lightning.Repo.reload(workflow_1)
      assert updated_workflow_1.id == workflow_1.id
      assert updated_workflow_1.name == "updated workflow 1"

      updated_job = Lightning.Repo.reload(job_to_update)
      assert updated_job.id == job_to_update.id
      assert updated_job.name == "updated webhook job"

      assert updated_job.body ==
               "console.log('updated webhook job')\nfn(state => state)\n"
    end
  end

  defp hyphenize(val) do
    String.replace(val, " ", "-")
  end

  defp expected_project_state(project) do
    state =
      Map.take(project, Lightning.Projects.Project.__schema__(:fields))

    workflows =
      Map.new(project.workflows, fn workflow ->
        {hyphenize(workflow.name), expected_workflow_state(workflow)}
      end)

    Map.merge(state, %{workflows: workflows})
  end

  defp expected_workflow_state(workflow) do
    state = Map.take(workflow, Lightning.Workflows.Workflow.__schema__(:fields))

    jobs =
      Map.new(workflow.jobs, fn job ->
        {hyphenize(job.name), expected_job_state(job)}
      end)

    triggers =
      Map.new(workflow.triggers, fn trigger ->
        {trigger.type, expected_trigger_state(trigger)}
      end)

    edges =
      Map.new(workflow.edges, fn edge ->
        source_key =
          if edge.source_trigger_id do
            source =
              Enum.find(workflow.triggers, &(&1.id == edge.source_trigger_id))

            source.type
          else
            source = Enum.find(workflow.jobs, &(&1.id == edge.source_job_id))
            source.name
          end

        target_job = Enum.find(workflow.jobs, &(&1.id == edge.target_job_id))

        key = hyphenize("#{source_key}->#{target_job.name}")

        {key, expected_edge_state(edge)}
      end)

    Map.merge(state, %{jobs: jobs, triggers: triggers, edges: edges})
  end

  defp expected_trigger_state(trigger) do
    trigger
    |> Map.take([:id, :type, :enabled, :cron_expression])
    |> Map.reject(fn {_key, val} -> is_nil(val) end)
  end

  defp expected_job_state(job) do
    Map.take(job, [:id, :name, :body, :adaptor])
  end

  defp expected_edge_state(edge) do
    edge
    |> Map.take([
      :id,
      :enabled,
      :condition_type,
      :source_job_id,
      :source_trigger_id,
      :target_job_id
    ])
    |> Map.reject(fn {_key, val} -> is_nil(val) end)
  end
end
