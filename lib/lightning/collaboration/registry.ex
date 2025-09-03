defmodule Lightning.Collaboration.Registry do
  @moduledoc """
  Registry for collaboration processes.

  This Registry provides local process tracking for the collaboration system,
  complementing the cluster-wide :pg process groups. It supports the following
  key patterns:

  ## Supported Key Patterns

  - `{:shared_doc, document_name}` - SharedDoc processes for documents (e.g., "workflow:workflow_id")
  - `{:persistence_writer, document_name}` - PersistenceWriter processes (future use)
  - `{:doc_supervisor, workflow_id}` - DocumentSupervisor processes (future use)

  Session processes are not registered here as there may be multiple sessions
  for the same workflow and the same user.

  ## Registry vs Process Groups

  This Registry is used for local node process lookup and coordination, while
  `:pg` (process groups) remains for cluster-wide SharedDoc uniqueness. The
  Registry provides faster local lookups and better integration with supervision
  trees.

  ## Usage

  Processes can register themselves either in their init callback or using via tuples
  in their child_spec:

      # Session registration in init callback
      Lightning.Collaboration.Registry.register({:session, "workflow_123", "user_456"})

      # SharedDoc registration via child_spec
      {SharedDoc, [
        doc_name: "workflow:workflow_123",
        name: {:via, Registry, {Lightning.Collaboration.Registry.registry_name(), {:shared_doc, "workflow:workflow_123"}}}
      ]}
  """

  @registry_name __MODULE__

  @doc """
  Child specification for starting the Registry.
  """
  def child_spec(_opts) do
    %{
      id: @registry_name,
      start: {Registry, :start_link, [[keys: :unique, name: @registry_name]]},
      type: :supervisor
    }
  end

  @doc """
  Register the current process with the given key.

  ## Examples

      Lightning.Collaboration.Registry.register({:session, "workflow_123"})
      # => {:ok, #PID<0.123.0>}

      Lightning.Collaboration.Registry.register({:shared_doc, "workflow:workflow_123"})
      # => {:ok, #PID<0.123.0>}

  ## Error Cases

      Lightning.Collaboration.Registry.register({:session, "workflow_123"})
      # => {:error, {:already_registered, #PID<0.456.0>}}

  """
  @spec register(term()) :: {:ok, pid()} | {:error, {:already_registered, pid()}}
  def register(key) do
    case Registry.register(@registry_name, key, nil) do
      {:ok, _pid} -> {:ok, self()}
      {:error, reason} -> {:error, reason}
    end
  end

  def via(key) do
    {:via, Registry, {@registry_name, key}}
  end

  @doc """
  Look up all processes registered with the given key.

  Returns a list of {pid, value} tuples. Since we use unique keys,
  this will typically return a single-item list or an empty list.

  ## Examples

      Lightning.Collaboration.Registry.lookup({:session, "workflow_123"})
      # => [{#PID<0.123.0>, nil}]

      Lightning.Collaboration.Registry.lookup({:session, "nonexistent"})
      # => []

  """
  @spec lookup(term()) :: [{pid(), term()}]
  def lookup(key) do
    Registry.lookup(@registry_name, key)
  end

  @doc """
  Find the pid registered with the given key.

  This is a convenience function that returns just the pid, or nil
  if no process is registered.

  ## Examples

      Lightning.Collaboration.Registry.whereis({:session, "workflow_123"})
      # => #PID<0.123.0>

      Lightning.Collaboration.Registry.whereis({:session, "nonexistent"})
      # => nil

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
    Registry.count(@registry_name)
  end

  def count(key) do
    select(key) |> length()
  end

  def select(key) when is_binary(key) do
    Registry.select(@registry_name, [
      {{{:"$1", key}, :"$2", :_}, [], [[:"$1", :"$2"]]}
    ])
  end

  def get_group(key) do
    select(key) |> Map.new(fn [type, pid] -> {type, pid} end)
  end

  @doc """
  Get the registry name.

  This is useful when processes need to register using via tuples.
  """
  @spec registry_name() :: atom()
  def registry_name, do: @registry_name
end
