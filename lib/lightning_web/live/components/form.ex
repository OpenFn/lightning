defmodule LightningWeb.Components.Form do
  @moduledoc false
  use LightningWeb, :component

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
      shadow-xs
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
    {PhoenixHTMLHelpers.Form.label(@form, @id, class: @label_classes)}
    <LightningWeb.CoreComponents.old_error field={@form[@id]} />
    {PhoenixHTMLHelpers.Form.email_input(@form, @id,
      class: @input_classes,
      required: @required
    )}
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
      shadow-xs
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
        {PhoenixHTMLHelpers.Form.checkbox(@form, @field, @checkbox_opts)}
      </div>
      <div class="ml-3 text-sm">
        <LightningWeb.CoreComponents.old_error field={@form[@field]} />
        {PhoenixHTMLHelpers.Form.label(@form, @label || @field, @label_opts)}
        {render_slot(@inner_block)}
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
        Phoenix.Naming.humanize(field)
      end)

    ~H"""
    <%= if assigns[:tooltip] do %>
      <div class="flex flex-row items-end">
        <%= PhoenixHTMLHelpers.Form.label(@form, @field, @opts) do %>
          <div class="flex items-center">
            {@title}
            <object :if={@logo} data={@logo} type="image/png" class="w-3 h-3 ml-1" />
          </div>
        <% end %>
        <LightningWeb.Components.Common.tooltip
          id={"#{@field}-tooltip"}
          title={@tooltip}
        />
      </div>
    <% else %>
      <%= PhoenixHTMLHelpers.Form.label(@form, @field, @opts) do %>
        <div class="flex items-center">
          {@title}
          <object :if={@logo} data={@logo} type="image/png" class="w-3 h-3 ml-1" />
        </div>
      <% end %>
    <% end %>
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
