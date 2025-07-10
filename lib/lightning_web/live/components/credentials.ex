defmodule LightningWeb.Components.Credentials do
  @moduledoc false
  use LightningWeb, :component

  alias LightningWeb.Components.Common
  alias LightningWeb.CredentialLive.JsonSchemaBodyComponent
  alias LightningWeb.CredentialLive.RawBodyComponent
  alias Phoenix.LiveView.JS

  @credentials_index_live_component "credentials-index-component"
  @close_active_modal JS.push("close_active_modal",
                        target: "##{@credentials_index_live_component}"
                      )

  def credentials_index_live_component(assigns) do
    assigns = assign(assigns, :id, @credentials_index_live_component)

    ~H"""
    <.live_component
      id={@id}
      module={LightningWeb.CredentialLive.CredentialIndexComponent}
      {assigns}
    />
    """
  end

  attr :id, :string, required: true
  attr :width, :string, default: "max-w-md"
  attr :on_modal_close, Phoenix.LiveView.JS, default: @close_active_modal
  slot :inner_block, required: true
  slot :title, required: true

  def credential_modal(assigns) do
    ~H"""
    <.modal id={@id} width={@width} on_close={@on_modal_close} show={true}>
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            {render_slot(@title)}
          </span>

          <button
            phx-click={hide_modal(@on_modal_close, @id)}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>

      {render_slot(@inner_block)}
    </.modal>
    """
  end

  attr :modal_id, :string, required: true
  attr :on_modal_close, Phoenix.LiveView.JS, default: @close_active_modal
  attr :rest, :global
  slot :inner_block

  def cancel_button(assigns) do
    ~H"""
    <.button
      type="button"
      phx-click={hide_modal(@on_modal_close, @modal_id)}
      theme="secondary"
      {@rest}
    >
      {render_slot(@inner_block) || "Cancel"}
    </.button>
    """
  end

  attr :id, :string, required: false
  attr :type, :string, required: true
  attr :form, :map, required: true
  slot :inner_block

  def form_component(%{type: "raw"} = assigns) do
    ~H"""
    <RawBodyComponent.fieldset :let={l} form={@form}>
      {render_slot(@inner_block, l)}
    </RawBodyComponent.fieldset>
    """
  end

  def form_component(%{type: _schema} = assigns) do
    ~H"""
    <JsonSchemaBodyComponent.fieldset :let={l} form={@form}>
      {render_slot(@inner_block, l)}
    </JsonSchemaBodyComponent.fieldset>
    """
  end

  attr :id, :string, required: true
  attr :type, :atom, required: true
  attr :available_projects, :list, required: true
  attr :projects, :list, required: true
  attr :selected_projects, :list, required: true
  attr :selected, :string, required: true
  attr :phx_target, :any, default: nil

  def projects_picker(assigns) do
    additionals =
      case assigns.type do
        :credential ->
          %{
            select_id: "project-credentials-list-#{assigns.id}",
            prompt: "Grant projects access to this credential",
            remove_project_id: "remove-project-credential-button-#{assigns.id}"
          }

        :oauth_client ->
          %{
            select_id: "project-oauth-clients-list-#{assigns.id}",
            prompt: "Grant projects access to this OAuth client",
            remove_project_id: "remove-project-oauth-client-button-#{assigns.id}"
          }
      end

    assigns = assign(assigns, additionals)

    ~H"""
    <div class="col-span-3">
      <div>
        <label
          for={@select_id}
          class={["block text-sm font-semibold leading-6 text-slate-800"]}
        >
          Project
        </label>
        <div class="mt-1 pb-3">
          <select
            id={@select_id}
            name="project_id"
            class={[
              "block w-full rounded-lg border border-secondary-300 bg-white",
              "sm:text-sm shadow-xs",
              "focus:border-primary-300 focus:ring focus:ring-primary-200 focus:ring-primary-200/50",
              "disabled:cursor-not-allowed "
            ]}
            phx-change="add_selected_project"
            phx-target={@phx_target}
          >
            <option value="">{@prompt}</option>
            {Phoenix.HTML.Form.options_for_select(
              map_projects_for_select(@available_projects),
              ""
            )}
          </select>
        </div>

        <div class="overflow-auto max-h-32">
          <span
            :for={project <- @selected_projects}
            class="inline-flex items-center gap-1 rounded-md bg-blue-100 px-4 mr-1 py-2 mb-2 text-gray-600"
          >
            {project.name}
            <button
              id={"#{@remove_project_id}-#{project.id}"}
              phx-target={@phx_target}
              phx-value-project_id={project.id}
              phx-click="remove_selected_project"
              type="button"
              class="group relative -mr-1 h-3.5 w-3.5 rounded-sm hover:bg-gray-500/20"
            >
              <span class="sr-only">Remove</span>
              <Heroicons.x_mark solid class="w-4 h-4" />
              <span class="absolute -inset-1"></span>
            </button>
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp map_projects_for_select(projects) do
    Enum.map(projects, fn %{id: id, name: name} ->
      {name, id}
    end)
  end

  attr :users, :list, required: true
  attr :form, :map, required: true

  def credential_transfer(assigns) do
    ~H"""
    <div class="hidden sm:block" aria-hidden="true">
      <div class="border-t border-secondary-200 mb-6"></div>
    </div>
    <fieldset>
      <legend class="contents text-base font-medium text-gray-900">
        Transfer Ownership
      </legend>
      <p class="text-sm text-gray-500">
        Assign ownership of this credential to someone else.
      </p>
      <div class="mt-4">
        <.input type="select" field={@form[:user_id]} options={@users} label="Owner" />
      </div>
    </fieldset>
    """
  end

  attr :id, :string, required: true
  attr :disabled, :boolean, default: false
  attr :phx_target, :any, default: "##{@credentials_index_live_component}"

  def new_credential_menu_button(assigns) do
    assigns =
      assign_new(assigns, :options, fn ->
        [
          %{
            name: "Credential",
            id: "new-credential-option-menu-item",
            target: "new_credential"
          },
          %{
            name: "Keychain credential",
            id: "new-keychain-credential-option-menu-item",
            target: "new_keychain_credential"
          },
          %{
            name: "OAuth client",
            id: "new-oauth-client-option-menu-item",
            target: "new_oauth_client",
            badge: "Advanced"
          }
        ]
      end)

    ~H"""
    <Common.simple_dropdown id={@id}>
      <:button>
        Add new
      </:button>
      <:options>
        <a
          :for={%{name: name, id: id, target: target} = option <- @options}
          href="#"
          role="menuitem"
          tabindex="-1"
          id={id}
          phx-click={target}
          phx-target={@phx_target}
          disabled={@disabled}
        >
          {name}<span
            :if={Map.get(option, :badge)}
            class="ml-2 inline-flex items-center rounded-md bg-gray-50 px-1.5 py-0.5 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10"
          ><%= Map.get(option, :badge) %></span>
        </a>
      </:options>
    </Common.simple_dropdown>
    """
  end
end
