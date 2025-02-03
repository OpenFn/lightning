defmodule LightningWeb.JobLive.CronRunButton do
  @moduledoc """
  Displays and manages cron runs in a form.
  """
  use LightningWeb, :live_component

  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.WorkOrder

  require Run

  @impl true
  def render(assigns) do
    ~H"""
    <div id="run-buttons" class="inline-flex shadow-sm">
      <div>
        <.button
          id={@id}
          phx-target={@myself}
          phx-click={@selected_option}
          phx-hook="DefaultRunViaCtrlEnter"
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
    </div>
    """
  end

  @impl true
  def update(
        %{follow_run: follow_run} = assigns,
        socket
      ) do
    snapshot_version_tag = "latest"
    disabled = processing(follow_run) or snapshot_version_tag != "latest"

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       disabled: disabled,
       follow_run: nil,
       selected_option: "clear_and_run"
     )}
  end

  @impl true
  def handle_event("clear_and_run", _params, socket) do
    cron_trigger =
      Enum.find(socket.assigns.workflow.triggers, &(&1.type == :cron))

    dataclip_id =
      Repo.one(
        from(wo in WorkOrder,
          where: wo.trigger_id == ^cron_trigger.id,
          select: wo.dataclip_id,
          limit: 1,
          order_by: [desc: :inserted_at]
        )
      )

    send(
      self(),
      {__MODULE__, "cron_trigger_manual_run", %{dataclip_id: dataclip_id}}
    )

    {:noreply, socket}
  end

  # @impl true
  # def handle_info(
  #       %RunUpdated{run: run},
  #       %{assigns: %{follow_run: %{id: follow_run_id}}} = socket
  #     )
  #     when run.id === follow_run_id do
  #   {:noreply,
  #    socket
  #    |> assign(follow_run: run)}
  # end

  defp cron_trigger_bt_classes(_assigns) do
    ["relative inline-flex"]
  end

  def button_text(selected) do
    case selected do
      "clear_and_run" -> "Run now"
      "run_last_state" -> "Run with last state"
      "run_custom_state" -> "Run with custom state"
    end
  end

  defp processing(%{state: state}), do: state not in Run.final_states()
  defp processing(_run), do: false
end
