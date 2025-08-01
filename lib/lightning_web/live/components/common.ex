defmodule LightningWeb.Components.Common do
  @moduledoc false
  use LightningWeb, :component

  import LightningWeb.Components.Icons

  alias Phoenix.LiveView.JS

  defp select_icon(type) do
    case type do
      "success" -> "hero-check-circle-solid"
      "warning" -> "hero-exclamation-triangle"
      "danger" -> "hero-x-circle-solid"
      _info -> "hero-information-circle-solid"
    end
  end

  attr :id, :string, default: "alert"
  attr :type, :string, required: true
  attr :class, :string, default: ""
  attr :header, :string, default: nil
  slot :message
  attr :link_right, :map, required: false, default: nil
  attr :border, :boolean, default: false
  attr :action_position, :atom, default: :right
  attr :actions, :list, default: []

  @doc """
  Use an alert to convey critical information about the state of a specific
  system or artifact (a credential, a job, a workflow, etc.) and provide a type
  to indicate whether the alert is info, success, warning, or error.
  """
  def alert(assigns) do
    color =
      case assigns.type do
        "success" -> "green"
        "warning" -> "yellow"
        "danger" -> "red"
        _info -> "blue"
      end

    icon = select_icon(assigns.type)

    assigns =
      assign(assigns,
        color: color,
        icon: icon,
        class: assigns.class
      )

    ~H"""
    <div id={@id} class={"rounded-md bg-#{@color}-50 p-4 text-wrap #{@class}"}>
      <div class="flex">
        <div class="flex-shrink-0">
          <.icon name={@icon} class={"align-top h-5 w-5 text-#{@color}-400"} />
        </div>
        <div class={[
          "ml-3 min-w-0 flex-1",
          assigns[:link_right] && "md:flex md:justify-between"
        ]}>
          <%= if @header do %>
            <h3 class={"text-sm font-medium text-#{@color}-800"}>{@header}</h3>
            <div class={"mt-2 text-sm text-#{@color}-700"}>
              {render_slot(@message)}
            </div>
          <% else %>
            <div class={"text-sm text-#{@color}-700"}>
              {render_slot(@message)}
            </div>
          <% end %>
          <%= if assigns[:link_right] do %>
            <p class="mt-3 text-sm md:ml-6 md:mt-0">
              <a
                href={@link_right.target}
                class={"whitespace-nowrap font-medium text-#{@color}-700 hover:text-#{@color}-600"}
              >
                {@link_right.text}
                <span aria-hidden="true"> &rarr;</span>
              </a>
            </p>
          <% end %>
          <%= if Enum.count(@actions) > 0 do %>
            <div :if={@actions} class={["mt-4"]}>
              <div class="-mx-2 -my-1.5 flex">
                <%= for item <- @actions do %>
                  <%= case item do %>
                    <% %{id: id, text: text, click: click, target: target} -> %>
                      <button
                        id={id}
                        type="button"
                        phx-click={click}
                        phx-target={target}
                        class={"rounded-md bg-#{@color}-50 px-2 py-1.5 text-sm font-medium text-#{@color}-800 hover:bg-#{@color}-100 focus:outline-none focus:ring-2 focus:ring-#{@color}-600 focus:ring-offset-2 focus:ring-offset-#{@color}-50"}
                      >
                        {text}
                      </button>
                    <% element -> %>
                      {element}
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, default: "banner"

  attr :type, :string,
    default: "info",
    values: ["info", "success", "warning", "danger"]

  attr :class, :string, default: ""
  attr :message, :string, required: true
  attr :centered, :boolean, default: false
  attr :icon, :boolean, default: false
  attr :action, :map, required: false, default: nil
  attr :dismissable, :boolean, default: false

  @doc """
  Banners can sometimes be dismissed, take the full width, and can optionally
  provide a link or button to perform a single action.
  """
  def banner(assigns) do
    assigns =
      assign(assigns,
        class: ["alert-#{assigns.type}" | List.wrap(assigns.class)],
        icon_name: select_icon(assigns.type)
      )

    ~H"""
    <div
      id={@id}
      class={[
        "w-full flex items-center gap-x-6 px-6 py-2.5 sm:px-3.5",
        @centered && "sm:before:flex-1",
        @class
      ]}
    >
      <p class="text-sm leading-6">
        <%= if @icon == true do %>
          <.icon name={@icon_name} class="h-5 w-5 align-top mr-1" />
        <% end %>
        {@message}
        <%= if assigns[:action] do %>
          <a href={@action.target} class="whitespace-nowrap font-semibold">
            {@action.text}
            <span aria-hidden="true"> &rarr;</span>
          </a>
        <% end %>
      </p>
      <div class="flex flex-1 justify-end">
        <%!-- todo - add if/when we have a dismissable banner --%>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :version, :string, required: true
  attr :tooltip, :string, required: false

  def snapshot_version_chip(assigns) do
    styles =
      if assigns.version == "latest",
        do: "bg-blue-100 text-blue-800",
        else: "bg-yellow-100 text-yellow-800"

    has_tooltip? = Map.has_key?(assigns, :tooltip)

    assigns = assign(assigns, has_tooltip?: has_tooltip?, styles: styles)

    ~H"""
    <div id={"#{@id}-container"} class="flex items-middle text-sm font-normal">
      <span
        id={@id}
        {if @has_tooltip?, do: ["phx-hook": "Tooltip", "data-placement": "bottom", "aria-label": @tooltip], else: []}
        class={"inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-medium #{@styles}"}
      >
        {@version}
      </span>
    </div>
    """
  end

  attr :id, :string, required: true

  def beta_chip(assigns) do
    ~H"""
    <div id={"#{@id}-container"} class="flex items-middle text-sm font-normal ml-1">
      <span
        id={@id}
        class="inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-medium bg-purple-100 text-purple-800"
      >
        BETA
      </span>
    </div>
    """
  end

  attr :icon_classes, :string,
    default: "size-4 flex-none my-auto align-middle opacity-20"

  def version_chip(assigns) do
    {display, message, type} =
      Lightning.release()
      |> case do
        %{image_tag: "edge"} = info ->
          {info.commit,
           "Docker image tag found: '#{info.image_tag}' unreleased build from #{info.commit} on #{info.branch}",
           :edge}

        %{image_tag: image} = info when not is_nil(image) ->
          {info.label,
           "Docker image tag found: '#{info.image_tag}' tagged release build from #{info.commit}",
           :release}

        info ->
          {info.label, "Lightning #{info.vsn}", :no_docker}
      end

    assigns =
      assign(assigns,
        display: display,
        message: message,
        type: type
      )

    ~H"""
    <div class="px-3 pb-3 text-xs block flex gap-1 justify-center">
      <%= case @type do %>
        <% :release -> %>
          <.icon name="hero-check-badge" class={@icon_classes} title={@message} />
        <% :edge -> %>
          <.icon name="hero-cube" class={@icon_classes} title={@message} />
        <% :warn -> %>
          <.icon
            name="hero-exclamation-triangle"
            class={@icon_classes}
            title={@message}
          />
        <% :no_docker -> %>
      <% end %>
      <code
        class={[
          "py-1 opacity-20 rounded-md",
          "break-keep font-mono text-gray-100",
          "inline-block align-middle text-center"
        ]}
        title={"OpenFn/Lightning #{@display}"}
      >
        {@display}
      </code>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :class, :string, default: ""
  attr :icon, :string, default: "hero-information-circle-solid"
  attr :icon_class, :string, default: "w-4 h-4 text-primary-600 opacity-50"

  def tooltip(assigns) do
    classes = ~w"relative ml-1 cursor-pointer"

    assigns = assign(assigns, class: classes ++ List.wrap(assigns.class))

    ~H"""
    <span class={@class} id={@id} aria-label={@title} phx-hook="Tooltip">
      <.icon name={@icon} class={@icon_class} />
    </span>
    """
  end

  attr :id, :string, required: true
  attr :tooltip, :string, default: nil
  slot :inner_block, required: true

  def wrapper_tooltip(%{tooltip: tooltip} = assigns)
      when not is_nil(tooltip) do
    ~H"""
    <span
      id={"#{@id}-tooltip"}
      phx-hook="Tooltip"
      aria-label={@tooltip}
      data-allow-html="true"
      data-hide-on-click="false"
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :datetime, :map, required: true
  attr :id, :string, default: nil
  attr :class, :string, default: ""
  attr :show_tooltip, :boolean, default: true

  attr :format, :atom,
    default: :relative,
    values: [:relative, :detailed]

  @doc """
  Renders a datetime with click-to-copy functionality and optional hover tooltip.

  ## Format Options

  - `:relative` - Shows relative time like "2 hours ago"
  - `:detailed` - Shows absolute time like "2024-01-15 14:30:00" in user's timezone

  ## Examples

      <Common.datetime datetime={@user.inserted_at} />
      <Common.datetime datetime={@run.finished_at} format={:detailed} />
      <Common.datetime datetime={@event.created_at} class="text-gray-500" show_tooltip={false} />
  """
  def datetime(assigns) do
    clean_timestamp =
      assigns.datetime &&
        case assigns.datetime do
          %DateTime{microsecond: {microseconds, _precision}}
          when microseconds > 0 ->
            Calendar.strftime(assigns.datetime, "%Y-%m-%d %H:%M:%S.%f UTC")
            |> String.replace(~r/\.(\d{3})\d+/, ".\\1")

          _ ->
            Calendar.strftime(assigns.datetime, "%Y-%m-%d %H:%M:%S UTC")
        end

    assigns =
      assigns
      |> assign(
        id: "datetime-" <> Base.encode16(:crypto.strong_rand_bytes(4)),
        iso_timestamp: clean_timestamp,
        copy_value: clean_timestamp
      )

    ~H"""
    <%= if is_nil(@datetime) do %>
      <span class={["text-gray-400", @class]}>--</span>
    <% else %>
      <%= if @show_tooltip do %>
        <Common.wrapper_tooltip
          id={@id}
          tooltip={"#{@iso_timestamp}<br/><span class=\"text-xs text-gray-500\">Click to copy timestamp</span>"}
        >
          <span
            id={"#{@id}-outer"}
            phx-hook="LocalTimeConverter"
            data-format={@format}
            data-iso-timestamp={@iso_timestamp}
          >
            <span
              id={"#{@id}-inner"}
              class={[
                "relative inline-flex items-center cursor-pointer select-none group",
                "rounded transition-colors",
                @class
              ]}
              phx-hook="Copy"
              data-content={@copy_value}
            >
              <span class="datetime-text">{@datetime}</span>
            </span>
          </span>
        </Common.wrapper_tooltip>
      <% else %>
        <span
          id={"#{@id}-outer"}
          phx-hook="LocalTimeConverter"
          data-format={@format}
          data-iso-timestamp={@iso_timestamp}
        >
          <span
            id={@id}
            class={[
              "relative inline-flex items-center cursor-pointer select-none group",
              "rounded transition-colors",
              @class
            ]}
            phx-hook="Copy"
            data-content={@copy_value}
          >
            <span class="datetime-text">{@datetime}</span>
          </span>
        </span>
      <% end %>
    <% end %>
    """
  end

  attr :function, {:fun, 1}, required: true
  attr :args, :map, required: true

  def dynamic_component(assigns) do
    ~H"""
    {Phoenix.LiveView.TagEngine.component(
      @function,
      @args,
      {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
    )}
    """
  end

  attr :kind, :atom, required: true, values: [:error, :info]
  attr :flash, :map, required: true
  attr :rest, :global

  def flash(%{kind: :error} = assigns) do
    assigns =
      assign(assigns, msg: Phoenix.Flash.get(assigns[:flash], :error))
      |> assign_new(:id, fn ->
        "flash-" <> Base.encode16(:crypto.strong_rand_bytes(3))
      end)

    ~H"""
    <div
      :if={@msg}
      id={@id}
      data-flash-kind={@kind}
      class="rounded-md bg-red-200 border-red-300 p-4 fixed w-fit mx-auto flex justify-center bottom-3 right-0 left-0 z-[100]"
      phx-click={
        JS.push("lv:clear-flash")
        |> JS.remove_class("fade-in-scale", to: @id)
        |> hide(@id)
      }
      phx-hook="Flash"
      {@rest}
    >
      <div class="flex justify-between items-center space-x-3 text-red-900">
        <.icon name="hero-exclamation-circle-solid" class="w-5 h-5" />
        <p class="flex-1 text-sm font-medium" role="alert">
          <%= if dynamic_component?(@msg) do %>
            <.dynamic_component function={@msg.function} args={@msg.args} />
          <% else %>
            {@msg}
          <% end %>
        </p>
        <button
          type="button"
          class="inline-flex bg-red-200 rounded-md p-1.5 text-red-500 hover:bg-red-400 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-red-50 focus:ring-red-800"
        >
          <.icon
            name="hero-x-mark-solid"
            class="w-4 h-4 ml-1 mr-1 text-white-400 dark:text-white-100"
          />
        </button>
      </div>
    </div>
    """
  end

  def flash(%{kind: :info} = assigns) do
    assigns =
      assign(assigns, msg: Phoenix.Flash.get(assigns[:flash], :info))
      |> assign_new(:id, fn ->
        "flash-" <> Base.encode16(:crypto.strong_rand_bytes(3))
      end)

    ~H"""
    <div
      :if={@msg}
      id={@id}
      data-flash-kind={@kind}
      class="rounded-md bg-blue-200 border-blue-300 rounded-md p-4 fixed w-fit mx-auto flex justify-center bottom-3 right-0 left-0 z-[100]"
      phx-click={
        JS.push("lv:clear-flash")
        |> JS.remove_class("fade-in-scale")
        |> hide(@id)
      }
      phx-value-key="info"
      phx-hook="Flash"
      {@rest}
    >
      <div class="flex justify-between items-center space-x-3 text-blue-900">
        <.icon name="hero-check-circle-solid" class="w-5 h-5" />
        <p class="flex-1 text-sm font-medium" role="alert">
          <%= if dynamic_component?(@msg) do %>
            <.dynamic_component function={@msg.function} args={@msg.args} />
          <% else %>
            {@msg}
          <% end %>
        </p>
        <button
          type="button"
          class="inline-flex bg-blue-200 rounded-md p-1.5 text-blue-500 hover:bg-blue-400 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-blue-200 focus:ring-blue-800"
        >
          <.icon
            name="hero-x-mark-solid"
            class="w-4 h-4 ml-1 mr-1 text-white-400 dark:text-white-100"
          />
        </button>
      </div>
    </div>
    """
  end

  defp hide(js, selector) do
    JS.hide(js,
      to: selector,
      time: 300,
      transition:
        {"transition ease-in duration-300", "transform opacity-100 scale-100",
         "transform opacity-0 scale-95"}
    )
  end

  attr :type, :atom,
    required: true,
    values: [:step_result, :http_request, :global, :saved_input]

  def dataclip_type_pill(assigns) do
    base_classes = ~w[
      px-2 py-1 rounded-full inline-block text-sm font-mono
    ]

    class =
      base_classes ++
        case assigns[:type] do
          :step_result -> ~w[bg-purple-500 text-purple-900]
          :http_request -> ~w[bg-green-500 text-green-900]
          :global -> ~w[bg-blue-500 text-blue-900]
          :saved_input -> ~w[bg-yellow-500 text-yellow-900]
          _other -> []
        end

    assigns = assign(assigns, class: class)

    ~H"""
    <div class={@class}>
      {@type}
    </div>
    """
  end

  def combobox(assigns) do
    ~H"""
    <div id="combobox-wrapper" phx-hook="Combobox" class="relative my-4 mx-2 px-0">
      <input
        id="combobox"
        type="text"
        spellcheck="false"
        placeholder={@placeholder || "Search..."}
        value={@selected_item && @selected_item.name}
        class="w-full rounded-md border-0 py-1.5 pl-3 pr-12 shadow-xs ring-1 ring-inset focus:ring-2 sm:text-sm sm:leading-6"
        role="combobox"
        aria-controls="options"
        aria-expanded="false"
        autocomplete="off"
      />
      <button
        type="button"
        class="absolute inset-y-0 right-0 flex items-center rounded-r-md px-2 focus:outline-none"
        aria-label="Toggle dropdown"
      >
        <.icon name="hero-chevron-up-down" class="h-5 w-5 text-gray-400" />
      </button>

      <ul
        class={[
          "absolute z-10 mt-1 max-h-60 py-1 w-full overflow-auto rounded-md",
          "shadow-lg ring-1 ring-black/5",
          "text-base sm:text-sm hidden focus:outline-none"
        ]}
        id="options"
        role="listbox"
        aria-labelledby="combobox"
      >
        <li
          :for={item <- @items}
          class="group relative cursor-pointer select-none py-2 px-3 text-sm flex items-center"
          id={"option-#{item.id}"}
          role="option"
          tabindex="0"
          data-item-id={item.id}
          data-item-selected={@selected_item && @selected_item.id == item.id}
          data-url={@url_func.(item)}
        >
          <span class={[
            "font-normal truncate flex-grow mr-6",
            "group-data-[item-selected]:font-semibold"
          ]}>
            {item.name}
          </span>
          <span class={[
            "flex-shrink-0 ml-auto",
            "group-[&:not([data-item-selected])]:hidden"
          ]}>
            <.icon name="hero-check" class="w-5 h-5" />
          </span>
        </li>
      </ul>
    </div>
    """
  end

  attr :sort_direction, :string,
    values: ["asc", "desc"],
    default: "asc"

  attr :active, :boolean, required: true
  attr :rest, :global, include: ~w(id href patch navigate), default: %{href: "#"}
  slot :inner_block, required: true

  def sortable_table_header(assigns) do
    ~H"""
    <.link class="group inline-flex cursor-pointer items-center" {@rest}>
      <span>{render_slot(@inner_block)}</span>
      <span class={[
        "ml-2 flex-none rounded",
        if(@active,
          do: "bg-gray-200 text-gray-900 group-hover:bg-gray-300",
          else: "invisible text-gray-400 group-hover:visible group-focus:visible"
        )
      ]}>
        <%= if @active and @sort_direction == "desc" do %>
          <.icon name="hero-chevron-down" class="size-5" />
        <% else %>
          <.icon name="hero-chevron-up" class="size-5" />
        <% end %>
      </span>
    </.link>
    """
  end

  attr :id, :string, required: true

  attr :button_theme, :string, default: "primary"
  slot :button, required: true

  slot :options, required: true

  def simple_dropdown(assigns) do
    ~H"""
    <div id={@id} class="relative inline-block">
      <div>
        <.button
          theme={@button_theme}
          phx-click={show_dropdown("#{@id}-menu")}
          class="relative inline-flex items-center"
          aria-expanded="true"
          aria-haspopup="true"
        >
          {render_slot(@button)}
          <.icon name="hero-chevron-down" class="ml-1 h-5 w-5" />
        </.button>
      </div>
      <div
        class="hidden absolute right-0 z-40 mt-2 w-56 origin-top-right rounded-md bg-white shadow-lg ring-1 ring-black/5 focus:outline-none"
        role="menu"
        aria-orientation="vertical"
        tabindex="-1"
        phx-click-away={hide_dropdown("#{@id}-menu")}
        id={"#{@id}-menu"}
      >
        <div
          class="py-1 text-sm text-gray-700 *:block *:px-4 *:py-2 *:hover:bg-gray-100"
          role="none"
        >
          {render_slot(@options)}
        </div>
      </div>
    </div>
    """
  end
end
