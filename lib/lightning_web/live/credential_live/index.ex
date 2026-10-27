defmodule LightningWeb.CredentialLive.Index do
  @moduledoc """
  The user's Credentials page: their own credentials and OAuth clients,
  drawn by the design system's CredentialsIndexPage. Its events are the
  credential index's, answered by `CredentialIndex`.
  """
  use LightningWeb, :live_view

  alias LightningWeb.CredentialLive.CredentialIndex

  on_mount {LightningWeb.Hooks, :assign_projects}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       active_menu_item: :credentials,
       page_title: "Credentials",
       project: nil
     )
     |> CredentialIndex.assign_index()}
  end

  @impl true
  def handle_event(event, params, socket),
    do: CredentialIndex.handle_event(event, params, socket)

  @impl true
  def handle_info({:forward, CredentialIndex, _answer} = message, socket),
    do: CredentialIndex.handle_info(message, socket)

  # The test mailer reports each email it sends to the sending process.
  def handle_info({:email, _email}, socket), do: {:noreply, socket}

  @impl true
  def handle_async(name, result, socket),
    do: CredentialIndex.handle_async(name, result, socket)
end
