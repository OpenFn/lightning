defmodule LightningWeb.RouteHelpers do
  @moduledoc """
  Convenience functions for generating paths.
  """
  alias LightningWeb.Router.Helpers, as: Routes

  def show_run_url(project_id, run_id) do
    Routes.project_run_show_url(
      LightningWeb.Endpoint,
      :show,
      project_id,
      run_id
    )
  end

  def oidc_callback_url do
    Routes.oidc_url(LightningWeb.Endpoint, :new)
  end
end
