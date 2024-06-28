defmodule LightningWeb.WorkflowLive.Presence do
  use Phoenix.Presence,
    otp_app: :lightning,
    pubsub_server: Lightning.PubSub
end
