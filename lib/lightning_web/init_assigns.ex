defmodule LightningWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """
  import Phoenix.LiveView
  alias Lightning.Accounts

  defp assign_current_user_from_session(socket, session) do
    user_token = session["user_token"]
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(socket, :current_user, user)
  end

  def on_mount(:default, _params, session, socket) do
    {:cont, assign_current_user_from_session(socket, session)}
  end
end
