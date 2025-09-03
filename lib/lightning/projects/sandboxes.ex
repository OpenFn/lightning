defmodule Lightning.Projects.Sandboxes do
  @moduledoc """
  Provision **sandbox** projects as children of an existing project.

  A sandbox is a full project that:
    * clones core **project settings** from the parent,
    * **references** the same credentials via `project_credentials` (no new credentials are created),
    * clones the **workflow DAG** (workflows, jobs, triggers, edges),
    * **disables all triggers** in the sandbox,
    * **remaps positions** (node coordinates) to the new node IDs,
    * copies the **latest** `WorkflowVersion` per workflow to seed version history,
    * can optionally **copy a subset of named dataclips**,
    * and assigns the **creator as :owner** (additional collaborators optional).

  ### Authorization

  The `actor` must be `:owner` or `:admin` on the **parent** project.
  Otherwise `{:error, :unauthorized}` is returned and nothing is created.

  ### Invariants & side effects

  * The sandbox is created in a single DB **transaction**.
  * The creator is added as the **only owner** at creation time; additional
    collaborators are added **after** creation to preserve the project’s
    “exactly one owner” validation.
  * Credentials are **not duplicated**; we create `project_credentials` rows
    that reference the parent’s existing `credentials`.
  * Trigger rows are cloned but always persisted with `enabled: false`.
  * Positions are remapped by translating old node IDs to new ones; if no valid
    positions remain, we store `nil` (UI → auto-layout).
  * There are **no runs** or dataclips copied by default.

  See the `provision/3` docs below for attribute details and return values.
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Repo
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowVersion

  @typedoc """
  Attributes accepted by `provision/3`.

  * `:name` (**required**) – sandbox name (scoped unique per `parent_id`)
  * `:color` (optional) – UI color string (e.g. `"#336699"`)
  * `:env` (optional) – environment slug for the project (e.g. `"staging"`)
  * `:collaborators` (optional) – list of `%{user_id: Ecto.UUID.t(), role: atom()}`
    to add in addition to the creator (owner). Any `:owner` entries are ignored;
    only one owner is allowed (the creator).
  * `:dataclip_ids` (optional) – list of dataclip IDs to copy **if** they are:
      * named (`name` not `nil`) **and**
      * of type in `[:global, :saved_input, :http_request]`.
  """
  @type provision_attrs :: %{
          required(:name) => String.t(),
          optional(:color) => String.t() | nil,
          optional(:env) => String.t() | nil,
          optional(:collaborators) => [%{user_id: Ecto.UUID.t(), role: atom()}],
          optional(:dataclip_ids) => [Ecto.UUID.t()]
        }

  @clone_fields ~w(
    allow_support_access concurrency description requires_mfa
    retention_policy history_retention_period dataclip_retention_period
  )a

  @allowed_clip_types [:global, :saved_input, :http_request]

  @doc """
  Provisions a sandbox project under `parent` on behalf of `actor`.

  This function performs the full sandbox provisioning workflow described in the
  module documentation. It returns either the newly created sandbox project or
  an error tuple without side effects outside the transaction.

  ## Parameters

    * `parent` – the parent `%Lightning.Projects.Project{}` to clone from
    * `actor` – the `%Lightning.Accounts.User{}` performing the action; must be
      `:owner` or `:admin` on the **parent**
    * `attrs` – map of attributes (see `t:provision_attrs/0` for details)

  ## Returns

    * `{:ok, %Lightning.Projects.Project{}}` on success
    * `{:error, :unauthorized}` if `actor` lacks permission on `parent`
    * `{:error, term()}` for validation/DB errors (e.g. name format/uniqueness)

  ## What gets cloned

    * Project settings: `allow_support_access`, `concurrency`, `description`,
      `requires_mfa`, `retention_policy`, `history_retention_period`,
      `dataclip_retention_period`.
    * Credentials: `project_credentials` rows pointing at the **same**
      underlying credentials (no new `credentials`).
    * DAG: workflows, jobs, triggers (disabled), edges, webhook auth methods.
    * Positions: remapped from parent node IDs to child node IDs; `nil` when
      nothing remaps (UI → auto-layout).
    * Version heads: latest `WorkflowVersion` per workflow (`hash`, `source`).

  ## Examples

      # Minimal: creator becomes owner
      {:ok, sandbox} =
        Lightning.Projects.Sandboxes.provision(parent, actor, %{
          name: "Sandbox – June load test"
        })

      # With collaborators, env, color, and a few named dataclips
      {:ok, sandbox} =
        Lightning.Projects.Sandboxes.provision(parent, actor, %{
          name: "SB – staging QA",
          color: "#336699",
          env: "staging",
          collaborators: [%{user_id: editor.id, role: :editor}],
          dataclip_ids: [clip1_id, clip2_id]
        })

      # Unauthorized
      {:error, :unauthorized} =
        Lightning.Projects.Sandboxes.provision(parent, viewer_user, %{name: "Nope"})

  """
  @spec provision(Project.t(), User.t(), provision_attrs) ::
          {:ok, Project.t()} | {:error, term()}
  def provision(%Project{} = parent, %User{} = actor, attrs) do
    case Lightning.Projects.get_project_user_role(actor, parent) do
      role when role in [:owner, :admin] -> do_provision(parent, actor, attrs)
      _ -> {:error, :unauthorized}
    end
  end

  defp do_provision(parent, actor, attrs) do
    name = Map.fetch!(attrs, :name)
    color = Map.get(attrs, :color)
    env = Map.get(attrs, :env)

    Repo.transaction(fn ->
      parent = preload_parent(parent)

      sandbox =
        parent
        |> build_base_attrs(actor, name, color, env)
        |> create_sandbox!()

      cred_map = copy_credentials!(parent, sandbox)

      wf_map = create_workflows!(parent, sandbox)
      job_map = clone_jobs!(parent, wf_map, cred_map)
      trg_map = clone_triggers!(parent, wf_map)
      clone_edges!(parent, wf_map, job_map, trg_map)
      remap_positions!(parent, wf_map, job_map, trg_map)
      copy_latest_heads!(wf_map)

      add_collaborators!(sandbox, actor, Map.get(attrs, :collaborators, []))

      maybe_clone_named_dataclips!(
        parent.id,
        sandbox.id,
        Map.get(attrs, :dataclip_ids)
      )

      sandbox
    end)
    |> case do
      {:ok, project} -> {:ok, project}
      {:error, reason} -> {:error, reason}
    end
  end

  defp preload_parent(parent) do
    Repo.preload(parent,
      workflows: [
        jobs: [:project_credential],
        triggers: [:webhook_auth_methods],
        edges: []
      ],
      project_credentials: [:credential]
    )
  end

  defp build_base_attrs(parent, actor, name, color, env) do
    owner_user = %{user_id: actor.id, role: :owner}

    parent
    |> Map.take(@clone_fields)
    |> Map.merge(%{
      name: name,
      color: color,
      env: env,
      parent_id: parent.id,
      project_users: [owner_user]
    })
  end

  defp create_sandbox!(attrs) do
    {:ok, sandbox} = Lightning.Projects.create_project(attrs, false)
    sandbox
  end

  defp copy_credentials!(parent, sandbox) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(parent.project_credentials, fn pc ->
        %{
          project_id: sandbox.id,
          credential_id: pc.credential_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    {_, returning} =
      Repo.insert_all(ProjectCredential, rows,
        on_conflict: :nothing,
        returning: [:id, :credential_id]
      )

    Map.new(returning, &{&1.credential_id, &1.id})
  end

  defp create_workflows!(parent, sandbox) do
    Enum.reduce(parent.workflows, %{}, fn w, acc ->
      {:ok, new_w} =
        %Workflow{}
        |> Workflow.changeset(%{
          name: w.name,
          project_id: sandbox.id,
          concurrency: w.concurrency,
          enable_job_logs: w.enable_job_logs,
          positions: %{}
        })
        |> Repo.insert()

      Map.put(acc, w.id, new_w.id)
    end)
  end

  defp clone_jobs!(parent, wf_map, cred_map) do
    parent.workflows
    |> Enum.flat_map(fn w ->
      new_wf_id = Map.fetch!(wf_map, w.id)

      Enum.map(w.jobs, fn j ->
        child_pc_id =
          case j.project_credential do
            %ProjectCredential{credential_id: cred_id} ->
              Map.get(cred_map, cred_id)

            _ ->
              nil
          end

        {:ok, new_job} =
          %Job{}
          |> Job.changeset(%{
            id: Ecto.UUID.generate(),
            name: j.name,
            body: j.body,
            adaptor: j.adaptor,
            workflow_id: new_wf_id,
            project_credential_id: child_pc_id,
            keychain_credential_id: nil
          })
          |> Repo.insert()

        {j.id, new_job.id}
      end)
    end)
    |> Map.new()
  end

  defp clone_triggers!(parent, wf_map) do
    parent.workflows
    |> Enum.flat_map(fn w ->
      new_wf_id = Map.fetch!(wf_map, w.id)

      Enum.map(w.triggers, fn t ->
        attrs = %{
          id: Ecto.UUID.generate(),
          workflow_id: new_wf_id,
          type: t.type,
          enabled: false,
          comment: t.comment,
          custom_path: t.custom_path,
          cron_expression: t.cron_expression,
          kafka_configuration: t.kafka_configuration
        }

        {:ok, new_t} = %Trigger{} |> Trigger.changeset(attrs) |> Repo.insert()

        if t.webhook_auth_methods && t.webhook_auth_methods != [] do
          new_t
          |> Repo.preload(:webhook_auth_methods)
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_assoc(
            :webhook_auth_methods,
            t.webhook_auth_methods
          )
          |> Repo.update!()
        end

        {t.id, new_t.id}
      end)
    end)
    |> Map.new()
  end

  defp clone_edges!(parent, wf_map, job_map, trg_map) do
    Enum.each(parent.workflows, fn w ->
      new_wf_id = Map.fetch!(wf_map, w.id)

      Enum.each(w.edges, fn e ->
        %Edge{}
        |> Edge.changeset(%{
          id: Ecto.UUID.generate(),
          workflow_id: new_wf_id,
          condition_type: e.condition_type,
          condition_expression: e.condition_expression,
          condition_label: e.condition_label,
          enabled: e.enabled,
          source_job_id: e.source_job_id && Map.fetch!(job_map, e.source_job_id),
          source_trigger_id:
            e.source_trigger_id && Map.fetch!(trg_map, e.source_trigger_id),
          target_job_id: e.target_job_id && Map.fetch!(job_map, e.target_job_id)
        })
        |> Repo.insert!()
      end)
    end)
  end

  defp remap_positions!(parent, wf_map, job_map, trg_map) do
    Enum.each(parent.workflows, fn w ->
      new_wf_id = Map.fetch!(wf_map, w.id)

      wf_job_ids = Enum.map(w.jobs, & &1.id)
      wf_trg_ids = Enum.map(w.triggers, & &1.id)

      id_map =
        Map.merge(
          Map.take(job_map, wf_job_ids),
          Map.take(trg_map, wf_trg_ids)
        )

      new_positions = remap_positions(w.positions || %{}, id_map)

      Repo.get!(Workflow, new_wf_id)
      |> Ecto.Changeset.change(positions: new_positions)
      |> Repo.update!()
    end)
  end

  defp copy_latest_heads!(wf_map) do
    latest =
      from(v in WorkflowVersion,
        where: v.workflow_id in ^Map.keys(wf_map),
        distinct: v.workflow_id,
        order_by: [asc: v.workflow_id, desc: v.inserted_at, desc: v.id],
        select: %{workflow_id: v.workflow_id, hash: v.hash, source: v.source}
      )
      |> Repo.all()

    Enum.each(latest, fn %{workflow_id: old_id, hash: h, source: s} ->
      Repo.insert!(%WorkflowVersion{
        workflow_id: Map.fetch!(wf_map, old_id),
        hash: h,
        source: s
      })
    end)
  end

  defp add_collaborators!(sandbox, actor, collaborators) do
    extras =
      Enum.reject(collaborators, fn c ->
        c.user_id == actor.id or c.role == :owner
      end)

    if extras != [] do
      {:ok, _} = Lightning.Projects.add_project_users(sandbox, extras, false)
    end

    :ok
  end

  defp maybe_clone_named_dataclips!(_parent_id, _sandbox_id, nil), do: :ok
  defp maybe_clone_named_dataclips!(_parent_id, _sandbox_id, []), do: :ok

  defp maybe_clone_named_dataclips!(parent_id, sandbox_id, dataclip_ids)
       when is_list(dataclip_ids) do
    clips =
      from(d in Lightning.Invocation.Dataclip,
        where:
          d.project_id == ^parent_id and
            d.id in ^dataclip_ids and
            d.type in ^@allowed_clip_types and
            not is_nil(d.name),
        select: %{name: d.name, body: d.body, type: d.type}
      )
      |> Repo.all()

    Enum.each(clips, fn attrs ->
      attrs
      |> Map.put(:project_id, sandbox_id)
      |> Lightning.Invocation.Dataclip.new()
      |> Repo.insert!()
    end)
  end

  defp remap_positions(pos_map, id_map) when is_map(pos_map) do
    pos_map
    |> Enum.reduce(%{}, fn {old_id, coords}, acc ->
      case Map.get(id_map, old_id) do
        nil -> acc
        new_id -> Map.put(acc, new_id, coords)
      end
    end)
    |> case do
      m when map_size(m) == 0 -> nil
      m -> m
    end
  end
end
