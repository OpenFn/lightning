defmodule LightningWeb.Components.Credentials do
  @moduledoc false
  use LightningWeb, :component

  alias LightningWeb.CredentialLive.JsonSchemaBodyComponent
  alias LightningWeb.CredentialLive.OauthComponent
  alias LightningWeb.CredentialLive.RawBodyComponent

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
      <div class="flex-grow bg-gray-100 h-0.5 my-[16px]"></div>
      <div class="flex flex-row-reverse gap-4 mx-6">
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
      <div class="flex-grow bg-gray-100 h-0.5 my-[16px]"></div>
      <div class="flex flex-row-reverse gap-4 mx-6">
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

  attr :available_projects, :list, required: true
  attr :all_projects, :list, required: true
  attr :selected, :string, required: true
  attr :phx_target, :any, default: nil
  attr :form, :any, required: true

  def project_credentials(assigns) do
    ~H"""
    <div class="col-span-3">
      <div>
        <label
          for={"project_oauth_clients_list_for_#{@form[:id].value}"}
          class={["block text-sm font-semibold leading-6 text-slate-800"]}
        >
          Project
        </label>

        <div class="flex w-full items-center gap-2 pb-3 mt-1">
          <div class="grow">
            <select
              id={"project_oauth_clients_list_for_#{@form[:id].value}"}
              name={:project_id}
              class={[
                "block w-full rounded-lg border border-secondary-300 bg-white",
                "sm:text-sm shadow-sm",
                "focus:border-primary-300 focus:ring focus:ring-primary-200 focus:ring-opacity-50",
                "disabled:cursor-not-allowed "
              ]}
              phx-change="select_item"
              phx-target={@phx_target}
            >
              <option value="">
                Select a project to associate to this credential
              </option>
              <%= Phoenix.HTML.Form.options_for_select(
                @available_projects,
                @selected
              ) %>
            </select>
          </div>

          <div class="grow-0 items-right">
            <.button
              id={"add-new-project-button-to-#{@form[:id].value}"}
              disabled={
                @selected == "" or @selected == nil or @available_projects == []
              }
              phx-target={@phx_target}
              phx-value-project_id={@selected}
              phx-click="add_new_project"
            >
              Add
            </.button>
          </div>
        </div>

        <div class="overflow-auto max-h-32">
          <.inputs_for
            :let={project_oauth_client}
            field={@form[:project_credentials]}
          >
            <span class="inline-flex items-center gap-1 rounded-md bg-blue-100 px-4 py-2 mb-2 text-gray-600">
              <%= project_name(
                @all_projects,
                project_oauth_client[:project_id].value
              ) %>
              <button
                id={"delete-project-oauth-client-#{@form[:id].value}-button"}
                phx-target={@phx_target}
                phx-value-project_id={project_oauth_client[:project_id].value}
                phx-click="delete_project"
                type="button"
                class="group relative -mr-1 h-3.5 w-3.5 rounded-sm hover:bg-gray-500/20"
              >
                <span class="sr-only">Remove</span>
                <svg
                  viewBox="0 0 14 14"
                  class="h-3.5 w-3.5 stroke-gray-700/50 group-hover:stroke-gray-700/75"
                >
                  <path d="M4 4l6 6m0-6l-6 6" />
                </svg>
                <span class="absolute -inset-1"></span>
              </button>
            </span>

            <.input type="hidden" field={project_oauth_client[:project_id]} />
          </.inputs_for>
        </div>
      </div>
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

  attr :id, :string, required: true
  attr :options, :list, required: true
  slot :inner_block, required: true

  def options_menu_button(assigns) do
    ~H"""
    <div id={@id} class="inline-flex rounded-md shadow-sm">
      <.button
        type="button"
        phx-click={show_dropdown("menu")}
        class="relative inline-flex items-center"
        aria-expanded="true"
        aria-haspopup="true"
      >
        <%= render_slot(@inner_block) %>
        <svg
          class="h-5 w-5"
          viewBox="0 0 20 20"
          fill="currentColor"
          aria-hidden="true"
        >
          <path
            fill-rule="evenodd"
            d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
            clip-rule="evenodd"
          />
        </svg>
      </.button>
      <div class="relative -ml-px block">
        <div
          class="hidden absolute right-0 z-10 -mr-1 mt-12 w-56 origin-top-right rounded-md bg-white shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none"
          role="menu"
          aria-orientation="vertical"
          aria-labelledby="option-menu-button"
          tabindex="-1"
          phx-click-away={hide_dropdown("menu")}
          id="menu"
        >
          <div class="py-1" role="none">
            <a
              :for={%{name: name, id: id, target: target} <- @options}
              href="#"
              class="text-gray-700 block px-4 py-2 text-sm hover:bg-gray-100"
              role="menuitem"
              tabindex="-1"
              id={id}
              phx-click={show_modal(target)}
            >
              <%= name %>
            </a>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :credentials, :list, required: true
  attr :title, :string, required: true

  slot :actions,
    doc: "the slot for showing user actions in the last table column"

  slot :empty_state,
    doc: "the slot for showing an empty state"

  def credentials_table(assigns) do
    ~H"""
    <div id={"#{@id}-table-container"}>
      <div class="py-4 leading-loose">
        <h6 class="font-normal text-black"><%= @title %></h6>
      </div>
      <%= if Enum.empty?(@credentials) do %>
        <%= render_slot(@empty_state) %>
      <% else %>
        <.table id={"#{@id}-table"}>
          <.tr>
            <.th>Name</.th>
            <.th>Projects with access</.th>
            <.th>Type</.th>
            <.th>Production</.th>
            <.th>Actions</.th>
          </.tr>

          <.tr
            :for={credential <- @credentials}
            id={"#{@id}-#{credential.id}"}
            class="hover:bg-gray-100 transition-colors duration-200"
          >
            <.td class="break-words max-w-[15rem]">
              <%= credential.name %>
            </.td>
            <.td class="break-words max-w-[25rem]">
              <%= for project_name <- credential.project_names do %>
                <span class="inline-flex items-center rounded-md bg-transparent px-1.5 py-0.5 my-0.5 text-xs font-medium ring-1 ring-inset ring-gray-500/10">
                  <%= project_name %>
                </span>
              <% end %>
            </.td>
            <.td class="break-words max-w-[10rem] border-">
              <%= credential.schema %>
            </.td>
            <.td class="break-words max-w-[5rem]">
              <%= if credential.production do %>
                <div class="flex">
                  <Heroicons.exclamation_triangle class="w-5 h-5 text-secondary-500" />
                  &nbsp;Production
                </div>
              <% end %>
            </.td>
            <.td>
              <%= render_slot(@actions, credential) %>
            </.td>
          </.tr>
        </.table>
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :clients, :list, required: true
  attr :title, :string, required: true

  slot :actions,
    doc: "the slot for showing user actions in the last table column"

  slot :empty_state,
    doc: "the slot for showing an empty state"

  def oauth_clients_table(assigns) do
    ~H"""
    <div id={"#{@id}-table-container"}>
      <div class="py-4 leading-loose">
        <h6 class="font-normal text-black"><%= @title %></h6>
      </div>
      <%= if Enum.empty?(@clients) do %>
        <%= render_slot(@empty_state) %>
      <% else %>
        <.table id={"#{@id}-table"}>
          <.tr>
            <.th>Name</.th>
            <.th>Projects With Access</.th>
            <.th>Authorization URL</.th>
            <.th>Actions</.th>
          </.tr>

          <.tr
            :for={client <- @clients}
            id={"#{@id}-#{client.id}"}
            class="hover:bg-gray-100 transition-colors duration-200"
          >
            <.td class="break-words max-w-[15rem]"><%= client.name %></.td>
            <.td class="break-words max-w-[20rem]">
              <%= for project_name <- client.project_names do %>
                <span class="inline-flex items-center rounded-md bg-transparent px-1.5 py-0.5 my-0.5 text-xs font-medium ring-1 ring-inset ring-gray-500/10">
                  <%= project_name %>
                </span>
              <% end %>
            </.td>
            <.td class="break-words max-w-[20rem]">
              <%= client.authorization_endpoint %>
            </.td>
            <.td>
              <%= render_slot(@actions, client) %>
            </.td>
          </.tr>
        </.table>
      <% end %>
    </div>
    """
  end
end
