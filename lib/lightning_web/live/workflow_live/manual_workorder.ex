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
  attr :follow_run, :map, required: true
  attr :step, :map, required: true
  attr :show_missing_dataclip_selector, :boolean, default: false

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
      <%= if @follow_run && is_nil(@selected_dataclip)  do %>
        <%= if @show_missing_dataclip_selector do %>
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
          <.missing_dataclip_viewer {assigns} />
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
            <Common.datetime datetime={@selected_dataclip.inserted_at} />
          </div>
        </div>
      <% end %>
    </div>
    <div
      :if={@selected_dataclip && is_nil(@selected_dataclip.wiped_at)}
      class="grow overflow-y-auto"
    >
      <LightningWeb.Components.Viewers.dataclip_viewer
        dataclip={@selected_dataclip}
        id={"selected-dataclip-#{@selected_dataclip.id}"}
      />
    </div>
    <LightningWeb.Components.Viewers.wiped_dataclip_viewer
      :if={@selected_dataclip && @selected_dataclip.wiped_at}
      input_or_output={:input}
      project_id={@project.id}
      admin_contacts={@admin_contacts}
      can_edit_data_retention={@can_edit_data_retention}
    />
    <div :if={is_nil(@selected_dataclip)} class="grow">
      <div phx-feedback-for={@form[:body].name} class="h-full flex flex-col">
        <.errors field={@form[:body]} />
        <.textarea_element
          id={@form[:body].id}
          name={@form[:body].name}
          value={@form[:body].value}
          disabled={@disabled}
          class="h-full font-mono proportional-nums text-slate-200 bg-slate-700"
          phx-debounce="300"
          phx-hook="BlurDataclipEditor"
        />
      </div>
    </div>
    """
  end

  defp missing_dataclip_viewer(assigns) do
    ~H"""
    <%= if dataclip_wiped?(@step, @selected_dataclip) do %>
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
              phx-click="toggle_missing_dataclip_selector"
              class="link"
            >
              click here
            </span>
            <span>to select/build an input.</span>
          </div>
        </:footer>
      </LightningWeb.Components.Viewers.wiped_dataclip_viewer>
    <% else %>
      <div class="border-2 border-gray-200 border-dashed rounded-lg px-8 pt-6 pb-8 mb-4 flex flex-col">
        <div class="mb-4">
          <div class="h-12 w-12 border-2 border-gray-300 border-solid mx-auto flex items-center justify-center rounded-full text-gray-400">
            <.icon name="hero-code-bracket" class="w-4 h-4" />
          </div>
        </div>
        <div class="text-center mb-4 text-gray-500">
          <h3 class="font-bold text-lg">
            <span class="capitalize">No Input Data</span> here!
          </h3>
          <p class="text-sm">
            This job was not/is not yet included in this Run. Select a step from this run in the Run tab or create a new work order by
            <span
              id="toggle_dataclip_selector_button"
              phx-click="toggle_missing_dataclip_selector"
              class="link"
            >
              clicking here
            </span>
            to select/build an input
          </p>
        </div>
      </div>
    <% end %>
    """
  end

  defp dataclip_wiped?(nil, _), do: false

  defp dataclip_wiped?(_step, %{wiped_at: %_{}}), do: true

  defp dataclip_wiped?(step, _dataclip) do
    is_struct(step.finished_at) and is_nil(step.input_dataclip_id)
  end
end
