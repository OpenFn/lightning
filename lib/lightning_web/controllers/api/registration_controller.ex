defmodule LightningWeb.API.RegistrationController do
  use LightningWeb, :controller

  def create(conn, _params) do
    Lightning.Config.get_extension_mod(:registration_controller)
    |> case do
      nil ->
        conn |> put_status(501) |> json(%{error: "Not Implemented"})

      controller ->
        controller.call(conn, :create)
    end
  end
end
