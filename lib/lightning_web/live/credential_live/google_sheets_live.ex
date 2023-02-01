defmodule LightningWeb.CredentialLive.GoogleSheetsLive do
  use LightningWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <p>Google Sheets</p>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
