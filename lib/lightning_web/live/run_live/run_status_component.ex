defmodule Lightning.RunLive.RunStatusComponent do
  @moduledoc """
  Run Status MutliSelect.
  """
  use LightningWeb, :live_component

  @impl true
  attr :label, :string

  def render(assigns) do
    ~H"""
    <div id={"#{@id}-options-container"}>
      <div class="font-semibold my-4">Filter by status</div>
      <%= inputs_for @form, :options, fn opt -> %>
        <div class="form-check">
          <div class="selectable-option">
            <%= checkbox(opt, :selected,
              value: opt.data.selected,
              phx_change: "checked",
              phx_target: @myself
            ) %>
            <%= label(opt, :label, opt.data.label) %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    %{options: options, form: form, id: id, selected: selected} = assigns

    socket =
      socket
      |> assign(:id, id)
      |> assign(:form, form)
      |> assign(:selected, selected)
      |> assign(:options, options)

    {:ok, socket}
  end

  @impl true
  def handle_event(
        "checked",
        %{"run_search_form" => %{"options" => values}},
        socket
      ) do
    [{index, %{"selected" => selected?}}] = Map.to_list(values)
    index = String.to_integer(index)
    current_option = Enum.at(socket.assigns.options, index)

    selected_statuses =
      List.replace_at(
        socket.assigns.options,
        index,
        %{current_option | selected: selected?}
      )

    socket.assigns.selected.(selected_statuses)

    {:noreply, socket}
  end
end
