defmodule Lightning.ExportUtils.DuplicateKeyError do
  @moduledoc """
  Raised when two entities in a project would be written into the project spec
  under the same key.

  A workflow, job, credential, collection or channel key is how the CLI
  addresses that entity, so two of them landing on the same key is data loss:
  the second silently replaces the first, and a round trip through the spec
  comes back with one fewer entity than it started with. The export used to do
  exactly that, quietly.

  Keys are the entity's name with each space turned into a hyphen, so `a b` and
  `a-b` collide even though they read as two different names.

  Edge keys are deliberately not in this list. Nothing parses them and the edge
  body carries its own identity in `source_job`, `source_trigger` and
  `target_job`, so a collision there is disambiguated rather than refused.
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
