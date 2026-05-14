defmodule LightningWeb.SlotEchoComponent do
  @moduledoc """
  Test-only LiveComponent that echoes its assigns into a div's `data-*`
  attributes. Used by slot-wrapper tests to verify that a wrapper forwards
  the right assigns to the registered downstream component.
  """
  use Phoenix.LiveComponent

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> Map.put_new(:current_user, nil)
      |> Map.put_new(:disabled, nil)

    ~H"""
    <div
      id={@id}
      data-project-id={@project.id}
      data-current-user-id={if @current_user, do: @current_user.id, else: ""}
      data-disabled={if is_nil(@disabled), do: "", else: "#{@disabled}"}
    >
      echo
    </div>
    """
  end
end
