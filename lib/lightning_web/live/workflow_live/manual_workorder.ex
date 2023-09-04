defmodule LightningWeb.WorkflowLive.ManualWorkorder do
  @moduledoc false
  use LightningWeb, :component

  import LightningWeb.Components.NewInputs
  import LightningWeb.WorkflowLive.Components

  attr :id, :string, required: true
  attr :dataclips, :list, default: []
  attr :form, :map, required: true
  attr :disabled, :boolean, default: true

  def component(assigns) do
    assigns =
      assigns
      |> assign(
        selected_dataclip:
          with dataclip_id when not is_nil(dataclip_id) <-
                 input_value(assigns.form, :dataclip_id),
               dataclip when not is_nil(dataclip) <-
                 Enum.find(assigns.dataclips, &match?(%{id: ^dataclip_id}, &1)) do
            dataclip
          end
      )

    ~H"""
    <div id={@id} class="h-full">
      <div>
        <div class="flex justify-between items-center">
        <div class="text-xl text-center font-semibold text-secondary-700 mb-2">
          Input
        </div>
        <div class="" phx-click={hide_panel_1()}>
            <Heroicons.minus_small class="w-10 h-10 p-2 hover:bg-gray-200 text-gray-600 rounded-lg"/>
          </div>
        </div>
        <.form
          for={@form}
          id={@form.id}
          phx-hook="SubmitViaCtrlEnter"
          phx-change="manual_run_change"
          phx-submit="manual_run_submit"
          class="h-full flex flex-col gap-4"
        >
          <div class="flex">
            <div class="flex-grow">
              <.input
                type="select"
                field={@form[:dataclip_id]}
                options={@dataclips |> Enum.map(&{&1.id, &1.id})}
                prompt="Create a new dataclip"
                disabled={@disabled}
              />
            </div>
          </div>
          <div class="flex-1 flex flex-col gap-4">
            <div>
              <div class="flex flex-row">
                <div class="basis-1/2 font-semibold text-secondary-700">
                  Dataclip Type
                </div>
                <div class="basis-1/2 text-right">
                  <Common.dataclip_type_pill type={
                    (@selected_dataclip && @selected_dataclip.type) || :saved_input
                  } />
                </div>
              </div>
              <div class="flex flex-row mt-4">
                <div class="basis-1/2 font-semibold text-secondary-700">
                  State Assembly
                </div>
                <div class="text-right text-sm">
                  <%= if(not is_nil(@selected_dataclip) and @selected_dataclip.type == :http_request) do %>
                    The JSON shown here is the <em>body</em>
                    of an HTTP request. The state assembler will place this payload into
                    <code>state.data</code>
                    when the job is run, before adding
                    <code>state.configuration</code>
                    from your selected credential.
                  <% else %>
                    The state assembler will overwrite the <code>configuration</code>
                    attribute below with the body of the currently selected credential.
                  <% end %>
                </div>
              </div>
            </div>
            <div :if={@selected_dataclip} class="h-32 overflow-y-auto">
              <.log_view dataclip={@selected_dataclip} />
            </div>
            <div :if={is_nil(@selected_dataclip)}>
              <.input
                type="textarea"
                field={@form[:body]}
                rows="10"
                disabled={@disabled}
                phx-debounce="300"
              />
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :dataclip, :map, required: true

  defp log_view(assigns) do
    assigns = assigns |> assign(log: format_dataclip_body(assigns.dataclip))

    ~H"""
    <LightningWeb.RunLive.Components.log_view log={@log} />
    """
  end

  defp format_dataclip_body(dataclip) do
    dataclip.body
    |> Jason.encode!()
    |> Jason.Formatter.pretty_print()
    |> String.split("\n")
  end
end
