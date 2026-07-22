defmodule Lightning.Bootstrap do
  @moduledoc """
  Declarative bootstrapping of Lightning for local dev, E2E testing, external
  test harnesses and initial-state seeding of real deployments.

  Given a plain map (typically decoded from a YAML/JSON scenario file), this
  module creates users and projects, and provisions each project's workflows
  (triggers, jobs and edges) through `Lightning.Projects.Provisioner` — the same
  engine that backs the `/api/provision` HTTP API. Each project is imported in a
  single atomic document, so every workflow ends up with a complete, current
  snapshot.

  This is the counterpart to `Lightning.SetupUtils.setup_demo/1`: `setup_demo`
  is a single fixed fixture, whereas `Lightning.Bootstrap` lets you *define* the
  shape of the world you want to boot into. It is wired into `bin/e2e` via
  `bin/e2e.d/load_scenario.exs` and the `--scenario` flag.

  ## Safety

  Bootstrapping is disabled unless explicitly enabled. Set the environment
  variable `ALLOW_BOOTSTRAP=true` for a release, or configure
  `config :lightning, Lightning.Bootstrap, enabled: true` (already set in dev
  and test). `create_from_map/1` raises otherwise.

  Re-running is partially idempotent: existing users are reused (matched by
  email), and workflow/trigger/job records pinned to explicit `id`s are upserted
  by the provisioner. Projects are still created fresh on each run (and any
  omitted `id`s are generated anew), so full deploy-time idempotency is not yet
  guaranteed at the project level.

  ## Scenario shape

      %{
        "users" => [
          %{
            "email" => "amy@openfn.org",
            "first_name" => "Amy",
            "superuser" => true,
            # when truthy, an API token is generated and returned in the manifest
            "api_token" => true
          }
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
  are applied for anything omitted. An optional `id` may be supplied on a
  workflow, trigger or job to pin its UUID (useful for idempotent deploys);
  otherwise one is generated. See `bin/e2e.d/scenarios/README.md` for the full
  authoring reference.
  """

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Projects
  alias Lightning.Projects.Provisioner
  alias Lightning.Repo

  @default_password "welcome12345"
  @default_adaptor "@openfn/language-common@latest"
  @default_body "fn(state => state);"

  @role_rank %{owner: 3, admin: 2, editor: 1, viewer: 0}

  @typedoc "Per-user result: the persisted user and any generated API token."
  @type user_result :: %{user: User.t(), api_token: String.t() | nil}

  @doc """
  Create everything described by `scenario` and return a result map describing
  the records that were created. Pass the result to `manifest/1` for a
  JSON-encodable summary, or `summary/1` for a human-readable one.

  Raises unless bootstrapping is enabled (see the module docs / `ALLOW_BOOTSTRAP`).
  """
  @spec create_from_map(map()) :: %{
          users: %{String.t() => user_result()},
          projects: [map()]
        }
  def create_from_map(scenario) when is_map(scenario) do
    ensure_enabled!()

    users = create_users(fetch_list(scenario, "users"))
    projects = create_projects(fetch_list(scenario, "projects"), users)

    %{users: users, projects: projects}
  end

  @doc """
  Structured, JSON-encodable manifest of a `create_from_map/1` result.

  Shape:

      %{
        users: [%{email:, id:, superuser:, api_token: <string or nil>}],
        projects: [%{
          id:, name:,
          workflows: [%{
            id:, name:,
            trigger: %{id:, type:, webhook_path: "/i/<trigger_id>" or nil} | nil,
            jobs: [%{id:, name:}]
          }]
        }]
      }

  `webhook_path` is populated only for webhook-type triggers.
  """
  @spec manifest(%{users: map(), projects: [map()]}) :: map()
  def manifest(%{users: users, projects: projects}) do
    %{
      users:
        Enum.map(users, fn {email, %{user: user, api_token: token}} ->
          %{
            email: email,
            id: user.id,
            superuser: user.role == :superuser,
            api_token: token
          }
        end),
      projects:
        Enum.map(projects, fn %{project: project, workflows: workflows} ->
          %{
            id: project.id,
            name: project.name,
            workflows: Enum.map(workflows, &workflow_manifest/1)
          }
        end)
    }
  end

  defp workflow_manifest(%{id: id, name: name, trigger: trigger, jobs: jobs}) do
    %{
      id: id,
      name: name,
      trigger: trigger_manifest(trigger),
      jobs:
        Enum.map(jobs, fn %{id: job_id, name: job_name} ->
          %{id: job_id, name: job_name}
        end)
    }
  end

  defp trigger_manifest(nil), do: nil

  defp trigger_manifest(%{id: id, type: type}) do
    %{
      id: id,
      type: type,
      webhook_path: if(type == :webhook, do: "/i/#{id}", else: nil)
    }
  end

  @doc "Human-readable one-liner-per-record summary of a `create_from_map/1` result."
  @spec summary(%{users: map(), projects: [map()]}) :: String.t()
  def summary(%{users: users, projects: projects}) do
    user_lines =
      Enum.map(users, fn {email, %{user: user}} ->
        "  user    #{email} (#{user.id})"
      end)

    project_lines =
      Enum.flat_map(projects, fn %{project: project, workflows: workflows} ->
        wf_lines =
          Enum.map(workflows, fn %{name: name, jobs: jobs} ->
            "    workflow  #{name} (#{length(jobs)} job(s))"
          end)

        ["  project #{project.name} (#{project.id})" | wf_lines]
      end)

    Enum.join(
      ["Bootstrapped scenario:" | user_lines ++ project_lines],
      "\n"
    )
  end

  # -- env gate --------------------------------------------------------------

  defp ensure_enabled! do
    enabled =
      :lightning
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:enabled, false)

    unless enabled do
      raise """
      Lightning.Bootstrap is disabled.

      Bootstrapping creates users and projects and must be opted into. Set the
      environment variable ALLOW_BOOTSTRAP=true (for a release), or configure
      `config :lightning, Lightning.Bootstrap, enabled: true`.
      """
    end
  end

  # -- users -----------------------------------------------------------------

  defp create_users(specs) do
    Map.new(specs, fn spec ->
      email = fetch!(spec, "email")

      user =
        case Accounts.get_user_by_email(email) do
          nil -> register_user(spec, email)
          existing -> existing
        end
        |> maybe_confirm()

      api_token =
        if truthy(spec["api_token"]),
          do: Accounts.generate_api_token(user),
          else: nil

      {email, %{user: user, api_token: api_token}}
    end)
  end

  defp register_user(spec, email) do
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

    user
  end

  defp maybe_confirm(%User{confirmed_at: nil} = user) do
    user |> User.confirm_changeset() |> Repo.update!()
  end

  defp maybe_confirm(%User{} = user), do: user

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

      workflow_infos =
        Enum.map(fetch_list(spec, "workflows"), &build_workflow_info/1)

      document = %{
        "id" => project.id,
        "name" => project.name,
        "workflows" => Enum.map(workflow_infos, & &1.document)
      }

      {:ok, imported} = Provisioner.import_document(project, actor, document)

      %{project: imported, workflows: workflow_infos}
    end)
  end

  defp build_members(specs, users) do
    Enum.map(specs, fn member ->
      email = fetch!(member, "email")
      %{user: user} = Map.fetch!(users, email)

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
    |> Enum.find_value(fn %{user: user} -> if user.id == user_id, do: user end)
  end

  # -- workflow -> provisioning document -------------------------------------

  defp build_workflow_info(spec) do
    workflow_id = spec["id"] || Ecto.UUID.generate()
    name = fetch!(spec, "name")

    trigger = build_trigger_info(Map.get(spec, "trigger", %{}))
    jobs = Enum.map(fetch_list(spec, "jobs"), &build_job_info/1)
    edges = build_edges(fetch_list(spec, "edges"), name, trigger, jobs)

    document =
      %{
        "id" => workflow_id,
        "name" => name,
        "jobs" => Enum.map(jobs, & &1.document),
        "edges" => edges,
        "triggers" =>
          case trigger do
            nil -> []
            %{document: trigger_doc} -> [trigger_doc]
          end
      }

    %{
      document: document,
      id: workflow_id,
      name: name,
      trigger: trigger && Map.take(trigger, [:id, :type]),
      jobs: Enum.map(jobs, &Map.take(&1, [:id, :name]))
    }
  end

  # `trigger: none` (or false/nil) skips trigger creation; anything else builds
  # one, defaulting to a webhook trigger.
  defp build_trigger_info(spec) when spec in [nil, false, "none"], do: nil

  defp build_trigger_info(spec) do
    spec = if is_map(spec), do: spec, else: %{}
    id = spec["id"] || Ecto.UUID.generate()
    type = spec["type"] || "webhook"

    document =
      %{"id" => id, "type" => type}
      |> maybe_put("cron_expression", spec["cron_expression"])
      |> maybe_put("enabled", spec["enabled"])

    %{id: id, type: String.to_existing_atom(type), document: document}
  end

  defp build_job_info(spec) do
    id = spec["id"] || Ecto.UUID.generate()
    name = fetch!(spec, "name")

    document = %{
      "id" => id,
      "name" => name,
      "body" => spec["body"] || @default_body,
      "adaptor" => spec["adaptor"] || @default_adaptor
    }

    %{id: id, name: name, document: document}
  end

  defp build_edges(specs, workflow_name, trigger, jobs) do
    job_ids_by_name = Map.new(jobs, fn %{name: name, id: id} -> {name, id} end)

    Enum.map(specs, fn spec ->
      from = spec["from"]
      to = fetch!(spec, "to")

      base = %{
        "id" => spec["id"] || Ecto.UUID.generate(),
        "target_job_id" => Map.fetch!(job_ids_by_name, to),
        "condition_type" => spec["condition"] || default_condition(from),
        "enabled" => Map.get(spec, "enabled", true)
      }

      if from in [nil, "trigger"] do
        if is_nil(trigger) do
          raise "Edge to \"#{to}\" references the trigger, but the workflow " <>
                  "\"#{workflow_name}\" has no trigger"
        end

        Map.put(base, "source_trigger_id", trigger.id)
      else
        Map.put(base, "source_job_id", Map.fetch!(job_ids_by_name, from))
      end
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
