defmodule LightningWeb.Components.Form do
  @moduledoc false
  use LightningWeb, :component

  slot :inner_block, required: true
  attr :changeset, :map
  attr :rest, :global, include: ~w(form disabled)

  @spec submit_button(Phoenix.LiveView.Socket.assigns()) :: any()
  def submit_button(assigns) do
    base_classes = ~w[
      inline-flex
      justify-center
      py-2
      px-4
      border
      border-transparent
      shadow-sm
      text-sm
      font-medium
      rounded-md
      text-white
      focus:outline-none
      focus:ring-2
      focus:ring-offset-2
      focus:ring-primary-500
    ]

    inactive_classes = ~w[
      bg-primary-300
    ] ++ base_classes

    active_classes = ~w[
      bg-primary-600
      hover:bg-primary-700
    ] ++ base_classes

    assigns =
      assigns
      |> assign_new(:class, fn -> "" end)
      |> update(:class, fn class, %{rest: rest} ->
        if rest[:disabled] do
          inactive_classes
        else
          active_classes
        end
        |> Enum.concat(List.wrap(class))
      end)

    ~H"""
    <button type="submit" class={@class} {@rest}>
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: false
  attr :rest, :global, include: ~w(disabled), default: %{class: ~w[
      rounded-md
      w-full
      font-mono
      bg-slate-800
      text-slate-50
      h-96
    ] |> Enum.join(" ")}

  def text_area(assigns) do
    label_classes = ~w[
      block
      text-sm
      font-medium
      text-secondary-700
    ]

    assigns =
      assigns
      |> assign(
        label_classes: label_classes,
        opts: assigns.rest |> Enum.into([])
      )
      |> assign_new(:label, fn -> false end)

    ~H"""
    <div class="flex">
      <div class="shrink">
        <%= if @label do %>
          <%= Phoenix.HTML.Form.label(@form, @field, @label, class: @label_classes) %>
        <% else %>
          <%= Phoenix.HTML.Form.label(@form, @field, class: @label_classes) %>
        <% end %>
      </div>
      <div class="grow text-right">
        <.old_error field={@form[@field]} />
      </div>
    </div>
    <%= Phoenix.HTML.Form.textarea(@form, @field, @opts) %>
    """
  end

  def password_field(assigns) do
    label_classes = ~w[
      block
      text-sm
      font-medium
      text-secondary-700
    ]

    error_classes = ~w[
      block
      w-full
      rounded-md
      text-sm
      text-secondary-700
    ]

    input_classes = ~w[
      mt-1
      focus:ring-primary-500
      focus:border-primary-500
      block w-full
      shadow-sm
      sm:text-sm
      border-secondary-300
      rounded-md
    ]

    assigns =
      assigns
      |> assign(
        label_classes: label_classes,
        error_classes: error_classes,
        input_classes: input_classes
      )
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:hint, fn -> nil end)
      |> assign_new(:required, fn -> false end)
      |> assign_new(:value, fn -> nil end)

    ~H"""
    <%= if @label do %>
      <%= Phoenix.HTML.Form.label(@form, @id, @label, class: @label_classes) %>
    <% else %>
      <%= Phoenix.HTML.Form.label(@form, @id, class: @label_classes) %>
    <% end %>
    <%= if assigns[:inner_block], do: render_slot(@inner_block) %>

    <LightningWeb.CoreComponents.old_error field={@form[@id]} />
    <%= Phoenix.HTML.Form.password_input(@form, @id,
      class: @input_classes,
      required: @required,
      value: @value
    ) %>
    """
  end

  def email_field(assigns) do
    label_classes = ~w[
      block
      text-sm
      font-medium
      text-secondary-700
    ]

    error_classes = ~w[
      block
      w-full
      rounded-md
    ]

    input_classes = ~w[
      mt-1
      focus:ring-primary-500
      focus:border-primary-500
      block w-full
      shadow-sm
      sm:text-sm
      border-secondary-300
      rounded-md
    ]

    assigns =
      assign(assigns,
        label_classes: label_classes,
        error_classes: error_classes,
        input_classes: input_classes
      )
      |> assign_new(:required, fn -> false end)

    ~H"""
    <%= Phoenix.HTML.Form.label(@form, @id, class: @label_classes) %>
    <LightningWeb.CoreComponents.old_error field={@form[@id]} />
    <%= Phoenix.HTML.Form.email_input(@form, @id,
      class: @input_classes,
      required: @required
    ) %>
    """
  end

  @doc """
  Generic text field wrapper for forms. Expects:

  * `form` - The form
  * `field` - The field key

  And optionally:

  * `label` - To override the string used in the field label.

  An inner block for a 'hint' section which is rendered below the label.

  ```
  <.text_field form={f} field={:discovery_url} label="Discovery URL">
    <span class="text-xs text-secondary-500">
      The URL to the <code>.well-known</code> endpoint.
    </span>
  </.text_field>
  ```
  """

  attr :form, :map, required: true
  attr :field, :any, required: true
  attr :label, :string, default: nil
  attr :hint, :string, default: nil
  attr :required, :boolean, default: false
  attr :disabled, :boolean, default: false
  slot :inner_block, required: false
  attr :rest, :global

  def text_field(assigns) do
    label_classes = ~w[
      block
      text-sm
      font-medium
      text-secondary-700
    ]

    error_classes = ~w[
      block
      w-full
      text-sm
      text-secondary-700
    ]

    input_classes = ~w[
      block
      w-full
      rounded-md
      border-0
      py-1.5
      text-gray-900
      shadow-sm
      ring-1
      ring-gray-300
      placeholder:text-gray-400
      focus:ring-2
      focus:ring-inset
      focus:ring-indigo-600
      disabled:cursor-not-allowed
      disabled:bg-gray-50
      disabled:text-gray-500
      disabled:ring-gray-200
      sm:text-sm
      sm:leading-6
    ]

    assigns =
      assigns
      |> assign(
        label_classes: label_classes,
        error_classes: error_classes,
        input_classes: input_classes,
        opts: assigns.rest |> assigns_to_attributes()
      )

    ~H"""
    <%= if @label do %>
      <%= Phoenix.HTML.Form.label(@form, @field, @label, class: @label_classes) %>
    <% else %>
      <%= Phoenix.HTML.Form.label(@form, @field, class: @label_classes) %>
    <% end %>
    <%= if assigns[:inner_block], do: render_slot(@inner_block) %>
    <%= Phoenix.HTML.Form.text_input(
      @form,
      @field,
      @opts ++ [class: @input_classes, required: @required, disabled: @disabled]
    ) %>
    <.old_error field={@form[@field]} />
    """
  end

  attr :form, :map, required: true
  attr :field, :any, required: true
  attr :label, :string, default: nil
  attr :disabled, :boolean
  attr :checked_value, :boolean
  attr :unchecked_value, :boolean
  attr :value, :boolean

  slot :inner_block,
    doc: "optional additional description to the label"

  def check_box(assigns) do
    checkbox_classes = ~w[
      focus:ring-primary-500
      h-4
      w-4
      text-primary-600
      text-sm
      border-secondary-300
      rounded
      disabled:bg-gray-300
      focus:disabled:ring-gray-300
      disabled:text-gray-300
    ]

    error_tag_classes = ~w[
      mt-1
      focus:ring-primary-500
      focus:border-primary-500
      block
      w-full
      shadow-sm
      text-sm
      border-secondary-300
      rounded-md
    ]

    label_classes = ~w[
      font-medium
      text-secondary-700
    ]

    opts = assigns_to_attributes(assigns, [:id, :form])

    assigns =
      assign(assigns,
        checkbox_opts: opts ++ [class: checkbox_classes],
        label_opts: opts ++ [class: label_classes],
        error_tag_opts: opts ++ [class: error_tag_classes]
      )

    ~H"""
    <div class="flex items-start">
      <div class="flex items-center h-5">
        <%= Phoenix.HTML.Form.checkbox(@form, @field, @checkbox_opts) %>
      </div>
      <div class="ml-3 text-sm">
        <LightningWeb.CoreComponents.old_error field={@form[@field]} />
        <%= Phoenix.HTML.Form.label(@form, @label || @field, @label_opts) %>
        <%= if assigns[:inner_block] do %>
          <%= render_slot(@inner_block) %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :field, :any, required: true
  attr :title, :string
  attr :logo, :string, default: nil
  attr :tooltip, :string
  attr :opts, :global, include: ~w(for value)

  def label_field(assigns) do
    label_classes = ~w[
      block
      text-sm
      font-medium
      text-secondary-700
    ]

    assigns =
      assigns
      |> update(:opts, fn opts ->
        assigns_to_attributes(opts)
        |> Keyword.put_new(:class, label_classes)
      end)
      |> assign_new(:title, fn %{field: field} ->
        Phoenix.HTML.Form.humanize(field)
      end)

    ~H"""
    <%= if assigns[:tooltip] do %>
      <div class="flex flex-row">
        <%= Phoenix.HTML.Form.label(@form, @field, @opts) do %>
          <div class="flex items-center">
            <%= @title %>
            <%= if @logo do %>
              <img src={@logo} class="w-3 h-3 ml-1" />
            <% end %>
          </div>
        <% end %>
        <LightningWeb.Components.Common.tooltip
          id={"#{@field}-tooltip"}
          title={@tooltip}
        />
      </div>
    <% else %>
      <%= Phoenix.HTML.Form.label(@form, @field, @opts) do %>
        <div class="flex items-center">
          <%= @title %>
          <%= if @logo do %>
            <img src={@logo} class="w-3 h-3 ml-1" />
          <% end %>
        </div>
      <% end %>
    <% end %>
    """
  end

  attr :form, :any
  attr :name, :any
  attr :values, :list
  attr :value, :any, required: false
  attr :rest, :global, include: ~w(selected disabled prompt)

  def select_field(assigns) do
    select_classes = ~w[
      mt-1
      block
      w-full
      rounded-md
      border-secondary-300
      shadow-sm
      text-md
      font-medium
      focus:border-primary-300
      focus:ring
      focus:ring-primary-200
      focus:ring-opacity-50
      disabled:cursor-not-allowed
    ]

    opts =
      assigns_to_attributes(assigns.rest, [:class, :form, :name, :values]) ++
        [class: select_classes]

    assigns = assign(assigns, opts: opts)

    ~H"""
    <%= Phoenix.HTML.Form.select(@form, @name, @values, @opts) %>
    """
  end

  def select(assigns) do
    select_classes = ~w[
      block
      w-full
      rounded-md
      border-secondary-300
      sm:text-sm
      shadow-sm
      focus:border-primary-300
      focus:ring
      focus:ring-primary-200
      focus:ring-opacity-50
      disabled:cursor-not-allowed
    ]

    opts = assigns_to_attributes(assigns) ++ [class: select_classes]

    assigns = assigns |> assign(opts: opts)

    ~H"""
    <select {@opts}>
      <%= render_slot(@inner_block) %>
    </select>
    """
  end

  def divider(assigns) do
    ~H"""
    <div class="hidden sm:block" aria-hidden="true">
      <div class="py-5">
        <div class="border-t border-secondary-200"></div>
      </div>
    </div>
    """
  end
end
