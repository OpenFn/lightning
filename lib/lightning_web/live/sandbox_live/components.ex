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

  attr :project, Project, required: true
  attr :count, :integer, required: true

  def header(assigns) do
    ~H"""
    <div class="mb-6 flex items-center justify-between">
      <h3 class="text-3xl font-bold">
        Sandboxes
        <span class="text-base font-normal">
          ({@count})
        </span>
      </h3>
      <.create_button project={@project} />
    </div>
    """
  end

  def create_button(assigns) do
    ~H"""
    <.button
      id="create-sandbox"
      theme="primary"
      size="lg"
      type="button"
      phx-click={JS.patch(~p"/projects/#{@project.id}/sandboxes/new")}
    >
      Create Sandbox
    </.button>
    """
  end

  attr :project, Project, required: true
  attr :sandboxes, :list, required: true

  def list(assigns) do
    ~H"""
    <%= if Enum.empty?(@sandboxes) do %>
      <div class="text-gray-500 text-center py-8">
        No sandboxes found.
        <.link navigate={~p"/projects/#{@project.id}/sandboxes/new"} class="link">
          Create one
        </.link>
        to start experimenting.
      </div>
    <% else %>
      <div class="space-y-3">
        <.sandbox_card :for={sb <- @sandboxes} project={@project} sandbox={sb} />
      </div>
    <% end %>
    """
  end

  attr :open?, :boolean, required: true
  attr :sandbox, Project, default: nil
  attr :confirm_cs, :any, required: true

  def confirm_delete_modal(assigns) do
    assigns =
      assign(assigns, :confirm_form, to_form(assigns.confirm_cs, as: :confirm))

    ~H"""
    <.modal
      :if={@open?}
      id="confirm-delete-sandbox"
      show
      width="sm:max-w-md max-w-md"
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
            <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>

      <section class="space-y-4">
        <p>
          Deleting a sandbox removes its workflows, triggers, versions, keychain clones, and dataclips.
          This action <span class="font-semibold">cannot be undone</span>. To confirm, type the sandbox name in the input below.
        </p>

        <.form
          for={@confirm_form}
          phx-submit="confirm-delete"
          phx-change="confirm-delete-validate"
        >
          <.input
            id="confirm-delete-name"
            type="text"
            field={@confirm_form[:name]}
            placeholder={if @sandbox, do: @sandbox.name, else: ""}
            autocomplete="off"
            class="mt-1 block w-full rounded-lg border border-slate-300 bg-white
                   placeholder-slate-400 focus:border-primary-300 focus:ring
                   focus:ring-primary-200/50 sm:text-sm"
          />
          <.errors field={@confirm_form[:name]} />

          <.modal_footer>
            <.button
              theme="danger"
              type="submit"
              disabled={is_nil(@sandbox) || !@confirm_cs.valid?}
              tooltip={
                (!@confirm_cs.valid? && "Type the sandbox name to enable") || nil
              }
            >
              Delete
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

  defp sandbox_card(assigns) do
    ~H"""
    <div
      class="group block cursor-pointer rounded-xl border border-slate-200 bg-white hover:border-slate-300 hover:shadow-md transition-all duration-200 overflow-hidden"
      phx-click={JS.navigate(~p"/projects/#{@sandbox.id}/w")}
      role="button"
      tabindex="0"
    >
      <div class="flex items-stretch">
        <% hex = @sandbox.color || "#9ca3af" %>
        <div class="w-3" style={"background-color: #{hex};"}></div>
        <div class="flex-1 px-4 py-4 flex items-center justify-between">
          <div>
            <h3 class="font-semibold text-slate-900 text-lg group-hover:text-slate-800">
              {@sandbox.name}
            </h3>
            <span
              :if={is_binary(@sandbox.env) and String.trim(@sandbox.env) != ""}
              class="inline-block mt-1 px-3 py-1 bg-slate-100 text-slate-600 text-xs rounded-full"
            >
              {@sandbox.env}
            </span>
          </div>
          <div class="flex gap-2">
            <button
              id={"branch-rewire-#{@sandbox.id}"}
              type="button"
              class="rounded-lg p-2 hover:bg-slate-100 transition-colors"
              phx-click={JS.patch(~p"/projects/#{@project.id}/sandboxes")}
              phx-stop-click
              phx-hook="Tooltip"
              aria-label="Branch/Rewire is coming soon"
            >
              <Icon.branches class="h-4 w-4 text-slate-400" />
            </button>
            <button
              id={"duplicate-sandbox-#{@sandbox.id}"}
              type="button"
              class="rounded-lg p-2 hover:bg-slate-100 transition-colors"
              phx-click={JS.patch(~p"/projects/#{@project.id}/sandboxes")}
              phx-stop-click
              phx-hook="Tooltip"
              aria-label="Duplicate is coming soon"
            >
              <Heroicons.clipboard_document class="h-4 w-4 text-slate-400" />
            </button>
            <button
              id={"edit-sandbox-#{@sandbox.id}"}
              type="button"
              class="rounded-lg p-2 hover:bg-slate-100 transition-colors"
              phx-click={
                JS.patch(~p"/projects/#{@project.id}/sandboxes/#{@sandbox.id}/edit")
              }
              phx-stop-click
              phx-hook="Tooltip"
              aria-label="Click to edit this sandbox"
            >
              <Heroicons.pencil_square class="h-4 w-4 text-slate-600" />
            </button>
            <button
              id={"delete-sandbox-#{@sandbox.id}"}
              type="button"
              class="rounded-lg p-2 text-red-500 hover:bg-red-50 hover:text-red-600 transition-colors"
              phx-click={JS.push("open-delete-modal", value: %{id: @sandbox.id})}
              phx-stop-click
              phx-hook="Tooltip"
              aria-label="Click to delete this sandbox"
            >
              <Heroicons.trash class="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

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
    <fieldset class={@class} disabled={@disabled}>
      <label class="block text-sm font-medium text-slate-800 mb-1">{@label}</label>
      <div class="space-y-3">
        <div role="radiogroup" class="grid w-fit grid-cols-4 gap-0.5 select-none">
          <label
            :for={{hex, _i} <- Enum.with_index(@hex_colors)}
            class="group relative inline-block cursor-pointer"
          >
            <input
              type="radio"
              name={@field.name}
              value={hex}
              checked={hex == @current}
              aria-label={Map.get(@names_map, hex, hex)}
              class="sr-only"
            />
            <span
              class={[
                "block w-12 h-12 transition-all duration-150",
                "group-hover:scale-[1.03]",
                if(hex == @current, do: "ring-2 ring-white", else: "")
              ]}
              style={"background-color: #{hex};"}
              aria-hidden="true"
            />
            <%= if hex == @current do %>
              <span class="pointer-events-none absolute inset-0 flex items-center justify-center">
                <svg viewBox="0 0 20 20" class="h-5 w-5 text-white">
                  <path
                    fill="currentColor"
                    stroke="currentColor"
                    stroke-width="0.5"
                    d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                  />
                </svg>
              </span>
            <% end %>
          </label>
        </div>
        <span class="inline-flex items-center gap-2 rounded-md border border-black/10 bg-white px-2 py-1 text-xs text-slate-700">
          <span
            class="inline-block h-3.5 w-3.5 rounded-sm ring-1 ring-black/10"
            style={"background-color: #{@current};"}
          />
          <span class="font-medium">{@current_name}</span>
          <span class="font-mono text-slate-400">{@current}</span>
        </span>
      </div>
      <p class="sr-only" aria-live="polite">
        Selected: {@current_name} ({@current})
      </p>
    </fieldset>
    """
  end
end
