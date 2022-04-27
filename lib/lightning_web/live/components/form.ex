defmodule LightningWeb.Components.Form do
  @moduledoc """
  Form Components
  """
  use LightningWeb, :component

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

    ~H"""
    <%= submit("Save",
      phx_disable_with: "Saving...",
      disabled: !@changeset.valid?,
      class: if(@changeset.valid?, do: active_classes, else: inactive_classes)
    ) %>
    """
  end

  def text_input(assigns, name) do
    input_classes = ~w[
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

    ~H"""
    <div>
      <%= label(f, :name, class: label_classes) %>
      <%= error_tag(f, :name, class: error_classes) %>
      <%= text_input(f, :name, class: input_classes) %>
    </div>
    """
  end

  def select(assigns, name, options, html_for, label) do
    select_classes = ~w[
      block
      w-full
      mt-1
      rounded-md
      border-gray-300
      shadow-sm
      focus:border-indigo-300
      focus:ring
      focus:ring-indigo-200
      focus:ring-opacity-50
    ]

    label_classes = ~w[
      block
      text-sm
      font-medium
      text-gray-700
    ]

    ~H"""
    <div>
      <%= label(f, name, label, for: html_for, class: label_classes) %>
      <%= select(f, name, options), id: html_for, class: select_classes) %>
    </div>
    """
  end
end
