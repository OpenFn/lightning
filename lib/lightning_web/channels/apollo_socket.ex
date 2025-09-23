defmodule LightningWeb.ApolloSocket do
  use Phoenix.Socket

  channel "apollo:stream", LightningWeb.ApolloChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
