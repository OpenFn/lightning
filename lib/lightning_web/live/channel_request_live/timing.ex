defmodule LightningWeb.ChannelRequestLive.Timing do
  @moduledoc """
  Timing visualization components for the channel request detail page.

  Renders a segmented timing bar with TTFB marker and legend,
  computing phase breakdowns from Finch timing metrics.
  """

  use LightningWeb, :component

  import LightningWeb.ChannelRequestLive.Components,
    only: [disclosure_section: 1]

  alias LightningWeb.ChannelRequestLive.Helpers

  # --- Public components ---

  def timing_section(assigns) do
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

  # --- Timing bar ---

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
      if ttfb_us && ttfb_us > 0 && inner_total > 0 do
        Float.round(ttfb_us / inner_total * 100, 1)
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
              title={"#{seg.label}: #{Helpers.format_us(seg.us)} ms"}
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
              TTFB: {Helpers.format_us(@ttfb_us)} ms
            </span>
          </div>
        </div>
      </div>

      <div class="flex items-center justify-between mt-1">
        <span class="text-[11px] text-secondary-500 font-mono">0 ms</span>
        <span class="text-[11px] text-secondary-500 font-mono">
          {Helpers.format_us(@total_us)} ms
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
      true -> "#{Helpers.format_us(us)}ms"
    end
  end

  # --- Timing legend ---

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
        TTFB: {Helpers.format_us(@ttfb_us)} ms
      </span>
    </div>
    """
  end

  # --- Timing computation ---

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
end
