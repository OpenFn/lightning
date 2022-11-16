defmodule LightningWeb.RunLive.Components do
  @moduledoc false
  use LightningWeb, :component

  @base_classes ~w[
    my-auto whitespace-nowrap rounded-full
    py-2 px-4 text-center align-baseline text-xs font-medium leading-none
  ]

  def failure_pill(assigns) do
    assigns = assigns |> apply_classes(~w[text-red-800 bg-red-200])

    ~H"""
    <span class={@classes}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  def success_pill(assigns) do
    assigns =
      assigns
      |> apply_classes(~w[bg-green-200 text-green-800])

    ~H"""
    <span class={@classes}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  def pending_pill(assigns) do
    assigns = assigns |> apply_classes(~w[bg-grey-200 text-grey-800])

    ~H"""
    <span class={@classes}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  defp apply_classes(assigns, classes) do
    assign(assigns,
      classes: @base_classes ++ classes ++ List.wrap(assigns[:class])
    )
  end
end
