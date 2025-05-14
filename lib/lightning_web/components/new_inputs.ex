defmodule LightningWeb.Components.NewInputs do
  @moduledoc """
  A temporary module that will serve as a place to put new inputs that conform
  with the newer CoreComponents conventions introduced in Phoenix 1.7.
  """
  use Phoenix.Component

  import LightningWeb.Components.Icons

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @button_themes [
    "primary",
    "secondary",
    "danger",
    "success",
    "warning",
    "custom"
  ]
  @button_sizes ["sm", "md", "lg"]

  @doc """
  Renders a button.

  ## Attributes

    * `:type` - The type of the button. Defaults to `"button"`. Acceptable values are:
      * `"button"`
      * `"submit"`

    * `:class` - Additional CSS classes to apply to the button. Defaults to an empty string.

    * `:theme` - The theme of the button. Acceptable values are:
      * `"primary"`
      * `"secondary"`
      * `"danger"`
      * `"success"`
      * `"warning"`
      * `"custom"`

    * `:size` - The padding size of the button. Defaults to `"md"`. Acceptable values are:
      * `"sm"` - Small
      * `"md"` - Medium
      * `"lg"` - Large

    * `:tooltip` - A tooltip to display when the button is disabled. Defaults to `nil`.

    * `:rest` - Any additional global attributes (e.g., `id`, `disabled`, `form`, `name`, `value`) that should be applied to the button.

  ## Slots

    * `:inner_block` (required) - The content to render inside the button.

  ## Examples

  Basic button:

  ```heex
  <.button>Click me</.button>
  ```

  Button with a click event:

  ```heex
  <.button phx-click="submit_form">Submit</.button>
  ```

  Button with a custom class:

  ```heex
  <.button class="ml-4">Custom Button</.button>
  ```

  Button with a theme:

  ```heex
  <.button theme="primary">Primary Button</.button>
  <.button theme="danger">Danger Button</.button>
  ```

  Button with a size:

  ```heex
  <.button size="sm">Small Button</.button>
  <.button size="lg">Large Button</.button>
  ```

  Button with a tooltip (visible when disabled):

  ```heex
  <.button disabled={true} tooltip="You cannot click this button right now">
    Disabled Button
  </.button>
  ```

  Button with additional attributes:

  ```heex
  <.button id="my-button" name="action" value="save" phx-click="save_data">
    Save
  </.button>
  ```

  ## Notes

    * The `theme` attribute applies predefined styles to the button. If you use the `"custom"` theme, no theme-specific styles will be applied, allowing you to fully customize the button using the `:class` attribute.
    * The `size` attribute adjusts the padding and dimensions of the button.
    * If the `tooltip` attribute is provided and the button is disabled, a tooltip will be displayed to explain why the button is not clickable.
  """
  attr :type, :string, default: "button", values: ["button", "submit"]
  attr :class, :any, default: ""
  attr :theme, :string, values: @button_themes
  attr :size, :string, default: "md", values: @button_sizes
  attr :tooltip, :any, default: nil
  attr :rest, :global, include: ~w(id disabled form name value)

  slot :inner_block, required: true

  def button(%{theme: theme} = assigns) when is_binary(theme) do
    assigns
    |> assign(:class, [
      # Base classes
      button_base_classes(),
      "cursor-pointer disabled:cursor-auto",
      # size variants
      button_size_classes(assigns.size),
      # theme variants
      button_theme_classes(theme),
      # other classes to override
      assigns.class
    ])
    |> assign(theme: nil)
    |> button()
  end

  def button(assigns) do
    ~H"""
    <.simple_button_with_tooltip
      tooltip={@tooltip}
      type={@type}
      class={@class}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.simple_button_with_tooltip>
    """
  end

  @doc """
  Renders a link, styled like a button.

  For available options, see `Phoenix.Component.link/1`.
  """
  attr :class, :any, default: ""
  attr :theme, :string, values: @button_themes, required: true
  attr :size, :string, default: "md", values: @button_sizes

  attr :rest, :global,
    include:
      ~w(id href patch navigate replace method csrf_token download hreflang referrerpolicy rel target type)

  slot :inner_block, required: true

  def button_link(assigns) do
    ~H"""
    <.link
      class={
        [
          # Base classes
          button_base_classes(),
          # size variants
          button_size_classes(@size),
          # theme variants
          button_theme_classes(@theme),
          # other classes to override
          @class
        ]
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp button_base_classes do
    "rounded-md text-sm font-semibold shadow-xs phx-submit-loading:opacity-75"
  end

  defp button_theme_classes(theme) do
    case theme do
      "primary" ->
        "bg-primary-600 hover:bg-primary-500 text-white disabled:bg-primary-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600"

      "secondary" ->
        "bg-white hover:bg-gray-50 text-gray-900 disabled:bg-gray-50 ring-1 ring-gray-300 ring-inset"

      "danger" ->
        "bg-red-600 hover:bg-red-500 text-white disabled:bg-red-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"

      "success" ->
        "bg-green-600 hover:bg-green-500 text-white disabled:bg-green-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-green-600"

      "warning" ->
        "bg-yellow-600 hover:bg-yellow-500 text-white disabled:bg-yellow-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-yellow-600"

      "custom" ->
        ""
    end
  end

  defp button_size_classes("sm"), do: "px-2.5 py-1.5"
  defp button_size_classes("md"), do: "px-3 py-2"
  defp button_size_classes("lg"), do: "px-3.5 py-2.5"

  attr :tooltip, :any, default: nil
  attr :rest, :global, include: ~w(id disabled form name value class type)

  slot :inner_block, required: true

  def simple_button_with_tooltip(assigns) do
    ~H"""
    <.tooltip_when_disabled
      id={@rest[:id]}
      tooltip={@tooltip}
      disabled={@rest[:disabled]}
    >
      <button {@rest}>
        {render_slot(@inner_block)}
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
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp tooltip_when_disabled(assigns) do
    ~H"""
    {render_slot(@inner_block)}
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

    * `type="tag"` renders a tag input with comma-separated values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
      <.input field={@form[:tags]} type="tag" />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :sublabel, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values:
      ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select custom-select tag tel text textarea time url week toggle integer-toggle)

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

  attr :placeholder, :string, default: ""

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

  attr :on_click, :string, default: nil

  attr :value_key, :any, default: nil

  attr :standalone, :boolean,
    default: false,
    doc:
      "indicates if the tag input operates independently of a form's validation flow"

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> maybe_assign_radio_checked()
    |> assign(field: nil)
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
        {@label}<span :if={Map.get(@rest, :required, false)} class="text-red-500"> *</span>
      </label>
      <.error :for={msg <- @errors} :if={@display_errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label :if={@label} class="mb-2" for={@id}>
        {@label}<span :if={Map.get(@rest, :required, false)} class="text-red-500"> *</span>
        <.tooltip_for_label :if={@tooltip} id={"#{@id}-tooltip"} tooltip={@tooltip} />
      </.label>
      <div class="flex w-full">
        <div class="relative items-center w-full">
          <select
            id={@id}
            name={@name}
            class={[
              "block w-full rounded-lg border border-secondary-300 bg-white",
              "sm:text-sm shadow-xs",
              "focus:border-primary-300 focus:ring focus:ring-primary-200 focus:ring-primary-200/50",
              "disabled:cursor-not-allowed",
              @button_placement == "right" && "rounded-r-none",
              @button_placement == "left" && "rounded-l-none",
              @class
            ]}
            multiple={@multiple}
            {@rest}
          >
            <option :if={@prompt} value="">{@prompt}</option>
            {Phoenix.HTML.Form.options_for_select(@options, @value)}
          </select>
        </div>
        <div class="relative ronded-l-none">
          {render_slot(@inner_block)}
        </div>
      </div>
      <.error :for={msg <- @errors} :if={@display_errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "custom-select"} = assigns) do
    assigns =
      assigns
      |> assign_new(:hidden_input_selector, fn %{name: name} ->
        "input[type=hidden][name='#{name}']"
      end)
      |> update(:options, fn options, %{prompt: prompt} ->
        if prompt do
          [{prompt, ""} | options]
        else
          options
        end
      end)
      |> assign_new(:selected_option, fn %{options: options, value: value} ->
        selected_option =
          Enum.find(options, fn option ->
            to_string(select_option_value(option)) == to_string(value)
          end)

        selected_option || hd(options)
      end)

    ~H"""
    <div phx-feedback-for={@name}>
      <.label :if={@label} class="mb-2" for={@id}>
        {@label}<span :if={Map.get(@rest, :required, false)} class="text-red-500"> *</span>
      </.label>
      <div class="flex w-full items-center">
        <div
          class="relative w-full"
          phx-click={JS.show(to: {:inner, "ul[role='listbox']"})}
        >
          <button
            type="button"
            class={[
              "grid grid-cols-1 w-full rounded-lg bg-white border border-secondary-300",
              "sm:text-sm",
              "focus:border-primary-300 focus:ring focus:ring-primary-200 focus:ring-primary-200/50",
              "py-2 pr-2 pl-3 text-left",
              "disabled:cursor-not-allowed",
              @button_placement == "right" && "rounded-r-none",
              @button_placement == "left" && "rounded-l-none",
              @class
            ]}
            aria-haspopup="listbox"
            aria-expanded="true"
            {@rest}
          >
            <span class="col-start-1 row-start-1 truncate pr-6">
              {select_option_label(@selected_option)}
            </span>

            <.icon
              name="hero-chevron-up-down"
              class="col-start-1 row-start-1 size-5 self-center justify-self-end text-gray-500 sm:size-4"
            />
          </button>
          <ul
            id={@id}
            class="absolute z-10 mt-1 max-h-60 w-full overflow-auto rounded-md bg-white py-1 text-base shadow-lg ring-1 ring-black/5 focus:outline-hidden sm:text-sm hidden"
            tabindex="-1"
            role="listbox"
            phx-click-away={JS.hide()}
          >
            <li
              :for={option <- @options}
              class="relative cursor-default py-2 pr-4 pl-8 text-gray-900 select-none group hover:bg-indigo-600 hover:text-white hover:outline-hidden"
              role="option"
              phx-click={
                JS.set_attribute(
                  {"value", select_option_value(option)},
                  to: @hidden_input_selector
                )
                |> JS.dispatch("input", to: @hidden_input_selector)
                |> JS.hide(to: {:closest, "ul[role='listbox']"})
              }
              aria-selected={
                to_string(
                  select_option_label(option) != @prompt &&
                    option == @selected_option
                )
              }
            >
              <span class={[
                "block truncate",
                if(option == @selected_option,
                  do: "font-semibold",
                  else: "font-normal"
                )
              ]}>
                {select_option_label(option)}
              </span>

              <span
                :if={option == @selected_option}
                class="absolute inset-y-0 left-0 flex items-center pl-1.5 text-indigo-600 group-hover:text-white"
              >
                <.icon name="hero-check" class="size-5" />
              </span>
            </li>
          </ul>
        </div>
        <div class="relative ronded-l-none">
          {render_slot(@inner_block)}
        </div>
      </div>
      <input type="hidden" name={@name} value={@value} />

      <.error :for={msg <- @errors} :if={@display_errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class={@stretch && "h-full"}>
      <.label :if={@label} for={@id}>
        {@label}<span :if={Map.get(@rest, :required, false)} class="text-red-500"> *</span>
      </.label>
      <.textarea_element
        id={@id}
        name={@name}
        class={@class}
        value={@value}
        placeholder={@placeholder}
        {@rest}
      />
      <.error :for={msg <- @errors} :if={@display_errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "password"} = assigns) do
    assigns =
      assign_new(assigns, :reveal_id, fn ->
        :crypto.strong_rand_bytes(5)
        |> Base.encode16(case: :lower)
        |> binary_part(0, 5)
      end)

    ~H"""
    <div phx-feedback-for={@name}>
      <.label :if={@label} for={@id}>
        {@label}<span :if={Map.get(@rest, :required, false)} class="text-red-500"> *</span>
      </.label>
      <div class="relative mt-2 rounded-lg shadow-xs">
        <input
          type={@type}
          name={@name}
          id={@id}
          data-reveal-id={@reveal_id}
          value={Form.normalize_value(@type, @value)}
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
            phx-click={
              JS.toggle_class("hero-eye-slash")
              |> JS.toggle_class("hero-eye")
              |> JS.toggle_attribute({"type", "password", "text"},
                to: "input[data-reveal-id='#{@reveal_id}']"
              )
            }
          />
        </div>
      </div>
      <div :if={Enum.any?(@errors) and @display_errors} class="error-space">
        <.error :for={msg <- @errors}>{msg}</.error>
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

  def input(%{type: "tag"} = assigns) do
    assigns =
      assigns
      |> assign_new(:tags, fn ->
        case assigns[:value] do
          tags when is_list(tags) ->
            tags

          value when is_binary(value) ->
            value
            |> String.split(",", trim: true)
            |> Enum.map(&String.trim/1)

          _ ->
            []
        end
      end)
      |> assign(:id, assigns.id || assigns.name)

    ~H"""
    <div
      id={"#{@id}-container"}
      class="tag-input-container"
      phx-hook="TagInput"
      phx-feedback-for={@name}
      data-standalone-mode={@standalone}
      data-text-el={"#{@id}_raw"}
      data-hidden-el={@id}
      data-tag-list={"#{@id}-container-tag-list"}
    >
      <.label :if={@label} for={@id} class="mb-2">
        {@label}<span :if={Map.get(@rest, :required, false)} class="text-red-500"> *</span>
        <.tooltip_for_label :if={@tooltip} id={"#{@id}-tooltip"} tooltip={@tooltip} />
      </.label>

      <small :if={@sublabel} class="mb-2 block text-xs text-gray-600">
        {@sublabel}
      </small>

      <div class="relative">
        <input
          id={"#{@id}_raw"}
          type="text"
          name={"#{@name}_raw"}
          placeholder={@placeholder}
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
        <input type="hidden" name={@name} id={@id} value={Enum.join(@tags, ",")} />
      </div>
      <.error :for={msg <- @errors} :if={@display_errors}>{msg}</.error>

      <div id={"#{@id}-container-tag-list"} class="tag-list mt-2">
        <span
          :for={tag <- @tags}
          id={"tag-#{String.replace(tag, " ", "-")}"}
          class="inline-flex items-center rounded-md bg-blue-50 p-2 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 mr-1 my-1"
          data-tag={tag}
        >
          {tag}
          <button
            type="button"
            class="group relative -mr-1 h-3.5 w-3.5 rounded-sm hover:bg-gray-500/20"
          >
            <span class="sr-only">Remove</span>
            <.icon
              name="hero-x-mark"
              class="h-3 w-3 stroke-gray-600/50 group-hover:stroke-gray-600/75"
            />
          </button>
        </span>
      </div>
    </div>
    """
  end

  def input(%{type: "integer-toggle"} = assigns) do
    assigns =
      assigns
      |> assign_new(:hidden_input_selector, fn %{name: name} ->
        "input[type=hidden][name='#{name}']"
      end)
      |> assign_new(:disabled, fn assigns ->
        get_in(assigns, [:rest, :disabled]) || false
      end)
      |> assign_new(:values, fn ->
        # TODO: placeholder for alternative values, like "0" and "1",
        # or "false" and "true" when this might replace the other toggle component
        [get_in(assigns, [:rest, :max]), "1"]
        |> Enum.map(fn v ->
          Phoenix.HTML.html_escape(v) |> Phoenix.HTML.safe_to_string()
        end)
      end)
      |> update(:value, &to_string/1)

    ~H"""
    <button
      type="button"
      disabled={@disabled}
      class={[
        "relative inline-flex h-6 w-11 shrink-0",
        "cursor-pointer rounded-full border-2 border-transparent",
        "transition-colors duration-200 ease-in-out",
        "focus:outline-none focus:ring-2 focus:ring-indigo-600 focus:ring-offset-2",
        "disabled:cursor-not-allowed",
        "bg-gray-200 aria-checked:bg-indigo-600 group"
      ]}
      role="switch"
      aria-checked={"#{@value == "1" || false}"}
      phx-click={
        if !@disabled,
          do:
            JS.toggle_attribute(
              ["value" | @values] |> List.to_tuple(),
              to: @hidden_input_selector
            )
            |> JS.dispatch("input", to: @hidden_input_selector)
      }
    >
      <span class="sr-only">Use setting</span>
      <span
        aria-hidden="true"
        class={[
          "pointer-events-none inline-block size-5",
          "transform transition duration-200 ease-in-out",
          "rounded-full bg-white shadow ring-0",
          "translate-x-0 group-aria-checked:translate-x-5"
        ]}
      >
      </span>
      <input type="hidden" name={@name} value={@value} />
    </button>
    """
  end

  def input(%{type: "toggle"} = assigns) do
    assigns =
      assigns
      |> assign_new(:checked, fn ->
        Form.normalize_value("checkbox", assigns[:value]) == true
      end)
      |> assign_new(:tooltip, fn -> nil end)

    ~H"""
    <div
      id={"toggle-container-#{@id}"}
      class={["flex flex-col gap-1", @class]}
      {if @tooltip, do: ["phx-hook": "Tooltip", "aria-label": @tooltip], else: []}
    >
      <div
        id={"toggle-control-#{@id}"}
        class="flex items-center gap-3"
        {if @on_click, do: ["phx-click": JS.push(@on_click,
          value: %{
            _target: @name,
            "#{@name}": !@checked,
            value_key: to_string(@value_key)
          }
        )], else: []}
      >
        <label class="relative inline-flex items-center cursor-pointer">
          <input type="hidden" name={@name} value="false" />
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            class="sr-only peer"
            checked={@checked}
            {@rest}
          />

          <div
            tabindex={if @rest[:disabled], do: "-1", else: "0"}
            role="switch"
            aria-checked={@checked}
            class={[
              "relative inline-flex w-11 h-6 rounded-full transition-colors duration-200 ease-in-out border-2 border-transparent",
              "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500",
              @checked && "bg-indigo-600",
              !@checked && "bg-gray-200",
              if(@rest[:disabled],
                do: "opacity-50 cursor-not-allowed",
                else: "cursor-pointer"
              )
            ]}
          >
            <span class={[
              "pointer-events-none absolute h-5 w-5 inline-block transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
              @checked && "translate-x-5",
              !@checked && "translate-x-0"
            ]}>
              <span
                class={[
                  "absolute inset-0 flex h-full w-full items-center justify-center transition-opacity duration-200 ease-in",
                  @checked && "opacity-0",
                  !@checked && "opacity-100"
                ]}
                aria-hidden="true"
              >
                <.icon name="hero-x-mark-micro" class="h-4 w-4 text-gray-400" />
              </span>
              <span
                class={[
                  "absolute inset-0 flex h-full w-full items-center justify-center transition-opacity duration-200 ease-in",
                  @checked && "opacity-100",
                  !@checked && "opacity-0"
                ]}
                aria-hidden="true"
              >
                <.icon name="hero-check-micro" class="h-4 w-4 text-indigo-600" />
              </span>
            </span>
          </div>

          <span
            :if={@label}
            class={[
              "ml-3 text-sm font-medium select-none",
              if(@rest[:disabled], do: "text-gray-400", else: "text-gray-900")
            ]}
          >
            {@label}
            <span :if={@rest[:required]} class="text-red-500 ml-1">*</span>
          </span>
        </label>
      </div>
    </div>
    """
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input
      type="hidden"
      name={@name}
      id={@id}
      value={Form.normalize_value(@type, @value)}
    />
    """
  end

  # All other inputs text, datetime-local, url etc. are handled here...
  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label :if={@label} for={@id} class="mb-2">
        {@label}
        <span :if={Map.get(@rest, :required, false)} class="text-red-500"> *</span>
      </.label>
      <small :if={@sublabel} class="mb-2 block text-xs text-gray-600">
        {@sublabel}
      </small>
      <.input_element
        type={@type}
        name={@name}
        id={@id}
        class={@class}
        value={Form.normalize_value(@type, @value)}
        {@rest}
      />
      <div :if={Enum.any?(@errors) and @display_errors} class="error-space">
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </div>
    """
  end

  defp select_option_label({label, _value}), do: label
  defp select_option_label(value), do: value

  defp select_option_value({_label, value}), do: value
  defp select_option_value(value), do: value

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
  Renders a textarea element.

  This function is used internally by `input/1` and generally should not
  be used directly.

  Look at `input type="textarea"` to see how these values `attr` get populated
  """

  attr :id, :string, default: nil
  attr :name, :string, required: true
  attr :value, :any
  attr :errors, :list, default: []
  attr :class, :string, default: ""

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
              multiple pattern placeholder readonly required rows size step)

  def textarea_element(assigns) do
    ~H"""
    <textarea
      id={@id}
      name={@name}
      class={[
        "focus:outline focus:outline-2 focus:outline-offset-1 rounded-md shadow-xs text-sm",
        "block w-full focus:ring-0",
        "sm:text-sm sm:leading-6",
        "phx-no-feedback:border-slate-300 phx-no-feedback:focus:border-slate-400 overflow-y-auto",
        @errors == [] &&
          "border-slate-300 focus:border-slate-400 focus:outline-indigo-600",
        @errors != [] &&
          "border-danger-400 focus:border-danger-400 focus:outline-danger-400",
        @class
      ]}
      {@rest}
    ><%= Form.normalize_value("textarea", @value) %></textarea>
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
      class={["text-sm/6 font-medium text-slate-800", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
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
      <.error :for={msg <- @errors}>{msg}</.error>
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
      {render_slot(@inner_block)}
    </p>
    """
  end
end
