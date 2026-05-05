defmodule Lightning.Collaboration.Registry do
  @moduledoc """
  Registry-helpers for collaboration processes.

  This module provides convenience helpers around the `Registry` started by
  `Lightning.Collaboration.Supervisor`. The actual registry name is resolved
  through `Lightning.Collaboration.Topology` so the same call sites work for
  the production singleton supervisor and per-test isolated supervisors.

  ## Supported Key Patterns

  - `{:shared_doc, document_name}` - SharedDoc processes for documents
    (e.g., "workflow:workflow_id")
  - `{:persistence_writer, document_name}` - PersistenceWriter processes
  - `{:doc_supervisor, document_name}` - DocumentSupervisor processes

  Session processes are not registered here as there may be multiple sessions
  for the same workflow and the same user.

  ## Registry vs Process Groups

  This Registry is used for local node process lookup and coordination, while
  `:pg` (process groups) remains for cluster-wide SharedDoc uniqueness. The
  Registry provides faster local lookups and better integration with
  supervision trees.
  """

  alias Lightning.Collaboration.Topology

  @doc """
  Register the current process with the given key in the active registry.
  """
  @spec register(term()) :: {:ok, pid()} | {:error, {:already_registered, pid()}}
  def register(key) do
    case Registry.register(Topology.registry(), key, nil) do
      {:ok, _pid} -> {:ok, self()}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns a `:via` tuple suitable for naming a process under the active
  registry.
  """
  def via(key), do: Topology.via(key)

  @doc """
  Look up all processes registered with the given key.

  Returns a list of `{pid, value}` tuples.
  """
  @spec lookup(term()) :: [{pid(), term()}]
  def lookup(key) do
    Registry.lookup(Topology.registry(), key)
  end

  @doc """
  Find the pid registered with the given key.
  """
  @spec whereis(term()) :: pid() | nil
  def whereis(key) do
    case lookup(key) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  def count(key \\ nil)

  def count(nil) do
    Registry.count(Topology.registry())
  end

  def count(key) do
    select(key) |> length()
  end

  @doc """
  Select processes whose key starts with the given binary prefix.
  """
  @spec select(binary()) :: [[term() | pid()]]
  def select(key) when is_binary(key) do
    Registry.select(Topology.registry(), [
      {{{:"$1", :"$2"}, :"$3", :"$4"},
       [{:==, {:binary_part, :"$2", 0, byte_size(key)}, key}], [[:"$1", :"$3"]]},
      {{{:"$1", :"$2", :"$5"}, :"$3", :"$4"},
       [{:==, {:binary_part, :"$2", 0, byte_size(key)}, key}], [[:"$1", :"$3"]]}
    ])
  end

  def get_group(key) do
    select(key)
    |> Enum.reduce(%{}, fn [type, pid], acc ->
      case type do
        :session ->
          Map.update(acc, :sessions, [pid], fn existing -> existing ++ [pid] end)

        _ ->
          Map.put(acc, type, pid)
      end
    end)
  end
end
