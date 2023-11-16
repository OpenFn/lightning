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
  * `:run_result`
    The final state of a successful run.
  * `:saved_input`
    An arbitrary input, created by a user. (Only configuration will be overwritten.)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Invocation.Run
  alias Lightning.Projects.Project

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          project_id: Ecto.UUID.t() | nil,
          body: %{} | nil,
          source_run: Run.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @type source_type :: :http_request | :global | :run_result | :saved_input
  @source_types [:http_request, :global, :run_result, :saved_input]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "dataclips" do
    field :body, :map, load_in_query: false
    field :type, Ecto.Enum, values: @source_types
    belongs_to :project, Project

    has_one :source_run, Run, foreign_key: :output_dataclip_id

    timestamps(type: :utc_datetime_usec)
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{id: Ecto.UUID.generate()}, attrs)
    |> change(attrs)
    |> redact_password()
    |> validate()
  end

  defp redact_password(
         %Ecto.Changeset{
           valid?: true,
           changes: %{
             body: %{"configuration" => %{"password" => _password}} = body
           }
         } =
           changeset
       ) do
    body =
      update_in(body, ["configuration", "password"], fn _any -> "***" end)

    put_change(changeset, :body, body)
  end

  defp redact_password(changeset), do: changeset

  @doc false
  def changeset(dataclip, attrs) do
    dataclip
    |> cast(attrs, [:body, :type, :project_id])
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

  - `:run_result` must have an associated Run model.
  """
  def validate_by_type(changeset) do
    changeset
    |> fetch_field!(:type)
    |> case do
      :run_result ->
        changeset
        |> foreign_key_constraint(:source_run)

      _ ->
        changeset
    end
  end

  defp validate(changeset) do
    changeset
    |> validate_by_type()
  end

  def get_types do
    @source_types
  end
end
