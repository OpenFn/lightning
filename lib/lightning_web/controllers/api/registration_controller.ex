defmodule LightningWeb.API.RegistrationController do
  use LightningWeb, :controller

  alias LightningWeb.API.Problem

  def create(conn, _params) do
    Lightning.Config.get_extension_mod(:registration_controller)
    |> case do
      nil ->
        Problem.respond(conn, Problem.new(:not_implemented))

      controller ->
        controller.call(conn, :create)
    end
  end
end
