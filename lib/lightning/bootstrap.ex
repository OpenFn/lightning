defmodule Lightning.Bootstrap do
  @moduledoc """
  Declarative bootstrapping of Lightning for local dev and E2E testing.

  Given a plain map (typically decoded from a YAML/JSON scenario file), this
  module creates users, projects, workflows, triggers, jobs and edges using the
  regular context functions — so the data it produces is indistinguishable from
  data created through the UI.

  This is the counterpart to `Lightning.SetupUtils.setup_demo/1`: `setup_demo`
  is a single fixed fixture, whereas `Lightning.Bootstrap` lets you *define* the
  shape of the world you want to boot into. It is wired into `bin/e2e` via
  `bin/e2e.d/load_scenario.exs` and the `--scenario` flag.

  ## Scenario shape

      %{
        "users" => [
          %{"email" => "amy@openfn.org", "first_name" => "Amy", "superuser" => true}
        ],
        "projects" => [
          %{
            "name" => "my-project",
            "members" => [%{"email" => "amy@openfn.org", "role" => "owner"}],
            "workflows" => [
              %{
                "name" => "My Workflow",
                "trigger" => %{"type" => "webhook"},
                "jobs" => [%{"name" => "Job 1", "adaptor" => "@openfn/language-common@latest"}],
                "edges" => [%{"from" => "trigger", "to" => "Job 1"}]
              }
            ]
          }
        ]
      }

  Keys may be strings (as produced by the YAML/JSON parsers). Sensible defaults
  are applied for anything omitted. See `bin/e2e.d/scenarios/README.md` for the
  full authoring reference.
  """

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Jobs
  alias Lightning.Projects
  alias Lightning.Repo
  alias Lightning.Workflows

  @default_password "welcome12345"
  @default_adaptor "@openfn/language-common@latest"
  @default_body "fn(state => state);"

  @role_rank %{owner: 3, admin: 2, editor: 1, viewer: 0}

  @doc """
  Create everything described by `scenario` and return a summary map of the
  records that were created (keyed by the identifiers used in the scenario).
  """
  @spec create_from_map(map()) :: %{users: map(), projects: [map()]}
  def create_from_map(scenario) when is_map(scenario) do
    users = create_users(fetch_list(scenario, "users"))
    projects = create_projects(fetch_list(scenario, "projects"), users)

    %{users: users, projects: projects}
  end

  @doc "Human-readable one-liner-per-record summary of a `create_from_map/1` result."
  @spec summary(map()) :: String.t()
  def summary(%{users: users, projects: projects}) do
    user_lines =
      Enum.map(users, fn {email, user} ->
        "  user    #{email} (#{user.id})"
      end)

    project_lines =
      Enum.flat_map(projects, fn %{project: project, workflows: workflows} ->
        wf_lines =
          Enum.map(workflows, fn %{workflow: wf, jobs: jobs} ->
            "    workflow  #{wf.name} (#{length(jobs)} job(s))"
          end)

        ["  project #{project.name} (#{project.id})" | wf_lines]
      end)

    Enum.join(
      ["Bootstrapped scenario:" | user_lines ++ project_lines],
      "\n"
    )
  end

  # -- users -----------------------------------------------------------------

  defp create_users(specs) do
    Map.new(specs, fn spec ->
      email = fetch!(spec, "email")

      attrs = %{
        first_name: spec["first_name"] || default_first_name(email),
        last_name: spec["last_name"] || "User",
        email: email,
        password: spec["password"] || @default_password
      }

      {:ok, user} =
        if truthy(spec["superuser"]) do
          Accounts.register_superuser(attrs)
        else
          Accounts.create_user(attrs)
        end

      confirmed = user |> User.confirm_changeset() |> Repo.update!()

      {email, confirmed}
    end)
  end

  # -- projects --------------------------------------------------------------

  defp create_projects(specs, users) do
    Enum.map(specs, fn spec ->
      members = build_members(fetch_list(spec, "members"), users)

      {:ok, project} =
        Projects.create_project(
          %{
            name: fetch!(spec, "name"),
            history_retention_period:
              Application.get_env(:lightning, :default_retention_period),
            project_users: members
          },
          false
        )

      actor = most_privileged_actor(members, users)
      workflows = create_workflows(fetch_list(spec, "workflows"), project, actor)

      %{project: project, workflows: workflows}
    end)
  end

  defp build_members(specs, users) do
    Enum.map(specs, fn member ->
      email = fetch!(member, "email")
      user = Map.fetch!(users, email)

      %{
        user_id: user.id,
        role: String.to_existing_atom(member["role"] || "editor")
      }
    end)
  end

  defp most_privileged_actor([], _users) do
    raise "A project must have at least one member to own its workflows"
  end

  defp most_privileged_actor(members, users) do
    %{user_id: user_id} =
      Enum.max_by(members, fn %{role: role} -> Map.get(@role_rank, role, 0) end)

    users
    |> Map.values()
    |> Enum.find(&(&1.id == user_id))
  end

  # -- workflows -------------------------------------------------------------

  defp create_workflows(specs, project, actor) do
    Enum.map(specs, fn spec ->
      {:ok, workflow} =
        Workflows.save_workflow(
          %{name: fetch!(spec, "name"), project_id: project.id},
          actor
        )

      trigger = create_trigger(Map.get(spec, "trigger", %{}), workflow)
      jobs = create_jobs(fetch_list(spec, "jobs"), workflow, actor)
      create_edges(fetch_list(spec, "edges"), workflow, trigger, jobs, actor)

      %{workflow: workflow, trigger: trigger, jobs: Map.values(jobs)}
    end)
  end

  # `trigger: none` (or false) skips trigger creation; anything else builds one,
  # defaulting to a webhook trigger.
  defp create_trigger(spec, _workflow) when spec in [nil, false, "none"], do: nil

  defp create_trigger(spec, workflow) do
    spec = if is_map(spec), do: spec, else: %{}

    attrs =
      %{
        type: String.to_existing_atom(spec["type"] || "webhook"),
        workflow_id: workflow.id
      }
      |> maybe_put(:cron_expression, spec["cron_expression"])

    {:ok, trigger} = Workflows.build_trigger(attrs)
    trigger
  end

  defp create_jobs(specs, workflow, actor) do
    Map.new(specs, fn spec ->
      {:ok, job} =
        Jobs.create_job(
          %{
            name: fetch!(spec, "name"),
            body: spec["body"] || @default_body,
            adaptor: spec["adaptor"] || @default_adaptor,
            workflow_id: workflow.id
          },
          actor
        )

      {job.name, job}
    end)
  end

  defp create_edges(specs, workflow, trigger, jobs, actor) do
    Enum.each(specs, fn spec ->
      from = spec["from"]
      to = fetch!(spec, "to")

      base = %{
        workflow_id: workflow.id,
        condition_type:
          String.to_existing_atom(spec["condition"] || default_condition(from)),
        target_job: Map.fetch!(jobs, to),
        enabled: Map.get(spec, "enabled", true)
      }

      attrs =
        if from in [nil, "trigger"] do
          if is_nil(trigger) do
            raise "Edge to \"#{to}\" references the trigger, but the workflow " <>
                    "\"#{workflow.name}\" has no trigger"
          end

          Map.put(base, :source_trigger, trigger)
        else
          Map.put(base, :source_job, Map.fetch!(jobs, from))
        end

      {:ok, _edge} = Workflows.create_edge(attrs, actor)
    end)
  end

  # -- helpers ---------------------------------------------------------------

  defp default_condition(from) when from in [nil, "trigger"], do: "always"
  defp default_condition(_job), do: "on_job_success"

  defp default_first_name(email) do
    email |> String.split("@") |> hd() |> String.capitalize()
  end

  defp fetch!(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when value not in [nil, ""] ->
        value

      _ ->
        raise "Scenario entry #{inspect(map)} is missing required key #{inspect(key)}"
    end
  end

  defp fetch_list(map, key) do
    case Map.get(map, key) do
      nil ->
        []

      list when is_list(list) ->
        list

      other ->
        raise "Expected #{inspect(key)} to be a list, got: #{inspect(other)}"
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp truthy(true), do: true
  defp truthy("true"), do: true
  defp truthy(_), do: false
end
