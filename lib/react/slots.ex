defmodule React.Slots do
  @moduledoc false

  import Phoenix.Component

  @doc false
  def render_slots(assigns) do
    for(
      attr <- assigns,
      into: %{},
      do:
        case attr do
          {key, [%{__slot__: _}] = slot} ->
            {if key == :inner_block do
               :children
             else
               key
             end,
             %{
               __type__: "__slot__",
               data:
                 render(%{slot: slot})
                 |> Phoenix.HTML.Safe.to_iodata()
                 |> List.to_string()
                 |> String.trim()
                 |> Base.encode64()
             }}

          _ ->
            attr
        end
    )
  end

  @doc false
  defp render(assigns) do
    ~H"""
    <%= if assigns[:slot] do %>
      <%= render_slot(@slot) %>
    <% end %>
    """
  end
end
