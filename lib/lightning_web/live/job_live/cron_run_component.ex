defmodule LightningWeb.JobLive.CronRunButton do
  @moduledoc """
  Displays and manages cron runs in a form.
  """
  use LightningWeb, :live_component

  alias Lightning.Run

  require Run

  @impl true
  def render(assigns) do
    ~H"""
    <div id="run-buttons" class="inline-flex shadow-sm">
      <div>
        <.button
          id={@id}
          phx-hook="DefaultRunViaCtrlEnter"
          type="button"
          phx-click={@selected_option}
          class={cron_trigger_bt_classes(assigns)}
          disabled={@disabled}
        >
          <%= if processing(@follow_run) do %>
            <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin mr-1" />
            Processing
          <% else %>
            <.icon name="hero-play-mini" class="w-4 h-4 mr-1" /> <%= button_text(
              @selected_option
            ) %>
          <% end %>
        </.button>
      </div>
      <div class="relative -ml-px block">
        <.dropdown_action {assigns} />
      </div>
    </div>
    """
  end

  @impl true
  def update(
        assigns,
        socket
      ) do
    follow_run = Map.get(assigns, :follow_run)
    snapshot_version_tag = "latest"
    disabled = processing(follow_run) or snapshot_version_tag != "latest"
    selected_option = Map.get(assigns, :selected_option, "clear_and_run")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       disabled: disabled,
       follow_run: follow_run,
       selected_option: selected_option
     )}
  end

  @impl true
  def handle_event("clear_and_run", _params, socket) do
    {:noreply, assign(socket, selected_option: "clear_and_run")}
  end

  def handle_event("run_last_state", _params, socket) do
    {:noreply, assign(socket, selected_option: "run_last_state")}
  end

  def handle_event("run_custom_state", _params, socket) do
    {:noreply, assign(socket, selected_option: "run_custom_state")}
  end

  defp cron_trigger_bt_classes(_assigns) do
    ["relative inline-flex rounded-r-none"]
  end

  def button_text(selected) do
    case selected do
      "clear_and_run" -> "Clear state and run"
      "run_last_state" -> "Run with last state"
      "run_custom_state" -> "Run with custom state"
    end
  end

  defp processing(%{state: state}), do: state not in Run.final_states()
  defp processing(_run), do: false

  defp dropdown_action(assigns) do
    ~H"""
    <.button
      type="button"
      class="h-full rounded-l-none pr-1 pl-1 focus:ring-inset"
      id="option-menu-button"
      aria-expanded="true"
      aria-haspopup="true"
      disabled={@disabled}
      phx-click={show_dropdown("dropdown-bt")}
    >
      <span class="sr-only">Open options</span>
      <.icon name="hero-chevron-down" class="w-4 h-4" />
    </.button>
    <div
      role="menu"
      aria-orientation="vertical"
      aria-labelledby="option-menu-button"
      tabindex="-1"
    >
      <button
        id="dropdown-bt"
        phx-target={@myself}
        phx-click-away={hide_dropdown("dropdown-bt")}
        phx-hook="AltRunViaCtrlShiftEnter"
        type="submit"
        class={[
          "flex justify-start hidden absolute right-0 bottom-9 z-10 mb-2 w-max",
          "rounded-md bg-white px-4 py-2 text-sm font-semibold",
          "text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
        ]}
        disabled={@disabled}
      >
        <div phx-click="run_last_state">
          <.icon name="hero-play-solid" class="w-4 h-4 mr-1" /> Run with last state
        </div>
        <div phx-click="run_custom_state" class="mt-2">
          <.icon name="hero-play-solid" class="w-4 h-4 mr-1" /> Run with custom state
        </div>
      </button>
    </div>
    """
  end
end
