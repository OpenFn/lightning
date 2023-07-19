defmodule LightningWeb.UserTOTPController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias LightningWeb.UserAuth
  alias Lightning.Accounts.User

  def new(conn, _params) do
    render(conn, "new.html", error_message: nil)
  end
end
