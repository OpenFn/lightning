defmodule LightningWeb.ChannelLive.Helpers do
  @moduledoc """
  Shared helpers for channel LiveViews.
  """
  use Phoenix.Component

  def channel_proxy_path(channel_id) do
    "/channels/#{channel_id}"
  end

  def channel_proxy_url(channel_id) do
    "#{LightningWeb.Endpoint.url()}/channels/#{channel_id}"
  end

  @doc false
  def channel_proxy_url_parts(channel_id) do
    url = channel_proxy_url(channel_id)

    case String.split(url, "://", parts: 2) do
      [scheme, rest] -> {scheme <> "://", rest}
      _ -> {"", url}
    end
  end

  @doc """
  Renders a clickable proxy URL that copies to clipboard on click.

  The entire element is a button — clicking anywhere copies the URL.
  Accepts `:leading` and `:trailing` slots for icons or other content
  flanking the URL text.

  ## Attributes

    * `:id` - Required. Used for the button and tooltip element IDs.
    * `:channel_id` - Required. The channel whose proxy URL to display.
    * `:class` - Extra classes for the outer button element.
    * `:text_class` - Extra classes for the URL text span.

  ## Slots

    * `:leading` - Content rendered before the URL text (e.g. an icon).
    * `:trailing` - Content rendered after the URL text (e.g. a copy icon).
  """
  attr :id, :string, required: true
  attr :channel_id, :string, required: true
  attr :class, :string, default: nil
  attr :text_class, :string, default: nil

  slot :leading
  slot :trailing

  def proxy_url_copy(assigns) do
    {scheme, rest} = channel_proxy_url_parts(assigns.channel_id)
    assigns = assign(assigns, scheme: scheme, url_rest: rest)

    ~H"""
    <div
      phx-hook="Copy"
      id={@id}
      data-content={channel_proxy_url(@channel_id)}
      aria-label="Copy proxy URL"
      class={[
        "group/copy flex items-center gap-1.5 leading-none cursor-pointer",
        @class
      ]}
    >
      {render_slot(@leading)}
      <span class={["flex min-w-0 font-mono text-xs translate-y-px", @text_class]}>
        <span class="shrink-0">{@scheme}</span>
        <span class="truncate" style="direction:rtl;text-align:left">
          {@url_rest}
        </span>
      </span>
      {render_slot(@trailing)}
      <span class="sr-only">Copy proxy URL</span>
    </div>
    """
  end
end
