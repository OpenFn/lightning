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
    Application.ensure_all_started(:timex)

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Lightning.Repo, fn _repo ->
        SetupUtils.tear_down(destroy_super: true)
        SetupUtils.setup_demo(create_super: true)
      end)
  end
end
