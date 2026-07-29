defmodule Lightning.Setup do
  @moduledoc """
  Demo encapsulates logic for setting up a demonstration site.
  """

  alias Lightning.SetupUtils

  @doc """
  This makes it possible to run setup_user as an external command

  See: Lightning.SetupUtils.setup_user() for more docs.

  ## Examples

    iex> kubectl exec -it deploy/demo-web -- /app/bin/lightning eval Lightning.Setup.setup_user(%{email: "td@openfn.org", first_name: "taylor", last_name: "downs", password: "shh12345!"})
    :ok

  """
  @spec setup_user(map(), String.t() | nil, list(map()) | nil) ::
          {:ok, any(), any()} | {:error, any()}
  def setup_user(user, token \\ nil, credentials \\ nil) do
    {:ok, _pid} = Lightning.Setup.ensure_minimum_setup()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Lightning.Repo, fn _repo ->
        SetupUtils.setup_user(user, token, credentials)
      end)
  end

  @doc """
  Bootstrap the instance from a declarative scenario file, without needing the
  full application running. See `Lightning.Bootstrap` for the file format.

  Designed for release environments:

      bin/lightning eval 'Lightning.Setup.bootstrap("/etc/lightning/state.yaml")'
      bin/lightning eval 'Lightning.Setup.bootstrap("/state.yaml", manifest: "/state.manifest.json")'

  Requires `ALLOW_BOOTSTRAP=true` in a release. Prints a summary of the
  records; pass `manifest: path` to also write the JSON manifest (ids, API
  tokens, webhook paths) for consumption by scripts or test harnesses.
  """
  @spec bootstrap(Path.t(), keyword()) :: Lightning.Bootstrap.result()
  def bootstrap(path, opts \\ []) do
    {:ok, _pid} = ensure_minimum_setup()

    {:ok, result, _apps} =
      Ecto.Migrator.with_repo(Lightning.Repo, fn _repo ->
        Lightning.Bootstrap.run_file(path, opts)
      end)

    IO.puts(Lightning.Bootstrap.summary(result))
    result
  end

  @doc """
  Set up the bare minimum so that commands can be executed against the repo.
  """
  def ensure_minimum_setup do
    Lightning.Release.load_app()

    children =
      [
        {Phoenix.PubSub,
         name: Lightning.PubSub, adapter: Lightning.Setup.FakePubSub},
        {Lightning.Vault, Application.get_env(:lightning, Lightning.Vault, [])}
      ]
      |> Enum.reject(fn {mod, _} -> Process.whereis(mod) end)

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defmodule FakePubSub do
    @moduledoc false

    # FakePubSub is a Phoenix.PubSub adapter that does nothing.
    # The purpose of this adapter is to allow the demo to run without
    # the whole application running.

    @behaviour Phoenix.PubSub.Adapter

    @impl true
    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
    end

    def start_link do
      {:ok, self()}
    end

    @impl true
    def node_name(_), do: nil

    @impl true
    def broadcast(_, _, _, _) do
      :ok
    end

    @impl true
    def direct_broadcast(_, _, _, _, _) do
      :ok
    end
  end
end
