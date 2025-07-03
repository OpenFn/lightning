defmodule Lightning.Adaptors.Registry do
  @moduledoc """
  Local process storage for Adaptors instances.
  """

  @type role :: term()
  @type key ::
          Lightning.Adaptors.API.name() | {Lightning.Adaptors.API.name(), role()}
  @type value :: term()

  @doc false
  def child_spec(_arg) do
    [keys: :unique, name: __MODULE__]
    |> Registry.child_spec()
  end

  @doc """
  Fetch the config for an Adaptors supervisor instance.

  ## Example

  Get the default instance config:

      Lightning.Adaptors.Registry.config(Lightning.Adaptors)

  Get config for a custom named instance:

      Lightning.Adaptors.Registry.config(MyApp.Adaptors)
  """
  @spec config(Lightning.Adaptors.API.name()) :: Lightning.Adaptors.API.config()
  def config(adaptors_name) do
    case lookup(adaptors_name) do
      {_pid, config} ->
        config

      _ ->
        raise RuntimeError, """
        No Adaptors instance named `#{inspect(adaptors_name)}` is running and config isn't available.
        """
    end
  end

  @doc """
  Find the `{pid, value}` pair for a registered Adaptors process.

  ## Example

  Get the default instance config:

      Lightning.Adaptors.Registry.lookup(Lightning.Adaptors)

  Get a supervised module's pid:

      Lightning.Adaptors.Registry.lookup(Lightning.Adaptors, :cache)
  """
  @spec lookup(Lightning.Adaptors.API.name(), role()) :: nil | {pid(), value()}
  def lookup(adaptors_name, role \\ nil) do
    __MODULE__
    |> Registry.lookup(key(adaptors_name, role))
    |> List.first()
  end

  @doc """
  Returns the pid of a supervised Adaptors process, or `nil` if the process can't be found.

  ## Example

  Get the Adaptors supervisor's pid:

      Lightning.Adaptors.Registry.whereis(Lightning.Adaptors)

  Get a supervised module's pid:

      Lightning.Adaptors.Registry.whereis(Lightning.Adaptors, :cache)
  """
  @spec whereis(Lightning.Adaptors.API.name(), role()) ::
          pid() | {atom(), node()} | nil
  def whereis(adaptors_name, role \\ nil) do
    adaptors_name
    |> via(role)
    |> GenServer.whereis()
  end

  @doc """
  Build a via tuple suitable for calls to a supervised Adaptors process.

  ## Example

  For an Adaptors supervisor:

      Lightning.Adaptors.Registry.via(Lightning.Adaptors)

  For a supervised module:

      Lightning.Adaptors.Registry.via(Lightning.Adaptors, :cache)
  """
  @spec via(Lightning.Adaptors.API.name(), role(), value()) ::
          {:via, Registry, {__MODULE__, key()}}
  def via(adaptors_name, role \\ nil, value \\ nil)

  def via(adaptors_name, role, nil),
    do: {:via, Registry, {__MODULE__, key(adaptors_name, role)}}

  def via(adaptors_name, role, value),
    do: {:via, Registry, {__MODULE__, key(adaptors_name, role), value}}

  defp key(adaptors_name, nil), do: adaptors_name
  defp key(adaptors_name, role), do: {adaptors_name, role}
end
