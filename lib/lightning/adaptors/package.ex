defmodule Lightning.Adaptors.Package do
  @moduledoc false

  @type t :: %__MODULE__{
          name: String.t(),
          repo: String.t(),
          latest: String.t(),
          versions: [%{version: String.t()}]
        }

  defstruct [:name, :repo, :latest, :versions]
end
