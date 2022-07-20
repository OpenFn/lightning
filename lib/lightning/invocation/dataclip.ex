defmodule Lightning.Invocation.Dataclip do
  @moduledoc """
  Ecto model for Dataclips.

  Dataclips represent some data that arrived in the system, and records both
  the data and the source of the data.

  ## Types

  * `:http_request`
    The data arrived via a webhook.
  * `:global`
    Was created manually, and is intended to be used multiple times.
    When repetitive static data is needed to be maintained, instead of hard-coding
    into a Job - a more convenient solution is to create a `:global` Dataclip
    and access it inside the Job.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Invocation.Event

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          project_id: Ecto.UUID.t() | nil,
          body: %{} | nil,
          source_event: Event.t() | Ecto.Association.NotLoaded.t() | nil,
          events: [Event.t()] | Ecto.Association.NotLoaded.t()
        }

  @type source_type :: :http_request | :global | :run_result
  @source_types [:http_request, :global, :run_result]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "dataclips" do
    field :body, :map
    field :type, Ecto.Enum, values: @source_types
    belongs_to :project, Project
    belongs_to :source_event, Event
    has_many :events, Event

    timestamps(usec: true)
  end

  @doc false
  def changeset(dataclip, attrs) do
    dataclip
    |> cast(attrs, [:body, :type, :source_event_id, :project_id])
    |> case do
      %{action: :delete} = c ->
        c |> validate_required([:type]) |> Map.put(:action, :update)

      c ->
        c |> validate_required([:type, :body])
    end
    |> validate_by_type()
  end

  @doc """
  Append validations based on the type of the Dataclip.

  - `:run_result` must have an associated Event model.
  """
  def validate_by_type(changeset) do
    changeset
    |> fetch_field!(:type)
    |> case do
      :run_result ->
        changeset
        |> assoc_constraint(:source_event)

      _ ->
        changeset
    end
  end

  def get_types do
    @source_types
  end
end
