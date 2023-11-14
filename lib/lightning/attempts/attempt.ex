defmodule Lightning.Attempt do
  @moduledoc """
  Ecto model for Attempts.


  """
  use Ecto.Schema
  import Ecto.Changeset
  import Lightning.Validators

  alias Lightning.Accounts.User
  alias Lightning.InvocationReason
  alias Lightning.WorkOrder
  alias Lightning.Invocation.Run
  alias Lightning.Invocation.LogLine
  alias Lightning.AttemptRun
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  # alias Lightning.Workflows.Node

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
  Returns the list of final states for an attempt.
  """
  defmacro final_states do
    quote do
      unquote(@final_states)
    end
  end

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          reason: InvocationReason.t() | Ecto.Association.NotLoaded.t(),
          work_order: WorkOrder.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "attempts" do
    belongs_to :work_order, WorkOrder
    belongs_to :reason, InvocationReason

    belongs_to :starting_job, Job
    belongs_to :starting_trigger, Trigger
    belongs_to :created_by, User
    belongs_to :dataclip, Lightning.Invocation.Dataclip

    has_one :workflow, through: [:work_order, :workflow]

    has_many :log_lines, LogLine

    many_to_many :runs, Run,
      join_through: AttemptRun,
      preload_order: [asc: :started_at]

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
    |> validate_required_assoc(:dataclip)
    |> validate_required_assoc(:starting_trigger)
  end

  def for(%Job{} = job, attrs) do
    %__MODULE__{}
    |> change()
    |> put_assoc(:starting_job, job)
    |> put_assoc(:created_by, attrs[:created_by])
    |> put_assoc(:dataclip, attrs[:dataclip])
    |> validate_required_assoc(:dataclip)
    |> validate_required_assoc(:starting_job)
    |> validate_required_assoc(:created_by)
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()})
    |> change(attrs)
    |> validate()
  end

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:reason_id, :work_order_id, :priority])
    |> cast_assoc(:runs, required: false)
    |> validate_required([:reason_id, :work_order_id])
    |> assoc_constraint(:work_order)
    |> validate()
  end

  def start(attempt) do
    attempt
    |> change(
      state: :started,
      started_at: DateTime.utc_now()
    )
    |> validate_state_change()
  end

  @spec complete(
          {map(), map()}
          | %{
              :__struct__ =>
                atom() | %{:__changeset__ => map(), optional(any()) => any()},
              optional(atom()) => any()
            },
          {any(), any(), any()}
        ) :: Ecto.Changeset.t()
  def complete(attempt, {state, error_type, _error_message}) do
    attempt
    |> cast(%{state: state}, [:state])
    |> put_change(:finished_at, DateTime.utc_now())
    |> validate_required([:state])
    |> validate_inclusion(:state, @final_states)
    |> cast(%{error_type: error_type}, [:error_type])
    |> validate_state_change()
  end

  defp validate_state_change(changeset) do
    {changeset.data |> Map.get(:state), get_field(changeset, :state)}
    |> case do
      {:available, :claimed} ->
        changeset

      {:available, to} ->
        changeset
        |> add_error(
          :state,
          "cannot mark attempt #{to} that has not been claimed by a worker"
        )

      {:claimed, :started} ->
        changeset |> validate_required([:started_at])

      {from, to} when from in @final_states and to in @final_states ->
        add_error(changeset, :state, "already in completed state")

      {from, to} when from in [:claimed, :started] and to in @final_states ->
        changeset |> validate_required([:finished_at])

      {from, to} when from == to ->
        changeset
    end
  end

  defp validate(changeset) do
    changeset
    |> assoc_constraint(:work_order)
    |> check_constraint(:job, name: "validate_job_or_trigger")
  end
end
