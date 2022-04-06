defmodule LightningWeb.Plugs.FirstSetup do
  @moduledoc """
  Plug to redirect HTTP requests to `/first_setup` if there are no
  superusers in the system yet.
  """
  use LightningWeb, :controller
  alias Lightning.Users

  def init(opts), do: opts

  def call(%{request_path: "/first_setup"} = conn, _opts) do
    if Users.has_one_superuser?() do
      conn |> redirect(to: "/") |> halt()
    else
      conn
    end
  end

  def call(conn, _opts) do
    if Users.has_one_superuser?() do
      conn
    else
      conn |> redirect(to: "/first_setup") |> halt()
    end
  end
end
