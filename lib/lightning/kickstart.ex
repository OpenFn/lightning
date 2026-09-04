defmodule Lightning.Kickstart do
  @moduledoc """
  Declarative, idempotent kickstarting of Lightning from a scenario file.

  Given a plain map (typically decoded from a YAML/JSON scenario file), this
  module creates users (with optional API tokens), credentials and projects,
  and provisions each project's workflows through
  `Lightning.Projects.Provisioner` — the same engine that backs the
  `/api/provision` HTTP API.

  It serves local development (`bin/e2e --scenario`) and external test
  harnesses: boot Lightning into a known state, read the manifest, drive the
  public APIs.

  It is **not** a way to provision a live instance. There is no release entry
  point, and `run/1` refuses to run outside `dev` and `test` — see "Safety".
  Deploying state to a running instance is what `/api/provision` and the CLI
  are for.

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

  Renaming a record changes its derived id, and what that costs depends on the
  record:

  * Renaming a **job, trigger or edge** deletes the old row and creates a new
    one - `Workflow` declares `has_many :jobs, on_replace: :delete`. A renamed
    webhook trigger answers at a new `/i/<id>` URL.
  * Renaming a **workflow or collection** fails, naming the record: the old one
    is still on the project and the provisioner treats the document as the
    complete set. Pin an explicit `id` on a workflow you intend to rename and
    its jobs, triggers and edges keep their ids too.
  * Renaming a **project** creates a new one and leaves the old one alone.

  The whole run happens in a single transaction — a failing scenario leaves
  the database untouched.

  ## Safety

  Kickstarting creates users (including superusers), and applies a scenario as
  the desired state: records it declares are overwritten from the file, so a
  job body edited in the editor is reverted on the next run. That is fine for
  a database that exists to be thrown away, and wrong for one anybody relies
  on — so it is confined to `dev` and `test`, and `run/1` raises anywhere
  else.

  Mix tasks aren't shipped in a release, so `mix lightning.kickstart` cannot
  be reached in production at all; the environment check exists to also stop
  someone calling this module directly from a remote console.

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
  alias Lightning.Collections.Collection
  alias Lightning.Config
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.ProjectUser
  alias Lightning.Projects.Provisioner
  alias Lightning.Repo
  alias Lightning.Workflows.Spec
  alias Lightning.Workflows.Workflow

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
      # The manifest carries API tokens, so it must not be world-readable.
      File.chmod!(manifest_path, 0o600)
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
    env = Config.env()

    unless env in [:dev, :test] do
      raise """
      Lightning.Kickstart is a dev/test facility, but the environment is #{inspect(env)}.

      Kickstarting creates users (including superusers) and overwrites the
      records a scenario declares, so it is not safe to point at an instance
      anybody relies on. Use /api/provision or the CLI to deploy state to a
      live instance.
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
        case Accounts.get_user_by_email(email) do
          nil -> register_user(spec, email)
          existing -> reuse_user!(existing, spec, email)
        end
        |> confirm_user()

      api_token =
        if boolean!(spec["api_token"], "api_token for user #{email}"),
          do: ensure_api_token(user)

      {email, %{user: user, api_token: api_token}}
    end)
  end

  # An existing account is reused as it stands. Nothing in Lightning casts a
  # user's `role` after registration, so there is no way to promote one, and
  # handing back an ordinary user while reporting success defeats the point of
  # booting into a known state. Say so instead.
  defp reuse_user!(%User{role: :superuser} = user, _spec, _email), do: user

  defp reuse_user!(%User{} = user, spec, email) do
    if boolean!(spec["superuser"], "superuser for user #{email}") do
      raise """
      Scenario declares #{email} as a superuser, but that account already
      exists and is not one.

      Lightning only sets the superuser role when an account is created, so
      kickstart cannot promote it. Drop `superuser: true`, use an email that
      isn't taken, or start from a database without this account.
      """
    end

    user
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
    |> Credentials.create_credential(owner)
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

    reconcile_members(project, members, actor)

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
      %{"id" => id, "name" => name}
      |> maybe_put("description", spec["description"])
      |> maybe_put_declared("workflows", Enum.map(workflow_infos, & &1.document))
      |> maybe_put_declared("collections", collections)

    guard_undeclared!(project, document, name)

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
  #
  # A membership write submits the whole list: `Projects.add_project_users/4`
  # runs the rows through `membership_params/2`, which keeps an entry for every
  # member already on the project and replaces only the ones named here. So
  # "never removes" comes for free, the one-owner validation runs across the
  # whole list at once rather than per row, and an ownership handover no longer
  # depends on the order the scenario happens to declare members in. `false`
  # suppresses the project-addition emails, which is what we want for seeding.
  defp reconcile_members(project, members, actor) do
    rows =
      members
      |> Enum.map(fn %{user: user, role: role} ->
        case Repo.get_by(ProjectUser, project_id: project.id, user_id: user.id) do
          nil -> %{user_id: user.id, role: role}
          %ProjectUser{role: ^role} -> nil
          project_user -> %{id: project_user.id, role: role}
        end
      end)
      |> Enum.reject(&is_nil/1)

    if rows != [] do
      case Projects.add_project_users(project, rows, actor, false) do
        {:ok, _project_users} -> :ok
        {:error, changeset} -> raise_invalid("project members", changeset)
      end
    end
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
    scope = workflow_scope(spec, project_scope, name)

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

  # A workflow's jobs, triggers and edges derive their ids from this scope, so
  # anchor it to the workflow's pinned `id` when it has one. Anchoring it to the
  # name instead meant renaming a workflow re-derived every child id, and since
  # `Workflow` declares `has_many :jobs, on_replace: :delete` the old jobs and
  # triggers were silently deleted and recreated - taking each webhook
  # trigger's `/i/<id>` URL with them. Pinning an `id`, which is what the docs
  # tell you to do before a rename, now keeps the children too.
  defp workflow_scope(spec, project_scope, name) do
    case spec["id"] do
      nil -> "#{project_scope}/workflow:#{name}"
      id -> "#{project_scope}/workflow-id:#{id}"
    end
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
        raise "Scenario entry with keys [#{describe_keys(map)}] is missing " <>
                "required key #{inspect(key)}"
    end
  end

  defp fetch!(other, key) do
    raise "Expected a map with key #{inspect(key)}, got a #{type_name(other)}"
  end

  # Entries reach here after `interpolate_env/1`, so their values can hold
  # resolved secrets. Name the entry by its keys and never by its values.
  defp describe_keys(map) do
    map |> Map.keys() |> Enum.sort() |> Enum.join(", ")
  end

  defp type_name(value) when is_list(value), do: "list"
  defp type_name(value) when is_map(value), do: "map"
  defp type_name(value) when is_binary(value), do: "string"
  defp type_name(value) when is_number(value), do: "number"
  defp type_name(value) when is_boolean(value), do: "boolean"
  defp type_name(nil), do: "nil"
  defp type_name(_value), do: "value"

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

  # `cast_assoc` is a no-op for a key the document omits, so a scenario that
  # declares no workflows (or no collections) leaves the project's own alone
  # rather than looking like it wants them all gone.
  defp maybe_put_declared(document, _key, []), do: document
  defp maybe_put_declared(document, key, list), do: Map.put(document, key, list)

  # For an association the document *does* carry, the provisioner treats it as
  # authoritative: `Project` declares `has_many :workflows` and
  # `has_many :collections` with Ecto's default `on_replace: :raise`, so a
  # record that exists on the project but is absent from the document aborts
  # the run with a bare Ecto error naming neither the record nor the scenario.
  # Kickstart never removes anything, so name what is in the way instead.
  defp guard_undeclared!(project, document, project_name) do
    with {:ok, declared} <- Map.fetch(document, "workflows") do
      declared_ids = MapSet.new(declared, & &1["id"])

      workflows =
        Repo.all(
          from w in Workflow,
            where: w.project_id == ^project.id,
            select: {w.id, w.name, not is_nil(w.deleted_at)}
        )

      # Live and undeclared: the provisioner would try to replace it.
      undeclared =
        for {id, name, false} <- workflows,
            not MapSet.member?(declared_ids, id),
            do: name

      # Soft-deleted and declared: invisible to the provisioner's preload, so
      # the same id comes back as an insert and collides on the primary key.
      resurrected =
        for {id, name, true} <- workflows,
            MapSet.member?(declared_ids, id),
            do: name

      raise_in_the_way!(project_name, "workflow", undeclared)

      unless resurrected == [] do
        raise """
        Project #{project_name} has deleted workflow(s) whose ids the scenario \
        still derives: #{Enum.join(resurrected, ", ")}.

        A deleted workflow keeps its row, so kickstart cannot recreate it under \
        the same id. Rename it in the scenario (which derives a new id), pin a \
        different `id`, or purge the deleted workflow first.
        """
      end
    end

    with {:ok, declared} <- Map.fetch(document, "collections") do
      declared_ids = MapSet.new(declared, & &1["id"])

      undeclared =
        Repo.all(
          from c in Collection,
            where: c.project_id == ^project.id,
            select: {c.id, c.name}
        )
        |> Enum.reject(fn {id, _name} -> MapSet.member?(declared_ids, id) end)
        |> Enum.map(&elem(&1, 1))

      raise_in_the_way!(project_name, "collection", undeclared)
    end
  end

  defp raise_in_the_way!(_project_name, _label, []), do: :ok

  defp raise_in_the_way!(project_name, label, names) do
    raise """
    Project #{project_name} already has #{label}(s) the scenario does not \
    declare: #{Enum.join(names, ", ")}.

    Kickstart never removes records, but the provisioner treats the document as \
    the complete set, so a re-run cannot leave them out. Either add them to the \
    scenario, or start from a project holding only what the scenario describes.
    """
  end

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
        raise "Expected #{inspect(key)} to be a list, got a #{type_name(other)}"
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

  # Not every context returns a changeset - `Credentials.create_credential/1`
  # is specced `{:error, any()}` and an `oauth` credential fails validation
  # with a plain term. Without this clause that surfaced as a
  # FunctionClauseError instead of the scenario error.
  defp raise_invalid(what, reason) do
    raise "Failed to kickstart #{what}: #{inspect(reason)}"
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
