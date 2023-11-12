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
    |> then(fn changeset ->
      previous_state = changeset.data |> Map.get(:state)

      if previous_state == :claimed do
        changeset
      else
        changeset
        |> add_error(
          :state,
          "cannot start attempt that is not in a claimed state"
        )
      end
    end)
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
    |> validate_required([:state])
    |> validate_inclusion(:state, @final_states)
    |> cast(%{error_type: error_type}, [:error_type])
    |> validate_state_change()
  end

  defp validate_state_change(%{data: previous, changes: changes} = changeset) do
    %{state: previous_state, error_type: previous_error} = previous

    add_timestamp = change(changeset, finished_at: DateTime.utc_now())

    if is_nil(previous_error) do
      case changes do
        %{state: :lost} ->
          if Enum.member?([:claimed, :started], previous_state) do
            add_timestamp
          else
            changeset
            |> add_error(
              :state,
              "cannot mark attempt lost that has not been claimed by a worker"
            )
          end

        %{state: _any_other} ->
          if previous_state == :started do
            add_timestamp
          else
            changeset
            |> add_error(
              :state,
              "cannot complete attempt that has not been started"
            )
          end

        _other ->
          changeset
      end
    else
      changeset
      |> add_error(:state, "cannot complete attempt that already has an error")
    end
  end

  defp validate(changeset) do
    changeset
    |> assoc_constraint(:work_order)
    |> check_constraint(:job, name: "validate_job_or_trigger")
  end
end
