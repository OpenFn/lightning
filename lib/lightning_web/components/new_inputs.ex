defmodule LightningWeb.Components.NewInputs do
  @moduledoc """
  A temporary module that will serve as a place to put new inputs that conform
  with the newer CoreComponents conventions introduced in Phoenix 1.7.
  """
  use Phoenix.Component

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
    default: "bg-primary-600 hover:bg-primary-700 text-white"

  attr :rest, :global, include: ~w(disabled form name value)
  attr :tooltip, :any, default: nil

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <.tooltip_when_disabled
      id={@rest[:id]}
      tooltip={@tooltip}
      disabled={@rest[:disabled]}
    >
      <button
        id={@id}
        type={@type}
        class={[
          "inline-flex justify-center py-2 px-4 border border-transparent",
          "shadow-sm text-sm font-medium rounded-md focus:outline-none",
          "focus:ring-2 focus:ring-offset-2 focus:ring-primary-500",
          "disabled:bg-primary-300",
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
  attr :disabled, :boolean, default: false
  attr :tooltip, :string, default: nil

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
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"

  attr :options, :list,
    doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"

  attr :multiple, :boolean,
    default: false,
    doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  attr :class, :string, default: ""

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
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

  def input(%{type: "checkbox", value: value} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", value)
      end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label class="flex items-center gap-2 text-sm leading-6 text-slate-600">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-600
            checked:disabled:bg-indigo-300 checked:disabled:border-indigo-300
            checked:bg-indigo-600 checked:border-indigo-600 focus:outline-none
            transition duration-200 cursor-pointer text-indigo-600"
          {@rest}
        />
        <%= @label %>
      </label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <select
        id={@id}
        name={@name}
        class={[
          "block w-full rounded-md border border-secondary-300 bg-white mt-2",
          "text-sm shadow-sm",
          "focus:border-primary-300 focus:ring focus:ring-primary-200 focus:ring-opacity-50",
          "disabled:cursor-not-allowed"
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value=""><%= @prompt %></option>
        <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
      </select>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class={@class}>
      <.label for={@id}><%= @label %></.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "focus:outline focus:outline-2 focus:outline-offset-1 rounded-md shadow-sm font-mono proportional-nums text-sm",
          "mt-2 block w-full focus:ring-0",
          "text-slate-200 bg-slate-700 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-slate-300 phx-no-feedback:focus:border-slate-400 overflow-y-auto",
          @errors == [] &&
            "border-slate-300 focus:border-slate-400 focus:outline-indigo-600",
          @errors != [] && @field && @field.field == @name && @field.errors != [] &&
            "border-danger-400 focus:border-danger-400 focus:outline-danger-400",
          @class
        ]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "password"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <div class="relative mt-2 rounded-lg shadow-sm">
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
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
          <Heroicons.eye_slash
            class="h-5 w-5 cursor-pointer"
            id={"show_password_#{@id}"}
            phx-hook="TogglePassword"
            data-target={@id}
            phx-then={
              JS.toggle(to: "#hide_password_#{@id}")
              |> JS.toggle(to: "#show_password_#{@id}")
            }
          />
          <Heroicons.eye
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
      <div class="error-space h-6">
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
      class="h-4 w-4 border-gray-300 text-indigo-600 focus:ring-indigo-600"
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
      <.label for={@id}><%= @label %></.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "focus:outline focus:outline-2 focus:outline-offset-1 mt-2 block w-full rounded-lg text-slate-900 focus:ring-0 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-slate-300 phx-no-feedback:focus:border-slate-400 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500",
          @class,
          @errors == [] &&
            "border-slate-300 focus:border-slate-400 focus:outline-indigo-600",
          @errors != [] &&
            "border-danger-400 focus:border-danger-400 focus:outline-danger-400"
        ]}
        {@rest}
      />
      <div :if={Enum.any?(@errors)} class="error-space h-6">
        <.error :for={msg <- @errors}><%= msg %></.error>
      </div>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :any, default: nil
  attr :class, :any, default: ""
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label
      for={@for}
      class={["block text-sm font-semibold leading-6 text-slate-800", @class]}
    >
      <%= render_slot(@inner_block) %>
    </label>
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
      class="mt-3 inline-flex items-center gap-x-1.5 text-xs text-danger-600"
    >
      <.icon name="hero-exclamation-circle" class="h-4 w-4" />
      <%= render_slot(@inner_block) %>
    </p>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from your `assets/vendor/heroicons` directory and bundled
  within your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} {@rest} />
    """
  end
end
