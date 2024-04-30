defmodule LightningWeb.Components.Credentials do
  @moduledoc false
  use LightningWeb, :component

  alias LightningWeb.CredentialLive.JsonSchemaBodyComponent
  alias LightningWeb.CredentialLive.RawBodyComponent
  alias LightningWeb.CredentialLive.OauthComponent

  def delete_credential_modal(assigns) do
    ~H"""
    <.modal id={@id} width="max-w-md">
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Delete Credential
          </span>

          <button
            phx-click={hide_modal(@id)}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <div class="px-6">
        <p class="text-sm text-gray-500">
          You are about the delete the credential "<%= @credential.name %>" which may be used in other projects. All jobs using this credential will fail.
          <br /><br />Do you want to proceed with this action?
        </p>
      </div>
      <div class="flex flex-row-reverse gap-4 mx-6 mt-2">
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          phx-value-credential_id={@credential.id}
          phx-click="delete_credential"
          color_class="bg-red-600 hover:bg-red-700 text-white"
          phx-disable-with="Deleting..."
        >
          Delete
        </.button>
        <button
          type="button"
          phx-click={hide_modal(@id)}
          class="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
        >
          Cancel
        </button>
      </div>
    </.modal>
    """
  end

  def delete_oauth_client_modal(assigns) do
    ~H"""
    <.modal id={@id} width="max-w-md">
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Delete Oauth Client
          </span>

          <button
            phx-click={hide_modal(@id)}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <div class="px-6">
        <p class="text-sm text-gray-500">
          You are about the delete the Oauth client "<%= @client.name %>" which may be used in other projects. All jobs dependent on this client will fail.
          <br /><br />Do you want to proceed with this action?
        </p>
      </div>
      <div class="flex flex-row-reverse gap-4 mx-6 mt-2">
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          phx-value-oauth_client_id={@client.id}
          phx-click="delete_oauth_client"
          color_class="bg-red-600 hover:bg-red-700 text-white"
          phx-disable-with="Deleting..."
        >
          Delete
        </.button>
        <button
          type="button"
          phx-click={hide_modal(@id)}
          class="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
        >
          Cancel
        </button>
      </div>
    </.modal>
    """
  end

  attr :id, :string, required: false
  attr :type, :string, required: true
  attr :form, :map, required: true
  attr :action, :any, required: false
  attr :phx_target, :any, default: nil
  attr :schema, :string, required: false
  attr :sandbox_value, :boolean, default: false
  attr :api_version, :string, default: ""
  attr :update_body, :any, required: false
  attr :scopes_changed, :boolean, required: false
  attr :oauth_clients, :list, required: false
  slot :inner_block

  def form_component(%{type: "googlesheets"} = assigns) do
    ~H"""
    <OauthComponent.fieldset
      :let={l}
      id={@id}
      form={@form}
      action={@action}
      schema={@schema}
      update_body={@update_body}
    >
      <%= render_slot(@inner_block, l) %>
    </OauthComponent.fieldset>
    """
  end

  def form_component(%{type: "salesforce_oauth"} = assigns) do
    ~H"""
    <OauthComponent.fieldset
      :let={l}
      id={@id}
      form={@form}
      action={@action}
      schema={@schema}
      update_body={@update_body}
      sandbox_value={@sandbox_value}
      api_version={@api_version}
      scopes_changed={@scopes_changed}
    >
      <%= render_slot(@inner_block, l) %>
    </OauthComponent.fieldset>
    """
  end

  def form_component(%{type: "raw"} = assigns) do
    ~H"""
    <RawBodyComponent.fieldset :let={l} form={@form}>
      <%= render_slot(@inner_block, l) %>
    </RawBodyComponent.fieldset>
    """
  end

  def form_component(%{type: _schema} = assigns) do
    ~H"""
    <JsonSchemaBodyComponent.fieldset :let={l} form={@form}>
      <%= render_slot(@inner_block, l) %>
    </JsonSchemaBodyComponent.fieldset>
    """
  end

  attr :projects, :list, required: true
  attr :selected, :map, required: true
  attr :phx_target, :any, default: nil
  attr :form, :map, required: true

  def project_credentials(assigns) do
    ~H"""
    <div class="col-span-3">
      <%= Phoenix.HTML.Form.label(@form, :project_credentials, "Project Access",
        class: "block text-sm font-medium text-secondary-700"
      ) %>

      <div class="flex w-full items-center gap-2 pb-3 mt-1">
        <div class="grow">
          <LightningWeb.Components.Form.select_field
            form={:selected_project}
            name={:id}
            values={@projects}
            value={@selected}
            prompt=""
            phx-change="select_item"
            phx-target={@phx_target}
            id={"project_credentials_list_for_#{@form[:id].value}"}
          />
        </div>
        <div class="grow-0 items-right">
          <.button
            id={"add-new-project-button-to-credential-#{@form[:id].value}"}
            disabled={@selected == ""}
            phx-target={@phx_target}
            phx-click="add_new_project"
            phx-value-projectid={@selected}
          >
            Add
          </.button>
        </div>
      </div>

      <.inputs_for :let={project_credential} field={@form[:project_credentials]}>
        <%= if project_credential[:delete].value != true do %>
          <div class="flex w-full gap-2 items-center pb-2">
            <div class="grow">
              <%= project_name(@projects, project_credential[:project_id].value) %>
              <.old_error field={project_credential[:project_id]} />
            </div>
            <div class="grow-0 items-right">
              <.button
                id={"delete-project-credential-#{@form[:id].value}-button"}
                phx-target={@phx_target}
                phx-value-projectid={project_credential[:project_id].value}
                phx-click="delete_project"
              >
                Remove
              </.button>
            </div>
          </div>
        <% end %>
        <.input type="hidden" field={project_credential[:project_id]} />
        <.input
          type="hidden"
          field={project_credential[:delete]}
          value={to_string(project_credential[:delete].value)}
        />
      </.inputs_for>
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
        <%= Phoenix.HTML.Form.label(@form, :owner,
          class: "block text-sm font-medium text-secondary-700"
        ) %>
        <LightningWeb.Components.Form.select_field
          form={@form}
          name={:user_id}
          values={@users}
        />
        <.old_error field={@form[:user_id]} />
      </div>
    </fieldset>
    """
  end

  defp project_name(projects, id) do
    Enum.find_value(projects, fn {name, project_id} ->
      if project_id == id, do: name
    end)
  end
end
