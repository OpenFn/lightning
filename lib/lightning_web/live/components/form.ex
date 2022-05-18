defmodule LightningWeb.Components.Form do
  @moduledoc """
  Form Components
  """
  use LightningWeb, :component

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
      focus:ring-indigo-500
    ]

    inactive_classes = ~w[
      bg-indigo-300
    ] ++ base_classes

    active_classes = ~w[
      bg-indigo-600
      hover:bg-indigo-700
    ] ++ base_classes

    disabled =
      if Map.has_key?(assigns, :changeset) do
        !assigns.changeset.valid?
      else
        false
      end

    class =
      if disabled do
        inactive_classes
      else
        active_classes
      end

    ~H"""
    <%= submit(@value,
      type: "submit",
      phx_disable_with:
        if(Map.has_key?(assigns, :disable_with), do: @disable_with, else: ""),
      disabled: disabled,
      class: class
    ) %>
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

    ~H"""
    <%= error_tag(@form, @id) %>
    <%= textarea(@form, @id, class: classes) %>
    """
  end

  def password_field(assigns) do
    label_classes = ~w[
      block
      text-sm
      font-medium
      text-gray-700
    ]

    error_classes = ~w[
      block
      w-full
      rounded-md
    ]

    input_classes = ~w[
      mt-1
      focus:ring-indigo-500
      focus:border-indigo-500
      block w-full
      shadow-sm
      sm:text-sm
      border-gray-300
      rounded-md
    ]

    ~H"""
    <%= label(@form, @id, class: label_classes) %>
    <%= error_tag(@form, @id, class: error_classes) %>
    <%= password_input(@form, @id,
      class: input_classes,
      required: if(Map.has_key?(assigns, "required"), do: @required, else: false)
    ) %>
    """
  end

  def email_field(assigns) do
    label_classes = ~w[
      block
      text-sm
      font-medium
      text-gray-700
    ]

    error_classes = ~w[
      block
      w-full
      rounded-md
    ]

    input_classes = ~w[
      mt-1
      focus:ring-indigo-500
      focus:border-indigo-500
      block w-full
      shadow-sm
      sm:text-sm
      border-gray-300
      rounded-md
    ]

    ~H"""
    <%= label(@form, @id, class: label_classes) %>
    <%= error_tag(@form, @id, class: error_classes) %>
    <%= email_input(@form, @id,
      class: input_classes,
      required: if(Map.has_key?(assigns, "required"), do: @required, else: false)
    ) %>
    """
  end

  def text_field(assigns) do
    label_classes = ~w[
      block
      text-sm
      font-medium
      text-gray-700
    ]

    error_classes = ~w[
      block
      w-full
      rounded-md
    ]

    input_classes = ~w[
      mt-1
      focus:ring-indigo-500
      focus:border-indigo-500
      block w-full
      shadow-sm
      sm:text-sm
      border-gray-300
      rounded-md
    ]

    ~H"""
    <%= label(@form, @id, class: label_classes) %>
    <%= error_tag(@form, @id, class: error_classes) %>
    <%= text_input(@form, @id, class: input_classes) %>
    """
  end

  def check_box(assigns) do
    checkbox_classes = ~w[
      "focus:ring-indigo-500
      h-4
      w-4
      text-indigo-600
      border-gray-300
      rounded
    ]

    error_tag_classes = ~w[
      mt-1
      focus:ring-indigo-500
      focus:border-indigo-500
      block
      w-full
      shadow-sm
      sm:text-sm
      border-gray-300
      rounded-md
    ]

    label_classes = ~w[
      font-medium
      text-gray-700
    ]

    ~H"""
    <div class="flex items-start">
      <div class="flex items-center h-5">
        <%= checkbox(@form, @id, class: checkbox_classes) %>
      </div>
      <div class="ml-3 text-sm">
        <%= error_tag(@form, @id, class: error_tag_classes) %>
        <%= label(@form, @id, class: label_classes) %>
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  def label_field(assigns) do
    label_classes = ~w[
      block
      text-sm
      font-medium
      text-gray-700
    ]

    ~H"""
    <%= label(@form, @id, @title,
      for: @for,
      class: label_classes
    ) %>
    """
  end

  def select_field(assigns) do
    select_classes = ~w[
      block
      w-full
      rounded-md
      border-gray-300
      shadow-sm
      focus:border-indigo-300
      focus:ring
      focus:ring-indigo-200
      focus:ring-opacity-50
    ]

    opts =
      assigns_to_attributes(assigns, [:form, :name, :values]) ++
        [class: select_classes]

    ~H"""
    <%= select(@form, @name, @values, opts) %>
    """
  end

  def divider(assigns) do
    ~H"""
    <div class="hidden sm:block" aria-hidden="true">
      <div class="py-5">
        <div class="border-t border-gray-200"></div>
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
