defmodule Lightning.Workflows.Edge do
  @moduledoc """
  Ecto model for Workflow Edges.

  A Workflow Edge represents a connection between two jobs
  (or a trigger and a job) in a workflow.

  The source of the edge is either a job or a trigger.
  The target of the edge is always a job.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Lightning.Validators

  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow

  @type edge_condition() ::
          :always | :on_job_success | :on_job_failure | :js_expression
  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          condition_type: edge_condition(),
          enabled: boolean(),
          workflow: nil | Workflow.t() | Ecto.Association.NotLoaded.t(),
          source_job: nil | Job.t() | Ecto.Association.NotLoaded.t(),
          source_trigger: nil | Trigger.t() | Ecto.Association.NotLoaded.t(),
          target_job: nil | Job.t() | Ecto.Association.NotLoaded.t(),
          delete: boolean()
        }

  @conditions [:on_job_success, :on_job_failure, :always, :js_expression]
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "workflow_edges" do
    belongs_to :workflow, Workflow
    belongs_to :source_job, Job
    belongs_to :source_trigger, Trigger
    belongs_to :target_job, Job

    field :condition_type, Ecto.Enum, values: @conditions
    field :condition_expression, :string
    field :condition_label, :string

    field :enabled, :boolean, default: true

    field :delete, :boolean, virtual: true

    timestamps()
  end

  def new(attrs) do
    change(%__MODULE__{}, Map.merge(attrs, %{id: Ecto.UUID.generate()}))
    |> change(attrs)
  end

  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [
      :id,
      :workflow_id,
      :source_job_id,
      :source_trigger_id,
      :condition_type,
      :enabled,
      :target_job_id,
      :condition_label,
      :condition_expression
    ])
    |> validate()
  end

  def validate(changeset) do
    changeset
    |> assoc_constraint(:workflow)
    |> assoc_constraint(:source_trigger)
    |> assoc_constraint(:source_job)
    |> assoc_constraint(:target_job)
    |> validate_required([:condition_type])
    |> validate_node_in_same_workflow()
    |> foreign_key_constraint(:workflow_id)
    |> validate_exclusive(
      [:source_job_id, :source_trigger_id],
      "source_job_id and source_trigger_id are mutually exclusive"
    )
    |> validate_source_condition()
    |> validate_js_condition()
    |> validate_different_nodes()
  end

  defp validate_source_condition(changeset) do
    if nil != get_field(changeset, :source_trigger_id) do
      changeset
      |> validate_inclusion(:condition_type, [:always, :js_expression],
        message: "must be :always or :js_expression when source is a trigger"
      )
    else
      changeset
    end
  end

  defp validate_js_condition(changeset) do
    if :js_expression == get_field(changeset, :condition_type) do
      changeset
      |> validate_required([:condition_expression])
      |> validate_condition_expression()
    else
      changeset
    end
  end

  defp validate_condition_expression(%{valid?: false} = changeset), do: changeset

  defp validate_condition_expression(changeset) do
    js_expr = get_field(changeset, :condition_expression)

    if String.match?(js_expr, ~r/(import\b|require\b|process\b|await\b|eval\b)/) do
      add_error(
        changeset,
        :condition_expression,
        "contains unacceptable words"
      )
    else
      changeset
      |> validate_length(:condition_label, max: 255)
      |> validate_length(:condition_expression, max: 255)
    end
  end

  defp validate_different_nodes(changeset) do
    [:source_job_id, :target_job_id]
    |> Enum.map(&get_field(changeset, &1))
    |> case do
      [source, target] when is_nil(source) or is_nil(target) ->
        changeset

      [source, target] when source == target ->
        add_error(
          changeset,
          :target_job_id,
          "target_job_id must be different from source_job_id"
        )

      _else ->
        changeset
    end
  end

  defp validate_node_in_same_workflow(changeset) do
    changeset
    |> foreign_key_constraint(:source_job_id,
      message: "job doesn't exist, or is not in the same workflow"
    )
    |> foreign_key_constraint(:source_trigger_id,
      message: "trigger doesn't exist, or is not in the same workflow"
    )
    |> foreign_key_constraint(:target_job_id,
      message: "job doesn't exist, or is not in the same workflow"
    )
  end
end
