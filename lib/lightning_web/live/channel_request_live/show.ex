defmodule LightningWeb.ChannelRequestLive.Show do
  use LightningWeb, :live_view

  import LightningWeb.ChannelRequestLive.Components

  import LightningWeb.ChannelRequestLive.Timing,
    only: [timing_section: 1]

  alias Lightning.Channels
  alias LightningWeb.ChannelRequestLive.Helpers

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
        <% event = Helpers.primary_event(cr) %>
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
            {Helpers.format_auth_type(@channel_request.client_auth_type)}
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
              do: "#{Helpers.format_us(@event.latency_us)} ms",
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
              {Helpers.format_bytes(@event.request_body_size)}
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
                {Helpers.format_bytes(@event.response_body_size)}
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
end
