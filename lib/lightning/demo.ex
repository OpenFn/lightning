defmodule Lightning.Demo do
  @moduledoc """
  Demo encapsulates logic for setting up a demonstration site.
  """

  alias Lightning.SetupUtils

  @doc """
  Deletes everything in the database including the superuser and creates a set
  of publicly available users for a demo site via a command that can be run on
  Kubernetes-deployed systems.
  """
  def reset_demo do
    Lightning.Release.load_app()

    children =
      [
        {Phoenix.PubSub,
         name: Lightning.PubSub, adapter: Lightning.Demo.FakePubSub},
        {Lightning.Vault, Application.get_env(:lightning, Lightning.Vault, [])}
      ]
      |> Enum.reject(fn {mod, _} -> Process.whereis(mod) end)

    Supervisor.start_link(children, strategy: :one_for_one)

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Lightning.Repo, fn _repo ->
        SetupUtils.tear_down(destroy_super: true)
        SetupUtils.setup_demo(create_super: true)
      end)
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
