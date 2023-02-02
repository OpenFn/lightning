defmodule LightningWeb.OauthCredentialHelper do
  alias Lightning.SafetyString

  def build_state(subscription_id, mod, component_id) do
    SafetyString.encode([
      subscription_id,
      mod |> to_string(),
      component_id
    ])
  end

  def decode_state(state) do
    [subscription_id, mod, component_id] = SafetyString.decode(state)

    [subscription_id, mod |> String.to_existing_atom(), component_id]
  end

  # NOTE: the subscription id is currently the socket id of the liveview
  # this _may_ be a little difficult to work with if it changes a lot.
  # consider the users session_id instead
  def subscribe(subscription_id) do
    Phoenix.PubSub.subscribe(Lightning.PubSub, topic(subscription_id))
  end

  @doc """
  Broadcast a message specifically for forwarding a message to a component.
  It expects a `subscription_id`, the module of the component and `opts`
  being a keyword list containing an `:id` key of the specific component.

  See: `Phoenix.LiveView.send_update/3` for more info.

  A corresponding LiveView (that is subscribed) is expected to have a matching
  `handle_info/2` that looks like this:

  ```
  def handle_info({:forward, mod, opts}, socket) do
    send_update(mod, opts)
    {:noreply, socket}
  end
  ```
  """
  def broadcast_forward(subscription_id, mod, opts) do
    broadcast(subscription_id, {:forward, mod, opts})
  end

  def broadcast(subscription_id, msg) do
    Phoenix.PubSub.broadcast(Lightning.PubSub, topic(subscription_id), msg)
  end

  defp topic(subscription_id) do
    "oauth_credential:#{subscription_id}" |> IO.inspect()
  end
end
