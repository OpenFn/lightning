defmodule LightningWeb.Components.NewInputs do
  @moduledoc """
  A temporary module that will serve as a place to put new inputs that conform
  with the newer CoreComponents conventions introduced in Phoenix 1.7.
  """
  alias Phoenix.LiveView.JS

  use Phoenix.Component

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :id, :string, default: "no-id"
  attr :type, :string, default: "button", values: ["button", "submit"]
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)
  attr :tooltip, :any, default: nil

  slot :inner_block, required: true

  def button(assigns) do
    assigns = tooltip_when_disabled(assigns)

    ~H"""
    <span {@span_attrs}>
      <button
        type={@type}
        class={[
          "inline-flex justify-center py-2 px-4 border border-transparent
      shadow-sm text-sm font-medium rounded-md text-white focus:outline-none
      focus:ring-2 focus:ring-offset-2 focus:ring-primary-500",
          "bg-primary-600 hover:bg-primary-700",
          "disabled:bg-primary-300",
          "phx-submit-loading:opacity-75 ",
          @class
        ]}
        {@rest}
      >
        <%= render_slot(@inner_block) %>
      </button>
    </span>
    """
  end

  defp tooltip_when_disabled(assigns) do
    with true <- Map.get(assigns.rest, :disabled, false),
         tooltip when not is_nil(tooltip) <- Map.get(assigns, :tooltip) do
      assign(assigns, :span_attrs, %{
        "id" => assigns.id,
        "phx-hook" => "Tooltip",
        "aria-label" => tooltip
      })
    else
      _ -> assign(assigns, :span_attrs, %{})
    end
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
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
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
      <label class="flex items-center gap-4 text-sm leading-6 text-slate-600">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-slate-300 text-slate-900 focus:ring-0"
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
      <div class="error-space h-6">
        <.error :for={msg <- @errors}><%= msg %></.error>
      </div>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :any, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-slate-800">
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
      class="mt-3 inline-flex items-center gap-x-1.5 text-xs text-danger-600 phx-no-feedback:hidden"
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

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(LightningWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(LightningWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
