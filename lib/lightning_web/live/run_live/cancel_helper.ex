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
    with true <- Lightning.Validators.valid_uuid?(run_id),
         %Run{} = run <- Runs.get_for_project(run_id, project_id) do
      Runs.cancel_run(run)
    else
      _not_found -> {:error, :not_found}
    end
  end
end
