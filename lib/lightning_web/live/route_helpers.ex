defmodule LightningWeb.RouteHelpers do
  @moduledoc """
  Convenience functions for generating paths.
  """
  alias LightningWeb.Router.Helpers, as: Routes

  def workflow_new_job_path(project_id) do
    Routes.project_workflow_path(LightningWeb.Endpoint, :new_job, project_id)
  end

  def workflow_edit_job_path(project_id, job_id) do
    Routes.project_workflow_path(
      LightningWeb.Endpoint,
      :edit_job,
      project_id,
      job_id
    )
  end
end
