defmodule LightningWeb.RouteHelpers do
  @moduledoc """
  Convenience functions for generating paths.
  """
  alias LightningWeb.Router.Helpers, as: Routes

  def workflow_edit_job_path(project_id, workflow_id, job_id) do
    Routes.project_process_path(
      LightningWeb.Endpoint,
      :edit_job,
      project_id,
      workflow_id,
      job_id
    )
  end

  def show_run_path(project_id, run_id) do
    Routes.project_run_show_path(
      LightningWeb.Endpoint,
      :show,
      project_id,
      run_id
    )
  end
end
