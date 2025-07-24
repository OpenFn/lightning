defmodule LightningWeb.WorkflowLive.Helpers do
  @moduledoc """
  Helper functions for the Workflow LiveViews.
  """

  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Repo
  alias Lightning.Services.UsageLimiter

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

      case UsageLimiter.limit_action(%Action{type: :new_run}, %Context{
             project_id: project_id
           }) do
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
          # If it's already a param definition, use it
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
end
