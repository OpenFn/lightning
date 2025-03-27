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
     |> assign_new(:banner, fn ->
       if Lightning.Config.book_demo_banner_enabled?() and
            is_nil(current_user.preferences["demo_banner.dismissed_at"]) do
         %{
           function: &LightningWeb.LiveHelpers.book_demo_banner/1,
           attrs: %{current_user: current_user}
         }
       end
     end)
     |> assign_new(:gdpr_banner, fn -> Lightning.Config.gdpr_banner() end)}
  end
end
