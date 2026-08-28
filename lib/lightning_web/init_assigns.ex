defmodule LightningWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """
  import Phoenix.Component
  import Phoenix.LiveView
  alias Lightning.Accounts

  def on_mount(:default, _params, session, socket) do
    current_user =
      case session["user_token"] do
        nil -> nil
        token -> Accounts.get_user_by_session_token(token)
      end

    if current_user && Accounts.locked_out?(current_user) do
      {:halt,
       socket
       |> put_flash(:error, LightningWeb.ConfirmationLockout.message())
       |> redirect(to: LightningWeb.ConfirmationLockout.redirect_path())}
    else
      {:cont, assign_defaults(socket, current_user)}
    end
  end

  defp assign_defaults(socket, current_user) do
    sidebar_collapsed =
      if current_user do
        Accounts.get_preference(current_user, "sidebar_collapsed") || false
      else
        false
      end

    socket
    |> assign_new(:current_user, fn ->
      current_user
    end)
    |> assign(:sidebar_collapsed, sidebar_collapsed)
    |> assign_new(:banner, fn ->
      if current_user && Lightning.Config.book_demo_banner_enabled?() &&
           is_nil(current_user.preferences["demo_banner.dismissed_at"]) do
        %{
          function: &LightningWeb.LiveHelpers.book_demo_banner/1,
          attrs: %{current_user: current_user}
        }
      end
    end)
    |> assign_new(:gdpr_banner, fn -> Lightning.Config.gdpr_banner() end)
    |> attach_hook(:sidebar_toggle, :handle_event, &handle_sidebar_toggle/3)
    |> try_attach_current_path()
  end

  # `attach_hook/4` with `:handle_params` requires a LiveView mounted via
  # the router. Unit tests that exercise `on_mount/4` with a bare socket
  # will blow up otherwise — skip silently in that case.
  defp try_attach_current_path(socket) do
    attach_hook(socket, :current_path, :handle_params, &assign_current_path/3)
  rescue
    RuntimeError -> socket
  end

  # `:current_path` stays query-free — the project picker splits it on `/`.
  # `:current_uri` keeps the query for anything that needs to reproduce the
  # request, such as re-mounting the socket where the user left off.
  defp assign_current_path(_params, uri, socket) do
    parsed = if is_binary(uri), do: URI.parse(uri), else: %URI{}
    path = parsed.path

    current_uri = if parsed.query, do: "#{path}?#{parsed.query}", else: path

    {:cont,
     socket
     |> assign(:current_path, path)
     |> assign(:current_uri, current_uri)}
  end

  defp handle_sidebar_toggle("toggle_sidebar", _params, socket) do
    new_state = !socket.assigns.sidebar_collapsed
    user = socket.assigns.current_user

    {:ok, updated_user} =
      Accounts.update_user_preference(user, "sidebar_collapsed", new_state)

    {:halt,
     socket
     |> assign(:current_user, updated_user)
     |> assign(:sidebar_collapsed, new_state)}
  end

  defp handle_sidebar_toggle(_event, _params, socket) do
    {:cont, socket}
  end
end
