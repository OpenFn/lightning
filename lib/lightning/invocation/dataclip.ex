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
  * `:step_result`
    The final state of a step.
  * `:saved_input`
    An arbitrary input, created by a user. (Only configuration will be overwritten.)
  """
  use Lightning.Schema

  alias Lightning.Invocation.Step
  alias Lightning.Projects.Project

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          project_id: Ecto.UUID.t() | nil,
          body: %{} | String.t() | nil,
          request: %{} | nil,
          source_step: Step.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @type source_type ::
          :http_request | :global | :step_result | :saved_input | :kafka
  @source_types [:http_request, :global, :step_result, :saved_input, :kafka]

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :body,
             :request,
             :type,
             :wiped_at,
             :project_id,
             :inserted_at,
             :updated_at
           ]}

  schema "dataclips" do
    field :name, :string
    field :body, :map, load_in_query: false
    field :request, :map, load_in_query: false
    field :type, Ecto.Enum, values: @source_types
    field :wiped_at, :utc_datetime
    belongs_to :project, Project

    has_one :source_step, Step, foreign_key: :output_dataclip_id

    timestamps(type: :utc_datetime_usec)
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{id: Ecto.UUID.generate()}, attrs)
    |> remove_configuration()
    |> validate()
  end

  defp remove_configuration(%{valid?: true} = changeset) do
    case get_change(changeset, :body) do
      %{} = body ->
        body = Map.delete(body, "configuration")
        put_change(changeset, :body, body)

      nil ->
        changeset

      _other ->
        add_error(changeset, :body, "must be a map")
    end
  end

  defp remove_configuration(changeset) do
    changeset
  end

  @doc false
  def changeset(dataclip, attrs) do
    dataclip
    |> cast(attrs, [:name, :body, :type, :project_id])
    |> case do
      %{action: :delete} = c ->
        c |> validate_required([:type]) |> Map.put(:action, :update)

      c ->
        c |> validate_required([:type, :body])
    end
    |> validate()
  end

  @doc """
  Append validations based on the type of the Dataclip.

  - `:step_result` must have an associated Step model.
  """
  def validate_by_type(changeset) do
    changeset
    |> fetch_field!(:type)
    |> case do
      :step_result ->
        changeset
        |> foreign_key_constraint(:source_step)

      _other ->
        changeset
    end
  end

  defp validate_request(changeset) do
    request = fetch_field!(changeset, :request)
    type = fetch_field!(changeset, :type)

    case {type, request} do
      {:kafka, nil} ->
        add_error(changeset, :request, "must be set for kafka type")

      {:http_request, _request} ->
        changeset

      {:kafka, _request} ->
        changeset

      {_, request} when not is_nil(request) ->
        add_error(changeset, :request, "cannot be set for this type")

      {_, _} ->
        changeset
    end
  end

  defp validate(changeset) do
    changeset
    |> validate_request()
    |> validate_by_type()
  end

  def source_types do
    @source_types
  end
end
