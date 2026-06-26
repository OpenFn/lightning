defmodule Lightning.ConnectedSystems do
  @moduledoc """
  The Connected Systems registry: an instance-wide catalog of the external
  systems an organization works with, kept separate from the secrets needed to
  reach them.

  Entries are instance-scoped (there is no Organization entity); "organization
  wide" is realized by syncing the registry across instances. See
  `Lightning.ConnectedSystems.ConnectedSystem` for the schema.
  """
  import Ecto.Query

  alias Lightning.ConnectedSystems.ConnectedSystem
  alias Lightning.Repo

  @doc """
  Returns the list of connected systems.

  ## Options

    - `:order_by` - ordering for the results. Defaults to `[asc: :name]`.
    - `:preload` - associations to preload. Defaults to `[]`.
  """
  @spec list_connected_systems(keyword()) :: [ConnectedSystem.t()]
  def list_connected_systems(opts \\ []) do
    order_by = Keyword.get(opts, :order_by, asc: :name)
    preload = Keyword.get(opts, :preload, [])

    Repo.all(
      from(s in ConnectedSystem, order_by: ^order_by, preload: ^preload)
    )
  end

  @spec get_connected_system!(Ecto.UUID.t()) :: ConnectedSystem.t()
  def get_connected_system!(id), do: Repo.get!(ConnectedSystem, id)

  @spec get_connected_system(Ecto.UUID.t()) :: ConnectedSystem.t() | nil
  def get_connected_system(id), do: Repo.get(ConnectedSystem, id)

  @doc """
  Looks up a connected system by its stable `slug`.

  Used when resolving references carried in synced project configuration.
  """
  @spec get_connected_system_by_slug(String.t()) ::
          {:ok, ConnectedSystem.t()} | {:error, :not_found}
  def get_connected_system_by_slug(slug) do
    case Repo.get_by(ConnectedSystem, slug: slug) do
      nil -> {:error, :not_found}
      connected_system -> {:ok, connected_system}
    end
  end

  @spec create_connected_system(map()) ::
          {:ok, ConnectedSystem.t()} | {:error, Ecto.Changeset.t()}
  def create_connected_system(attrs) do
    %ConnectedSystem{}
    |> ConnectedSystem.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_connected_system(ConnectedSystem.t(), map()) ::
          {:ok, ConnectedSystem.t()} | {:error, Ecto.Changeset.t()}
  def update_connected_system(%ConnectedSystem{} = connected_system, attrs) do
    connected_system
    |> ConnectedSystem.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_connected_system(Ecto.UUID.t()) ::
          {:ok, ConnectedSystem.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :not_found}
  def delete_connected_system(id) do
    case Repo.get(ConnectedSystem, id) do
      nil -> {:error, :not_found}
      connected_system -> Repo.delete(connected_system)
    end
  end

  @spec change_connected_system(ConnectedSystem.t(), map()) ::
          Ecto.Changeset.t()
  def change_connected_system(%ConnectedSystem{} = connected_system, attrs \\ %{}) do
    ConnectedSystem.changeset(connected_system, attrs)
  end
end
