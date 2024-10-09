defmodule LightningWeb.RouteHelpers do
  @moduledoc """
  Convenience functions for generating paths.
  """
  alias LightningWeb.Router.Helpers, as: Routes

  def project_dashboard_url(project_id) do
    Routes.project_workflow_index_url(
      LightningWeb.Endpoint,
      :index,
      project_id
    )
  end

  def oidc_callback_url do
    Routes.oidc_url(LightningWeb.Endpoint, :new)
  end
end
