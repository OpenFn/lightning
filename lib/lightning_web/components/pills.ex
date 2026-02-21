defmodule LightningWeb.Components.Pills do
  @moduledoc """
  UI component to render a pill to create tags.
  """
  use Phoenix.Component
  import LightningWeb.Components.NewInputs

  @doc """
  Renders a pill with a color.

  ## Example

  ```
  <.pill color="red">
    Red pill
  </.pill>

  ## Colors

  - `gray` **default**
  - `red`
  - `yellow`
  - `green`
  - `blue`
  - `indigo`
  - `purple`
  - `pink`
  """
  attr :color, :string,
    default: "gray",
    values: [
      "gray",
      "red",
      "yellow",
      "green",
      "blue",
      "indigo",
      "purple",
      "pink"
    ]

  slot :inner_block, required: true
  attr :rest, :global

  def pill(assigns) do
    assigns =
      assigns
      |> assign(
        class:
          case assigns[:color] do
            "gray" -> "bg-gray-100 text-gray-600"
            "red" -> "bg-red-100 text-red-700"
            "yellow" -> "bg-yellow-100 text-yellow-800"
            "green" -> "bg-green-100 text-green-700"
            "blue" -> "bg-blue-100 text-blue-700"
            "indigo" -> "bg-indigo-100 text-indigo-700"
            "purple" -> "bg-purple-100 text-purple-700"
            "pink" -> "bg-pink-100 text-pink-700"
          end
      )

    ~H"""
    <span
      class={[
        "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Renders a preview of a derived URL-safe name inside a yellow badge.

  Shows the badge only when the derived name is non-empty.

  ## Example

  ```heex
  <.name_badge name={@name} field={f[:name]}>
    Your project will be named
  </.name_badge>
  ```
  """
  attr :name, :string, required: true, doc: "The derived URL-safe name"

  attr :field, Phoenix.HTML.FormField,
    required: true,
    doc: "The hidden :name field"

  slot :inner_block

  def name_badge(assigns) do
    ~H"""
    <%= if to_string(@field.value) != "" do %>
      {render_slot(@inner_block)}
      <span class="ml-1 rounded-md border border-slate-300 bg-yellow-100 p-1 font-mono text-xs"><%= @name %></span>.
    <% end %>
    """
  end

  @doc """
  Renders a filter badge with a close button.

  ## Example

  ```
  <.filter_badge
    form={@filters_changeset}
    fields={[{:workflow_id, nil}]}
    id="workflow_badge_123"
  >
    Workflow: My Workflow
  </.filter_badge>

  <.filter_badge
    form={@filters_changeset}
    fields={[{:wo_date_after, nil}, {:wo_date_before, nil}]}
    id="workorder_date_badge"
  >
    Date range: * - *
  </.filter_badge>
  ```
  """
  attr :form, :any, required: true, doc: "The form changeset"

  attr :fields, :list,
    required: true,
    doc:
      "List of {field_name, field_value} tuples representing the fields to reset"

  attr :id, :string, required: true, doc: "Unique ID for the badge"
  slot :inner_block, required: true

  def filter_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-x-1 rounded-md bg-blue-100 px-2 py-1 text-xs font-medium text-blue-700">
      <span class="flex items-center">{render_slot(@inner_block)}</span>
      <.form
        :let={f}
        for={@form}
        as={:filters}
        class="inline"
        phx-submit="apply_filters"
      >
        <%= for {{field_name, field_value}, idx} <- Enum.with_index(@fields) do %>
          <.input
            id={"#{@id}_#{idx}"}
            type="hidden"
            field={f[field_name]}
            value={field_value}
          />
        <% end %>

        <button
          type="submit"
          class="group relative -mr-1 flex items-center justify-center h-3.5 w-3.5 rounded-sm hover:bg-blue-600/20"
          aria-label="Remove filter"
        >
          <span class="sr-only">Remove</span>
          <svg
            viewBox="0 0 14 14"
            class="h-3.5 w-3.5 stroke-blue-800/50 group-hover:stroke-blue-800/75"
          >
            <path d="M4 4l6 6m0-6l-6 6" />
          </svg>
        </button>
      </.form>
    </span>
    """
  end
end
