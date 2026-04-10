defmodule LightningWeb.ChannelRequestLive.Show do
  use LightningWeb, :live_view

  import LightningWeb.RunLive.Components, only: [channel_state_pill: 1]

  alias Lightning.Channels
  alias LightningWeb.ChannelRequestLive.Helpers

  alias Phoenix.LiveView.JS

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    %{current_user: current_user, project: project} = socket.assigns

    if Lightning.Accounts.experimental_features_enabled?(current_user) do
      case Channels.get_channel_request_for_project(project.id, id) do
        nil ->
          {:ok, redirect(socket, to: ~p"/projects/#{project}/history")}

        channel_request ->
          {:ok,
           assign(socket,
             active_menu_item: :runs,
             page_title: "Channel Request",
             request_id: id,
             channel_request: channel_request
           )}
      end
    else
      {:ok, redirect(socket, to: ~p"/projects/#{project}/history")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:breadcrumbs>
            <LayoutComponents.breadcrumbs>
              <LayoutComponents.breadcrumb_project_picker label={@project.name} />
              <LayoutComponents.breadcrumb_items items={[
                {"History", ~p"/projects/#{@project}/history"},
                {"Channels", ~p"/projects/#{@project}/history/channels"}
              ]} />
              <LayoutComponents.breadcrumb>
                <:label>
                  Channel Request
                  <span class="pl-1 font-light font-mono">
                    {display_short_uuid(@request_id)}
                  </span>
                </:label>
              </LayoutComponents.breadcrumb>
            </LayoutComponents.breadcrumbs>
          </:breadcrumbs>
        </LayoutComponents.header>
      </:header>

      <LayoutComponents.centered>
        <% cr = @channel_request %>
        <% event = primary_event(cr) %>
        <% error_cat =
          event && event.error_message && Helpers.error_category(event.error_message) %>
        <div class="space-y-6">
          <.summary_card
            channel_request={cr}
            event={event}
            channel={cr.channel}
            error_category={error_cat}
          />

          <.request_section event={event} />

          <.response_section event={event} error_category={error_cat} />

          <.timing_section :if={error_cat != :credential} event={event} />

          <.context_section
            channel_request={cr}
            snapshot={cr.channel_snapshot}
            channel={cr.channel}
          />
        </div>
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end

  # --- Summary Card ---

  defp summary_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-secondary-200 p-6">
      <div class="flex flex-wrap items-center gap-3 mb-6">
        <.method_badge method={@event && @event.request_method} />
        <.request_path_display event={@event} />
        <.status_code_display status={@event && @event.response_status} />
        <.state_pill_with_tooltip
          state={@channel_request.state}
          error_message={@event && @event.error_message}
        />
      </div>

      <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4 text-sm">
        <div>
          <dt class="text-secondary-500 text-xs uppercase tracking-wide mb-1">
            Destination
          </dt>
          <dd class="text-secondary-900 break-all font-mono text-xs">
            {@channel.destination_url}
          </dd>
        </div>
        <div>
          <dt class="text-secondary-500 text-xs uppercase tracking-wide mb-1">
            Channel
          </dt>
          <dd>
            <.link
              navigate={
                ~p"/projects/#{@channel.project_id}/channels/#{@channel.id}/edit"
              }
              class="text-primary-600 hover:text-primary-800"
            >
              {@channel.name}
            </.link>
          </dd>
        </div>
        <div>
          <dt class="text-secondary-500 text-xs uppercase tracking-wide mb-1">
            Client IP
          </dt>
          <dd class="text-secondary-900">
            {@channel_request.client_identity || "—"}
          </dd>
        </div>
        <div>
          <dt class="text-secondary-500 text-xs uppercase tracking-wide mb-1">
            Auth
          </dt>
          <dd class="text-secondary-900 flex items-center gap-1">
            <.icon name="hero-shield-check" class="h-4 w-4 text-secondary-400" />
            {format_auth_type(@channel_request.client_auth_type)}
          </dd>
        </div>
        <div>
          <dt class="text-secondary-500 text-xs uppercase tracking-wide mb-1">
            Started
          </dt>
          <dd>
            <Common.datetime datetime={@channel_request.started_at} />
          </dd>
        </div>
        <div>
          <dt class="text-secondary-500 text-xs uppercase tracking-wide mb-1">
            Completed
          </dt>
          <dd>
            <Common.datetime datetime={@channel_request.completed_at} />
          </dd>
        </div>
        <div>
          <dt class="text-secondary-500 text-xs uppercase tracking-wide mb-1">
            Latency
          </dt>
          <dd class="text-secondary-900 font-mono">
            {if @event && @event.latency_ms, do: "#{@event.latency_ms} ms", else: "—"}
          </dd>
        </div>
        <div>
          <dt class="text-secondary-500 text-xs uppercase tracking-wide mb-1">
            Request ID
          </dt>
          <dd class="flex items-center gap-1">
            <span class="text-secondary-900 font-mono text-xs truncate">
              {String.slice(@channel_request.id, 0..7)}
            </span>
            <.copy_icon_button
              id="copy-request-id"
              value={@channel_request.id}
              title="Copy request ID"
            />
          </dd>
        </div>
      </div>
    </div>
    """
  end

  defp method_badge(assigns) do
    color_class =
      case assigns.method do
        "GET" -> "bg-blue-100 text-blue-800"
        "POST" -> "bg-green-100 text-green-800"
        "PUT" -> "bg-amber-100 text-amber-800"
        "PATCH" -> "bg-amber-100 text-amber-800"
        "DELETE" -> "bg-red-100 text-red-800"
        _ -> "bg-secondary-100 text-secondary-800"
      end

    assigns = assign(assigns, color_class: color_class)

    ~H"""
    <span
      id="method-badge"
      class={[
        "inline-flex items-center px-2.5 py-0.5 rounded text-sm font-bold font-mono uppercase",
        @color_class
      ]}
    >
      {@method || "—"}
    </span>
    """
  end

  defp request_path_display(assigns) do
    ~H"""
    <span class="font-mono text-sm break-all">
      <span class="text-secondary-900">{@event && @event.request_path}</span>
      <span
        :if={
          @event && @event.request_query_string && @event.request_query_string != ""
        }
        class="text-secondary-400"
      >
        ?{@event.request_query_string}
      </span>
    </span>
    """
  end

  defp status_code_display(assigns) do
    color_class =
      case assigns.status do
        s when is_integer(s) and s >= 200 and s < 300 ->
          "text-green-700 bg-green-50"

        s when is_integer(s) and s >= 300 and s < 400 ->
          "text-blue-700 bg-blue-50"

        s when is_integer(s) and s >= 400 and s < 500 ->
          "text-amber-700 bg-amber-50"

        s when is_integer(s) and s >= 500 ->
          "text-red-700 bg-red-50"

        _ ->
          "text-secondary-400"
      end

    assigns = assign(assigns, color_class: color_class)

    ~H"""
    <span class={["font-mono text-sm font-bold px-1.5 py-0.5 rounded", @color_class]}>
      {if @status, do: to_string(@status), else: "—"}
    </span>
    """
  end

  defp state_pill_with_tooltip(assigns) do
    ~H"""
    <%= if @state == :timeout and @error_message do %>
      <Common.wrapper_tooltip
        id="state-pill-tooltip"
        tooltip={Helpers.humanize_error(@error_message)}
      >
        <.channel_state_pill state={@state} />
      </Common.wrapper_tooltip>
    <% else %>
      <.channel_state_pill state={@state} />
    <% end %>
    """
  end

  # --- Request Section ---

  defp request_section(assigns) do
    ~H"""
    <.disclosure_section id="request-section" title="Request" open={true}>
      <:title_right>
        <.section_size_badge
          :if={@event && @event.request_body_size}
          size={@event.request_body_size}
          id="request-size-badge"
        />
      </:title_right>
      <%= if @event do %>
        <.headers_table
          :if={@event.request_headers}
          headers={@event.request_headers}
          id="request-headers"
        />
        <.body_viewer
          id="request-body"
          body_preview={@event.request_body_preview}
          body_hash={@event.request_body_hash}
          body_size={@event.request_body_size}
          headers={@event.request_headers}
        />
      <% end %>
    </.disclosure_section>
    """
  end

  # --- Response Section ---

  defp response_section(assigns) do
    ~H"""
    <.disclosure_section id="response-section" title="Response" open={true}>
      <:title_right>
        <.status_code_badge
          :if={@event && @event.response_status}
          status={@event.response_status}
        />
        <.section_size_badge
          :if={@event && @event.response_body_size}
          size={@event.response_body_size}
          id="response-size-badge"
        />
      </:title_right>
      <%= if @error_category == :transport do %>
        <.response_empty
          type={:transport}
          error_code={@event.error_message}
          human_message={Helpers.humanize_error(@event.error_message)}
        />
      <% end %>
      <%= if @error_category == :credential do %>
        <.response_empty
          type={:credential}
          error_code={@event.error_message}
          human_message={Helpers.humanize_error(@event.error_message)}
        />
      <% end %>
      <%= if is_nil(@error_category) and @event do %>
        <.headers_table
          :if={@event.response_headers}
          headers={@event.response_headers}
          id="response-headers"
        />
        <.body_viewer
          id="response-body"
          body_preview={@event.response_body_preview}
          body_hash={@event.response_body_hash}
          body_size={@event.response_body_size}
          headers={@event.response_headers}
        />
      <% end %>
    </.disclosure_section>
    """
  end

  defp response_empty(assigns) do
    {icon, label} =
      case assigns.type do
        :transport ->
          {"hero-exclamation-triangle", "No response received"}

        :credential ->
          {"hero-lock-closed", "Request not sent — credential error"}
      end

    assigns = assign(assigns, icon: icon, label: label)

    ~H"""
    <div class="flex flex-col items-center justify-center py-8 text-secondary-500">
      <.icon name={@icon} class="h-8 w-8 mb-3 text-secondary-400" />
      <p class="font-medium mb-1">{@label}</p>
      <p class="text-sm mb-2">{@human_message}</p>
      <code class="text-xs font-mono bg-secondary-100 px-2 py-1 rounded">
        {@error_code}
      </code>
    </div>
    """
  end

  # --- Timing Section ---

  defp timing_section(assigns) do
    event = assigns.event

    segments =
      if event do
        compute_timing_segments(event)
      else
        nil
      end

    assigns = assign(assigns, segments: segments, event: event)

    ~H"""
    <div :if={@segments} id="timing-section">
      <.disclosure_section id="timing-section-disclosure" title="Timing" open={true}>
        <div class="space-y-3">
          <.timing_bar segments={@segments} total_ms={@event.latency_ms} />
          <.timing_legend segments={@segments} event={@event} />
        </div>
      </.disclosure_section>
    </div>
    """
  end

  defp compute_timing_segments(event) do
    cond do
      is_nil(event.latency_ms) ->
        nil

      not is_nil(event.request_send_us) and not is_nil(event.ttfb_ms) and
          not is_nil(event.response_duration_us) ->
        upload_ms = event.request_send_us / 1000
        processing_ms = max(event.ttfb_ms - upload_ms, 0)
        download_ms = event.response_duration_us / 1000

        [
          %{label: "Upload", ms: upload_ms, color: "bg-blue-400"},
          %{label: "Processing", ms: processing_ms, color: "bg-secondary-300"},
          %{label: "Download", ms: download_ms, color: "bg-green-400"}
        ]

      not is_nil(event.ttfb_ms) ->
        download_ms = max(event.latency_ms - event.ttfb_ms, 0)

        [
          %{label: "TTFB", ms: event.ttfb_ms, color: "bg-blue-400"},
          %{label: "Download", ms: download_ms, color: "bg-green-400"}
        ]

      true ->
        [%{label: "Total", ms: event.latency_ms, color: "bg-blue-400"}]
    end
  end

  defp timing_bar(assigns) do
    total = Enum.reduce(assigns.segments, 0, fn s, acc -> acc + s.ms end)
    total = if total == 0, do: 1, else: total

    segments_with_pct =
      Enum.map(assigns.segments, fn s ->
        Map.put(s, :pct, max(Float.round(s.ms / total * 100, 1), 1))
      end)

    assigns = assign(assigns, segments: segments_with_pct)

    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-xs text-secondary-500 font-mono w-12 text-right">0 ms</span>
      <div class="flex-1 flex h-8 rounded overflow-hidden">
        <div
          :for={seg <- @segments}
          class={[
            "flex items-center justify-center text-xs font-mono text-white",
            seg.color
          ]}
          style={"width: #{seg.pct}%"}
          title={"#{seg.label}: #{format_ms(seg.ms)}"}
        >
          <span :if={seg.pct > 10} class="truncate px-1">
            {format_ms(seg.ms)}
          </span>
        </div>
      </div>
      <span class="text-xs text-secondary-500 font-mono w-16">
        {format_ms(@total_ms)} ms
      </span>
    </div>
    """
  end

  defp timing_legend(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-4 text-xs text-secondary-600">
      <div :for={seg <- @segments} class="flex items-center gap-1.5">
        <span class={["inline-block w-3 h-3 rounded-sm", seg.color]}></span>
        <span>{seg.label}: {format_ms(seg.ms)} ms</span>
      </div>
      <div :if={@event.ttfb_ms} class="flex items-center gap-1.5 text-secondary-500">
        TTFB: {@event.ttfb_ms} ms
      </div>
    </div>
    """
  end

  # --- Context Section ---

  defp context_section(assigns) do
    config_changed =
      assigns.snapshot.lock_version != assigns.channel.lock_version

    assigns = assign(assigns, config_changed: config_changed)

    ~H"""
    <.disclosure_section id="context-section" title="Context" open={false}>
      <div class="grid grid-cols-2 md:grid-cols-3 gap-4 text-sm">
        <div>
          <dt class="text-secondary-500 text-xs uppercase tracking-wide mb-1">
            Destination URL
          </dt>
          <dd class="text-secondary-900 break-all font-mono text-xs">
            {@snapshot.destination_url}
          </dd>
        </div>
        <div>
          <dt class="text-secondary-500 text-xs uppercase tracking-wide mb-1">
            Channel Name
          </dt>
          <dd class="text-secondary-900">{@snapshot.name}</dd>
        </div>
        <div>
          <dt class="text-secondary-500 text-xs uppercase tracking-wide mb-1">
            Config Version
          </dt>
          <dd class="flex items-center gap-2">
            <span class="text-secondary-900">{@snapshot.lock_version}</span>
            <span
              :if={@config_changed}
              class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-yellow-100 text-yellow-800"
            >
              Config changed
            </span>
          </dd>
        </div>
      </div>
    </.disclosure_section>
    """
  end

  # --- Shared Components ---

  defp disclosure_section(assigns) do
    assigns =
      assigns
      |> assign_new(:title_right, fn -> [] end)

    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-secondary-200">
      <button
        type="button"
        class="w-full flex items-center justify-between p-4 text-left cursor-pointer"
        phx-click={
          JS.toggle(to: "##{@id}-content")
          |> JS.toggle_class("rotate-180", to: "##{@id}-chevron")
        }
      >
        <div class="flex items-center gap-3">
          <h3 class="text-sm font-semibold text-secondary-900">{@title}</h3>
          {render_slot(@title_right)}
        </div>
        <.icon
          id={"#{@id}-chevron"}
          name="hero-chevron-down-mini"
          class={[
            "h-5 w-5 text-secondary-400 transition-transform",
            unless(@open, do: "rotate-180")
          ]}
        />
      </button>
      <div id={"#{@id}-content"} class={["px-4 pb-4", unless(@open, do: "hidden")]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp headers_table(assigns) do
    ~H"""
    <div class="mb-4">
      <h4 class="text-xs font-medium text-secondary-500 uppercase tracking-wide mb-2">
        Headers
      </h4>
      <table class="w-full text-sm">
        <tbody>
          <tr
            :for={[name, value] <- @headers}
            class="border-b border-secondary-100 last:border-0"
          >
            <td class="py-1.5 pr-4 text-secondary-500 font-medium whitespace-nowrap align-top">
              {name}
            </td>
            <td class={[
              "py-1.5 font-mono text-xs break-all",
              if(value == "[REDACTED]",
                do: "italic text-secondary-400",
                else: "text-secondary-900"
              )
            ]}>
              {value}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp body_viewer(assigns) do
    content_type = extract_content_type(assigns.headers)
    is_binary_content = content_type && !text_content_type?(content_type)

    assigns =
      assign(assigns,
        content_type: content_type,
        is_binary_content: is_binary_content
      )

    ~H"""
    <%= cond do %>
      <% is_nil(@body_preview) and is_nil(@body_size) -> %>
        <%!-- Hide entirely when both preview and size are nil --%>
      <% @is_binary_content -> %>
        <div id={@id} class="text-sm text-secondary-500 py-4">
          <span class="text-xs font-mono bg-secondary-100 px-1.5 py-0.5 rounded">
            {format_content_type_label(@content_type)}
          </span>
          <span :if={@body_size} class="ml-2">{format_bytes(@body_size)}</span>
          <span :if={@body_hash} class="ml-2 font-mono text-xs text-secondary-400">
            {@body_hash}
          </span>
        </div>
      <% is_nil(@body_preview) -> %>
        <div id={@id} class="text-sm text-secondary-500 py-4">
          Body not captured
          <span :if={@body_size} class="text-xs text-secondary-400 ml-1">
            ({format_bytes(@body_size)})
          </span>
        </div>
      <% true -> %>
        <div id={@id} class="mt-2">
          <div class="flex items-center gap-2 mb-2">
            <span
              :if={@content_type}
              class="text-xs font-mono bg-secondary-100 px-1.5 py-0.5 rounded text-secondary-600"
            >
              {format_content_type_label(@content_type)}
            </span>
            <.copy_icon_button
              id={"#{@id}-copy"}
              value={@body_preview}
              title="Copy body"
            />
            <span
              :if={
                @body_size && @body_preview && @body_size > byte_size(@body_preview)
              }
              class="text-xs text-secondary-400"
            >
              Preview: {format_bytes(byte_size(@body_preview))} of {format_bytes(
                @body_size
              )}
            </span>
          </div>
          <pre class="bg-secondary-50 border border-secondary-200 rounded p-3 text-xs font-mono text-secondary-900 max-h-80 overflow-auto whitespace-pre-wrap break-all">{@body_preview}</pre>
          <div
            :if={@body_hash}
            class="mt-1 flex items-center gap-1 text-xs text-secondary-400"
          >
            <span class="font-mono">{String.slice(@body_hash, 0..11)}</span>
            <.copy_icon_button
              id={"#{@id}-hash-copy"}
              value={@body_hash}
              title="Copy hash"
              size={3}
            />
          </div>
        </div>
    <% end %>
    """
  end

  defp status_code_badge(assigns) do
    color_class =
      case assigns.status do
        s when s >= 200 and s < 300 -> "bg-green-100 text-green-700"
        s when s >= 300 and s < 400 -> "bg-blue-100 text-blue-700"
        s when s >= 400 and s < 500 -> "bg-amber-100 text-amber-700"
        s when s >= 500 -> "bg-red-100 text-red-700"
        _ -> "bg-secondary-100 text-secondary-700"
      end

    assigns = assign(assigns, color_class: color_class)

    ~H"""
    <span class={[
      "inline-flex items-center rounded px-1.5 py-0.5 text-xs font-mono font-bold",
      @color_class
    ]}>
      {@status}
    </span>
    """
  end

  defp section_size_badge(assigns) do
    ~H"""
    <span id={@id} class="text-xs text-secondary-400 font-mono">
      {format_bytes(@size)}
    </span>
    """
  end

  attr :id, :string, required: true
  attr :value, :string, required: true
  attr :title, :string, default: "Copy"
  attr :size, :integer, default: 4

  defp copy_icon_button(assigns) do
    ~H"""
    <button
      id={@id}
      phx-hook="Copy"
      data-content={@value}
      class="copy-btn text-secondary-400 hover:text-secondary-600 transition-colors shrink-0 cursor-pointer"
      title={@title}
    >
      <.icon name="hero-clipboard" class={"h-#{@size} w-#{@size}"} />
    </button>
    """
  end

  # --- Helpers ---

  defp primary_event(channel_request) do
    channel_request.channel_events
    |> Enum.find(&(&1.type == :destination_response)) ||
      Enum.find(channel_request.channel_events, &(&1.type == :error))
  end

  defp format_auth_type(nil), do: "None"
  defp format_auth_type("api"), do: "API key"
  defp format_auth_type("basic"), do: "Basic auth"
  defp format_auth_type(type), do: type

  defp format_bytes(nil), do: "—"

  defp format_bytes(bytes) when bytes < 1024,
    do: "#{bytes} B"

  defp format_bytes(bytes) when bytes < 1_048_576,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes),
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_ms(ms) when is_float(ms) do
    if ms == Float.round(ms),
      do: trunc(ms) |> to_string(),
      else: Float.round(ms, 1) |> to_string()
  end

  defp format_ms(ms), do: to_string(ms)

  defp extract_content_type(nil), do: nil

  defp extract_content_type(headers) do
    headers
    |> Enum.find(fn [name, _] -> String.downcase(name) == "content-type" end)
    |> case do
      [_, value] -> value
      nil -> nil
    end
  end

  defp text_content_type?(ct) do
    String.contains?(ct, "text/") or
      String.contains?(ct, "json") or
      String.contains?(ct, "xml") or
      String.contains?(ct, "javascript") or
      String.contains?(ct, "html")
  end

  defp format_content_type_label(ct) when is_binary(ct) do
    cond do
      String.contains?(ct, "json") -> "JSON"
      String.contains?(ct, "xml") -> "XML"
      String.contains?(ct, "html") -> "HTML"
      String.contains?(ct, "text/") -> "TEXT"
      true -> ct
    end
  end

  defp format_content_type_label(_), do: nil
end
