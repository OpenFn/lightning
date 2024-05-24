defmodule LightningWeb.API.RegistrationController do
  use LightningWeb, :controller

  @extensions Application.compile_env(
                :lightning,
                Lightning.Extensions
              )

  def create(conn, _params) do
    external_controller = Keyword.fetch!(@extensions, :registration_controller)
    external_controller.call(conn, :create)
  end
end
