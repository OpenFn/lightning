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

  attr :id, :string, default: @credentials_index_live_component
  attr :current_user, :any, required: true
  attr :project, :any
  attr :projects, :list, required: true
  attr :can_create_project_credential, :any, required: true
  attr :show_owner_in_tables, :boolean, default: false
  attr :return_to, :string, required: true

  def credentials_index_live_component(assigns) do
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
  attr :show, :boolean, default: true
  slot :inner_block, required: true
  slot :title, required: true

  def credential_modal(assigns) do
    ~H"""
    <.modal id={@id} width={@width} on_close={@on_modal_close} show={@show}>
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
  attr :current_body, :map, default: %{}
  attr :schema_changeset, :any, default: nil
  attr :raw_body_touched, :boolean, default: false
  slot :inner_block

  def form_component(%{type: "raw"} = assigns) do
    ~H"""
    <RawBodyComponent.fieldset
      :let={l}
      form={@form}
      current_body={@current_body}
      touched={@raw_body_touched}
    >
      {render_slot(@inner_block, l)}
    </RawBodyComponent.fieldset>
    """
  end

  def form_component(%{type: _schema} = assigns) do
    ~H"""
    <JsonSchemaBodyComponent.fieldset
      :let={l}
      form={@form}
      current_body={@current_body}
      schema_changeset={@schema_changeset}
    >
      {render_slot(@inner_block, l)}
    </JsonSchemaBodyComponent.fieldset>
    """
  end

  attr :id, :string, required: true
  attr :type, :atom, required: true
  attr :available_projects, :list, required: true
  attr :projects, :list, required: true
  attr :selected_projects, :list, required: true
  attr :workflows_using_credentials, :map, default: %{}
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
        <%!-- <label
          for={@select_id}
          class={["block text-sm font-semibold leading-6 text-slate-800"]}
        >
          Project
        </label> --%>
        <div class="mt-1 pb-3">
          <select
            id={@select_id}
            name="project_id"
            class={[
              "block w-full rounded-lg border border-secondary-300 bg-white",
              "sm:text-sm shadow-xs",
              "focus:border-primary-300 focus:ring focus:ring-primary-200/50",
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
              {if(@workflows_using_credentials[project.id], do: %{"data-confirm": "Warning: This credential is in use by the following workflows: #{Enum.join(@workflows_using_credentials[project.id], ", ")}. If you revoke access to the \"#{project.name}\" project, runs for those workflows will probably fail until you provide a new credential. Are you sure you want to revoke access?"}, else: %{})}
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

  attr :id, :string, required: true

  attr :keychain_credential, Lightning.Credentials.KeychainCredential,
    required: true

  attr :keychain_changeset, Ecto.Changeset, required: true
  attr :available_credentials, :list, required: true
  attr :myself, :any, required: true
  attr :action, :atom, default: :new
  attr :from_collab_editor, :boolean, default: false
  attr :on_modal_close, Phoenix.LiveView.JS, required: true
  attr :show_modal, :boolean, default: true
  attr :on_back, :any, default: nil
  attr :on_validate, :string, default: "validate"
  attr :on_submit, :string, default: "save"

  def keychain_credential_form(assigns) do
    ~H"""
    <div class="text-xs text-left">
      <.credential_modal
        id={@id}
        width="xl:min-w-1/3 min-w-1/2 max-w-full"
        show={@show_modal}
        on_modal_close={@on_modal_close}
      >
        <:title>
          <%= if @action == :edit do %>
            Edit {@keychain_credential.name || "keychain credential"}
          <% else %>
            Create keychain credential
          <% end %>
        </:title>

        <.form
          :let={f}
          for={@keychain_changeset}
          id={"keychain-credential-form-#{@keychain_credential.id || "new"}"}
          phx-target={@myself}
          phx-change={@on_validate}
          phx-submit={@on_submit}
        >
          <div class="space-y-6 bg-white py-5">
            <fieldset>
              <div class="space-y-4">
                <div>
                  <.input
                    type="text"
                    field={f[:name]}
                    label="Name"
                    placeholder="Enter keychain credential name"
                  />
                  <p class="mt-1 text-sm text-gray-500">
                    A descriptive name for this keychain credential
                  </p>
                </div>

                <div>
                  <.input
                    type="text"
                    field={f[:path]}
                    label="JSONPath Expression"
                    placeholder="$.user_id"
                  />
                  <p class="mt-1 text-sm text-gray-500">
                    JSONPath expression to extract credential selector from run data
                  </p>
                </div>

                <div>
                  <.input
                    type="select"
                    field={f[:default_credential_id]}
                    label="Default Credential"
                    options={
                      [{"No default credential", nil}] ++
                        Enum.map(@available_credentials, &{&1.name, &1.id})
                    }
                  />
                  <p class="mt-1 text-sm text-gray-500">
                    Credential to use when JSONPath expression doesn't match
                  </p>
                </div>
              </div>
            </fieldset>
          </div>

          <.modal_footer>
            <.button
              id={"save-keychain-credential-button-#{@keychain_credential.id || "new"}"}
              type="submit"
              theme="primary"
              disabled={!f.source.valid?}
            >
              <%= case @action do %>
                <% :edit -> %>
                  Save Changes
                <% :new -> %>
                  Create
              <% end %>
            </.button>
            <%= if @from_collab_editor do %>
              <.button type="button" phx-click={@on_back} theme="secondary">
                Back
              </.button>
            <% else %>
              <.cancel_button modal_id={@id} />
            <% end %>
          </.modal_footer>
        </.form>
      </.credential_modal>
    </div>
    """
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

  slot :option, required: true do
    attr :id, :string, required: true
    attr :target, :string, required: true
    attr :badge, :string, required: false
    attr :disabled, :boolean, required: false
  end

  def new_credential_menu_button(assigns) do
    ~H"""
    <Common.simple_dropdown id={@id}>
      <:button>
        Add new
      </:button>
      <:options>
        <.menu_button_option
          :for={option <- @option}
          id={option.id}
          target={option.target}
          badge={option[:badge]}
          disabled={Map.get(option, :disabled, false)}
          phx-target={@phx_target}
        >
          {render_slot(option)}
        </.menu_button_option>
      </:options>
    </Common.simple_dropdown>
    """
  end

  attr :id, :string, required: true
  attr :target, :string, required: true
  attr :badge, :string, default: nil
  attr :disabled, :boolean, required: false
  attr :rest, :global
  slot :inner_block, required: true

  defp menu_button_option(assigns) do
    ~H"""
    <span
      role="menuitem"
      tabindex="-1"
      phx-click={!@disabled && "show_modal"}
      phx-value-target={!@disabled && @target}
      id={@id}
      class={
        if @disabled, do: "text-gray-400 cursor-not-allowed", else: "cursor-pointer"
      }
      {@rest}
    >
      {render_slot(@inner_block)}
      <span
        :if={@badge}
        class={[
          "ml-2 inline-flex items-center rounded-md bg-gray-50",
          "px-1.5 py-0.5 text-xs font-medium text-gray-600 ring-1",
          "ring-inset ring-gray-500/10"
        ]}
      >
        {@badge}
      </span>
    </span>
    """
  end
end
