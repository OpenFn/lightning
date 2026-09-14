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
    {:ok, _, _} =
      with_minimum_setup(fn ->
        SetupUtils.setup_user(user, token, credentials)
      end)
  end

  @doc """
  Runs `fun` with the bare minimum an out-of-band command needs: the vault
  (credential bodies are encrypted), a stub PubSub, the repo, and the adaptors
  subsystem (job and credential validation resolves adaptor names against it).
  The endpoint stays down - these commands often run against an instance that
  is already serving traffic, and booting it here would fight the running
  server for the port.

  Idempotent, so it is equally safe on a cold BEAM or inside the booted
  application.
  """
  @spec with_minimum_setup((-> result)) ::
          {:ok, result, [atom()]} | {:error, term()}
        when result: term()
  def with_minimum_setup(fun) when is_function(fun, 0) do
    {:ok, _pid} = ensure_minimum_setup()

    Ecto.Migrator.with_repo(Lightning.Repo, fn _repo ->
      {:ok, _pid} = Lightning.Adaptors.Supervisor.ensure_started()
      fun.()
    end)
  end

  @deprecated "Use with_minimum_setup/1 instead"
  def ensure_minimum_setup do
    Lightning.Release.load_app()

    children =
      [
        {Phoenix.PubSub,
         name: Lightning.PubSub, adapter: Lightning.Setup.FakePubSub},
        {Lightning.Vault, Application.get_env(:lightning, Lightning.Vault, [])}
      ]
      |> Enum.reject(fn {mod, opts} ->
        Process.whereis(Keyword.get(opts, :name, mod))
      end)

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
