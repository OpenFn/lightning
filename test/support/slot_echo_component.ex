defmodule LightningWeb.SlotEchoComponent do
  @moduledoc """
  Test-only LiveComponent that captures the assigns it receives and sends
  them back to the test process. Used by slot-wrapper tests to verify that
  a wrapper forwards the right assigns to the registered downstream
  component.

  Usage:

      render_component(&Settings.usage_caps_input_slot/1,
        component: LightningWeb.SlotEchoComponent,
        project: project,
        current_user: user
      )

      assert_received {:slot_echo, %{project: ^project, current_user: ^user}}
  """
  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    send(self(), {:slot_echo, Map.drop(assigns, [:__changed__, :flash, :myself])})

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}></div>
    """
  end
end
