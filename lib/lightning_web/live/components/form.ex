defmodule LightningWeb.Components.Form do
  @moduledoc false
  use LightningWeb, :component

  slot(:inner_block, required: true)
  attr(:changeset, :map)
  attr(:rest, :global, include: ~w(form disabled))

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

  def text_area(assigns) do
    classes = ~w[
      rounded-md
      w-full
      font-mono
      bg-slate-800
      text-slate-50
      h-96
      min-h-full
    ]

    label_classes = ~w[
      block
      text-sm
      font-medium
      text-secondary-700
    ]

    assigns =
      assigns
      |> assign(label_classes: label_classes)
      |> assign_new(:classes, fn -> classes end)

    ~H"""
    <%= if @label do %>
      <%= label(@form, @id, @label, class: @label_classes) %>
    <% end %>
    <%= error_tag(@form, @id) %>
    <%= textarea(@form, @id, class: @classes) %>
    """
  end

  def hidden_input(assigns) do
    ~H"""
    <%= textarea(@form, @id, class: "hidden") %>
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
  * `id` - The field key

  And optionally:

  * `label` - To override the string used in the field label.

  An inner block for a 'hint' section which is rendered below the label.

  ```
  <.text_field form={f} id={:discovery_url} label="Discovery URL">
    <span class="text-xs text-secondary-500">
      The URL to the <code>.well-known</code> endpoint.
    </span>
  </.text_field>
  ```
  """
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

    opts = assigns_to_attributes(assigns, [:id, :form, :name, :values])

    assigns =
      assigns
      |> assign(
        label_classes: label_classes,
        error_classes: error_classes,
        input_classes: input_classes,
        opts: opts
      )
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:hint, fn -> nil end)
      |> assign_new(:required, fn -> false end)
      |> assign_new(:disabled, fn -> false end)

    ~H"""
    <%= if @label do %>
      <%= label(@form, @id, @label, class: @label_classes) %>
    <% else %>
      <%= label(@form, @id, class: @label_classes) %>
    <% end %>
    <%= if assigns[:inner_block], do: render_slot(@inner_block) %>
    <%= error_tag(@form, @id, class: @error_classes) %>
    <%= text_input(
      @form,
      @id,
      @opts ++ [class: @input_classes, required: @required, disabled: @disabled]
    ) %>
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

    assigns =
      assign(assigns,
        checkbox_classes: checkbox_classes,
        error_tag_classes: error_tag_classes,
        label_classes: label_classes
      )

    ~H"""
    <div class="flex items-start">
      <div class="flex items-center h-5">
        <%= checkbox(@form, @id, class: @checkbox_classes) %>
      </div>
      <div class="ml-3 text-sm">
        <%= error_tag(@form, @id, class: @error_tag_classes) %>
        <%= label(@form, @id, class: @label_classes) %>
        <%= if assigns[:inner_block] do %>
          <%= render_slot(@inner_block) %>
        <% end %>
      </div>
    </div>
    """
  end

  def label_field(assigns) do
    label_classes = ~w[
      block
      text-sm
      font-medium
      text-secondary-700
    ]

    assigns = assign(assigns, label_classes: label_classes)

    ~H"""
    <%= label(@form, @id, @title,
      for: @for,
      class: @label_classes
    ) %>
    """
  end

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
      assigns_to_attributes(assigns, [:form, :name, :values]) ++
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
