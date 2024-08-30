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
    if Application.get_env(:lightning, :is_resettable_demo) do
      {:ok, _pid} = Lightning.Setup.ensure_minimum_setup()

      {:ok, _, _} =
        Ecto.Migrator.with_repo(Lightning.Repo, fn _repo ->
          SetupUtils.tear_down(destroy_super: true)
          SetupUtils.setup_demo(create_super: true)
        end)
    else
      IO.puts("I'm sorry, Dave. I'm afraid I can't do that.")
    end
  end
end
