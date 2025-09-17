defmodule LightningWeb.SandboxLive.Components do
  use LightningWeb, :component

  alias Lightning.Projects.Project
  alias Phoenix.LiveView.JS

  @color_palette [
    {"#E64A2E", "Tomato"},
    {"#E33D63", "Crimson"},
    {"#8E3FB1", "Purple"},
    {"#5E3FB8", "Deep Purple"},
    {"#4A55C5", "Indigo"},
    {"#5AA1F0", "Azure"},
    {"#67C1E2", "Sky"},
    {"#4AC1CE", "Teal"},
    {"#2E9B92", "Sea Green"},
    {"#56B15A", "Green"},
    {"#9AD04E", "Lime"},
    {"#C9E145", "Chartreuse"},
    {"#FFF35A", "Yellow"},
    {"#F4C644", "Amber"},
    {"#F39B33", "Orange"},
    {"#F0682E", "Vermilion"}
  ]

  def color_palette_hex_colors do
    Enum.map(@color_palette, fn {hex, _name} -> hex end)
  end

  attr :project, Project, required: true
  attr :sandbox_name, :string, required: true

  def header(assigns) do
    ~H"""
    <div class="mb-6 flex items-center justify-between">
      <h3 class="text-3xl font-bold">Sandboxes</h3>
      <.create_button project={@project} sandbox_name={@sandbox_name} />
    </div>
    """
  end

  attr :project, Project, required: true
  attr :sandbox_name, :string, required: true

  def create_button(assigns) do
    ~H"""
    <.button
      id="create-sandbox-button"
      theme="primary"
      size="lg"
      type="button"
      phx-click={
        JS.patch(~p"/projects/#{@project.id}/#{@sandbox_name}/sandboxes/new")
      }
    >
      Create Sandbox
    </.button>
    """
  end

  attr :root_project, Project, default: nil
  attr :sandboxes, :list, required: true
  attr :project, Project, required: true
  attr :current_sandbox, Project, default: nil
  attr :sandbox_name, :string, required: true

  def workspace_list(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.root_project_card
          root_project={@root_project}
          current_sandbox={@current_sandbox}
        />
      </div>
      <div>
        <%= if Enum.empty?(@sandboxes) do %>
          <div class="text-gray-500 text-center py-8 rounded-lg border-2 border-dashed border-gray-200">
            <div class="space-y-3">
              <div class="text-base font-medium">No sandboxes found</div>
              <div class="text-sm">
                <.link
                  navigate={
                    ~p"/projects/#{@project.id}/#{@sandbox_name}/sandboxes/new"
                  }
                  class="text-blue-600 hover:text-blue-800 font-medium"
                >
                  Create your first sandbox
                </.link>
                to start experimenting.
              </div>
            </div>
          </div>
        <% else %>
          <div class="space-y-3">
            <.sandbox_card
              :for={sandbox <- @sandboxes}
              project={@project}
              sandbox={sandbox}
              current_sandbox={@current_sandbox}
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :root_project, Project, required: true
  attr :current_sandbox, Project, default: nil

  defp root_project_card(assigns) do
    assigns = assign(assigns, :is_current, is_nil(assigns.current_sandbox))

    ~H"""
    <div
      class="group block cursor-pointer rounded-xl border border-slate-200 hover:border-slate-300 hover:shadow-xs bg-white transition-all duration-200 overflow-hidden"
      phx-click={JS.navigate(~p"/projects/#{@root_project.id}/w")}
      role="button"
      tabindex="0"
    >
      <div class="flex items-stretch">
        <div class="w-3 flex-shrink-0 bg-indigo-600"></div>

        <div class="flex-1 px-4 py-4 flex items-center justify-between min-w-0">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-3 mb-1">
              <h3 class="font-semibold text-slate-900 text-lg group-hover:text-slate-800 truncate">
                {@root_project.name}
              </h3>

              <.active_indicator
                :if={@is_current}
                id={"active-indicator-#{@root_project.id}"}
              />
            </div>

            <.environment_badge
              :if={has_environment?(@root_project)}
              env={@root_project.env}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :open?, :boolean, required: true
  attr :sandbox, Project, default: nil
  attr :changeset, :any, required: true

  def confirm_delete_modal(assigns) do
    assigns =
      assign(assigns, :confirm_form, to_form(assigns.changeset, as: :confirm))

    ~H"""
    <.modal
      :if={@open?}
      id="confirm-delete-sandbox"
      show
      width="max-w-md"
      close_on_click_away
      close_on_keydown
      on_close={JS.push("close-delete-modal")}
    >
      <:title>
        <div class="flex items-start justify-between">
          <span class="font-bold">Delete sandbox</span>
          <button
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            phx-click={JS.push("close-delete-modal")}
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </button>
        </div>
      </:title>

      <section class="space-y-4">
        <p class="text-gray-700">
          Deleting a sandbox permanently removes its workflows, triggers, versions, keychain clones, and dataclips.
          To confirm, type the sandbox name below.
        </p>

        <div class="bg-red-50 border border-red-200 rounded-md p-3">
          <p class="text-sm text-red-800">This action cannot be undone.</p>
        </div>

        <.form
          for={@confirm_form}
          phx-submit="confirm-delete"
          phx-change="confirm-delete-validate"
        >
          <.input
            id="confirm-delete-name-input"
            type="text"
            field={@confirm_form[:name]}
            label="Sandbox name"
            placeholder={if @sandbox, do: @sandbox.name, else: ""}
            autocomplete="off"
            required
          />
          <.errors field={@confirm_form[:name]} />

          <.modal_footer>
            <.button
              theme="danger"
              type="submit"
              disabled={is_nil(@sandbox) || !@changeset.valid?}
              tooltip={
                (!@changeset.valid? && "Type the sandbox name to enable") || nil
              }
            >
              Delete Sandbox
            </.button>
            <.button
              theme="secondary"
              type="button"
              phx-click={JS.push("close-delete-modal")}
            >
              Cancel
            </.button>
          </.modal_footer>
        </.form>
      </section>
    </.modal>
    """
  end

  attr :project, Project, required: true
  attr :sandbox, Project, required: true
  attr :current_sandbox, Project, default: nil

  defp sandbox_card(assigns) do
    is_current_sandbox =
      assigns.current_sandbox && assigns.sandbox.id == assigns.current_sandbox.id

    assigns = assign(assigns, :is_current, is_current_sandbox)

    ~H"""
    <div
      class="group block cursor-pointer rounded-xl border border-slate-200 hover:border-slate-300 hover:shadow-xs bg-white transition-all duration-200 overflow-hidden"
      phx-click={JS.navigate(~p"/projects/#{@project.id}/#{@sandbox.name}/w")}
      role="button"
      tabindex="0"
    >
      <div class="flex items-stretch">
        <div
          class="w-3 flex-shrink-0"
          style={"background-color: #{@sandbox.color || "#4f39f6"};"}
        >
        </div>
        <div class="flex-1 px-4 py-4 flex items-center justify-between min-w-0">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-3 mb-1">
              <h3 class="font-semibold text-slate-900 text-lg group-hover:text-slate-800 truncate">
                {@sandbox.name}
              </h3>
              <.environment_badge
                :if={has_environment?(@sandbox)}
                env={@sandbox.env}
              />
              <.active_indicator
                :if={@is_current}
                id={"active-indicator-#{@sandbox.id}"}
              />
            </div>
          </div>
          <.sandbox_actions sandbox={@sandbox} project={@project} />
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true

  defp active_indicator(assigns) do
    ~H"""
    <span
      id={@id}
      class="relative inline-flex items-center justify-center flex-shrink-0"
      phx-hook="Tooltip"
      aria-label="Currently active project"
    >
      <span class="absolute w-4 h-4 bg-green-400 rounded-full animate-pulse opacity-75">
      </span>
      <span class="relative w-2.5 h-2.5 bg-green-500 rounded-full"></span>
    </span>
    """
  end

  attr :env, :string, required: true

  defp environment_badge(assigns) do
    ~H"""
    <span class="inline-block px-2 py-1 bg-slate-100 text-slate-600 text-xs rounded-full truncate max-w-32">
      {@env}
    </span>
    """
  end

  attr :sandbox, Project, required: true
  attr :project, Project, required: true

  defp sandbox_actions(assigns) do
    ~H"""
    <div class="flex gap-1 flex-shrink-0 ml-4">
      <.action_button
        id={"branch-rewire-sandbox-#{@sandbox.id}"}
        icon_type="custom"
        icon_name="branches"
        label="Branch/Rewire (coming soon)"
        disabled
      />

      <.action_button
        id={"duplicate-sandbox-#{@sandbox.id}"}
        icon_type="heroicon"
        icon_name="hero-clipboard-document"
        label="Duplicate (coming soon)"
        disabled
      />

      <.action_button
        id={"edit-sandbox-#{@sandbox.id}"}
        icon_type="heroicon"
        icon_name="hero-pencil-square"
        label="Edit this sandbox"
        action={JS.patch(~p"/projects/#{@project.id}/#{@sandbox.name}/edit")}
        icon_class="text-slate-700"
      />

      <.action_button
        id={"delete-sandbox-#{@sandbox.id}"}
        icon_type="heroicon"
        icon_name="hero-trash"
        label="Delete this sandbox"
        action={JS.push("open-delete-modal", value: %{id: @sandbox.id})}
        icon_class="text-slate-700"
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :icon_type, :string, required: true
  attr :icon_name, :string, required: true
  attr :label, :string, required: true
  attr :action, JS, default: %JS{}
  attr :disabled, :boolean, default: false
  attr :button_class, :string, default: "hover:bg-slate-100"
  attr :icon_class, :string, default: "text-slate-400"

  defp action_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class={["rounded-lg p-2 transition-colors", @button_class]}
      phx-click={@action}
      phx-stop-click
      phx-hook="Tooltip"
      aria-label={@label}
      disabled={@disabled}
    >
      <%= if @icon_type == "custom" do %>
        <Icon.branches class={["h-4 w-4", @icon_class]} />
      <% else %>
        <.icon name={@icon_name} class={["h-4 w-4", @icon_class]} />
      <% end %>
    </button>
    """
  end

  defp has_environment?(%{env: env}) when is_binary(env) do
    String.trim(env) != ""
  end

  defp has_environment?(_), do: false

  attr :id, :string, required: true
  attr :field, Phoenix.HTML.FormField, required: true
  attr :palette, :list, default: @color_palette
  attr :label, :string, default: "Color"
  attr :class, :string, default: ""
  attr :disabled, :boolean, default: false

  def color_palette(assigns) do
    assigns =
      assigns
      |> assign_new(:hex_colors, fn %{palette: palette} ->
        Enum.map(palette, fn {hex, _name} -> hex end)
      end)
      |> assign_new(:names_map, fn %{palette: palette} ->
        Map.new(palette)
      end)
      |> assign_new(:current, fn %{field: f, hex_colors: colors} ->
        f.value || List.first(colors)
      end)
      |> assign_new(:current_name, fn %{current: hex, names_map: names} ->
        Map.get(names, hex, hex)
      end)

    ~H"""
    <fieldset class={[@class]} disabled={@disabled}>
      <label class="block text-sm font-medium text-slate-800 mb-2">{@label}</label>

      <div class="space-y-3">
        <div
          role="radiogroup"
          class="grid grid-cols-4 sm:grid-cols-8 gap-0.5 select-none w-fit"
          aria-label="Choose a color for your sandbox"
        >
          <.color_option
            :for={{hex, index} <- Enum.with_index(@hex_colors)}
            field={@field}
            hex={hex}
            name={Map.get(@names_map, hex, hex)}
            selected={hex == @current}
            index={index}
          />
        </div>

        <.color_display current={@current} current_name={@current_name} />
      </div>

      <p class="sr-only" aria-live="polite">
        Selected: {@current_name} ({@current})
      </p>
    </fieldset>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :hex, :string, required: true
  attr :name, :string, required: true
  attr :selected, :boolean, required: true
  attr :index, :integer, required: true

  defp color_option(assigns) do
    ~H"""
    <label class="group relative inline-block cursor-pointer">
      <input
        type="radio"
        name={@field.name}
        value={@hex}
        checked={@selected}
        aria-label={@name}
        class="sr-only"
      />

      <span
        class={[
          "block w-12 h-12 md:w-14 md:h-14 transition-all duration-200 rounded-xs",
          "group-hover:scale-102 group-hover:z-10 relative"
        ]}
        style={"background-color: #{@hex};"}
        aria-hidden="true"
      />

      <.selected_indicator :if={@selected} />
    </label>
    """
  end

  defp selected_indicator(assigns) do
    ~H"""
    <span class="pointer-events-none absolute inset-0 flex items-center justify-center z-10">
      <.icon
        name="hero-check"
        class="w-5 h-5 sm:w-6 sm:h-6 text-white drop-shadow-lg"
      />
    </span>
    """
  end

  attr :current, :string, required: true
  attr :current_name, :string, required: true

  defp color_display(assigns) do
    ~H"""
    <div class="inline-flex items-center gap-2 rounded-md border border-black/10 bg-white px-3 py-2 text-sm text-slate-700">
      <span
        class="inline-block h-4 w-4 rounded-sm ring-1 ring-black/10 flex-shrink-0"
        style={"background-color: #{@current};"}
        aria-hidden="true"
      />
      <span class="font-medium">{@current_name}</span>
      <span class="font-mono text-slate-400 text-xs">{@current}</span>
    </div>
    """
  end
end
