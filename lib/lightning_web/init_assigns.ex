defmodule LightningWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """
  import Phoenix.Component
  alias Lightning.Accounts

  def on_mount(:default, _params, session, socket) do
    {:cont,
     assign_new(socket, :current_user, fn ->
       Accounts.get_user_by_session_token(session["user_token"])
     end)}
  end
end
