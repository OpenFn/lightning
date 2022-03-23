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

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "dataclips" do
    field :body, :map
    field :type, Ecto.Enum, values: [:http_request, :global]

    timestamps(usec: true)
  end

  @doc false
  def changeset(dataclip, attrs) do
    dataclip
    |> cast(attrs, [:body, :type])
    |> validate_required([:body, :type])
  end
end
