defmodule Lightning.RunLive.RunStatusComponent do
  @moduledoc false
  use LightningWeb, :live_component

  @impl true
  def handle_event(
        "checked",
        %{"run_search_form" => %{"options" => values}},
        socket
      ) do
    [{index, %{"selected" => selected?}}] = Map.to_list(values)
    index = String.to_integer(index)
    selectable_options = socket.assigns.selectable_options
    current_option = Enum.at(selectable_options, index)

    updated_options =
      List.replace_at(
        selectable_options,
        index,
        %{current_option | selected: selected?}
      )

    send(self(), {:updated_options, updated_options})

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"#{@id}-options-container"}>
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
  def update(params, socket) do
    %{options: options, form: form, id: id} = params

    socket =
      socket
      |> assign(:id, id)
      |> assign(:selectable_options, options)
      |> assign(:form, form)

    {:ok, socket}
  end
end
