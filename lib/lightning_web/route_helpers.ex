defmodule LightningWeb.RouteHelpers do
  @moduledoc """
  Convenience functions for generating paths.
  """
  alias LightningWeb.Router.Helpers, as: Routes

  def show_attempt_url(project_id, attempt_id) do
    Routes.project_attempt_show_url(
      LightningWeb.Endpoint,
      :show,
      project_id,
      attempt_id
    )
  end

  def oidc_callback_url do
    Routes.oidc_url(LightningWeb.Endpoint, :new)
  end
end
