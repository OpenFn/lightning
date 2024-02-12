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

  alias Lightning.Invocation.Dataclip
  alias LightningWeb.Components.Icon
  alias Phoenix.LiveView.AsyncResult

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

  attr :stream, :list,
    required: true,
    doc: "A stream of `Lightning.Invocation.LogLine` structs"

  attr :stream_empty?, :boolean, required: true

  attr :highlight_id, :string,
    default: nil,
    doc: "The id of the log line to highlight, matching the `step_id` field"

  attr :class, :string,
    default: nil,
    doc: "Additional classes to add to the log viewer container"

  def log_viewer(assigns) do
    ~H"""
    <div class={[
      "rounded-md shadow-sm bg-slate-700 border-slate-300",
      "text-slate-200 text-sm font-mono proportional-nums w-full"
    ]}>
      <div
        id={@id}
        phx-hook="LogLineHighlight"
        data-highlight-id={@highlight_id}
        phx-update="stream"
        class={[
          "overscroll-contain scroll-smooth",
          "grid grid-flow-row-dense grid-cols-[min-content_1fr]",
          "log-viewer",
          @class
        ]}
      >
        <div
          :for={{dom_id, log_line} <- @stream}
          class="group contents"
          data-highlight-id={log_line.step_id}
          id={dom_id}
        >
          <div class="log-viewer__prefix" data-line-prefix={log_line.source}></div>
          <span data-log-line class="log-viewer__message">
            <pre><%= log_line.message %></pre>
          </span>
        </div>
      </div>
      <div
        :if={@stream_empty?}
        id={"#{@id}-nothing-yet"}
        class={[
          "m-2 relative rounded-md",
          "p-12 text-center col-span-full"
        ]}
      >
        <.text_ping_loader>
          Nothing yet
        </.text_ping_loader>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true

  attr :stream, :list,
    required: true,
    doc: """
    A stream of lines to render. In the shape of `%{id: String.t(), line: String.t(), index: integer()}`
    """

  attr :stream_empty?, :boolean, required: true

  attr :class, :string,
    default: nil,
    doc: "Additional classes to add to the log viewer container"

  attr :type, :atom,
    default: nil,
    values: [nil | Dataclip.source_types()]

  def dataclip_viewer(assigns) do
    ~H"""
    <div class={[
      "rounded-md shadow-sm bg-slate-700 border-slate-300",
      "text-slate-200 text-sm font-mono w-full h-full relative",
      @class
    ]}>
      <.dataclip_type :if={@type} type={@type} id={"#{@id}-type"} />
      <div
        class={[
          "overscroll-contain scroll-smooth",
          "grid grid-flow-row-dense grid-cols-[min-content_1fr]",
          "min-h-[2rem]",
          "log-viewer relative"
        ]}
        id={@id}
        phx-update="stream"
      >
        <div
          :for={{dom_id, %{line: line, index: index}} <- @stream}
          class="group contents"
          id={dom_id}
        >
          <div class="log-viewer__prefix" data-line-prefix={index}></div>
          <div data-log-line class="log-viewer__message">
            <pre class="whitespace-break-spaces"><%= line %></pre>
          </div>
        </div>
      </div>
      <div
        :if={@stream_empty?}
        id={"#{@id}-nothing-yet"}
        class={[
          "m-2 relative rounded-md",
          "p-12 text-center col-span-full"
        ]}
      >
        <.text_ping_loader>
          Nothing yet
        </.text_ping_loader>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true

  attr :stream, :list,
    required: true,
    doc: """
    A stream of lines to render. In the shape of `%{id: String.t(), line: String.t(), index: integer()}`
    """

  attr :stream_empty?, :boolean, required: true

  attr :class, :string,
    default: nil,
    doc: "Additional classes to add to the log viewer container"

  attr :step, :map
  attr :dataclip, :map, doc: "Can be an `AsyncResult` or `Dataclip`"
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
      <.dataclip_viewer
        id={@id}
        class={@class}
        stream={@stream}
        stream_empty?={@stream_empty?}
        type={
          case @dataclip do
            %AsyncResult{ok?: true, result: %{type: type}} -> type
            %{type: type} -> type
            _ -> nil
          end
        }
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
            href={~p"/projects/#{@project_id}/settings#data-storage"}
            class="underline inline-block text-blue-400 hover:text-blue-600"
          >
            this policy
          </.link>
          for future runs.
        <% else %>
          Contact one of your
          <span
            id="zero-persistence-admins-tooltip"
            phx-hook="Tooltip"
            class="underline inline-block text-blue-400"
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
      <div class="hidden group-hover:block font-mono"><%= @type %></div>
      <div class={[
        "rounded-bl-md rounded-tr-md rounded-br-md p-1 opacity-70 group-hover:opacity-100 content-center",
        @color
      ]}>
        <.icon :if={@icon} name={@icon} class="h-6 w-6 inline-block align-middle" />
      </div>
    </div>
    """
  end

  defp step_finished?(%{finished_at: %_{}}), do: true

  defp step_finished?(_other), do: false

  defp dataclip_wiped?(_step, %AsyncResult{ok?: false}, _input_or_output) do
    false
  end

  defp dataclip_wiped?(
         step,
         %AsyncResult{ok?: true, result: result},
         input_or_output
       ) do
    dataclip_wiped?(step, result, input_or_output)
  end

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
