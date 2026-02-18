defmodule LightningWeb.WorkflowLive.Helpers do
  @moduledoc """
  Helper functions for the Workflow LiveViews.
  """

  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Repo

  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowUsageLimiter
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders

  def subscribe_to_params_update(socket_id) do
    Lightning.subscribe(socket_id)
  end

  def broadcast_updated_params(socket, params) do
    Lightning.local_broadcast(socket.id, {:updated_params, params})
  end

  @spec save_workflow(Ecto.Changeset.t(), struct()) ::
          {:ok, Workflows.Workflow.t()}
          | {:error,
             Ecto.Changeset.t() | UsageLimiting.message() | :workflow_deleted}
  def save_workflow(changeset, actor) do
    case WorkflowUsageLimiter.limit_workflow_activation(changeset) do
      :ok ->
        Workflows.save_workflow(changeset, actor)

      {:error, _reason, message} ->
        {:error, message}
    end
  end

  @spec run_workflow(
          Ecto.Changeset.t(Workflows.Workflow.t()) | Workflows.Workflow.t(),
          map(),
          selected_job: map(),
          created_by: map(),
          project: map()
        ) ::
          {:ok,
           %{
             workorder: WorkOrder.t(),
             workflow: Workflows.Workflow.t(),
             message: UsageLimiting.message()
           }}
          | {:error, Ecto.Changeset.t(Workflows.Workflow.t())}
          | {:error, Ecto.Changeset.t(WorkOrders.Manual.t())}
          | {:error, UsageLimiting.message()}
          | {:error, :workflow_deleted}
  def run_workflow(workflow_or_changeset, params, opts) do
    Lightning.Repo.transact(fn ->
      %{id: project_id} = Keyword.fetch!(opts, :project)
      actor = Keyword.fetch!(opts, :created_by)

      case WorkOrders.limit_run_creation(project_id) do
        {:error, _reason, message} ->
          {:error, message}

        :ok ->
          with {:ok, workflow} <-
                 maybe_save_workflow(workflow_or_changeset, actor),
               {:ok, manual} <- build_manual_workorder(params, workflow, opts),
               {:ok, workorder} <- WorkOrders.create_for(manual) do
            {:ok, %{workorder: workorder, workflow: workflow}}
          end
      end
    end)
  end

  defp maybe_save_workflow(%Ecto.Changeset{} = changeset, actor) do
    Workflows.save_workflow(changeset, actor)
  end

  defp maybe_save_workflow(%Workflow{} = workflow, _actor) do
    {:ok, workflow}
  end

  defp build_manual_workorder(params, workflow, opts) do
    {selected_job, opts} = Keyword.pop!(opts, :selected_job)

    opts =
      Keyword.merge(opts, job: Repo.reload(selected_job), workflow: workflow)

    params
    |> WorkOrders.Manual.new(opts)
    |> Ecto.Changeset.apply_action(:validate)
  end

  @doc """
  Determines if a workflow is enabled based on its triggers.
  Accepts either a Workflow struct or an Ecto.Changeset.
  """
  def workflow_enabled?(%Workflow{} = workflow) do
    Enum.all?(workflow.triggers, & &1.enabled)
  end

  def workflow_enabled?(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.get_field(changeset, :triggers)
    |> Enum.all?(&trigger_enabled?/1)
  end

  @doc """
  Generates a tooltip describing the workflow's state.
  Accepts either a Workflow struct or an Ecto.Changeset.
  """
  def workflow_state_tooltip(%Workflow{triggers: triggers}) do
    generate_tooltip(triggers, Enum.all?(triggers, & &1.enabled))
  end

  def workflow_state_tooltip(%Ecto.Changeset{} = changeset) do
    triggers = Ecto.Changeset.fetch_field!(changeset, :triggers)
    generate_tooltip(triggers, Enum.all?(triggers, & &1.enabled))
  end

  defp trigger_enabled?(trigger), do: trigger.enabled

  defp generate_tooltip(triggers, all_enabled) do
    case {all_enabled, triggers} do
      {_, []} ->
        "This workflow is inactive (no triggers configured)"

      {true, [first_trigger | _]} ->
        "This workflow is active (#{first_trigger.type} trigger enabled)"

      {false, _} ->
        "This workflow is inactive (manual runs only)"
    end
  end

  @doc """
  Builds a URL with query parameters based on parameter definitions.

  ## Parameters

    * `assigns` - The assigns from the LiveView
    * `params` - List of parameter definitions. Each definition is a keyword list with:
      * `:name` - The parameter name in the URL (required)
      * `:value` - The value or a function that receives (assigns, params) (required)
      * `:when` - Condition as boolean or function that receives (assigns, params) (default: true)
      * `:transform` - Optional transformation function applied to the value
  """
  def build_url(assigns, params) when is_list(params) do
    query_string =
      params
      |> Enum.reduce(%{}, fn param_def, acc ->
        process_param(param_def, assigns, params, acc)
      end)
      |> remove_nil_values()
      |> URI.encode_query()

    if byte_size(query_string) > 0 do
      "#{assigns.base_url}?#{query_string}"
    else
      assigns.base_url
    end
  end

  defp process_param(param_def, assigns, all_params, acc) do
    name = Keyword.fetch!(param_def, :name)

    if should_include?(param_def, assigns, all_params) do
      value =
        param_def
        |> Keyword.fetch!(:value)
        |> resolve_value(assigns, all_params)
        |> apply_transform(param_def)

      Map.put(acc, name, value)
    else
      acc
    end
  end

  defp should_include?(param_def, assigns, all_params) do
    case Keyword.get(param_def, :when, true) do
      true -> true
      false -> false
      func when is_function(func, 2) -> func.(assigns, all_params)
      func when is_function(func, 1) -> func.(assigns)
      func when is_function(func, 0) -> func.()
    end
  end

  defp resolve_value(value, assigns, all_params) do
    case value do
      func when is_function(func, 2) -> func.(assigns, all_params)
      func when is_function(func, 1) -> func.(assigns)
      func when is_function(func, 0) -> func.()
      value -> value
    end
  end

  defp apply_transform(value, param_def) do
    case Keyword.get(param_def, :transform) do
      nil -> value
      transformer -> transformer.(value)
    end
  end

  defp remove_nil_values(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Creates a parameter definition with common defaults.
  """
  def param(name, value, opts \\ []) do
    [name: name, value: value] ++ opts
  end

  @doc """
  Creates a parameter that pulls from query_params
  """
  def query_param(name), do: param(name, fn a, _ -> a.query_params[name] end)

  @doc """
  Creates chat-related parameters
  """
  def chat_params do
    [
      param("w-chat", fn a, _ -> a.workflow_chat_session_id end),
      param("j-chat", fn a, _ -> a.job_chat_session_id end)
    ]
  end

  @doc """
  Creates URL parameters ignoring v (all common params except version tag)
  """
  def to_latest_params do
    [
      query_param("m"),
      query_param("s"),
      query_param("a"),
      query_param("method")
    ] ++ chat_params()
  end

  @doc """
  Creates standard URL parameters (all common params)
  """
  def standard_params do
    [
      query_param("m"),
      query_param("s"),
      query_param("a"),
      query_param("v"),
      query_param("method")
    ] ++ chat_params()
  end

  @doc """
  Creates orthogonal parameters (excludes mode and selection)
  """
  def orthogonal_params do
    [
      query_param("a"),
      query_param("v"),
      query_param("method")
    ] ++ chat_params()
  end

  @doc """
  Creates workflow input run parameters
  """
  def workflow_input_params(selection_id) do
    [
      param("s", selection_id),
      param("m", "workflow_input")
    ] ++ orthogonal_params()
  end

  @doc """
  Creates code view parameters
  """
  def code_view_params do
    [param("m", "code")] ++ orthogonal_params()
  end

  @doc """
  Creates parameters excluding mode and selection
  """
  def params_without_mode_selection do
    orthogonal_params()
  end

  @doc """
  Creates parameters with custom overrides
  """
  def with_params(overrides \\ []) do
    base = standard_params()

    Enum.map(overrides, fn {name, value_or_opts} ->
      name = to_string(name)

      case value_or_opts do
        opts when is_list(opts) ->
          if Keyword.has_key?(opts, :name) do
            opts
          else
            Keyword.put(opts, :name, name)
          end

        value ->
          param(name, value)
      end
    end) ++ remove_overridden_params(base, overrides)
  end

  defp remove_overridden_params(base_params, overrides) do
    override_names =
      overrides
      |> Keyword.keys()
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    Enum.reject(base_params, fn param ->
      MapSet.member?(override_names, Keyword.get(param, :name))
    end)
  end

  @param_mappings %{
    direct: %{
      "a" => "run",
      "run" => "a"
    },
    mode_to_panel: %{
      "expand" => "editor",
      "workflow_input" => "run",
      "settings" => "settings",
      "editor" => "expand",
      "run" => "workflow_input"
    },
    preserved: ["v", "method", "w-chat", "j-chat", "code"],
    collaborative_only: ["panel"]
  }

  def legacy_editor_url(params, live_action) do
    base_url = legacy_base_url(params, live_action)

    final_params =
      params
      |> Map.drop(["id", "project_id"])
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        convert_param(key, value, acc, params)
      end)

    build_url_with_params(base_url, final_params)
  end

  defp legacy_base_url(%{"project_id" => project_id}, :new) do
    "/projects/#{project_id}/w/new/legacy?method=template"
  end

  defp legacy_base_url(%{"id" => id, "project_id" => project_id}, :edit) do
    "/projects/#{project_id}/w/#{id}/legacy"
  end

  @doc """
  Builds a URL to the collaborative editor with converted query parameters.

  This function uses a data-driven approach with the `@param_mappings` configuration
  to convert classical editor parameters to collaborative editor equivalents.

  ## Conversion Rules

  - `a` (followed run) → `run`
  - `s` (selected step) → `job`/`trigger`/`edge` (context-aware based on selection)
  - `m=expand` → `panel=editor`
  - `m=workflow_input` → `panel=run`
  - `m=settings` → `panel=settings`
  - Preserves: `v`, `method`, `w-chat`, `j-chat`, `code`
  - Skips: `panel` (collaborative-only)

  ## Parameters

  - `params` - Route parameters map containing:
    - `"project_id"` - Project UUID (required)
    - `"id"` - Workflow UUID (required for `:edit`, absent for `:new`)
    - Additional query parameters to preserve (e.g., `"s"`, `"m"`, `"v"`)
  - `live_action` - Current LiveView action (`:new` or `:edit`)

  ## Returns

  A complete URL string for the collaborative editor with transformed query parameters

  ## Examples

      # Edit existing workflow with query params
      iex> collaborative_editor_url(%{
      ...>   "project_id" => "proj-1",
      ...>   "id" => "wf-1",
      ...>   "s" => "job-abc",
      ...>   "m" => "expand"
      ...> }, :edit)
      "/projects/proj-1/w/wf-1?job=job-abc&panel=editor"

      # New workflow
      iex> collaborative_editor_url(%{
      ...>   "project_id" => "proj-1"
      ...> }, :new)
      "/projects/proj-1/w/new?method=template"

      # With multiple query params
      iex> collaborative_editor_url(%{
      ...>   "project_id" => "proj-1",
      ...>   "id" => "wf-1",
      ...>   "s" => "job-123",
      ...>   "v" => "42",
      ...>   "custom" => "value"
      ...> }, :edit)
      "/projects/proj-1/w/wf-1?custom=value&job=job-123&v=42"

  """
  def collaborative_editor_url(params, live_action) do
    collaborative_params =
      params
      |> Map.drop(["id", "project_id"])
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        convert_param(key, value, acc, params)
      end)

    base_url = collaborative_base_url(params, live_action)

    build_url_with_params(base_url, collaborative_params)
  end

  defp convert_param(_key, nil, acc, _assigns), do: acc

  defp convert_param("a", value, acc, _assigns) do
    Map.put(acc, @param_mappings.direct["a"], value)
  end

  defp convert_param("run", value, acc, _assigns) do
    Map.put(acc, @param_mappings.direct["run"], value)
  end

  defp convert_param("s", value, acc, assigns) do
    selection_type = determine_selection_type(value, assigns)
    Map.put(acc, selection_type, value)
  end

  defp convert_param("job", value, acc, _assigns) do
    Map.put(acc, "s", value)
  end

  defp convert_param("trigger", value, acc, _assigns) do
    Map.put(acc, "s", value)
  end

  defp convert_param("edge", value, acc, _assigns) do
    Map.put(acc, "s", value)
  end

  defp convert_param("m", value, acc, _assigns) do
    case Map.get(@param_mappings.mode_to_panel, value) do
      nil -> acc
      panel -> Map.put(acc, "panel", panel)
    end
  end

  defp convert_param("panel", value, acc, _assigns) do
    case Map.get(@param_mappings.mode_to_panel, value) do
      nil -> acc
      panel -> Map.put(acc, "m", panel)
    end
  end

  defp convert_param(key, value, acc, _assigns) do
    cond do
      key in @param_mappings.collaborative_only ->
        acc

      key in @param_mappings.preserved ->
        Map.put(acc, key, value)

      true ->
        Map.put(acc, key, value)
    end
  end

  defp determine_selection_type(value, assigns) do
    cond do
      match?(%{selected_trigger: %{id: ^value}}, assigns) -> "trigger"
      match?(%{selected_job: %{id: ^value}}, assigns) -> "job"
      match?(%{selected_edge: %{id: ^value}}, assigns) -> "edge"
      true -> "job"
    end
  end

  defp collaborative_base_url(%{"project_id" => project_id}, :new) do
    "/projects/#{project_id}/w/new?method=template"
  end

  defp collaborative_base_url(%{"id" => id, "project_id" => project_id}, :edit) do
    "/projects/#{project_id}/w/#{id}"
  end

  defp build_url_with_params(base_url, params) when map_size(params) == 0 do
    base_url
  end

  defp build_url_with_params(base_url, params) do
    query_string = URI.encode_query(params)
    # Use & if base_url already has query params, otherwise use ?
    separator = if String.contains?(base_url, "?"), do: "&", else: "?"
    "#{base_url}#{separator}#{query_string}"
  end
end
