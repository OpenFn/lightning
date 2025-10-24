defmodule LightningWeb.SandboxLive.Components do
  use LightningWeb, :component

  alias Lightning.Projects.Project
  alias Phoenix.LiveView.JS

  @color_palette [
    "#870d4c",
    "#E33D63",
    "#E64A2E",
    "#F39B33",
    "#F4C644",
    "#fcde32",
    "#d6e819",
    "#9AD04E",
    "#E040FB",
    "#8E3FB1",
    "#5E3FB8",
    "#5AA1F0",
    "#68d6e2",
    "#4AC1CE",
    "#2E9B92",
    "#56B15A"
  ]

  def color_palette_hex_colors do
    @color_palette
  end

  attr :current_project, Project, required: true
  attr :enable_create_button, :boolean, required: true
  attr :disabled_button_tooltip, :string, default: nil

  def header(assigns) do
    ~H"""
    <div class="mb-6 flex items-center justify-between">
      <h3 class="text-3xl font-bold">Sandboxes</h3>
      <.create_button
        current_project={@current_project}
        disabled={!@enable_create_button}
        tooltip={@disabled_button_tooltip}
      />
    </div>
    """
  end

  attr :current_project, Project, required: true
  attr :disabled, :boolean, required: true
  attr :tooltip, :string, default: nil

  def create_button(assigns) do
    ~H"""
    <.button
      id="create-sandbox-button"
      theme="primary"
      size="lg"
      type="button"
      disabled={@disabled}
      tooltip={@disabled && @tooltip}
      phx-click={JS.patch(~p"/projects/#{@current_project.id}/sandboxes/new")}
    >
      Create Sandbox
    </.button>
    """
  end

  attr :root_project, Project, default: nil
  attr :current_project, Project, required: true
  attr :sandboxes, :list, required: true
  attr :enable_create_button, :boolean, required: true
  attr :disabled_button_tooltip, :string, default: nil

  def workspace_list(assigns) do
    ~H"""
    <div class="space-y-3">
      <div>
        <.root_project_card
          root_project={@root_project}
          is_current={@current_project.id == @root_project.id}
        />
      </div>
      <div>
        <%= if Enum.empty?(@sandboxes) do %>
          <div class="text-gray-500 text-center py-8 rounded-lg border-2 border-dashed border-gray-200">
            <div class="space-y-3">
              <div class="text-base font-medium">No sandboxes found</div>
              <div class="text-sm">
                <%= if @enable_create_button do %>
                  <.link
                    navigate={~p"/projects/#{@current_project.id}/sandboxes/new"}
                    class="text-blue-600 hover:text-blue-800 font-medium"
                  >
                    Create your first sandbox
                  </.link>
                  to start experimenting.
                <% else %>
                  {@disabled_button_tooltip}
                <% end %>
              </div>
            </div>
          </div>
        <% else %>
          <div class="space-y-3">
            <.sandbox_card :for={sandbox <- @sandboxes} sandbox={sandbox} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :open?, :boolean, required: true
  attr :sandbox, Project, required: true
  attr :changeset, :any, required: true
  attr :root_project, Project, required: true

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
          <%= if @sandbox.is_current do %>
            You are currently viewing this project.
            After deletion, you'll be redirected to <strong>{@root_project.name}</strong>.
          <% end %>
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
            placeholder={@sandbox.name}
            autocomplete="off"
            required
          />
          <.errors field={@confirm_form[:name]} />

          <.modal_footer>
            <.button
              theme="danger"
              type="submit"
              disabled={!@changeset.valid?}
              {if !@changeset.valid?, do: [tooltip: "Type the sandbox name to enable"], else: []}
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

  attr :open?, :boolean, required: true
  attr :sandbox, Project, required: true
  attr :target_options, :list, required: true
  attr :changeset, :any, required: true
  attr :descendants, :list, default: []
  attr :has_diverged, :boolean, default: false

  def merge_modal(assigns) do
    assigns =
      assigns
      |> assign(:merge_form, to_form(assigns.changeset, as: :merge))
      |> assign(:descendant_count, length(assigns.descendants))

    ~H"""
    <.modal
      :if={@open?}
      id="merge-sandbox-modal"
      show
      width="max-w-xl"
      close_on_click_away
      close_on_keydown
      on_close={JS.push("close-merge-modal")}
    >
      <:title>
        <div class="flex items-start justify-between">
          <span class="font-bold">Merge</span>
          <button
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            phx-click={JS.push("close-merge-modal")}
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </button>
        </div>
      </:title>

      <.form
        for={@merge_form}
        phx-change="select-merge-target"
        phx-submit="confirm-merge"
      >
        <section class="space-y-4">
          <div class="flex items-center gap-2 text-gray-700">
            <span>Merge</span>
            <span class="p-1 bg-gray-50 text-gray-800 rounded-md border border-slate-200 font-medium">
              {@sandbox.name}
            </span>
            <span>into</span>
            <div class="inline-block min-w-[200px]">
              <.input
                type="custom-select"
                id="merge-target-select"
                field={@merge_form[:target_id]}
                options={
                  Enum.map(@target_options, fn opt -> {opt.label, opt.value} end)
                }
                class="text-base"
              />
            </div>
          </div>

          <p class="text-gray-700">
            This will merge all workflows from <strong>{@sandbox.name}</strong>
            into <strong>{get_selected_target_label(@target_options, @merge_form[:target_id].value)}</strong>,
            then close <strong>{@sandbox.name}</strong>
            <%= if @descendant_count == 1 do %>
              and its child sandbox <strong>{List.first(@descendants).name}</strong>
            <% end %>
            <%= if @descendant_count > 1 do %>
              and its {@descendant_count} child sandboxes
            <% end %>. This action cannot be undone.
          </p>

          <%= if @descendant_count > 1 do %>
            <Common.alert
              id="merge-descendants-alert"
              type="warning"
              header="Child sandboxes will be closed"
            >
              <:message>
                <p class="mb-2">
                  The following {@descendant_count} sandboxes will be permanently closed:
                </p>
                <ul class="list-disc list-inside space-y-1 ml-2 mb-3">
                  <li :for={descendant <- @descendants}>
                    {descendant.name}
                  </li>
                </ul>
                <p>
                  Consider merging child sandboxes into
                  <strong>{@sandbox.name}</strong>
                  first to preserve their work before merging up.
                </p>
              </:message>
            </Common.alert>
          <% end %>

          <%= if @descendant_count == 1 do %>
            <Common.alert id="merge-single-descendant-alert" type="warning">
              <:message>
                <strong>{List.first(@descendants).name}</strong>
                will also be closed. Consider merging it into
                <strong>{@sandbox.name}</strong>
                first to preserve its work.
              </:message>
            </Common.alert>
          <% end %>

          <%= if @has_diverged do %>
            <Common.alert
              id="merge-divergence-alert"
              type="danger"
              header="Target project has diverged"
            >
              <:message>
                {get_selected_target_label(
                  @target_options,
                  @merge_form[:target_id].value
                )} has been modified since this sandbox was created. Merging may result in lost changes. Are you sure you wish to proceed?
              </:message>
            </Common.alert>
          <% end %>

          <Common.alert
            id="merge-beta-warning"
            type="warning"
            header="Beta feature warning"
          >
            <:message>
              Sandbox merging is in beta. For production projects, use the CLI to merge locally and preview changes first.
            </:message>
          </Common.alert>

          <.modal_footer>
            <.button theme="primary" type="submit">
              Merge
            </.button>
            <.button
              theme="secondary"
              type="button"
              phx-click={JS.push("close-merge-modal")}
            >
              Cancel
            </.button>
          </.modal_footer>
        </section>
      </.form>
    </.modal>
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
      |> assign_new(:hex_colors, fn %{palette: palette} -> palette end)
      |> assign_new(:current, fn %{field: f, hex_colors: colors} ->
        f.value || List.first(colors)
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
            name={hex}
            selected={hex == @current}
            index={index}
          />
        </div>
      </div>

      <p class="sr-only" aria-live="polite">
        Selected: {@current}
      </p>
    </fieldset>
    """
  end

  attr :root_project, Project, required: true
  attr :is_current, :boolean, required: true

  defp root_project_card(assigns) do
    ~H"""
    <div
      class="group block cursor-pointer rounded-xl border border-gray-200 bg-white hover:bg-gray-50 transition-all duration-200 overflow-hidden"
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
              <.badge
                id={"env-badge-#{@root_project.id}"}
                env={
                  if has_environment?(@root_project),
                    do: @root_project.env,
                    else: "main"
                }
              />
              <.badge
                :if={@is_current}
                id={"active-badge-#{@root_project.id}"}
                env="active"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :sandbox, :map, required: true

  defp sandbox_card(assigns) do
    ~H"""
    <div
      class="group block cursor-pointer rounded-xl bg-white border border-gray-200 bg-white hover:bg-gray-50 transition-all duration-200 overflow-hidden"
      phx-click={JS.navigate(~p"/projects/#{@sandbox.id}/w")}
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
              <.badge
                :if={has_environment?(@sandbox)}
                id={"env-badge-#{@sandbox.id}"}
                env={@sandbox.env}
              />
              <.badge
                :if={@sandbox.is_current}
                id={"active-badge-#{@sandbox.id}"}
                env="active"
              />
            </div>
          </div>
          <.sandbox_actions sandbox={@sandbox} />
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :env, :string, required: true

  defp badge(assigns) do
    ~H"""
    <span
      id={@id}
      class="inline-block px-2 py-1 bg-slate-100 text-slate-600 text-xs rounded-full truncate max-w-32"
    >
      {@env}
    </span>
    """
  end

  attr :sandbox, :map, required: true

  defp sandbox_actions(assigns) do
    ~H"""
    <div class="flex gap-1 flex-shrink-0 ml-4">
      <.action_button
        id={"branch-rewire-sandbox-#{@sandbox.id}"}
        icon_type="custom"
        icon_name="branches"
        label={
          if not @sandbox.can_merge do
            "You are not authorized to merge this sandbox"
          else
            "Merge this sandbox"
          end
        }
        action={
          if @sandbox.can_merge,
            do: JS.push("open-merge-modal", value: %{id: @sandbox.id}),
            else: %JS{}
        }
        disabled={not @sandbox.can_merge}
        icon_class={
          if @sandbox.can_merge, do: "text-slate-700", else: "text-slate-300"
        }
        button_class={
          if @sandbox.can_merge,
            do: "hover:bg-slate-100",
            else: "cursor-not-allowed"
        }
      />

      <.action_button
        id={"duplicate-sandbox-#{@sandbox.id}"}
        icon_type="heroicon"
        icon_name="hero-clipboard-document"
        label="Duplicate (coming soon)"
        disabled={true}
        icon_class="text-slate-300"
        button_class="cursor-not-allowed"
      />

      <.action_button
        id={"edit-sandbox-#{@sandbox.id}"}
        icon_type="heroicon"
        icon_name="hero-pencil-square"
        label={
          if not @sandbox.can_edit do
            "You are not authorized to edit this sandbox"
          else
            "Edit this sandbox"
          end
        }
        action={
          if @sandbox.can_edit,
            do:
              JS.patch(
                ~p"/projects/#{@sandbox.parent_id}/sandboxes/#{@sandbox.id}/edit"
              ),
            else: %JS{}
        }
        disabled={not @sandbox.can_edit}
        icon_class={
          if @sandbox.can_edit, do: "text-slate-700", else: "text-slate-300"
        }
        button_class={
          if @sandbox.can_edit,
            do: "hover:bg-slate-100",
            else: "cursor-not-allowed"
        }
      />

      <.action_button
        id={"delete-sandbox-#{@sandbox.id}"}
        icon_type="heroicon"
        icon_name="hero-trash"
        label={
          if not @sandbox.can_delete do
            "You are not authorized to delete this sandbox"
          else
            "Delete this sandbox"
          end
        }
        action={
          if @sandbox.can_delete,
            do: JS.push("open-delete-modal", value: %{id: @sandbox.id}),
            else: %JS{}
        }
        disabled={not @sandbox.can_delete}
        icon_class={
          if @sandbox.can_delete, do: "text-slate-700", else: "text-slate-300"
        }
        button_class={
          if @sandbox.can_delete,
            do: "hover:bg-slate-100",
            else: "cursor-not-allowed"
        }
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
    <span id={@id} class="inline-block" phx-hook="Tooltip" aria-label={@label}>
      <button
        type="button"
        class={[
          "rounded-lg p-2 transition-colors flex items-center justify-center",
          @button_class
        ]}
        phx-click={(@disabled && %JS{}) || @action}
        phx-stop-click
        disabled={@disabled}
        aria-disabled={@disabled}
      >
        <%= if @icon_type == "custom" do %>
          <Icon.branches class={["h-4 w-4", @icon_class]} />
        <% else %>
          <.icon name={@icon_name} class={["h-4 w-4", @icon_class]} />
        <% end %>
      </button>
    </span>
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

  defp has_environment?(%{env: env}) when is_binary(env) do
    String.trim(env) != ""
  end

  defp has_environment?(_), do: false

  defp get_selected_target_label(target_options, selected_target_id) do
    case Enum.find(target_options, &(&1.value == selected_target_id)) do
      nil -> "MAIN"
      target -> target.label
    end
  end
end
