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

  @doc """
  Renders out a log line stream

  Internally it uses the `LogLineHighlight` hook to highlight the log line
  with the `highlight_id` attribute.

  ## Example

      <Viewers.log_viewer
        id="log-viewer-data"
        stream={@log_lines}
        highlight_id={@selected_run_id}
      />
  """

  attr :id, :string, required: true

  attr :stream, :list,
    required: true,
    doc: "A stream of `Lightning.Invocation.LogLine` structs"

  attr :highlight_id, :string,
    default: nil,
    doc: "The id of the log line to highlight, matching the `run_id` field"

  attr :class, :string,
    default: nil,
    doc: "Additional classes to add to the log viewer container"

  def log_viewer(assigns) do
    ~H"""
    <div
      class={[
        "rounded-md shadow-sm bg-slate-700 border-slate-300",
        "text-slate-200 text-sm font-mono proportional-nums w-full",
        "overflow-y-auto overscroll-contain scroll-smooth",
        "grid grid-flow-row-dense grid-cols-[min-content_1fr]",
        @class
      ]}
      id={@id}
      phx-hook="LogLineHighlight"
      data-highlight-id={@highlight_id}
      phx-update="stream"
    >
      <div
        :for={{dom_id, log_line} <- @stream}
        class="group contents"
        data-highlight-id={log_line.run_id}
        id={dom_id}
      >
        <div class="log-viewer__prefix" data-line-prefix={log_line.source}></div>
        <div data-log-line class="log-viewer__message">
          <pre class="whitespace-break-spaces"><%= log_line.message %></pre>
        </div>
      </div>
      <div
        id={"#{@id}-nothing-yet"}
        class={[
          "hidden only:block m-2 relative block rounded-md",
          "border-2 border-dashed border-gray-500 p-12 text-center col-span-full"
        ]}
      >
        Nothing yet...
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

  attr :class, :string,
    default: nil,
    doc: "Additional classes to add to the log viewer container"

  def dataclip_viewer(assigns) do
    ~H"""
    <div
      class={[
        "rounded-md shadow-sm bg-slate-700 border-slate-300",
        "text-slate-200 text-sm font-mono proportional-nums w-full",
        "overflow-y-auto overscroll-contain scroll-smooth",
        "grid grid-flow-row-dense grid-cols-[min-content_1fr]",
        @class
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
      <div
        id={"#{@id}-nothing-yet"}
        class={[
          "hidden only:block m-2 relative block rounded-md",
          "border-2 border-dashed border-gray-500 p-12 text-center col-span-full"
        ]}
      >
        Nothing yet...
      </div>
    </div>
    """
  end
end
