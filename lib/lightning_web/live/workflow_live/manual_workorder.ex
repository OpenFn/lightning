defmodule LightningWeb.WorkflowLive.ManualWorkorder do
  @moduledoc false
  use LightningWeb, :component

  attr :id, :string, required: true
  attr :dataclips, :list, default: []
  attr :form, :map, required: true
  attr :disabled, :boolean, default: true

  attr :project, :map, required: true

  attr :admin_contacts, :list,
    required: true,
    doc: "list of project admin emails"

  attr :can_edit_data_retention, :boolean, required: true
  attr :follow_run_id, :string, required: true
  attr :show_wiped_dataclip_selector, :boolean, default: false

  def component(assigns) do
    assigns =
      assigns
      |> assign(
        selected_dataclip:
          with dataclip_id when not is_nil(dataclip_id) <-
                 Phoenix.HTML.Form.input_value(assigns.form, :dataclip_id),
               dataclip when not is_nil(dataclip) <-
                 Enum.find(assigns.dataclips, &match?(%{id: ^dataclip_id}, &1)) do
            dataclip
          end
      )

    ~H"""
    <.form
      for={@form}
      id={@form.id}
      phx-change="manual_run_change"
      phx-submit="manual_run_submit"
      class="h-full flex flex-col gap-4"
    >
      <%= if @follow_run_id && is_nil(@selected_dataclip)  do %>
        <%= if @show_wiped_dataclip_selector do %>
          <.dataclip_selector_fields
            form={@form}
            dataclips={@dataclips}
            selected_dataclip={@selected_dataclip}
            disabled={@disabled}
            project={@project}
            admin_contacts={@admin_contacts}
            can_edit_data_retention={@can_edit_data_retention}
          />
        <% else %>
          <LightningWeb.Components.Viewers.wiped_dataclip_viewer
            input_or_output={:input}
            project_id={@project.id}
            admin_contacts={@admin_contacts}
            can_edit_data_retention={@can_edit_data_retention}
          >
            <:footer>
              <div class="text-center text-gray-500 text-sm mt-4">
                <span>To create a new work order, first</span>
                <span
                  id="toggle_dataclip_selector_button"
                  phx-click="toggle_wiped_dataclip_selector"
                  class="underline inline-block text-blue-400 hover:text-blue-600 cursor-pointer"
                >
                  click here
                </span>
                <span>to select/build an input.</span>
              </div>
            </:footer>
          </LightningWeb.Components.Viewers.wiped_dataclip_viewer>
        <% end %>
      <% else %>
        <.dataclip_selector_fields
          form={@form}
          dataclips={@dataclips}
          selected_dataclip={@selected_dataclip}
          disabled={@disabled}
          project={@project}
          admin_contacts={@admin_contacts}
          can_edit_data_retention={@can_edit_data_retention}
        />
      <% end %>
    </.form>
    """
  end

  defp dataclip_selector_fields(assigns) do
    ~H"""
    <div class="">
      <div class="flex-grow">
        <.input
          type="select"
          field={@form[:dataclip_id]}
          options={@dataclips |> Enum.map(&{&1.id, &1.id})}
          prompt="Create a new input"
          disabled={@disabled}
        />
      </div>
    </div>

    <div class="flex-0">
      <div class="flex flex-row">
        <div class="basis-1/2 font-semibold text-secondary-700 text-xs xl:text-base">
          Type
        </div>
        <div class="basis-1/2 text-right">
          <Common.dataclip_type_pill type={
            (@selected_dataclip && @selected_dataclip.type) || :saved_input
          } />
        </div>
      </div>
      <%= unless is_nil(@selected_dataclip) do %>
        <div class="flex flex-row mt-4">
          <div class="basis-1/2 font-semibold text-secondary-700 text-xs xl:text-base">
            Created at
          </div>
          <div class="basis-1/2 text-right">
            <%= Calendar.strftime(@selected_dataclip.inserted_at, "%c %Z") %>
          </div>
        </div>
      <% end %>
    </div>
    <div
      :if={@selected_dataclip && is_nil(@selected_dataclip.wiped_at)}
      class="grow overflow-y-auto rounded-md"
    >
      <.log_view dataclip={@selected_dataclip} class="" />
    </div>
    <LightningWeb.Components.Viewers.wiped_dataclip_viewer
      :if={@selected_dataclip && @selected_dataclip.wiped_at}
      input_or_output={:input}
      project_id={@project.id}
      admin_contacts={@admin_contacts}
      can_edit_data_retention={@can_edit_data_retention}
    />
    <div :if={is_nil(@selected_dataclip)} class="grow">
      <.input
        type="textarea"
        field={@form[:body]}
        disabled={@disabled}
        class="h-full pb-2"
        phx-debounce="300"
        phx-hook="BlurDataclipEditor"
      />
    </div>
    """
  end

  attr :dataclip, :map, required: true
  attr :class, :string, default: nil

  defp log_view(assigns) do
    assigns = assigns |> assign(log: format_dataclip_body(assigns.dataclip))

    ~H"""
    <LightningWeb.RunLive.Components.log_view log={@log} class={@class} />
    """
  end

  defp format_dataclip_body(dataclip) do
    dataclip.body
    |> Jason.encode!()
    |> Jason.Formatter.pretty_print()
    |> String.split("\n")
  end
end
