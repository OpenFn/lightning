defmodule Lightning.Strategy do
  @type t :: %__MODULE__{
          multi: Ecto.Multi.t() | nil,
          after_hooks: MapSet.t((... -> any))
        }

  defstruct [:multi, :after_hooks]

  alias Ecto.Multi

  def new(multi \\ nil) do
    struct!(__MODULE__, multi: multi, after_hooks: MapSet.new())
  end

  def insert(%__MODULE__{multi: multi} = strategy, key, changeset) do
    %__MODULE__{strategy | multi: Multi.insert(multi, key, changeset)}
  end

  def afterwards(%__MODULE__{after_hooks: hooks} = strategy, fun) do
    %__MODULE__{strategy | after_hooks: hooks |> MapSet.put(fun)}
  end

  def execute(%__MODULE__{multi: multi, after_hooks: after_hooks}) do
    multi
    |> Lightning.Repo.transaction()
    |> tap(fn result ->
      with {:ok, changes} <- result do
        Enum.each(after_hooks, fn fun -> fun.(changes) end)
      end
    end)
  end
end
