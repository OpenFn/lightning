defmodule LightningWeb.SandboxLive.Components do
  use LightningWeb, :component

  alias Lightning.Projects.Project
  alias Phoenix.LiveView.JS

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
      class="group block cursor-pointer rounded-xl border border-slate-300 bg-white hover:bg-slate-50 transition"
      phx-click={JS.navigate(~p"/projects/#{@sandbox.id}/w")}
      role="button"
      tabindex="0"
    >
      <div class="flex items-center justify-between px-4 py-4">
        <div class="flex items-center gap-3">
          <% hex = @sandbox.color || "#9ca3af" %>
          <span
            class="inline-block h-5 w-5 rounded-md"
            style={"background-color: #{hex}; --ring: #{hex}; box-shadow: 0 0 0 1px var(--ring) inset, 0 0 0 2px white inset; border-color: var(--ring);"}
            aria-hidden="true"
          />
          <span class="text-base font-medium text-slate-800 group-hover:text-slate-900">
            {@sandbox.name}
          </span>
          <span
            :if={is_binary(@sandbox.env) and String.trim(@sandbox.env) != ""}
            class="inline-flex items-center rounded-full border border-slate-200 px-2 py-0.5 text-[11px] font-medium text-slate-600"
          >
            {@sandbox.env}
          </span>
        </div>

        <div class="flex items-center gap-4 text-slate-700/80">
          <button
            id={"branch-rewire-#{@sandbox.id}"}
            type="button"
            class="rounded p-1 hover:bg-slate-100"
            phx-click={JS.patch(~p"/projects/#{@project.id}/sandboxes")}
            phx-stop-click
            phx-hook="Tooltip"
            aria-label="Branch/Rewire is coming soon"
          >
            <Icon.branches class="h-5 w-5 text-slate-300" />
          </button>

          <button
            id={"duplicate-sandbox-#{@sandbox.id}"}
            type="button"
            class="rounded p-1 hover:bg-slate-100"
            phx-click={JS.patch(~p"/projects/#{@project.id}/sandboxes")}
            phx-stop-click
            phx-hook="Tooltip"
            aria-label="Duplicate is coming soon"
          >
            <Heroicons.clipboard_document class="h-5 w-5 text-slate-300" />
          </button>

          <button
            id={"edit-sandbox-#{@sandbox.id}"}
            type="button"
            class="rounded p-1 hover:bg-slate-100"
            phx-click={
              JS.patch(~p"/projects/#{@project.id}/sandboxes/#{@sandbox.id}/edit")
            }
            phx-stop-click
            phx-hook="Tooltip"
            aria-label="Click to edit this sandbox"
          >
            <Heroicons.pencil_square class="h-5 w-5" />
          </button>

          <button
            id={"delete-sandbox-#{@sandbox.id}"}
            type="button"
            class="rounded p-1 text-red-600 hover:bg-slate-100"
            phx-click={JS.push("open-delete-modal", value: %{id: @sandbox.id})}
            phx-stop-click
            phx-hook="Tooltip"
            aria-label="Click to delete this sandbox"
          >
            <Heroicons.trash class="h-5 w-5" />
          </button>
        </div>
      </div>
    </div>
    """
  end
end
