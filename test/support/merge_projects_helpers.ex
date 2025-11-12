defmodule Lightning.MergeProjectsHelpers do
  @moduledoc """
  Helper functions for creating project state JSON structures for merge testing.
  These helpers create plain maps (not Ecto structs) suitable for JSON serialization.

  Uses ExMachina factories to avoid duplicating factory logic.
  """

  import Lightning.Factories

  @doc """
  Builds a minimal valid project state structure.

  ## Options
    * `:id` - Project ID (default: generated UUID)
    * `:name` - Project name (default: "Test Project")
    * `:description` - Project description (optional)
    * `:env` - Environment name (optional)
    * `:color` - Project color (optional)
    * `:workflows` - List of workflow maps (default: [])

  ## Examples

      iex> build_project_state(name: "My Project", workflows: [])
      %{
        "id" => "...",
        "name" => "My Project",
        "workflows" => []
      }
  """
  def build_project_state(opts \\ []) do
    {nested, base_opts} = Keyword.split(opts, [:workflows])
    id = Keyword.get_lazy(base_opts, :id, &Ecto.UUID.generate/0)

    string_params_for(:project, base_opts |> Keyword.put_new(:workflows, []))
    |> Map.take(["name", "description", "env", "color", "workflows"])
    |> Map.put("id", id)
    |> Map.merge(Map.new(nested, fn {k, v} -> {to_string(k), v} end))
    |> Enum.reject(fn {k, v} ->
      k in ["description", "env", "color"] and is_nil(v)
    end)
    |> Map.new()
  end

  @doc """
  Builds a minimal valid workflow structure.

  ## Options
    * `:id` - Workflow ID (default: generated UUID)
    * `:name` - Workflow name (default: "Test Workflow")
    * `:lock_version` - Lock version for optimistic locking (default: 1)
    * `:jobs` - List of job maps (default: [])
    * `:triggers` - List of trigger maps (default: [])
    * `:edges` - List of edge maps (default: [])
    * `:concurrency` - Concurrency setting (optional)
    * `:enable_job_logs` - Whether to enable job logs (optional)

  ## Examples

      iex> build_workflow(name: "My Workflow")
      %{
        "id" => "...",
        "name" => "My Workflow",
        "lock_version" => 1,
        "jobs" => [],
        "triggers" => [],
        "edges" => []
      }
  """
  def build_workflow(opts \\ []) do
    {nested, base_opts} = Keyword.split(opts, [:jobs, :triggers, :edges])
    id = Keyword.get_lazy(base_opts, :id, &Ecto.UUID.generate/0)

    string_params_for(
      :workflow,
      base_opts
      |> Keyword.put_new(:lock_version, 1)
      |> Keyword.put_new(:jobs, [])
      |> Keyword.put_new(:triggers, [])
      |> Keyword.put_new(:edges, [])
    )
    |> Map.take([
      "name",
      "lock_version",
      "jobs",
      "triggers",
      "edges",
      "concurrency",
      "enable_job_logs"
    ])
    |> Map.put("id", id)
    |> Map.merge(Map.new(nested, fn {k, v} -> {to_string(k), v} end))
    |> Enum.reject(fn {k, v} ->
      k in ["concurrency", "enable_job_logs"] and is_nil(v)
    end)
    |> Map.new()
  end

  @doc """
  Builds a minimal valid job structure.

  ## Options
    * `:id` - Job ID (default: generated UUID)
    * `:name` - Job name (default: "Test Job")
    * `:body` - Job body/code (default: "fn(state => state);")
    * `:adaptor` - Adaptor spec (default: "@openfn/language-common@latest")
    * `:project_credential_id` - Project credential ID (default: nil)
    * `:keychain_credential_id` - Keychain credential ID (default: nil)

  ## Examples

      iex> build_job(name: "My Job", body: "console.log('hello');")
      %{
        "id" => "...",
        "name" => "My Job",
        "body" => "console.log('hello');",
        "adaptor" => "@openfn/language-common@latest",
        "project_credential_id" => nil,
        "keychain_credential_id" => nil
      }
  """
  def build_job(opts \\ []) do
    id = Keyword.get_lazy(opts, :id, &Ecto.UUID.generate/0)
    project_credential_id = Keyword.get(opts, :project_credential_id, nil)
    keychain_credential_id = Keyword.get(opts, :keychain_credential_id, nil)

    string_params_for(
      :job,
      opts
      |> Keyword.put_new(:body, "fn(state => state);")
      |> Keyword.put_new(:adaptor, "@openfn/language-common@latest")
    )
    |> Map.take(["name", "body", "adaptor"])
    |> Map.put("id", id)
    |> Map.put("project_credential_id", project_credential_id)
    |> Map.put("keychain_credential_id", keychain_credential_id)
  end

  @doc """
  Builds a minimal valid trigger structure.

  ## Options
    * `:id` - Trigger ID (default: generated UUID)
    * `:type` - Trigger type (default: "webhook")
    * `:comment` - Trigger comment (optional)
    * `:custom_path` - Custom webhook path (optional)
    * `:cron_expression` - Cron expression for cron triggers (optional)
    * `:kafka_configuration` - Kafka configuration map for kafka triggers (optional)

  ## Examples

      iex> build_trigger(type: "webhook")
      %{"id" => "...", "type" => "webhook"}

      iex> build_trigger(type: "cron", cron_expression: "0 * * * *")
      %{"id" => "...", "type" => "cron", "cron_expression" => "0 * * * *"}
  """
  def build_trigger(opts \\ []) do
    id = Keyword.get_lazy(opts, :id, &Ecto.UUID.generate/0)

    string_params_for(:trigger, opts |> Keyword.put_new(:type, :webhook))
    |> Map.take([
      "type",
      "comment",
      "custom_path",
      "cron_expression",
      "kafka_configuration"
    ])
    |> Map.put("id", id)
    |> Enum.reject(fn {k, v} ->
      k in ["comment", "custom_path", "cron_expression", "kafka_configuration"] and
        is_nil(v)
    end)
    |> Map.new()
  end

  @doc """
  Builds a minimal valid edge structure.

  ## Options
    * `:id` - Edge ID (default: generated UUID)
    * `:source_trigger_id` - Source trigger ID (default: nil)
    * `:source_job_id` - Source job ID (default: nil)
    * `:target_job_id` - Target job ID (required)
    * `:condition_type` - Condition type (default: "always")
    * `:condition_expression` - JS expression for condition (optional)
    * `:condition_label` - Label for condition (optional)
    * `:enabled` - Whether edge is enabled (default: true)

  ## Examples

      iex> build_edge(source_trigger_id: "trigger-1", target_job_id: "job-1")
      %{
        "id" => "...",
        "source_trigger_id" => "trigger-1",
        "source_job_id" => nil,
        "target_job_id" => "job-1",
        "condition_type" => "always",
        "enabled" => true
      }
  """
  def build_edge(opts) do
    unless Keyword.has_key?(opts, :target_job_id) do
      raise ArgumentError, "target_job_id is required for build_edge"
    end

    id = Keyword.get_lazy(opts, :id, &Ecto.UUID.generate/0)

    string_params_for(
      :edge,
      opts
      |> Keyword.put_new(:condition_type, :always)
      |> Keyword.put_new(:enabled, true)
    )
    |> Map.take([
      "source_trigger_id",
      "source_job_id",
      "target_job_id",
      "condition_type",
      "condition_expression",
      "condition_label",
      "enabled"
    ])
    |> Map.put("id", id)
    |> Enum.reject(fn {k, v} ->
      k in [
        "condition_expression",
        "condition_label",
        "source_trigger_id",
        "source_job_id"
      ] and
        is_nil(v)
    end)
    |> Map.new()
  end

  @doc """
  Builds a complete project with a simple workflow.

  This is a convenience function for creating a typical test scenario:
  a project with one workflow containing one trigger, one job, and one edge.

  ## Options
  All options from `build_project_state/1`, plus:
    * `:workflow_name` - Name for the workflow (default: "Test Workflow")
    * `:job_name` - Name for the job (default: "Test Job")
    * `:job_body` - Body for the job (default: "fn(state => state);")
    * `:trigger_type` - Type of trigger (default: "webhook")

  ## Examples

      iex> build_simple_project(name: "My Project", job_body: "console.log('test');")
      %{
        "id" => "...",
        "name" => "My Project",
        "workflows" => [
          %{
            "id" => "...",
            "name" => "Test Workflow",
            "lock_version" => 1,
            "jobs" => [...],
            "triggers" => [...],
            "edges" => [...]
          }
        ]
      }
  """
  def build_simple_project(opts \\ []) do
    trigger = build_trigger(type: Keyword.get(opts, :trigger_type, "webhook"))

    job =
      build_job(
        name: Keyword.get(opts, :job_name, "Test Job"),
        body: Keyword.get(opts, :job_body, "fn(state => state);")
      )

    edge =
      build_edge(
        source_trigger_id: trigger["id"],
        target_job_id: job["id"]
      )

    workflow =
      build_workflow(
        name: Keyword.get(opts, :workflow_name, "Test Workflow"),
        jobs: [job],
        triggers: [trigger],
        edges: [edge]
      )

    # Extract only project-level options
    project_opts =
      opts
      |> Keyword.drop([:workflow_name, :job_name, :job_body, :trigger_type])
      |> Keyword.put(:workflows, [workflow])

    build_project_state(project_opts)
  end
end
