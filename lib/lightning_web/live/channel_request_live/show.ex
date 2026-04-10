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
        <div class="space-y-4">
          <.summary_card
            channel_request={cr}
            event={event}
            channel={cr.channel}
            error_category={error_cat}
          />

          <.timing_section :if={error_cat != :credential} event={event} />

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 items-start">
            <.request_section event={event} />
            <.response_section event={event} error_category={error_cat} />
          </div>

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
            {if @event && @event.latency_us,
              do: "#{format_us(@event.latency_us)} ms",
              else: "—"}
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
    event = assigns.event

    show_body =
      event &&
        not (is_nil(event.request_body_preview) and
               is_nil(event.request_body_size))

    assigns = assign(assigns, show_body: show_body)

    ~H"""
    <.disclosure_section
      id="request-section"
      title="Request"
      open={true}
      padded={false}
    >
      <:title_right>
        <.section_size_badge
          :if={@event && @event.request_body_size && @event.request_body_size > 0}
          size={@event.request_body_size}
          id="request-size-badge"
        />
      </:title_right>
      <%= if @event do %>
        <.sub_section
          :if={@event.request_headers}
          id="req-headers"
          title="Headers"
          open={true}
        >
          <.headers_table headers={@event.request_headers} id="request-headers" />
        </.sub_section>
        <.sub_section :if={@show_body} id="req-body" title="Body" open={true}>
          <:title_right>
            <span
              :if={@event.request_body_size && @event.request_body_size > 0}
              class="text-[11px] text-secondary-400 font-mono"
            >
              {format_bytes(@event.request_body_size)}
            </span>
          </:title_right>
          <.body_viewer
            id="request-body"
            body_preview={@event.request_body_preview}
            body_hash={@event.request_body_hash}
            body_size={@event.request_body_size}
            headers={@event.request_headers}
          />
        </.sub_section>
      <% end %>
    </.disclosure_section>
    """
  end

  # --- Response Section ---

  defp response_section(assigns) do
    event = assigns.event

    show_body =
      event && is_nil(assigns.error_category) &&
        not (is_nil(event.response_body_preview) and
               is_nil(event.response_body_size))

    assigns = assign(assigns, show_body: show_body)

    ~H"""
    <.disclosure_section
      id="response-section"
      title="Response"
      open={true}
      padded={false}
    >
      <:title_right>
        <.status_code_badge
          :if={@event && @event.response_status}
          status={@event.response_status}
        />
        <.section_size_badge
          :if={@event && @event.response_body_size && @event.response_body_size > 0}
          size={@event.response_body_size}
          id="response-size-badge"
        />
      </:title_right>
      <%= if @error_category in [:transport, :credential] do %>
        <.response_empty
          type={@error_category}
          error_code={@event.error_message}
          human_message={Helpers.humanize_error(@event.error_message)}
        />
      <% else %>
        <%= if @event do %>
          <.sub_section
            :if={@event.response_headers}
            id="resp-headers"
            title="Headers"
            open={true}
          >
            <.headers_table headers={@event.response_headers} id="response-headers" />
          </.sub_section>
          <.sub_section :if={@show_body} id="resp-body" title="Body" open={true}>
            <:title_right>
              <span
                :if={@event.response_body_size && @event.response_body_size > 0}
                class="text-[11px] text-secondary-400 font-mono"
              >
                {format_bytes(@event.response_body_size)}
              </span>
            </:title_right>
            <.body_viewer
              id="response-body"
              body_preview={@event.response_body_preview}
              body_hash={@event.response_body_hash}
              body_size={@event.response_body_size}
              headers={@event.response_headers}
            />
          </.sub_section>
        <% end %>
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
    <div class="border-t border-secondary-100">
      <div class="flex flex-col items-center justify-center px-4 py-8 text-secondary-500">
        <.icon name={@icon} class="h-8 w-8 mb-3 text-secondary-400" />
        <p class="font-medium mb-1">{@label}</p>
        <p class="text-sm mb-2">{@human_message}</p>
        <code class="text-xs font-mono bg-secondary-100 px-2 py-1 rounded">
          {@error_code}
        </code>
      </div>
    </div>
    """
  end

  # --- Timing Section ---

  defp timing_section(assigns) do
    event = assigns.event

    timing_data =
      if event do
        compute_timing_segments(event)
      else
        nil
      end

    assigns = assign(assigns, timing_data: timing_data, event: event)

    ~H"""
    <div :if={@timing_data} id="timing-section">
      <.disclosure_section id="timing-section-disclosure" title="Timing" open={true}>
        <div class="space-y-3">
          <.timing_bar timing_data={@timing_data} />
          <.timing_legend timing_data={@timing_data} />
        </div>
      </.disclosure_section>
    </div>
    """
  end

  defp compute_timing_segments(event) do
    cond do
      is_nil(event.latency_us) ->
        nil

      has_finch_phases?(event) ->
        compute_full_timing(event)

      not is_nil(event.ttfb_us) ->
        compute_ttfb_timing(event)

      true ->
        compute_minimal_timing(event)
    end
  end

  defp has_finch_phases?(event) do
    not is_nil(event.request_send_us) and not is_nil(event.ttfb_us) and
      not is_nil(event.response_duration_us)
  end

  defp compute_full_timing(event) do
    queue_us = event.queue_us || 0
    connect_us = event.connect_us || 0
    send_us = event.request_send_us
    recv_us = event.response_duration_us
    ttfb_us = event.ttfb_us
    latency_us = event.latency_us

    wait_us = max(ttfb_us - queue_us - connect_us - send_us, 0)

    inner_sum = queue_us + connect_us + send_us + wait_us + recv_us

    {overhead_left_pct, overhead_right_pct} =
      compute_overhead(inner_sum, latency_us)

    reused =
      event.reused_connection == true and
        (connect_us == 0 or is_nil(event.connect_us))

    segments =
      []
      |> maybe_add_segment(queue_us > 0, %{
        label: "Queue",
        us: queue_us,
        color: "bg-amber-300",
        text_color: "text-amber-900"
      })
      |> maybe_add_connect_segment(connect_us, reused)
      |> Kernel.++([
        %{
          label: "Send",
          us: send_us,
          color: "bg-blue-400",
          text_color: "text-blue-900"
        },
        %{
          label: "Processing",
          us: wait_us,
          color: "bg-gray-300",
          text_color: "text-gray-700"
        },
        %{
          label: "Recv",
          us: recv_us,
          color: "bg-green-400",
          text_color: "text-green-900"
        }
      ])

    %{
      segments: segments,
      total_us: latency_us,
      ttfb_us: ttfb_us,
      overhead_left_pct: overhead_left_pct,
      overhead_right_pct: overhead_right_pct,
      tier: :full
    }
  end

  defp compute_ttfb_timing(event) do
    download_us = max(event.latency_us - event.ttfb_us, 0)

    segments = [
      %{
        label: "TTFB",
        us: event.ttfb_us,
        color: "bg-blue-400",
        text_color: "text-blue-900"
      },
      %{
        label: "Download",
        us: download_us,
        color: "bg-green-400",
        text_color: "text-green-900"
      }
    ]

    %{
      segments: segments,
      total_us: event.latency_us,
      ttfb_us: event.ttfb_us,
      overhead_left_pct: 0,
      overhead_right_pct: 0,
      tier: :partial
    }
  end

  defp compute_minimal_timing(event) do
    segments = [
      %{
        label: "Total",
        us: event.latency_us,
        color: "bg-blue-400",
        text_color: "text-blue-900"
      }
    ]

    %{
      segments: segments,
      total_us: event.latency_us,
      ttfb_us: nil,
      overhead_left_pct: 0,
      overhead_right_pct: 0,
      tier: :minimal
    }
  end

  defp compute_overhead(inner_sum, latency_us)
       when inner_sum >= latency_us or latency_us == 0 do
    {0, 0}
  end

  defp compute_overhead(inner_sum, latency_us) do
    gap_pct = (latency_us - inner_sum) / latency_us * 100
    half = Float.round(gap_pct / 2, 1)
    {half, half}
  end

  defp maybe_add_segment(segments, true, segment),
    do: segments ++ [segment]

  defp maybe_add_segment(segments, false, _segment), do: segments

  defp maybe_add_connect_segment(segments, _connect_us, true) do
    segments ++
      [
        %{
          label: "Connect",
          us: 0,
          color: "bg-orange-400",
          text_color: "text-orange-900",
          badge: "(reused)"
        }
      ]
  end

  defp maybe_add_connect_segment(segments, connect_us, false)
       when connect_us > 0 do
    segments ++
      [
        %{
          label: "Connect",
          us: connect_us,
          color: "bg-orange-400",
          text_color: "text-orange-900"
        }
      ]
  end

  defp maybe_add_connect_segment(segments, _connect_us, false),
    do: segments

  @hatch_gradient_style IO.iodata_to_binary([
                          "background: repeating-linear-gradient(",
                          "-45deg, ",
                          "rgba(156, 163, 175, 0.18) 0px, ",
                          "rgba(156, 163, 175, 0.18) 3px, ",
                          "rgba(209, 213, 219, 0.55) 3px, ",
                          "rgba(209, 213, 219, 0.55) 6px)"
                        ])

  defp timing_bar(assigns) do
    segments = assigns.timing_data.segments
    total_us = assigns.timing_data.total_us
    ttfb_us = assigns.timing_data.ttfb_us

    inner_total =
      Enum.reduce(segments, 0, fn s, acc -> acc + s.us end)

    inner_total = if inner_total == 0, do: 1, else: inner_total

    segments_with_pct =
      Enum.map(segments, fn s ->
        Map.put(
          s,
          :pct,
          max(Float.round(s.us / inner_total * 100, 1), 0.5)
        )
      end)

    ttfb_pct =
      if ttfb_us && ttfb_us > 0 && total_us > 0 do
        Float.round(ttfb_us / total_us * 100, 1)
      else
        nil
      end

    tier = assigns.timing_data.tier
    show_overhead = tier == :full
    seg_count = length(segments_with_pct)

    assigns =
      assign(assigns,
        segments: segments_with_pct,
        seg_count: seg_count,
        total_us: total_us,
        ttfb_us: ttfb_us,
        ttfb_pct: ttfb_pct,
        show_overhead: show_overhead,
        hatch_style: @hatch_gradient_style
      )

    ~H"""
    <div class="mt-1">
      <div class="relative">
        <%!-- Outer bar: hatch background with inner segments on top --%>
        <div
          class="w-full h-10 rounded-lg relative overflow-hidden flex items-center justify-center p-1.5"
          style={
            if(@show_overhead,
              do: @hatch_style,
              else: "background: rgb(243 244 246)"
            )
          }
        >
          <%!-- Inner phase segments --%>
          <div class="flex h-7 min-w-0 w-full">
            <div
              :for={{seg, idx} <- Enum.with_index(@segments)}
              class={[
                "flex items-center justify-center relative",
                seg.color,
                if(idx == 0, do: "rounded-l"),
                if(idx == @seg_count - 1, do: "rounded-r")
              ]}
              style={"width: #{seg.pct}%; min-width: 20px;"}
              title={"#{seg.label}: #{format_us(seg.us)} ms"}
            >
              <span
                :if={Map.get(seg, :badge)}
                class="absolute -top-5 left-1/2 -translate-x-1/2 text-[9px] font-medium text-orange-600 bg-orange-50 border border-orange-200 rounded px-1 py-0 whitespace-nowrap"
              >
                {seg.badge}
              </span>
              <span class={[
                "text-[10px] font-medium truncate px-0.5",
                seg.text_color
              ]}>
                {format_segment_label(seg)}
              </span>
            </div>
          </div>
          <%!-- TTFB marker line --%>
          <div
            :if={@ttfb_pct}
            class="absolute top-0 bottom-0 w-0.5 bg-secondary-700 z-10"
            style={"left: #{@ttfb_pct}%"}
          >
          </div>
        </div>

        <div :if={@ttfb_pct} class="relative mt-1.5 h-4">
          <div
            class="absolute flex items-center gap-1 whitespace-nowrap"
            style={"left: clamp(0px, calc(#{@ttfb_pct}% - 36px), calc(100% - 110px))"}
          >
            <.icon name="hero-arrow-up-mini" class="h-3 w-3 text-secondary-500" />
            <span class="text-[11px] font-mono font-medium text-secondary-600">
              TTFB: {format_us(@ttfb_us)} ms
            </span>
          </div>
        </div>
      </div>

      <div class="flex items-center justify-between mt-1">
        <span class="text-[11px] text-secondary-500 font-mono">0 ms</span>
        <span class="text-[11px] text-secondary-500 font-mono">
          {format_us(@total_us)} ms
        </span>
      </div>
    </div>
    """
  end

  defp format_segment_label(%{us: us} = seg) do
    ms = us / 1000

    cond do
      Map.has_key?(seg, :badge) -> ""
      us == 0 -> ""
      ms >= 1000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{format_us(us)}ms"
    end
  end

  defp timing_legend(assigns) do
    timing_data = assigns.timing_data
    segments = timing_data.segments
    ttfb_us = timing_data.ttfb_us

    show_overhead = timing_data.tier == :full

    assigns =
      assign(assigns,
        segments: segments,
        ttfb_us: ttfb_us,
        show_overhead: show_overhead,
        swatch_style: @hatch_gradient_style
      )

    ~H"""
    <div class="flex flex-wrap items-center gap-x-4 gap-y-1.5 text-xs text-secondary-500">
      <span :for={seg <- @segments} class="inline-flex items-center gap-1.5">
        <span class={[
          "inline-block w-2.5 h-2.5 rounded-sm shrink-0",
          seg.color
        ]}>
        </span>
        <span class="leading-none">{seg.label}</span>
      </span>
      <span :if={@show_overhead} class="inline-flex items-center gap-1.5">
        <span
          class="inline-block w-3 h-2.5 rounded-sm shrink-0 bg-secondary-100 border border-secondary-200"
          style={@swatch_style}
        >
        </span>
        <span class="leading-none">Proxy overhead</span>
      </span>
      <span
        :if={@ttfb_us}
        class="ml-auto inline-flex items-center font-mono text-secondary-400 leading-none"
      >
        TTFB: {format_us(@ttfb_us)} ms
      </span>
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
      |> assign_new(:padded, fn -> true end)

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
      <div
        id={"#{@id}-content"}
        class={[
          if(@padded, do: "px-4 pb-4"),
          unless(@open, do: "hidden")
        ]}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp sub_section(assigns) do
    assigns = assign_new(assigns, :title_right, fn -> [] end)

    ~H"""
    <div class="border-t border-secondary-100">
      <button
        type="button"
        class="w-full px-4 py-2.5 flex items-center justify-between cursor-pointer"
        phx-click={
          JS.toggle(to: "##{@id}-content")
          |> JS.toggle_class("rotate-180", to: "##{@id}-chevron")
        }
      >
        <div class="flex items-center gap-2">
          <span class="text-xs font-medium text-secondary-500 uppercase tracking-wider">
            {@title}
          </span>
          {render_slot(@title_right)}
        </div>
        <.icon
          id={"#{@id}-chevron"}
          name="hero-chevron-down-mini"
          class={[
            "h-4 w-4 text-secondary-400 transition-transform",
            unless(@open, do: "rotate-180")
          ]}
        />
      </button>
      <div id={"#{@id}-content"} class={["px-4 pb-3", unless(@open, do: "hidden")]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp headers_table(assigns) do
    ~H"""
    <table class="w-full text-xs">
      <tbody class="divide-y divide-secondary-50">
        <tr :for={[name, value] <- @headers}>
          <td class="py-1.5 pr-3 text-secondary-500 font-medium whitespace-nowrap align-top w-1/3">
            {name}
          </td>
          <td class={[
            "py-1.5 font-mono break-all",
            if(value == "[REDACTED]",
              do: "italic text-secondary-400",
              else: "text-secondary-700"
            )
          ]}>
            {value}
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp body_viewer(assigns) do
    content_type = extract_content_type(assigns.headers)
    is_binary_content = content_type && !text_content_type?(content_type)

    no_body =
      assigns.body_size == 0 and
        (is_nil(assigns.body_preview) or assigns.body_preview == "")

    assigns =
      assign(assigns,
        content_type: content_type,
        is_binary_content: is_binary_content,
        no_body: no_body
      )

    ~H"""
    <%= cond do %>
      <% @no_body -> %>
        <div id={@id} class="py-6 flex flex-col items-center text-secondary-400">
          <.icon name="hero-document" class="h-6 w-6 mb-1 text-secondary-300" />
          <span class="text-xs">No body</span>
        </div>
      <% @is_binary_content -> %>
        <div id={@id} class="py-4 text-sm text-secondary-500">
          <span class="text-xs font-mono bg-secondary-100 px-1.5 py-0.5 rounded">
            {format_content_type_label(@content_type)}
          </span>
          <span :if={@body_size} class="ml-2">{format_bytes(@body_size)}</span>
          <span :if={@body_hash} class="ml-2 font-mono text-xs text-secondary-400">
            SHA256: {@body_hash}
          </span>
        </div>
      <% is_nil(@body_preview) -> %>
        <div id={@id} class="py-4 text-sm text-secondary-500">
          Body not captured
          <span :if={@body_size} class="text-xs text-secondary-400 ml-1">
            ({format_bytes(@body_size)})
          </span>
        </div>
      <% true -> %>
        <div id={@id}>
          <div class="relative rounded-md bg-secondary-50 border border-secondary-200">
            <div class="absolute top-2 right-2 flex items-center gap-1.5">
              <span
                :if={@content_type}
                class="text-[10px] font-mono text-secondary-400 bg-white/80 rounded px-1.5 py-0.5"
              >
                {format_content_type_label(@content_type)}
              </span>
              <.copy_icon_button
                id={"#{@id}-copy"}
                value={@body_preview}
                title="Copy body"
                size={3}
                class="p-1 bg-white/80 rounded"
              />
            </div>
            <pre class="text-xs font-mono p-3 pr-20 max-h-80 overflow-auto text-secondary-700 whitespace-pre-wrap break-all">{@body_preview}</pre>
          </div>
          <div
            :if={@body_hash}
            class="mt-2 flex items-center gap-2 text-[11px] text-secondary-400"
          >
            <span class="font-mono">
              SHA256: {String.slice(@body_hash, 0..15)}...
            </span>
            <.copy_icon_button
              id={"#{@id}-hash-copy"}
              value={@body_hash}
              title="Copy hash"
              size={3}
            />
          </div>
          <div
            :if={
              @body_size && @body_preview && @body_size > byte_size(@body_preview)
            }
            class="mt-1 text-[11px] text-secondary-400"
          >
            Preview: {format_bytes(byte_size(@body_preview))} of {format_bytes(
              @body_size
            )}
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
  attr :class, :string, default: nil

  defp copy_icon_button(assigns) do
    ~H"""
    <button
      id={@id}
      phx-hook="Copy"
      data-content={@value}
      class={[
        "copy-btn text-secondary-400 hover:text-secondary-600 transition-colors shrink-0 cursor-pointer",
        @class
      ]}
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

  defp format_us(nil), do: "—"

  defp format_us(us) when is_number(us) do
    ms = us / 1000

    if ms == Float.round(ms),
      do: trunc(ms) |> to_string(),
      else: Float.round(ms, 1) |> to_string()
  end

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
