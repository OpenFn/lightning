defmodule LightningWeb.Components.Viewers do
  @moduledoc """
  Components for rendering Logs and Dataclips.

  > #### Scrolling can be tricky {: .info}
  >
  > We seldom know how long a log or a dataclip will be, and we want to
  > be able to contain the element in a fixed height container.
  > In some situations wrapping the component in a `div` with `inline-flex`
  > class will help with scrolling.
  """

  use LightningWeb, :component

  import LightningWeb.Components.Icons

  alias Lightning.Invocation.Dataclip
  alias LightningWeb.Components.Icon

  require Lightning.Run

  @doc """
  Renders out a log line stream

  Internally it uses the `LogLineHighlight` hook to highlight the log line
  with the `highlight_id` attribute.

  ## Example

      <Viewers.log_viewer
        id="log-viewer-data"
        stream={@log_lines}
        highlight_id={@selected_step_id}
      />
  """

  attr :id, :string, required: true
  attr :run_id, :string, required: true
  attr :run_state, :any, required: true
  attr :logs_empty?, :boolean, required: true
  attr :selected_step_id, :string

  attr :current_user, Lightning.Accounts.User,
    default: nil,
    doc: "for checking log filter preference"

  attr :class, :string,
    default: nil,
    doc: "Additional classes to add to the log viewer container"

  def log_viewer(assigns) do
    assigns =
      assign_new(assigns, :selected_log_level, fn ->
        if assigns[:current_user] do
          Map.get(assigns.current_user.preferences, "desired_log_level", "info")
        else
          "info"
        end
      end)

    ~H"""
    <%= if @run_state in Lightning.Run.final_states() and @logs_empty? do %>
      <div class={["m-2 relative p-12 text-center col-span-full"]}>
        <span class="relative inline-flex">
          <div class="inline-flex">
            No logs were received for this run.
          </div>
        </span>
      </div>
    <% else %>
      <div class="relative flex grow">
        <.log_level_filter
          :if={@current_user}
          id={"#{@id}-filter"}
          selected_level={@selected_log_level}
        />

        <div
          id={@id}
          class={["flex grow", @class]}
          phx-hook="LogViewer"
          phx-update="ignore"
          data-run-id={@run_id}
          data-step-id={@selected_step_id}
          data-log-level={@selected_log_level}
          data-loading-el={"#{@id}-nothing-yet"}
          data-viewer-el={"#{@id}-viewer"}
        >
          <div class="relative grow">
            <div
              id={"#{@id}-nothing-yet"}
              class="relative rounded-md p-12 text-center bg-slate-700 font-mono text-gray-200"
            >
              <.text_ping_loader>
                Nothing yet
              </.text_ping_loader>
            </div>
            <div id={"#{@id}-viewer"} class="hidden absolute inset-0 rounded-md">
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :selected_level, :string

  defp log_level_filter(assigns) do
    assigns =
      assign(assigns,
        log_levels: [
          {"debug", "Show all logs"},
          {"info", "Standard logging, excluding low-level debug logs (default)"},
          {"warn", "Only show warnings, errors and key logs"},
          {"error", "Only show errors and key logs"}
        ]
      )

    ~H"""
    <div id={@id} class="absolute top-0 right-4 z-50">
      <.modal
        id={"#{@id}-modal"}
        close_on_click_away={false}
        close_on_keydown={false}
      >
        <:title>
          <div class="flex justify-between gap-2">
            <span class="font-bold">
              Configure log levels
            </span>

            <button
              phx-click={hide_modal("#{@id}-modal")}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <.form id={"#{@id}-form"} for={to_form(%{})} phx-change="save-log-filter">
          <fieldset>
            <p class="mt-1 text-sm/6 text-gray-600">
              Which logs do you prefer to see?
            </p>
            <div class="mt-6 space-y-4">
              <%= for {level, description} <- @log_levels do %>
                <div class="relative flex items-start">
                  <div class="flex h-6 items-center">
                    <.input
                      type="radio"
                      id={"desired_level_#{level}"}
                      name="desired_log_level"
                      value={level}
                      checked={level == @selected_level}
                      class="relative size-4 appearance-none rounded-full border border-gray-300 bg-white before:absolute before:inset-1 before:rounded-full before:bg-white checked:border-indigo-600 checked:bg-indigo-600 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 disabled:border-gray-300 disabled:bg-gray-100 disabled:before:bg-gray-400 forced-colors:appearance-auto forced-colors:before:hidden [&:not(:checked)]:before:hidden"
                    />
                  </div>
                  <div class="ml-3 text-sm/6">
                    <.label
                      for={"desired_level_#{level}"}
                      class="font-medium text-gray-900 uppercase"
                    >
                      <%= level %>
                    </.label>
                    <p class="text-gray-500"><%= description %></p>
                  </div>
                </div>
              <% end %>
            </div>
          </fieldset>
        </.form>
      </.modal>
      <button
        phx-click={show_modal("#{@id}-modal")}
        type="button"
        class="rounded-bl-md rounded-br-md p-1 pt-0 opacity-70 hover:opacity-100 content-center bg-blue-500 text-blue-900"
      >
        <.icon name="hero-cog-6-tooth" class="h-4 w-4 inline-block align-middle" />
      </button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :dataclip, :map, required: true

  def dataclip_viewer(assigns) do
    ~H"""
    <div
      id={@id}
      class="h-full relative"
      phx-hook="DataclipViewer"
      phx-update="ignore"
      data-id={@dataclip.id}
      data-target={"#{@id}-viewer"}
    >
      <.dataclip_type id={"#{@id}-type"} type={@dataclip.type} />
      <div id={"#{@id}-viewer"} class="h-full"></div>
    </div>
    """
  end

  attr :id, :string, required: true

  attr :run_state, :any, required: true

  attr :class, :string,
    default: nil,
    doc: "Additional classes to add to the log viewer container"

  attr :step, :map
  attr :dataclip, Dataclip
  attr :input_or_output, :atom, required: true, values: [:input, :output]
  attr :project_id, :string, required: true

  attr :admin_contacts, :list,
    required: true,
    doc: "list of project admin emails"

  attr :can_edit_data_retention, :boolean, required: true

  def step_dataclip_viewer(assigns) do
    ~H"""
    <%= if dataclip_wiped?(@step, @dataclip, @input_or_output) do %>
      <.wiped_dataclip_viewer
        id={@id}
        can_edit_data_retention={@can_edit_data_retention}
        admin_contacts={@admin_contacts}
        input_or_output={@input_or_output}
        project_id={@project_id}
      />
    <% else %>
      <div
        :if={
          @run_state in Lightning.Run.final_states() and
            is_nil(@dataclip)
        }
        class={[
          "m-2 relative rounded-md",
          "p-12 text-center col-span-full"
        ]}
      >
        <span class="relative inline-flex">
          <div class="inline-flex">
            No <%= @input_or_output %> state could be saved for this run.
          </div>
        </span>
      </div>

      <div
        :if={
          @run_state not in Lightning.Run.final_states() and
            is_nil(@dataclip)
        }
        id={"#{@id}-nothing-yet"}
        class="relative rounded-md p-12 text-center bg-slate-700 font-mono text-gray-200"
      >
        <.text_ping_loader>
          Nothing yet
        </.text_ping_loader>
      </div>

      <.dataclip_viewer
        :if={@dataclip}
        id={"step-#{@input_or_output}-dataclip-viewer"}
        dataclip={@dataclip}
      />
    <% end %>
    """
  end

  attr :id, :string, default: nil
  attr :input_or_output, :atom, required: true, values: [:input, :output]
  attr :project_id, :string, required: true

  attr :admin_contacts, :list,
    required: true,
    doc: "list of project admin emails"

  attr :can_edit_data_retention, :boolean, required: true

  slot :footer

  def wiped_dataclip_viewer(assigns) do
    ~H"""
    <div
      id={@id}
      class="border-2 border-gray-200 border-dashed rounded-lg px-8 pt-6 pb-8 mb-4 flex flex-col"
    >
      <div class="mb-4">
        <div class="h-12 w-12 border-2 border-gray-300 border-solid mx-auto flex items-center justify-center rounded-full text-gray-400">
          <Heroicons.code_bracket class="w-4 h-4" />
        </div>
      </div>
      <div class="text-center mb-4 text-gray-500">
        <h3 class="font-bold text-lg">
          <span class="capitalize">No <%= @input_or_output %> Data</span> here!
        </h3>
        <p class="text-sm">
          <span class="capitalize"><%= @input_or_output %></span>
          data for this step has not been retained in accordance
          with your project's data storage policy.
        </p>
      </div>
      <div class="text-center text-gray-500 text-sm">
        <%= if @can_edit_data_retention do %>
          You can’t rerun this work order, but you can change
          <.link
            navigate={~p"/projects/#{@project_id}/settings#data-storage"}
            class="link"
          >
            this policy
          </.link>
          for future runs.
        <% else %>
          Contact one of your
          <span
            id="zero-persistence-admins-tooltip"
            phx-hook="Tooltip"
            class="link inline-block"
            aria-label={Enum.join(@admin_contacts, ", ")}
          >
            project admins
          </span>
          for more information.
        <% end %>
      </div>
      <%= render_slot(@footer) %>
    </div>
    """
  end

  attr :id, :string, required: true

  attr :type, :atom,
    default: nil,
    values: [nil | Dataclip.source_types()]

  defp dataclip_type(assigns) do
    assigns =
      assign(assigns,
        icon: Icon.dataclip_icon_class(assigns.type),
        color: Icon.dataclip_icon_color(assigns.type)
      )

    ~H"""
    <div
      id={@id}
      class={[
        "absolute top-0 right-0 flex items-center gap-2 group z-10"
      ]}
    >
      <div class="hidden group-hover:block font-mono text-white text-xs">
        type: <%= @type %>
      </div>
      <div class={[
        "rounded-bl-md rounded-tr-md p-1 pt-0 opacity-70 group-hover:opacity-100 content-center",
        @color
      ]}>
        <.icon :if={@icon} name={@icon} class="h-4 w-4 inline-block align-middle" />
      </div>
    </div>
    """
  end

  defp step_finished?(%{finished_at: %_{}}), do: true

  defp step_finished?(_other), do: false

  defp dataclip_wiped?(_step, %{wiped_at: %_{}} = _dataclip, _input_or_output) do
    true
  end

  defp dataclip_wiped?(step, _dataclip, input_or_output) do
    dataclip_field = dataclip_field(input_or_output)

    step_finished?(step) and is_nil(Map.fetch!(step, dataclip_field))
  end

  defp dataclip_field(:input), do: :input_dataclip_id
  defp dataclip_field(:output), do: :output_dataclip_id
end
