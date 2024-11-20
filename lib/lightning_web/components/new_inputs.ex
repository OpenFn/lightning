defmodule LightningWeb.Components.NewInputs do
  @moduledoc """
  A temporary module that will serve as a place to put new inputs that conform
  with the newer CoreComponents conventions introduced in Phoenix 1.7.
  """
  use Phoenix.Component

  import LightningWeb.Components.Icons

  alias Phoenix.LiveView.JS

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :id, :string, default: ""
  attr :type, :string, default: "button", values: ["button", "submit"]
  attr :class, :any, default: ""

  attr :color_class, :any,
    default:
      "bg-primary-600 hover:bg-primary-700 text-white focus:ring-primary-500 disabled:bg-primary-300"

  attr :rest, :global, include: ~w(disabled form name value)
  attr :tooltip, :any, default: nil

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <.tooltip_when_disabled id={@id} tooltip={@tooltip} disabled={@rest[:disabled]}>
      <button
        id={@id}
        type={@type}
        class={[
          "inline-flex justify-center items-center py-2 px-4 border border-transparent",
          "shadow-sm text-sm font-medium rounded-md focus:outline-none",
          "focus:ring-2 focus:ring-offset-2",
          "phx-submit-loading:opacity-75",
          @color_class,
          @class
        ]}
        {@rest}
      >
        <%= render_slot(@inner_block) %>
      </button>
    </.tooltip_when_disabled>
    """
  end

  attr :id, :string, required: true
  attr :tooltip, :string, default: nil
  attr :disabled, :boolean, default: false
  slot :inner_block, required: true

  defp tooltip_when_disabled(%{disabled: true, tooltip: tooltip} = assigns)
       when not is_nil(tooltip) do
    ~H"""
    <span
      id={"#{@id}-tooltip"}
      phx-hook="Tooltip"
      aria-label={@tooltip}
      data-allow-html="true"
    >
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  defp tooltip_when_disabled(assigns) do
    ~H"""
    <%= render_slot(@inner_block) %>
    """
  end

  attr :id, :string, required: true
  attr :tooltip, :string, required: true
  attr :class, :string, default: ""
  attr :icon, :string, default: "hero-information-circle-solid"
  attr :icon_class, :string, default: "w-4 h-4 text-primary-600 opacity-50"

  defp tooltip_for_label(assigns) do
    classes = ~w"relative cursor-pointer"

    assigns = assign(assigns, class: classes ++ List.wrap(assigns.class))

    ~H"""
    <span class={@class} id={@id} aria-label={@tooltip} phx-hook="Tooltip">
      <.icon name={@icon} class={@icon_class} />
    </span>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values:
      ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc:
      "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox/radio inputs"

  attr :checked_value, :any,
    default: "true",
    doc: "the value to be sent when the checkbox is checked. Defaults to 'true'"

  attr :unchecked_value, :any,
    default: "false",
    doc:
      "the value to be sent when the checkbox is unchecked, Defaults to 'false'"

  attr :hidden_input, :boolean,
    default: true,
    doc:
      "controls if this function will generate a hidden input to submit the unchecked value or not. Defaults to 'true'"

  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"

  attr :options, :list,
    doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"

  attr :multiple, :boolean,
    default: false,
    doc: "the multiple flag for select inputs"

  attr :button_placement, :string, default: nil

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  attr :class, :string, default: ""

  attr :stretch, :boolean,
    default: false,
    doc: "control the wrapping div classes of some components like the textarea"

  attr :display_errors, :boolean, default: true

  attr :tooltip, :any, default: nil

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> maybe_assign_radio_checked()
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(
      :errors,
      Enum.map(field.errors, &LightningWeb.CoreComponents.translate_error(&1))
    )
    |> assign_new(:name, fn ->
      if assigns.multiple, do: field.name <> "[]", else: field.name
    end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <label class="flex items-center gap-2 text-sm leading-6 text-slate-600">
        <.checkbox_element {assigns} />
        <%= @label %><span
          :if={Map.get(@rest, :required, false)}
          class="text-red-500"
        > *</span>
      </label>
      <.error :for={msg <- @errors} :if={@display_errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label :if={@label} class="mb-2" for={@id}>
        <%= @label %><span
          :if={Map.get(@rest, :required, false)}
          class="text-red-500"
        > *</span>
        <.tooltip_for_label :if={@tooltip} id={"#{@id}-tooltip"} tooltip={@tooltip} />
      </.label>
      <div class="flex w-full">
        <div class="relative items-center w-full">
          <select
            id={@id}
            name={@name}
            class={[
              "block w-full rounded-lg border border-secondary-300 bg-white",
              "sm:text-sm shadow-sm",
              "focus:border-primary-300 focus:ring focus:ring-primary-200 focus:ring-opacity-50",
              "disabled:cursor-not-allowed",
              @button_placement == "right" && "rounded-r-none",
              @button_placement == "left" && "rounded-l-none",
              @class
            ]}
            multiple={@multiple}
            {@rest}
          >
            <option :if={@prompt} value=""><%= @prompt %></option>
            <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
          </select>
        </div>
        <div class="relative ronded-l-none">
          <%= render_slot(@inner_block) %>
        </div>
      </div>
      <.error :for={msg <- @errors} :if={@display_errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class={@stretch && "h-full"}>
      <.label :if={@label} for={@id}>
        <%= @label %><span
          :if={Map.get(@rest, :required, false)}
          class="text-red-500"
        > *</span>
      </.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "focus:outline focus:outline-2 focus:outline-offset-1 rounded-md shadow-sm text-sm",
          "mt-2 block w-full focus:ring-0",
          "sm:text-sm sm:leading-6",
          "phx-no-feedback:border-slate-300 phx-no-feedback:focus:border-slate-400 overflow-y-auto",
          @errors == [] &&
            "border-slate-300 focus:border-slate-400 focus:outline-indigo-600",
          @errors != [] && @field && @field.field == @name && @field.errors != [] &&
            "border-danger-400 focus:border-danger-400 focus:outline-danger-400",
          @class
        ]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors} :if={@display_errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "password"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label :if={@label} for={@id}>
        <%= @label %><span
          :if={Map.get(@rest, :required, false)}
          class="text-red-500"
        > *</span>
      </.label>
      <div class="relative mt-2 rounded-lg shadow-sm">
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          lv-keep-type
          class={[
            "focus:outline focus:outline-2 focus:outline-offset-1 block w-full rounded-lg text-slate-900 focus:ring-0 sm:text-sm sm:leading-6",
            "phx-no-feedback:border-slate-300 phx-no-feedback:focus:border-slate-400 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500",
            @class,
            @errors == [] &&
              "border-slate-300 focus:border-slate-400 focus:outline-indigo-600",
            @errors != [] && @field && @field.field == @name && @field.errors != [] &&
              "border-danger-400 focus:border-danger-400 focus:outline-danger-400"
          ]}
          {@rest}
        />
        <div class="absolute inset-y-0 right-0 flex items-center pr-3">
          <.icon
            name="hero-eye-slash"
            class="h-5 w-5 cursor-pointer"
            id={"show_password_#{@id}"}
            phx-hook="TogglePassword"
            data-target={@id}
            phx-then={
              JS.toggle(to: "#hide_password_#{@id}")
              |> JS.toggle(to: "#show_password_#{@id}")
            }
          />
          <.icon
            name="hero-eye"
            class="h-5 w-5 cursor-pointer hidden"
            phx-hook="TogglePassword"
            data-target={@id}
            phx-then={
              JS.toggle(to: "#hide_password_#{@id}")
              |> JS.toggle(to: "#show_password_#{@id}")
            }
            id={"hide_password_#{@id}"}
          />
        </div>
      </div>
      <div :if={Enum.any?(@errors) and @display_errors} class="error-space">
        <.error :for={msg <- @errors}><%= msg %></.error>
      </div>
    </div>
    """
  end

  def input(%{type: "radio"} = assigns) do
    ~H"""
    <input
      type="radio"
      id={@id}
      name={@name}
      checked={@checked}
      value={@value}
      class={[
        "h-4 w-4 border-gray-300 text-indigo-600 focus:ring-indigo-600",
        @class
      ]}
      {@rest}
    />
    """
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input
      type="hidden"
      name={@name}
      id={@id}
      value={Phoenix.HTML.Form.normalize_value(@type, @value)}
    />
    """
  end

  # All other inputs text, datetime-local, url etc. are handled here...
  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label :if={@label} for={@id} class="mb-2">
        <%= @label %>
        <span :if={Map.get(@rest, :required, false)} class="text-red-500"> *</span>
      </.label>
      <.input_element
        type={@type}
        name={@name}
        id={@id}
        class={@class}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        {@rest}
      />
      <div :if={Enum.any?(@errors) and @display_errors} class="error-space">
        <.error :for={msg <- @errors}><%= msg %></.error>
      </div>
    </div>
    """
  end

  @doc """
  Renders an input element.

  This function is used internally by `input/1` and generally should not
  be used directly.

  In the case of inputs that are different enough to warrant a new function,
  this component can be used to maintain style consistency.
  """

  attr :id, :string, default: nil
  attr :name, :string, required: true
  attr :type, :string, required: true
  attr :value, :any
  attr :errors, :list, default: []
  attr :class, :string, default: ""

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
              multiple pattern placeholder readonly required rows size step)

  def input_element(assigns) do
    ~H"""
    <input
      type={@type}
      name={@name}
      id={@id}
      value={@value}
      class={[
        "focus:outline focus:outline-2 focus:outline-offset-1 block w-full rounded-lg text-slate-900 focus:ring-0 sm:text-sm sm:leading-6",
        "phx-no-feedback:border-slate-300 phx-no-feedback:focus:border-slate-400 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500",
        @errors == [] &&
          "border-slate-300 focus:border-slate-400 focus:outline-indigo-600",
        @errors != [] &&
          "border-danger-400 focus:border-danger-400 focus:outline-danger-400",
        @class
      ]}
      {@rest}
    />
    """
  end

  @doc """
  Renders a checkbox input element.

  This function is used internally by `input/1` and generally should not
  be used directly.

  Look at `input type="checkbox"` to see how these values `attr` get populated
  """

  attr :id, :string, default: nil
  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :class, :string
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :checked_value, :any, default: "true"
  attr :unchecked_value, :any, default: "false"
  attr :hidden_input, :boolean, default: true
  attr :rest, :global, include: ~w(disabled form readonly required)

  def checkbox_element(%{value: value, checked_value: checked_value} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.html_escape(checked_value) ==
          Phoenix.HTML.html_escape(value)
      end)

    ~H"""
    <input
      :if={@hidden_input}
      type="hidden"
      name={@name}
      value={to_string(@unchecked_value)}
    />
    <input
      type="checkbox"
      id={@id}
      name={@name}
      value={to_string(@checked_value)}
      checked={@checked}
      class={["rounded border-gray-300 text-indigo-600 focus:ring-indigo-600
        checked:disabled:bg-indigo-300 checked:disabled:border-indigo-300
        checked:bg-indigo-600 checked:border-indigo-600 focus:outline-none
        transition duration-200 cursor-pointer", @class]}
      {@rest}
    />
    """
  end

  defp maybe_assign_radio_checked(
         %{field: %Phoenix.HTML.FormField{} = field, type: "radio"} = assigns
       ) do
    if Map.has_key?(assigns, :value) do
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.html_escape(field.value) ==
          Phoenix.HTML.html_escape(assigns.value)
      end)
    else
      assigns
    end
  end

  defp maybe_assign_radio_checked(assigns), do: assigns

  @doc """
  Generates hidden inputs for a form.
  Adapted from [PhoenixHTMLHelpers.Form.html#hidden_inputs_for/1](https://github.com/phoenixframework/phoenix_html_helpers/blob/v1.0.1/lib/phoenix_html_helpers/form.ex#L406)
  """
  attr :form, Phoenix.HTML.Form, required: true

  def form_hidden_inputs(assigns) do
    ~H"""
    <%= for {key, value} <- @form.hidden do %>
      <%= if is_list(value) do %>
        <.input
          :for={{v, index} <- Enum.with_index(value)}
          type="hidden"
          id={@form[key].id <> "_#{index}"}
          name={@form[key].name <> "[]"}
          value={v}
        />
      <% else %>
        <.input type="hidden" field={@form[key]} value={value} />
      <% end %>
    <% end %>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :any, default: nil
  attr :class, :any, default: ""
  attr :rest, :global
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label
      for={@for}
      class={["block text-sm font-semibold leading-6 text-slate-800", @class]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </label>
    """
  end

  @doc """
  Generic wrapper for rendering error messages in custom input components.
  """
  attr :field, Phoenix.HTML.FormField, required: true

  def errors(assigns) do
    assigns =
      assigns
      |> assign(
        :errors,
        Enum.map(
          assigns.field.errors,
          &LightningWeb.CoreComponents.translate_error(&1)
        )
      )

    ~H"""
    <div :if={Enum.any?(@errors)} class="error-space">
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p
      data-tag="error_message"
      class="phx-no-feedback:hidden mt-1 inline-flex items-center gap-x-1.5 text-xs text-danger-600"
    >
      <.icon name="hero-exclamation-circle" class="h-4 w-4" />
      <%= render_slot(@inner_block) %>
    </p>
    """
  end
end
