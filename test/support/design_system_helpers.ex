defmodule LightningWeb.DesignSystemHelpers do
  @moduledoc """
  Drives a design-system page the way its React island does: reads its
  `data-props` and pushes its events to the LiveView.
  """
  import Phoenix.LiveViewTest

  @doc "The decoded `data-props` of the page mounted at `selector`."
  def page_props(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.attribute("data-props")
    |> List.first()
    |> Jason.decode!()
  end

  @doc "Sends an event from the page, as the kit's `send` and `request` do."
  def push_page_event(view, selector, event, payload \\ %{}) do
    view |> element(selector) |> render_hook(event, payload)
  end
end
