defmodule Lightning.Run do
  @moduledoc """
  Ecto model for Runs.


  """
  use Ecto.Schema

  import Ecto.Changeset
  import Lightning.Validators

  alias Lightning.Accounts.User
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Invocation.LogLine
  alias Lightning.Invocation.Step
  alias Lightning.RunStep
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.WorkOrder

  @final_states [
    :success,
    :failed,
    :crashed,
    :cancelled,
    :killed,
    :exception,
    :lost
  ]

  @doc """
  Returns the list of final states for a run.
  """
  defmacro final_states do
    quote do
      unquote(@final_states)
    end
  end

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          work_order: WorkOrder.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "runs" do
    belongs_to :work_order, WorkOrder

    belongs_to :starting_job, Job
    belongs_to :starting_trigger, Trigger
    belongs_to :created_by, User
    belongs_to :dataclip, Lightning.Invocation.Dataclip

    has_one :workflow, through: [:work_order, :workflow]
    belongs_to :snapshot, Snapshot

    has_many :log_lines, LogLine

    many_to_many :steps, Step,
      join_through: RunStep,
      preload_order: [asc: :started_at]

    embeds_one :options, Lightning.Runs.RunOptions

    field :state, Ecto.Enum,
      values:
        Enum.concat(
          [
            :available,
            :claimed,
            :started
          ],
          @final_states
        ),
      default: :available

    field :error_type, :string

    field :claimed_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    field :priority, Ecto.Enum,
      values: [immediate: 0, normal: 1],
      default: :normal

    timestamps type: :utc_datetime_usec, updated_at: false
  end

  def for(%Trigger{} = trigger, attrs) do
    %__MODULE__{}
    |> change()
    |> put_assoc(:starting_trigger, trigger)
    |> put_assoc(:dataclip, attrs[:dataclip])
    |> put_assoc(:snapshot, attrs[:snapshot])
    |> add_options(attrs.dataclip.project_id)
    |> validate_required_assoc(:dataclip)
    |> validate_required_assoc(:snapshot)
    |> validate_required_assoc(:starting_trigger)
  end

  def for(%Job{} = job, attrs) do
    %__MODULE__{priority: attrs[:priority]}
    |> change()
    |> put_assoc(:created_by, attrs[:created_by])
    |> put_assoc(:dataclip, attrs[:dataclip])
    |> put_assoc(:snapshot, attrs[:snapshot])
    |> put_assoc(:starting_job, job)
    |> add_options(attrs.dataclip.project_id)
    |> validate_required_assoc(:created_by)
    |> validate_required_assoc(:dataclip)
    |> validate_required_assoc(:snapshot)
    |> validate_required_assoc(:starting_job)
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()})
    |> change(attrs)
    |> validate()
  end

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, [:work_order_id, :snapshot_id, :priority])
    |> cast_assoc(:steps, required: false)
    |> validate_required([:work_order_id, :snapshot_id])
    |> assoc_constraint(:work_order)
    |> validate()
  end

  @doc """
  Adds options (project-level logging options, resource limits such as timeout
  and memory usage, etc.) to the run before storing in the DB.
  """
  def add_options(changeset, project_id) do
    put_change(
      changeset,
      :options,
      UsageLimiter.get_run_options(%Context{project_id: project_id})
      |> Enum.into(%{})
    )
  end

  def start(run) do
    run
    |> change(
      state: :started,
      started_at: DateTime.utc_now()
    )
    |> validate_state_change()
  end

  @spec complete(%__MODULE__{}, %{optional(any()) => any()}) ::
          Ecto.Changeset.t()
  def complete(run, params) do
    run
    |> change()
    |> put_change(:state, nil)
    |> cast(params, [:state, :error_type])
    |> put_change(:finished_at, DateTime.utc_now())
    |> validate_required([:state])
    |> validate_inclusion(:state, @final_states)
    |> validate_state_change()
  end

  # credo:disable-for-next-line
  defp validate_state_change(changeset) do
    {changeset.data |> Map.get(:state), get_field(changeset, :state)}
    |> case do
      {:available, :claimed} ->
        changeset

      {:available, to} ->
        changeset
        |> add_error(
          :state,
          "cannot mark run #{to} that has not been claimed by a worker"
        )

      {:claimed, :started} ->
        changeset |> validate_required([:started_at])

      {from, to} when from in @final_states and to in @final_states ->
        add_error(changeset, :state, "already in completed state")

      {from, to} when from in [:claimed, :started] and to in @final_states ->
        changeset |> validate_required([:finished_at])

      {from, to} when from == to ->
        changeset

      {_from, _to} ->
        changeset
    end
  end

  defp validate(changeset) do
    changeset
    |> assoc_constraint(:work_order)
    |> assoc_constraint(:snapshot)
    |> check_constraint(:job, name: "validate_job_or_trigger")
  end
end
