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

  def random_color do
    Enum.random(color_palette_hex_colors())
  end

  attr :open?, :boolean, required: true
  attr :sandbox, Project, required: true
  attr :changeset, :any, required: true
  attr :root_project, Project, required: true
  attr :descendants, :list, default: []

  def confirm_delete_modal(assigns) do
    assigns =
      assigns
      |> assign(:confirm_form, to_form(assigns.changeset, as: :confirm))
      |> assign(:descendant_count, length(assigns.descendants))

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
          Deleting a sandbox removes it from OpenFn.
          <span :if={@descendant_count == 1}>
            Its child sandbox will also be deleted.
          </span>
          <span :if={@descendant_count > 1}>
            Its {@descendant_count} child sandboxes will also be deleted.
          </span>
        </p>

        <p class="text-gray-700">
          Workflows, triggers, versions, keychain clones, and dataclips will be permanently removed.
        </p>

        <p :if={@sandbox.is_current} class="text-gray-700">
          You are currently viewing this project.
          After deletion, you'll be redirected to <strong>{@root_project.name}</strong>.
        </p>

        <p class="text-gray-700">
          To confirm, type the sandbox name below.
        </p>

        <div class="bg-amber-50 border border-amber-200 rounded-md p-3">
          <p class="text-sm text-amber-800">
            This sandbox will be retained for {grace_period_label()} before being permanently removed. You can restore it from the sandbox list during that window.
          </p>
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
            required
          />

          <.modal_footer>
            <.button
              theme="danger"
              type="submit"
              disabled={!@changeset.valid?}
              {if !@changeset.valid?, do: [tooltip: "Type the sandbox name to enable"], else: []}
            >
              Delete sandbox
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

  defp grace_period_label do
    case Lightning.Config.purge_deleted_after_days() do
      nil -> "the configured grace period"
      1 -> "1 day"
      days when is_integer(days) -> "#{days} days"
    end
  end
end
