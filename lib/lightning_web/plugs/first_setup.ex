defmodule LightningWeb.Plugs.FirstSetup do
  @moduledoc """
  Plug to redirect HTTP requests to `/first_setup` if there are no
  superusers in the system yet, unless first setup is disabled.
  """
  use LightningWeb, :controller
  alias Lightning.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    if Lightning.Config.check_flag?(:allow_first_setup) do
      redirect_to_first_setup(conn)
    else
      conn
    end
  end

  defp redirect_to_first_setup(%{request_path: "/first_setup"} = conn) do
    if Accounts.has_one_superuser?() do
      conn |> redirect(to: "/projects") |> halt()
    else
      conn
    end
  end

  defp redirect_to_first_setup(conn) do
    if Accounts.has_one_superuser?() do
      conn
    else
      conn |> redirect(to: "/first_setup") |> halt()
    end
  end
end
