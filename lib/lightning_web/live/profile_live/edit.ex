defmodule LightningWeb.ProfileLive.Edit do
  @moduledoc """
  LiveView for editing a single dataclip, which inturn uses
  `LightningWeb.JobLive.JobFormComponent` for common functionality.
  """
  use LightningWeb, :live_view
  alias Lightning.Accounts
  # alias LightningWeb.UserAuth

  # import Plug.Conn
  # @behaviour Plug

  # plug :assign_email_and_password_changesets

  # alias Lightning.Invocation

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     apply_action(
       socket,
       socket.assigns.live_action,
       socket.assigns.current_user
     )}
  end

  defp apply_action(socket, :edit, params) do
    socket
    |> assign(:page_title, "Settings")
    |> assign(:email_changeset, Accounts.change_user_email(params))
    |> assign(:password_changeset, Accounts.change_user_password(params))
    # |> assign(:current_user, params)
  end

  # defp assign_email_and_password_changesets(conn, _opts) do
  #   user = conn.assigns.current_user

  #   conn
  #   |> assign(:email_changeset, Accounts.change_user_email(user))
  #   |> assign(:password_changeset, Accounts.change_user_password(user))
  # end
end
