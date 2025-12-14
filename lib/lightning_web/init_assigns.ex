defmodule LightningWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """
  import Phoenix.Component
  import Phoenix.LiveView
  alias Lightning.Accounts

  def on_mount(:default, _params, session, socket) do
    current_user = Accounts.get_user_by_session_token(session["user_token"])
    confirmation_required? = Accounts.confirmation_required?(current_user)

    sidebar_collapsed =
      if current_user do
        Accounts.get_preference(current_user, "sidebar_collapsed") || false
      else
        false
      end

    {:cont,
     socket
     |> assign_new(:current_user, fn ->
       current_user
     end)
     |> assign(:sidebar_collapsed, sidebar_collapsed)
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
     |> assign_new(:gdpr_banner, fn -> Lightning.Config.gdpr_banner() end)
     |> attach_hook(:sidebar_toggle, :handle_event, &handle_sidebar_toggle/3)}
  end

  defp handle_sidebar_toggle("toggle_sidebar", _params, socket) do
    user = socket.assigns[:current_user]
    new_state = !socket.assigns.sidebar_collapsed

    socket =
      if user do
        case Accounts.update_user_preference(
               user,
               "sidebar_collapsed",
               new_state
             ) do
          {:ok, updated_user} ->
            assign(socket, :current_user, updated_user)

          {:error, _} ->
            socket
        end
      else
        socket
      end

    {:halt, assign(socket, :sidebar_collapsed, new_state)}
  end

  defp handle_sidebar_toggle(_event, _params, socket) do
    {:cont, socket}
  end
end
