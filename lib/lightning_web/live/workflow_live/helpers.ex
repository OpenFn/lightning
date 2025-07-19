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

  ## Examples

      # Simple static parameters
      build_url(assigns, [
        [name: "m", value: "edit"],
        [name: "s", value: "job_1"]
      ])

      # Dynamic values from assigns
      build_url(assigns, [
        [name: "a", value: fn a, _ -> a.selected_run end],
        [name: "chat", value: fn a, _ -> a.chat_session_id end]
      ])

      # Conditional parameters
      build_url(assigns, [
        [name: "v",
         value: fn a, _ -> Ecto.Changeset.get_field(a.changeset, :lock_version) end,
         when: fn a, _ -> a.snapshot_version_tag != "latest" end]
      ])

      # With transformations
      build_url(assigns, [
        [name: "ts",
         value: fn _, _ -> DateTime.utc_now() end,
         transform: &DateTime.to_unix/1]
      ])

      # Complex example with all features
      build_url(assigns, [
        [name: "m", value: "edit"],
        [name: "s", value: fn _, params -> params["node_id"] end],
        [name: "method", value: "ai", when: fn a, _ -> a.show_workflow_ai_chat end],
        [name: "chat",
         value: fn a, _ -> a.chat_session_id end,
         when: fn a, _ -> a.show_workflow_ai_chat end],
        [name: "v",
         value: fn a, _ -> Ecto.Changeset.get_field(a.changeset, :lock_version) end,
         when: fn a, _ -> a.snapshot_version_tag != "latest" end,
         transform: &to_string/1]
      ])
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
  Common parameter definitions for workflows.

  These can be used as a starting point and modified as needed:

      params = workflow_params() ++ [
        [name: "custom", value: "value"]
      ]

      build_url(assigns, params)
  """
  def workflow_params do
    [
      [name: "m", value: fn _, params -> params[:mode] end],
      [name: "s", value: fn _, params -> params[:selection] end],
      [
        name: "a",
        value: fn a, _ -> a.selected_run end,
        when: fn a, params -> params[:include_run] && a.selected_run end
      ],
      [
        name: "v",
        value: fn a, _ ->
          Ecto.Changeset.get_field(a.changeset, :lock_version)
        end,
        when: fn a, params ->
          params[:include_version] && a.snapshot_version_tag != "latest"
        end
      ],
      [
        name: "method",
        value: "ai",
        when: fn a, _ -> a.show_workflow_ai_chat end
      ],
      [
        name: "chat",
        value: fn a, _ -> a.chat_session_id end,
        when: fn a, _ -> a.show_workflow_ai_chat end
      ]
    ]
  end

  @doc """
  Creates a parameter definition with common defaults.

  ## Examples

      param("m", "edit")
      param("s", fn a, _ -> a.selected_job.id end)
      param("v", fn a, _ -> a.version end, when: fn a, _ -> a.version != nil end)
  """
  def param(name, value, opts \\ []) do
    [name: name, value: value] ++ opts
  end

  @doc """
  Cleans query parameters, removing nil values and optionally specific parameters.

  ## Options

    * `:drop` - List of parameter names to remove
    * `:keep_if` - Function that receives {name, value} and returns boolean

  ## Examples

      clean_query_params(%{"v" => "1", "chat" => nil})
      #=> %{"v" => "1"}

      clean_query_params(%{"v" => "1", "m" => "edit"}, drop: ["v"])
      #=> %{"m" => "edit"}

      clean_query_params(params, keep_if: fn {k, _} -> k != "v" end)
  """
  def clean_query_params(params, opts \\ []) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> then(fn params ->
      case Keyword.get(opts, :drop) do
        nil -> params
        drop_list -> Enum.reject(params, fn {k, _} -> k in drop_list end)
      end
    end)
    |> then(fn params ->
      case Keyword.get(opts, :keep_if) do
        nil -> params
        keep_func -> Enum.filter(params, keep_func)
      end
    end)
    |> Map.new()
  end
end
