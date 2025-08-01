defmodule LightningWeb.Components.Table do
  @moduledoc """
  A collection of composable table components for building consistent, flexible tables across the Lightning application.

  This module provides a set of table primitives that can be composed together to create tables
  with consistent styling, sorting capabilities, and pagination support. The components are designed
  to be flexible while maintaining a unified look and feel.

  ## Features

  - Consistent styling with proper spacing, borders, and hover states
  - Built-in support for pagination
  - Sortable columns with visual indicators
  - Flexible cell content handling
  - Support for header, body, and footer sections
  - Responsive design with proper overflow handling

  ## Example

  ```elixir
  <.table page={@page} url={@pagination_path}>
    <:header>
      <.tr>
        <.th sortable={true} sort_by="name" active={@sort_key == "name"}>
          Name
        </.th>
        <.th>Email</.th>
      </.tr>
    </:header>
    <:body>
      <%= for user <- @users do %>
        <.tr>
          <.td>{user.name}</.td>
          <.td>{user.email}</.td>
        </.tr>
      <% end %>
    </:body>
  </.table>
  ```
  """
  use Phoenix.Component

  import LightningWeb.Components.Icons

  alias LightningWeb.Components.Common

  @doc """
  Renders a table container with optional pagination.

  ## Attributes

  - `:page` - Optional map containing pagination information
  - `:url` - Optional URL or function for pagination links
  - `:id` - Optional HTML id attribute
  - `:class` - Optional additional CSS classes

  ## Slots

  - `:header` - Content for the table header (thead)
  - `:body` - Content for the table body (tbody)
  - `:footer` - Optional content for the table footer (tfoot)

  ## Example

  ```elixir
  <.table page={@page} url={@pagination_path}>
    <:header>
      <.tr>
        <.th>Name</.th>
        <.th>Email</.th>
      </.tr>
    </:header>
    <:body>
      <%= for user <- @users do %>
        <.tr>
          <.td>{user.name}</.td>
          <.td>{user.email}</.td>
        </.tr>
      <% end %>
    </:body>
  </.table>
  ```
  """
  slot :header
  slot :body
  slot :footer
  attr :class, :string, default: nil
  attr :page, :map, default: nil
  attr :url, :any, default: nil
  attr :id, :string, default: nil
  attr :divide, :boolean, default: true

  def table(assigns) do
    ~H"""
    <div
      id={@id}
      class="overflow-x-auto shadow ring-1 ring-black/5 sm:rounded-lg bg-gray-50"
    >
      <table class={["min-w-full", @divide && "divide-y divide-gray-200"]}>
        <thead>{render_slot(@header)}</thead>
        <tbody class={[
          "bg-white",
          @divide && "divide-y divide-gray-200"
        ]}>
          {render_slot(@body)}
        </tbody>
        <%= for footer <- @footer do %>
          <tfoot>{footer}</tfoot>
        <% end %>
      </table>
      <%= if @page && @url do %>
        <div class={!@divide && "border-t border-gray-200"}>
          <LightningWeb.Pagination.pagination_bar page={@page} url={@url} />
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a table row with hover effects and optional click handling.

  ## Attributes

  - `:class` - Optional additional CSS classes
  - `:id` - Optional HTML id attribute
  - `:onclick` - Optional Phoenix LiveView click event handler

  ## Slots

  - `:inner_block` - Required content for the table row

  ## Example

  ```elixir
  <.tr id={"user-123"} onclick={JS.navigate(~p"/users/123")}>
    <.td>{user.name}</.td>
    <.td>{user.email}</.td>
  </.tr>
  ```
  """
  slot :inner_block, required: true
  attr :class, :string, default: nil
  attr :id, :string, default: nil
  attr :onclick, :any, default: nil

  def tr(assigns) do
    ~H"""
    <tr
      id={@id}
      phx-click={@onclick}
      class={[
        "transition-colors duration-150",
        "has-[td]:hover:bg-gray-50",
        @onclick && "cursor-pointer",
        "last:rounded-b-lg",
        "[&>td:first-child]:py-4 [&>td:first-child]:pr-3 [&>td:first-child]:pl-4 [&>td:first-child]:sm:pl-6",
        "[&>th:first-child]:py-3.5 [&>th:first-child]:pr-3 [&>th:first-child]:pl-4 [&>th:first-child]:sm:pl-6",
        "[&>td:not(:first-child):not(:last-child)]:px-3 [&>td:not(:first-child):not(:last-child)]:py-4",
        "[&>th:not(:first-child):not(:last-child)]:px-3 [&>th:not(:first-child):not(:last-child)]:py-3.5",
        "[&>td:last-child]:relative [&>td:last-child]:py-4 [&>td:last-child]:pr-4 [&>td:last-child]:pl-3 [&>td:last-child]:sm:pr-6",
        "[&>th:last-child]:relative [&>th:last-child]:py-3.5 [&>th:last-child]:pr-4 [&>th:last-child]:pl-3 [&>th:last-child]:sm:pr-6",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </tr>
    """
  end

  @doc """
  Renders a table header cell with optional sorting capabilities.

  ## Attributes

  - `:class` - Optional additional CSS classes
  - `:id` - Optional HTML id attribute
  - `:scope` - HTML scope attribute (default: "col")
  - `:colspan` - Optional number of columns to span
  - `:sortable` - Whether the column is sortable (default: false)
  - `:sort_by` - The field to sort by when clicked
  - `:active` - Whether this column is currently being sorted
  - `:sort_direction` - Current sort direction ("asc" or "desc")
  - `:phx_click` - Phoenix LiveView click event (default: "sort")
  - `:phx_target` - Target for the click event

  ## Slots

  - `:inner_block` - Required content for the header cell

  ## Example

  ```elixir
  <.th
    sortable={true}
    sort_by="name"
    active={@sort_key == "name"}
    sort_direction={@sort_direction}
    phx-target={@myself}
  >
    Name
  </.th>
  ```
  """
  slot :inner_block, required: true
  attr :class, :string, default: nil
  attr :id, :string, default: nil
  attr :scope, :string, default: "col"
  attr :colspan, :integer, default: nil
  attr :sortable, :boolean, default: false
  attr :sort_by, :string, default: nil
  attr :active, :boolean, default: false
  attr :sort_direction, :string, default: nil
  attr :phx_click, :string, default: "sort"
  attr :phx_target, :any, default: nil

  def th(assigns) do
    ~H"""
    <th
      id={@id}
      scope={@scope}
      colspan={@colspan}
      class={[
        "text-sm text-left font-semibold text-gray-900 select-none whitespace-nowrap",
        @class
      ]}
    >
      <%= if @sortable && @sort_by do %>
        <Common.sortable_table_header
          phx-click={@phx_click}
          phx-value-by={@sort_by}
          active={@active}
          sort_direction={@sort_direction}
          phx-target={@phx_target}
        >
          {render_slot(@inner_block)}
        </Common.sortable_table_header>
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </th>
    """
  end

  @doc """
  Renders a table data cell with consistent styling and spacing.

  ## Attributes

  - `:class` - Optional additional CSS classes
  - `:id` - Optional HTML id attribute
  - `:colspan` - Optional number of columns to span
  - `:rowspan` - Optional number of rows to span

  ## Slots

  - `:inner_block` - Required content for the data cell

  ## Example

  ```elixir
  <.td class="wrap-break-word max-w-[25rem]">
    {user.name}
  </.td>
  ```
  """
  slot :inner_block, required: true
  attr :class, :string, default: nil
  attr :id, :string, default: nil
  attr :rest, :global, include: ~w(colspan rowspan)

  def td(assigns) do
    ~H"""
    <td
      id={@id}
      class={[
        "text-sm text-gray-500 first:rounded-bl-lg last:rounded-br-lg",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </td>
    """
  end

  attr :icon, :string, default: "hero-plus-circle"
  attr :message, :string, required: true
  attr :button_text, :string, default: nil
  attr :button_id, :string, default: nil
  attr :button_click, :any, default: nil
  attr :button_disabled, :boolean, default: false
  attr :button_target, :any, default: nil
  attr :button_action_value, :any, default: nil
  attr :interactive, :boolean, default: true
  attr :rest, :global

  def empty_state(assigns) do
    ~H"""
    <%= if @interactive do %>
      <button
        type="button"
        id={@button_id}
        phx-click={@button_click}
        phx-target={@button_target}
        phx-value-action={@button_action_value}
        class="relative block w-full rounded-lg border-2 border-dashed border-gray-300 p-4 text-center hover:border-gray-400 disabled:hover:border-gray-300 focus:outline-none"
        disabled={@button_disabled}
        {@rest}
      >
        <.icon name={@icon} class="mx-auto w-12 h-12 text-secondary-400" />
        <span class="mt-2 block text-xs font-semibold text-secondary-600">
          {@button_text}
        </span>
        <div class="mt-2 text-xs text-gray-500">
          {@message}
        </div>
      </button>
    <% else %>
      <div class="relative block w-full rounded-lg border-2 border-dashed border-gray-300 p-4 text-center">
        <.icon name={@icon} class="mx-auto w-12 h-12 text-secondary-400" />
        <div class="mt-2 text-xs text-gray-500">
          {@message}
        </div>
      </div>
    <% end %>
    """
  end
end
