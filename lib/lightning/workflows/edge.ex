defmodule Lightning.Workflows.Edge do
  @moduledoc """
  Ecto model for Workflow Edges.

  A Workflow Edge represents a connection between two jobs
  (or a trigger and a job) in a workflow.

  The source of the edge is either a job or a trigger.
  The target of the edge is always a job.
  """
  use Lightning.Schema
  import Lightning.Validators

  alias Lightning.Validators
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

  @derive {Jason.Encoder,
           only: [
             :id,
             :condition_type,
             :condition_expression,
             :condition_label,
             :enabled,
             :source_job_id,
             :source_trigger_id,
             :target_job_id
           ]}
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
    |> enable_if_source_trigger()
  end

  defp enable_if_source_trigger(changeset) do
    if changeset.valid? and get_field(changeset, :source_trigger_id) do
      put_change(changeset, :enabled, true)
    else
      changeset
    end
  end

  def validate(changeset) do
    changeset
    |> validate_uuid([
      :id,
      :workflow_id,
      :source_job_id,
      :source_trigger_id,
      :target_job_id
    ])
    |> assoc_constraint(:workflow)
    |> assoc_constraint(:source_trigger)
    |> assoc_constraint(:source_job)
    |> assoc_constraint(:target_job)
    |> validate_required([:condition_type])
    |> validate_node_in_same_workflow()
    |> foreign_key_constraint(:workflow_id)
    |> validate_has_source()
    |> validate_exclusive(
      [:source_job_id, :source_trigger_id],
      "source_job_id and source_trigger_id are mutually exclusive"
    )
    |> validate_source_condition()
    |> validate_js_condition()
    |> validate_condition_label()
    |> validate_condition_expression()
    |> validate_different_nodes()
    |> unique_constraint(:id, name: "workflow_edges_pkey")
  end

  defp validate_has_source(changeset) do
    if get_field(changeset, :source_trigger_id) != nil or
         get_field(changeset, :source_job_id) != nil do
      changeset
    else
      add_error(
        changeset,
        :source_job_id,
        "source_job_id or source_trigger_id must be present"
      )
    end
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
      validate_required(changeset, [:condition_expression])
    else
      changeset
    end
  end

  # cast/3 accepts an expression on every condition type, and it is written
  # into the workflow_snapshots.edges jsonb whatever the type is, so this runs
  # unconditionally.
  #
  # There is deliberately no `valid?: false` short circuit: the changeset is
  # invalid for unrelated missing fields on plenty of real save paths, and
  # skipping these checks there is how the hole stayed open.
  defp validate_condition_expression(changeset) do
    changeset
    |> Validators.validate_no_null_bytes(
      :condition_expression,
      "condition expression can't contain a null byte"
    )
    |> validate_length(:condition_expression, max: 255)
    |> Validators.validate_name_fits_column(
      :condition_expression,
      "condition expression is too long, please use a shorter one"
    )
  end

  # A label is set on every condition type, not just :js_expression, and it is
  # written into the workflow_snapshots.edges jsonb either way.
  defp validate_condition_label(changeset) do
    changeset
    |> Validators.validate_name(
      :condition_label,
      "condition label can't contain control characters"
    )
    |> validate_length(:condition_label, max: 255)
    |> Validators.validate_name_fits_column(
      :condition_label,
      "condition label is too long, please use a shorter one"
    )
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
