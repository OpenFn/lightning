defmodule LightningWeb.WorkflowDiagramLive do
  use LightningWeb, :live_component

  def handle_event("component.mounted", params, socket) do
    IO.inspect(params, label: "component.mounted")

    {:noreply, push_event(socket, "update_diagram", %{"foo" => "bar"})}
  end
end
