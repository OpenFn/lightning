defmodule LightningWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """
  import Phoenix.Component
  alias Lightning.Accounts

  def on_mount(:default, _params, session, socket) do
    current_user = Accounts.get_user_by_session_token(session["user_token"])
    confirmation_required? = Accounts.confirmation_required?(current_user)

    {:cont,
     socket
     |> assign_new(:current_user, fn ->
       current_user
     end)
     |> assign_new(:account_confirmation_required?, fn ->
       confirmation_required?
     end)
     |> assign(:side_menu_theme, "primary-theme")}
  end
end
