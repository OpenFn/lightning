defmodule Lightning.Kickstart do
  @moduledoc """
  Declarative, idempotent kickstarting of Lightning from a scenario file.

  Given a plain map (typically decoded from a YAML/JSON scenario file), this
  module creates users (with optional API tokens), credentials and projects,
  and provisions each project's workflows through
  `Lightning.Projects.Provisioner` — the same engine that backs the
  `/api/provision` HTTP API.

  It serves local development (`bin/e2e --scenario`), external test harnesses
  (boot Lightning into a known state, read the manifest, drive the public
  APIs) and initial-state seeding of real deployments
  (`bin/lightning eval 'Lightning.Setup.kickstart("/etc/lightning/state.yaml")'`).

  ## Idempotency

  Re-running the same scenario converges instead of duplicating:

  * Users are matched by email, credentials by `{owner, name}`, and both are
    reused when they already exist.
  * API tokens are signed JWTs and cannot be supplied; when `api_token: true`
    the user's oldest existing API token is reused, and one is generated only
    if none exists. Tokens are surfaced through `manifest/1`.
  * Projects, workflows, triggers, jobs and edges get **deterministic ids**
    (UUIDv5-style, derived from a project/workflow's name and from a record's
    key in the workflow spec) unless an explicit `id` is given, so the
    provisioner upserts them on subsequent runs.
  * Project members are added or have their role updated, never removed.

  Renaming a record changes its derived id: the renamed record is created
  fresh and the old one is left in place (the provisioner only deletes records
  explicitly marked with `delete: true`). Pin an explicit `id` on anything you
  intend to rename.

  The whole run happens in a single transaction — a failing scenario leaves
  the database untouched.

  ## Safety

  Kickstarting creates users (including superusers) and must be explicitly
  enabled. It is enabled in `dev` and `test` config; releases opt in with the
  `ALLOW_KICKSTART=true` environment variable. `run/1` raises otherwise.

  ## Scenario shape

      users:
        - email: amy@openfn.org          # required
          first_name: Amy
          superuser: true
          api_token: true                # generate/reuse a token, see manifest
          # password defaults to "welcome12345"

      credentials:
        - name: dhis2-prod               # required, unique per scenario
          owner: amy@openfn.org          # required, a user declared above
          schema: dhis2
          body:
            password: ${env:DHIS2_PASSWORD}  # explicit env interpolation

      projects:
        - name: my-project               # required, url-safe
          description: An example project # optional
          members:                       # required, exactly one owner
            - { email: amy@openfn.org, role: owner }
          credentials: [dhis2-prod]      # optional, exposed to this project
          collections:                   # optional
            - name: my-collection
          workflows:                     # workflow-spec documents, see below
            - name: my-workflow
              jobs:
                transform:
                  name: transform
                  adaptor: "@openfn/language-common@latest"
                  body: "fn(state => state);"
                  credential: dhis2-prod   # optional, a credential above
              triggers:
                webhook:
                  type: webhook
                  enabled: true
              edges:
                webhook->transform:
                  source_trigger: webhook
                  target_job: transform
                  condition_type: always
                  enabled: true

  Each entry under `workflows` is a **workflow spec** — the same
  hand-writable format the collaborative editor imports and exports and that
  workflow templates are written in, validated against the same JSON Schema
  and converted by `Lightning.Workflows.Spec`. There is no kickstart-specific
  workflow dialect: anything you can paste into the editor's YAML import works
  here, and vice versa. The one extra key kickstart resolves is a job's
  `credential`, which names a credential declared at the top level (the schema
  already allows it; the editor ignores it).

  Every other key — the scenario itself, and each user, credential, member and
  project — is checked against an explicit allow-list, so a typo (`usres:`) or
  an unsupported field (e.g. `channels`, not yet handled here) raises instead
  of being silently ignored.

  Keys are strings, as produced by the YAML/JSON parsers.

  Env interpolation is explicit: only `${env:VAR}` references are replaced
  (and it is an error for `VAR` to be unset). Plain `${...}` is left alone,
  so JS template literals in job bodies (`${id}`, `${HOME}`, `${state.data}`)
  can never collide with interpolation.
  """

  import Ecto.Query

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserToken
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.ProjectUser
  alias Lightning.Projects.Provisioner
  alias Lightning.Repo
  alias Lightning.Workflows.Spec

  @default_password "welcome12345"

  # Namespace for deterministic (UUIDv5-style) record ids. Changing it changes
  # every derived id, breaking idempotent re-runs against existing databases.
  @uuid_namespace "lightning.kickstart.v1"

  @roles %{
    "owner" => :owner,
    "admin" => :admin,
    "editor" => :editor,
    "viewer" => :viewer
  }
  @role_rank %{owner: 3, admin: 2, editor: 1, viewer: 0}

  # Allowed keys at each level of the scenario. Anything else — a typo, or a
  # provisioner field we don't (yet) support — raises instead of silently
  # doing nothing. Workflow/trigger/job/edge maps aren't listed here: those
  # pass straight through to the provisioner, which runs its own check.
  @scenario_keys ~w(users credentials projects)
  @user_keys ~w(email first_name last_name password superuser api_token)
  @credential_keys ~w(name owner schema body credential_bodies)
  @project_keys ~w(id name description members credentials collections workflows)
  @member_keys ~w(email role)
  @collection_keys ~w(id name)

  @typedoc "Per-user result: the persisted user and any generated API token."
  @type user_result :: %{user: User.t(), api_token: String.t() | nil}

  @type result :: %{
          users: %{String.t() => user_result()},
          credentials: %{String.t() => Credential.t()},
          projects: [map()]
        }

  @doc """
  Create or update everything described by `scenario`, atomically.

  Returns a result map describing the records; pass it to `manifest/1` for a
  JSON-encodable summary or `summary/1` for a human-readable one.

  Raises unless kickstarting is enabled (see the module docs), and rolls the
  whole run back on any error.
  """
  @spec run(map()) :: result()
  def run(scenario) when is_map(scenario) do
    ensure_enabled!()

    scenario = interpolate_env(scenario)
    allowed_keys!(scenario, @scenario_keys, "scenario")

    {:ok, result} =
      Repo.transaction(
        fn ->
          users =
            scenario
            |> fetch_list("users")
            |> ensure_unique!("email", "users")
            |> ensure_users()

          credentials =
            scenario
            |> fetch_list("credentials")
            |> ensure_unique!("name", "credentials")
            |> ensure_credentials(users)

          projects =
            scenario
            |> fetch_list("projects")
            |> ensure_unique!("name", "projects")
            |> Enum.map(&ensure_project(&1, users, credentials))

          %{users: users, credentials: credentials, projects: projects}
        end,
        timeout: :timer.minutes(2)
      )

    result
  end

  @doc """
  Load a scenario file (`.yaml`, `.yml` or `.json`) and `run/1` it.

  Options:

  * `:manifest` - path to write the JSON manifest to.
  """
  @spec run_file(Path.t(), keyword()) :: result()
  def run_file(path, opts \\ []) do
    result = path |> load_file!() |> run()

    if manifest_path = opts[:manifest] do
      File.write!(manifest_path, Jason.encode!(manifest(result), pretty: true))
    end

    result
  end

  @doc """
  Parse a scenario file into a map. Supports YAML and JSON.
  """
  @spec load_file!(Path.t()) :: map()
  def load_file!(path) do
    File.exists?(path) || raise "Scenario file not found: #{path}"

    case Path.extname(path) do
      ext when ext in [".yaml", ".yml"] ->
        {:ok, _apps} = Application.ensure_all_started(:yamerl)
        YamlElixir.read_from_file!(path)

      ".json" ->
        path |> File.read!() |> Jason.decode!()

      other ->
        raise "Unsupported scenario file extension: #{inspect(other)} " <>
                "(use .yaml, .yml or .json)"
    end
  end

  @doc """
  Structured, JSON-encodable manifest of a `run/1` result — everything an
  external harness needs to drive the instance: user emails and API tokens,
  record ids, and webhook paths.
  """
  @spec manifest(result()) :: map()
  def manifest(%{users: users, credentials: credentials, projects: projects}) do
    %{
      users:
        for {email, %{user: user, api_token: token}} <- users do
          %{
            email: email,
            id: user.id,
            superuser: user.role == :superuser,
            api_token: token
          }
        end,
      credentials:
        for {name, credential} <- credentials do
          %{name: name, id: credential.id, owner_id: credential.user_id}
        end,
      projects:
        for %{project: project, credentials: pc_ids, workflows: workflows} <-
              projects do
          %{
            id: project.id,
            name: project.name,
            credentials:
              for {name, pc_id} <- pc_ids do
                %{name: name, project_credential_id: pc_id}
              end,
            workflows: Enum.map(workflows, &workflow_manifest/1)
          }
        end
    }
  end

  @doc "Human-readable one-line-per-record summary of a `run/1` result."
  @spec summary(result()) :: String.t()
  def summary(%{users: users, projects: projects}) do
    user_lines =
      for {email, %{user: user}} <- users do
        "  user     #{email} (#{user.id})"
      end

    project_lines =
      Enum.flat_map(projects, fn %{project: project, workflows: workflows} ->
        workflow_lines =
          for %{name: name, jobs: jobs} <- workflows do
            "    workflow #{name} (#{length(jobs)} job(s))"
          end

        ["  project  #{project.name} (#{project.id})" | workflow_lines]
      end)

    Enum.join(["Kickstarted:" | user_lines ++ project_lines], "\n")
  end

  defp workflow_manifest(%{id: id, name: name, triggers: triggers, jobs: jobs}) do
    %{
      id: id,
      name: name,
      triggers: Enum.map(triggers, &trigger_manifest/1),
      jobs: Enum.map(jobs, &Map.take(&1, [:id, :name]))
    }
  end

  defp trigger_manifest(%{id: id, type: type}) do
    %{
      id: id,
      type: type,
      webhook_path: if(type == "webhook", do: "/i/#{id}")
    }
  end

  defp ensure_enabled! do
    enabled =
      :lightning
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:enabled, false)

    unless enabled do
      raise """
      Lightning.Kickstart is disabled.

      Kickstarting creates users (including superusers) and must be opted
      into. Set ALLOW_KICKSTART=true in the environment (for a release), or
      configure `config :lightning, Lightning.Kickstart, enabled: true`.
      """
    end
  end

  # Interpolation is explicit and namespaced — only `${env:VAR}` is replaced —
  # so JS template literals in job bodies (`${id}`, or even `${HOME}`) can
  # never collide with it.
  defp interpolate_env(value) when is_binary(value) do
    Regex.replace(~r/\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}/, value, fn _, var ->
      System.get_env(var) ||
        raise "Scenario references ${env:#{var}}, but that environment " <>
                "variable is not set"
    end)
  end

  defp interpolate_env(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {k, interpolate_env(v)} end)
  end

  defp interpolate_env(value) when is_list(value) do
    Enum.map(value, &interpolate_env/1)
  end

  defp interpolate_env(value), do: value

  # UUIDv5-style: name-based SHA-1 uuid so the same scenario always yields the
  # same ids and the provisioner upserts rather than duplicates.
  defp stable_id(scope) do
    <<a::48, _::4, b::12, _::2, c::62, _rest::binary>> =
      :crypto.hash(:sha, @uuid_namespace <> scope)

    {:ok, id} = Ecto.UUID.load(<<a::48, 5::4, b::12, 2::2, c::62>>)
    id
  end

  defp ensure_users(specs) do
    Map.new(specs, fn spec ->
      allowed_keys!(spec, @user_keys, "user #{spec["email"]}")
      email = spec |> fetch!("email") |> String.downcase()

      user =
        (Accounts.get_user_by_email(email) || register_user(spec, email))
        |> confirm_user()

      api_token =
        if boolean!(spec["api_token"], "api_token for user #{email}"),
          do: ensure_api_token(user)

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

    result =
      if boolean!(spec["superuser"], "superuser for user #{email}"),
        do: Accounts.register_superuser(attrs),
        else: Accounts.create_user(attrs)

    case result do
      {:ok, user} -> user
      {:error, changeset} -> raise_invalid("user #{email}", changeset)
    end
  end

  defp confirm_user(%User{confirmed_at: nil} = user) do
    user |> User.confirm_changeset() |> Repo.update!()
  end

  defp confirm_user(%User{} = user), do: user

  defp ensure_api_token(user) do
    existing =
      from(t in UserToken,
        where: t.user_id == ^user.id and t.context == "api",
        order_by: [asc: t.inserted_at],
        limit: 1,
        select: t.token
      )
      |> Repo.one()

    existing || Accounts.generate_api_token(user)
  end

  defp ensure_credentials(specs, users) do
    Map.new(specs, fn spec ->
      name = fetch!(spec, "name")
      allowed_keys!(spec, @credential_keys, "credential #{name}")
      owner = lookup_user!(users, fetch!(spec, "owner"), "credential #{name}")

      credential =
        Repo.get_by(Credential, user_id: owner.id, name: name) ||
          create_credential(spec, name, owner)

      {name, credential}
    end)
  end

  defp create_credential(spec, name, owner) do
    # `body` is sugar for a single "main" environment body; multi-environment
    # credentials can pass `credential_bodies` through directly.
    credential_bodies =
      spec["credential_bodies"] ||
        [%{"name" => "main", "body" => spec["body"] || %{}}]

    %{
      "name" => name,
      "user_id" => owner.id,
      "schema" => spec["schema"] || "raw",
      "credential_bodies" => credential_bodies
    }
    |> Credentials.create_credential()
    |> case do
      {:ok, credential} -> credential
      {:error, changeset} -> raise_invalid("credential #{name}", changeset)
    end
  end

  defp ensure_project(spec, users, credentials) do
    name = fetch!(spec, "name")
    allowed_keys!(spec, @project_keys, "project #{name}")
    scope = "project:#{name}"
    id = spec["id"] || stable_id(scope)

    members = parse_members(spec, users, name)
    actor = most_privileged_member(members)

    project = Repo.get(Project, id) || create_project_shell(id, name, actor)

    reconcile_members(project, members)

    pc_ids =
      ensure_project_credentials(project, scope, spec, credentials)

    workflow_infos =
      spec
      |> fetch_list("workflows")
      |> ensure_unique!("name", "workflows in project #{name}")
      |> Enum.map(&build_workflow_info(&1, scope, pc_ids))

    collections =
      spec
      |> fetch_list("collections")
      |> ensure_unique!("name", "collections in project #{name}")
      |> Enum.map(&build_collection(&1, scope))

    document =
      %{
        "id" => id,
        "name" => name,
        "workflows" => Enum.map(workflow_infos, & &1.document),
        "collections" => collections
      }
      |> maybe_put("description", spec["description"])

    project = Repo.get!(Project, id)

    case Provisioner.import_document(project, actor, document) do
      {:ok, imported} ->
        %{project: imported, credentials: pc_ids, workflows: workflow_infos}

      {:error, %Ecto.Changeset{} = changeset} ->
        raise_invalid("project #{name}", changeset)

      {:error, other} ->
        raise "Failed to provision project #{name}: #{inspect(other)}"
    end
  end

  defp create_project_shell(id, name, actor) do
    case Provisioner.import_document(nil, actor, %{"id" => id, "name" => name}) do
      {:ok, project} ->
        project

      {:error, %Ecto.Changeset{} = cs} ->
        raise_invalid("project #{name}", cs)

      {:error, other} ->
        raise "Failed to create project #{name}: #{inspect(other)}"
    end
  end

  defp parse_members(spec, users, project_name) do
    members =
      spec
      |> fetch_list("members")
      |> Enum.map(fn member ->
        email = fetch!(member, "email")

        allowed_keys!(
          member,
          @member_keys,
          "member #{email} of project #{project_name}"
        )

        user = lookup_user!(users, email, "project #{project_name}")

        role =
          Map.get(@roles, member["role"] || "editor") ||
            raise "Unknown role #{inspect(member["role"])} for #{email} in " <>
                    "project #{project_name} (expected one of: #{Enum.join(Map.keys(@roles), ", ")})"

        %{user: user, role: role}
      end)

    case Enum.count(members, &(&1.role == :owner)) do
      1 ->
        :ok

      0 ->
        raise "Project #{project_name} needs exactly one member with role: owner"

      _ ->
        raise "Project #{project_name} declares more than one member with " <>
                "role: owner — a project can only have one"
    end

    members
  end

  defp most_privileged_member(members) do
    %{user: user} = Enum.max_by(members, &Map.fetch!(@role_rank, &1.role))
    user
  end

  # Adds missing members and corrects drifted roles; never removes members.
  # `members` is validated to have exactly one declared owner, but an
  # existing owner not mentioned in this scenario may still hold the role —
  # non-owner changes are applied first so a same-run ownership handover
  # (demote old owner, promote new owner) doesn't trip the one-owner-per-
  # project constraint. A conflict with an *undeclared* existing owner still
  # surfaces, as a friendly changeset error rather than a raw one.
  defp reconcile_members(project, members) do
    members
    |> Enum.sort_by(&if(&1.role == :owner, do: 1, else: 0))
    |> Enum.each(&reconcile_member(project, &1))
  end

  defp reconcile_member(project, %{user: user, role: role}) do
    case Repo.get_by(ProjectUser, project_id: project.id, user_id: user.id) do
      nil ->
        project
        |> Projects.add_project_users([%{user_id: user.id, role: role}], false)
        |> handle_member_result(user)

      %ProjectUser{role: ^role} ->
        :ok

      project_user ->
        project_user
        |> Projects.update_project_user(%{role: role})
        |> handle_member_result(user)
    end
  end

  defp handle_member_result({:ok, _}, _user), do: :ok

  defp handle_member_result({:error, changeset}, user) do
    raise_invalid("project member #{user.email}", changeset)
  end

  # Exposes credentials to the project (ProjectCredential), returning a
  # `credential name => project_credential_id` map for job wiring. Credentials
  # can be listed under the project's "credentials" key or referenced directly
  # from a job's "credential" key.
  defp ensure_project_credentials(project, scope, spec, credentials) do
    referenced_names =
      fetch_list(spec, "credentials") ++
        for workflow <- fetch_list(spec, "workflows"),
            {_key, job} <- job_specs(workflow),
            name = job["credential"],
            do: name

    referenced_names
    |> Enum.uniq()
    |> Map.new(fn name ->
      credential =
        Map.get(credentials, name) ||
          raise "Project #{project.name} references credential #{inspect(name)}, " <>
                  "which is not declared under the scenario's top-level \"credentials\""

      project_credential =
        Repo.get_by(ProjectCredential,
          project_id: project.id,
          credential_id: credential.id
        ) ||
          Repo.insert!(%ProjectCredential{
            id: stable_id("#{scope}/credential:#{name}"),
            project_id: project.id,
            credential_id: credential.id
          })

      {name, project_credential.id}
    end)
  end

  defp build_workflow_info(spec, project_scope, pc_ids) do
    name = fetch!(spec, "name")
    scope = "#{project_scope}/workflow:#{name}"

    document =
      case Spec.to_document(spec, credentials: pc_ids, id_fun: id_fun(scope)) do
        {:ok, document} ->
          document

        {:error, message} ->
          raise "Workflow #{inspect(name)}: #{message}"
      end

    %{
      document: document,
      id: document["id"],
      name: name,
      triggers:
        Enum.map(document["triggers"], &%{id: &1["id"], type: &1["type"]}),
      jobs: Enum.map(document["jobs"], &%{id: &1["id"], name: &1["name"]})
    }
  end

  # Records without an explicit `id` get one derived from their key in the
  # spec, so re-running a scenario upserts the same rows.
  defp id_fun(workflow_scope) do
    fn
      :workflow, _name -> stable_id(workflow_scope)
      kind, key -> stable_id("#{workflow_scope}/#{kind}:#{key}")
    end
  end

  defp lookup_user!(users, email, context) do
    case Map.get(users, String.downcase(email)) do
      %{user: user} ->
        user

      nil ->
        raise "#{String.capitalize(context)} references user #{email}, who is " <>
                "not declared under the scenario's top-level \"users\""
    end
  end

  defp default_first_name(email) do
    email |> String.split("@") |> hd() |> String.capitalize()
  end

  defp fetch!(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when value not in [nil, ""] ->
        value

      _ ->
        raise "Scenario entry #{inspect(map)} is missing required key #{inspect(key)}"
    end
  end

  defp fetch!(other, key) do
    raise "Expected a map with key #{inspect(key)}, got: #{inspect(other)}"
  end

  # Duplicate names would derive the same deterministic id and surface as
  # opaque provisioner errors (or silently last-win) — fail upfront instead.
  defp ensure_unique!(specs, key, what) do
    specs
    |> Enum.map(&(&1 |> fetch!(key) |> to_string() |> String.downcase()))
    |> Enum.frequencies()
    |> Enum.filter(fn {_value, count} -> count > 1 end)
    |> case do
      [] ->
        specs

      duplicates ->
        values = Enum.map_join(duplicates, ", ", &elem(&1, 0))
        raise "Duplicate #{key} among #{what}: #{values}"
    end
  end

  # A typo or an unsupported provisioner field (e.g. "channels", not yet
  # handled by the kickstarter) would otherwise be silently ignored — fail
  # loudly and name the bad key(s) instead.
  defp allowed_keys!(map, allowed, context) when is_map(map) do
    unknown = Map.keys(map) -- allowed

    unless unknown == [] do
      raise "Unknown key(s) for #{context}: #{Enum.join(unknown, ", ")} " <>
              "(allowed: #{Enum.join(allowed, ", ")})"
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp build_collection(spec, project_scope) do
    name = fetch!(spec, "name")
    allowed_keys!(spec, @collection_keys, "collection #{name}")
    id = spec["id"] || stable_id("#{project_scope}/collection:#{name}")
    %{"id" => id, "name" => name}
  end

  # A workflow spec's jobs, keyed by slug. A malformed workflow is left alone
  # here: `Lightning.Workflows.Spec` validates it against the schema further
  # down and reports the problem naming the workflow it's in.
  defp job_specs(workflow) when is_map(workflow) do
    case Map.get(workflow, "jobs") do
      %{} = jobs -> jobs
      _other -> %{}
    end
  end

  defp job_specs(_workflow), do: %{}

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

  defp raise_invalid(what, %Ecto.Changeset{} = changeset) do
    errors =
      changeset
      |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(inspect(value)))
        end)
      end)

    raise "Failed to kickstart #{what}: #{inspect(errors)}"
  end

  # Real YAML booleans (`true`/`false`) decode to Elixir booleans, but YAML
  # 1.1 also treats `yes`/`no`/`on`/`off` as booleans while yamerl doesn't
  # coerce them — they arrive as plain strings. Accepting only the real
  # boolean plus "true"/"false" would silently treat `superuser: yes` as
  # false; raising on anything else (rather than defaulting) makes that kind
  # of typo visible instead of a silent no-op.
  defp boolean!(nil, _field), do: false
  defp boolean!(value, _field) when is_boolean(value), do: value
  defp boolean!(value, _field) when value in ["true", "yes"], do: true
  defp boolean!(value, _field) when value in ["false", "no"], do: false

  defp boolean!(value, field) do
    raise "Expected #{field} to be a boolean (true/false or yes/no), " <>
            "got: #{inspect(value)}"
  end
end
