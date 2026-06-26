defmodule Lightning.ConnectedSystems do
  @moduledoc """
  The Connected Systems context.

  A Connected System is an organization-wide catalog entry describing an external
  system the organization connects to. Entries are managed at the deployment
  level (not scoped to a single project) and hold no secrets: a `name` unique
  within the deployment and a `type` linking to the relevant adaptor.

  Credentials can reference a Connected System, which lets the systems a project
  expects to talk to travel with its configuration while the secrets stay behind.
  """

  import Ecto.Query, warn: false

  alias Lightning.ConnectedSystems.ConnectedSystem
  alias Lightning.Repo

  @doc """
  Returns the list of connected systems, ordered by name.
  """
  @spec list_connected_systems() :: [ConnectedSystem.t()]
  def list_connected_systems do
    ConnectedSystem
    |> order_by([cs], asc: cs.name)
    |> Repo.all()
  end

  @doc """
  Gets a single connected system. Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_connected_system!(Ecto.UUID.t()) :: ConnectedSystem.t()
  def get_connected_system!(id), do: Repo.get!(ConnectedSystem, id)

  @doc """
  Gets a single connected system by name, returning `nil` if not found.
  """
  @spec get_connected_system_by_name(String.t()) :: ConnectedSystem.t() | nil
  def get_connected_system_by_name(name) when is_binary(name) do
    Repo.get_by(ConnectedSystem, name: name)
  end

  @doc """
  Creates a connected system.
  """
  @spec create_connected_system(map()) ::
          {:ok, ConnectedSystem.t()} | {:error, Ecto.Changeset.t()}
  def create_connected_system(attrs \\ %{}) do
    %ConnectedSystem{}
    |> ConnectedSystem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a connected system.
  """
  @spec update_connected_system(ConnectedSystem.t(), map()) ::
          {:ok, ConnectedSystem.t()} | {:error, Ecto.Changeset.t()}
  def update_connected_system(%ConnectedSystem{} = connected_system, attrs) do
    connected_system
    |> ConnectedSystem.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a connected system. Credentials referencing it have their reference
  cleared (the credential itself is preserved).
  """
  @spec delete_connected_system(ConnectedSystem.t()) ::
          {:ok, ConnectedSystem.t()} | {:error, Ecto.Changeset.t()}
  def delete_connected_system(%ConnectedSystem{} = connected_system) do
    Repo.delete(connected_system)
  end

  @doc """
  Returns a changeset for tracking connected system changes.
  """
  @spec change_connected_system(ConnectedSystem.t(), map()) ::
          Ecto.Changeset.t()
  def change_connected_system(%ConnectedSystem{} = connected_system, attrs \\ %{}) do
    ConnectedSystem.changeset(connected_system, attrs)
  end
end
