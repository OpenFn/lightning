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
          <%= label(@form, @field, @label, class: @label_classes) %>
        <% else %>
          <%= label(@form, @field, class: @label_classes) %>
        <% end %>
      </div>
      <div class="grow text-right">
        <.error form={@form} field={@field} />
      </div>
    </div>
    <%= textarea(@form, @field, @opts) %>
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
      <%= label(@form, @id, @label, class: @label_classes) %>
    <% else %>
      <%= label(@form, @id, class: @label_classes) %>
    <% end %>
    <%= if assigns[:inner_block], do: render_slot(@inner_block) %>
    <%= error_tag(@form, @id, class: @error_classes) %>
    <%= password_input(@form, @id,
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
    <%= label(@form, @id, class: @label_classes) %>
    <%= error_tag(@form, @id, class: @error_classes) %>
    <%= email_input(@form, @id,
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
        input_classes: input_classes,
        opts: assigns.rest |> assigns_to_attributes()
      )

    ~H"""
    <%= if @label do %>
      <%= label(@form, @field, @label, class: @label_classes) %>
    <% else %>
      <%= label(@form, @field, class: @label_classes) %>
    <% end %>
    <%= if assigns[:inner_block], do: render_slot(@inner_block) %>
    <.error form={@form} field={@field} />
    <%= text_input(
      @form,
      @field,
      @opts ++ [class: @input_classes, required: @required, disabled: @disabled]
    ) %>
    """
  end

  attr :form, :any, required: true
  attr :field, :any, required: true

  attr :opts, :global,
    default: %{class: "block w-full text-sm text-secondary-700"}

  def error(assigns) do
    assigns =
      assigns
      |> update(:opts, &assigns_to_attributes/1)

    ~H"""
    <%= error_tag(@form, @field, @opts) %>
    """
  end

  def check_box(assigns) do
    checkbox_classes = ~w[
      "focus:ring-primary-500
      h-4
      w-4
      text-primary-600
      text-sm
      border-secondary-300
      rounded
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
        <%= checkbox(@form, @field, @checkbox_opts) %>
      </div>
      <div class="ml-3 text-sm">
        <%= error_tag(@form, @field, @error_tag_opts) %>
        <%= label(@form, @field, @label_opts) %>
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
        humanize(field)
      end)

    ~H"""
    <%= if assigns[:tooltip] do %>
      <div class="flex flex-row">
        <%= label(@form, @field, @title, @opts) %>
        <LightningWeb.Components.Common.tooltip
          id={"#{@field}-tooltip"}
          title={@tooltip}
        />
      </div>
    <% else %>
      <%= label(@form, @field, @title, @opts) %>
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
      text-sm
      focus:border-primary-300
      focus:ring
      focus:ring-primary-200
      focus:ring-opacity-50
    ]

    opts =
      assigns_to_attributes(assigns.rest, [:class, :form, :name, :values]) ++
        [class: select_classes]

    assigns = assign(assigns, opts: opts)

    ~H"""
    <%= select(@form, @name, @values, @opts) %>
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

  def form_field(assigns) do
    ~H"""
    <div class="grid grid-cols-6 gap-6">
      <div class="col-span-3">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end
end
