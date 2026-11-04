defmodule LightningWeb.RunLive.CancelHelper do
  @moduledoc """
  Shared logic for cancelling individual runs from LiveViews.
  """

  alias Lightning.Run
  alias Lightning.Runs

  @spec cancel_run(String.t(), Ecto.UUID.t()) ::
          {:ok, Run.t()}
          | {:error, :not_found | :not_available | Ecto.Changeset.t()}
  def cancel_run(run_id, project_id) do
    with {:ok, run} <- Runs.get_for_project(project_id, run_id),
         do: Runs.cancel_run(run)
  end
end
