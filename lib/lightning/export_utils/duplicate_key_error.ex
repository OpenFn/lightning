defmodule Lightning.ExportUtils.DuplicateKeyError do
  @moduledoc """
  Raised when two entities in a project would be written into the project spec
  under the same key.

  A key is how the CLI addresses an entity, so two landing on the same key is
  data loss: the second silently replaces the first. Keys are the entity's name
  with each space turned into a hyphen, so `a b` and `a-b` collide.

  Edge keys are exempt; see `disambiguate_edge_keys/1` in `ExportUtils`.
  """
  defexception [:kind, :key, :first, :second]

  @type t :: %__MODULE__{
          kind: String.t(),
          key: String.t(),
          first: String.t(),
          second: String.t()
        }

  @impl true
  def message(%__MODULE__{kind: kind, key: key, first: first, second: second}) do
    "two #{kind} in this project are both written as #{inspect(key)} in the " <>
      "project spec: #{inspect(first)} and #{inspect(second)}. Rename one of " <>
      "them and export again."
  end
end
