defmodule LightningWeb.Components.DataTables do
  @moduledoc false
  use LightningWeb, :component

  alias Lightning.Accounts.User
  alias Lightning.Credentials.Credential
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects.ProjectUser

  attr :id, :string, required: true
  attr :credentials, :list, required: true
  attr :title, :string, required: true
  attr :display_table_title, :boolean, default: true
  attr :show_owner, :boolean, default: false

  slot :actions,
    doc: "the slot for showing user actions in the last table column"

  slot :empty_state,
    doc: "the slot for showing an empty state"

  def credentials_table(assigns) do
    ~H"""
    <div id={"#{@id}-table-container"}>
      <div :if={@display_table_title} class="pb-1 leading-loose">
        <h6 class="font-normal text-black">{@title}</h6>
      </div>
      <%= if Enum.empty?(@credentials) do %>
        {render_slot(@empty_state)}
      <% else %>
        <.table id={"#{@id}-table"}>
          <:header>
            <.tr>
              <.th>Name</.th>
              <.th>Type</.th>
              <.th :if={@show_owner}>
                Owner
              </.th>
              <.th>
                Projects with access
              </.th>
              <.th>External ID</.th>
              <.th>Environments</.th>
              <.th>
                <span class="sr-only">Actions</span>
              </.th>
            </.tr>
          </:header>
          <:body>
            <%= for credential <- @credentials do %>
              <.tr id={"#{@id}-#{credential.id}"}>
                <.td class="max-w-[15rem]">
                  <div class="flex items-center">
                    {credential.name}

                    <%= if missing_oauth_client?(credential) do %>
                      <span
                        id={"#{credential.id}-client-not-found-tooltip"}
                        phx-hook="Tooltip"
                        aria-label="OAuth client not found"
                        data-allow-html="true"
                      >
                        <.icon name="hero-exclamation-triangle" class="h-5 w-5 ml-2" />
                      </span>
                    <% end %>
                  </div>
                </.td>
                <.td class="wrap-break-word max-w-[10rem] border-">
                  {credential_type(credential)}
                </.td>
                <.td :if={@show_owner} class="wrap-break-word max-w-[15rem]">
                  <div class="flex-auto items-center">
                    {credential.user.email}
                  </div>
                </.td>
                <.td class="wrap-break-word max-w-[25rem]">
                  <%= for project_name <- credential.project_names do %>
                    <span class="inline-flex items-center rounded-md bg-primary-50 p-1 my-0.5 text-xs font-medium ring-1 ring-inset ring-gray-500/10">
                      {project_name}
                    </span>
                  <% end %>
                </.td>
                <.td class="wrap-break-word max-w-[12rem]">
                  <%= if credential.external_id do %>
                    <code
                      class="text-xs bg-gray-100 px-1 py-0.5 rounded truncate inline-block max-w-full"
                      title={credential.external_id}
                    >
                      {credential.external_id}
                    </code>
                  <% else %>
                    <span class="text-gray-400 text-sm">-</span>
                  <% end %>
                </.td>
                <.td class="text-left">
                  <span
                    id={"#{credential.id}-environments-tooltip"}
                    class="text-base cursor-default text-gray-700"
                    phx-hook="Tooltip"
                    aria-label={
                      Enum.join(credential.environment_names || ["main"], ", ")
                    }
                  >
                    {length(credential.environment_names || [1])}
                  </span>
                </.td>
                <.td>
                  <div class="flex justify-end items-center">
                    {render_slot(@actions, credential)}
                  </div>
                </.td>
              </.tr>
            <% end %>
          </:body>
        </.table>
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :keychain_credentials, :list, required: true
  attr :title, :string, required: true
  attr :display_table_title, :boolean, default: true
  attr :show_owner, :boolean, default: false

  slot :actions,
    doc: "the slot for showing user actions in the last table column"

  slot :empty_state,
    doc: "the slot for showing an empty state"

  def keychain_credentials_table(assigns) do
    ~H"""
    <div id={"#{@id}-table-container"}>
      <div :if={@display_table_title} class="pb-1 leading-loose">
        <h6 class="font-normal text-black">{@title}</h6>
      </div>
      <%= if Enum.empty?(@keychain_credentials) do %>
        {render_slot(@empty_state)}
      <% else %>
        <.table id={"#{@id}-table"}>
          <:header>
            <.tr>
              <.th>Name</.th>
              <.th>Path</.th>
              <.th>Default Credential</.th>
              <.th :if={@show_owner}>
                Owner
              </.th>
              <.th>
                <span class="sr-only">Actions</span>
              </.th>
            </.tr>
          </:header>
          <:body>
            <%= for keychain_credential <- @keychain_credentials do %>
              <.tr id={"#{@id}-#{keychain_credential.id}"}>
                <.td class="max-w-[15rem]">
                  {keychain_credential.name}
                </.td>
                <.td class="wrap-break-word max-w-[25rem]">
                  <code
                    class="text-xs bg-gray-100 px-1 py-0.5 rounded truncate inline-block max-w-full"
                    title={keychain_credential.path}
                  >
                    {keychain_credential.path}
                  </code>
                </.td>
                <.td class="wrap-break-word max-w-[15rem]">
                  <%= if keychain_credential.default_credential do %>
                    {keychain_credential.default_credential.name}
                  <% else %>
                    <span class="text-gray-400 text-sm">None</span>
                  <% end %>
                </.td>
                <.td :if={@show_owner} class="wrap-break-word max-w-[15rem]">
                  <div class="flex-auto items-center">
                    {keychain_credential.created_by.email}
                  </div>
                </.td>
                <.td>
                  <div class="flex justify-end items-center">
                    {render_slot(@actions, keychain_credential)}
                  </div>
                </.td>
              </.tr>
            <% end %>
          </:body>
        </.table>
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :clients, :list, required: true
  attr :title, :string, required: true
  attr :show_owner, :boolean, default: false

  slot :actions,
    doc: "the slot for showing user actions in the last table column"

  slot :empty_state,
    doc: "the slot for showing an empty state"

  def oauth_clients_table(assigns) do
    ~H"""
    <div id={"#{@id}-table-container"}>
      <div class="leading-loose pb-2">
        <h6 class="font-normal text-black">{@title}</h6>
      </div>
      <%= if Enum.empty?(@clients) do %>
        {render_slot(@empty_state)}
      <% else %>
        <.table id={"#{@id}-table"}>
          <:header>
            <.tr>
              <.th>Name</.th>
              <.th :if={@show_owner}>
                Owner
              </.th>
              <.th>
                Projects With Access
              </.th>
              <.th>Authorization URL</.th>
              <.th>
                <span class="sr-only">Actions</span>
              </.th>
            </.tr>
          </:header>
          <:body>
            <%= for client <- @clients do %>
              <.tr id={"#{@id}-#{client.id}"}>
                <.td class="wrap-break-word max-w-[15rem]">
                  {client.name}
                </.td>
                <.td :if={@show_owner} class="wrap-break-word max-w-[15rem]">
                  {if client.global, do: "GLOBAL", else: client.user.email}
                </.td>
                <.td class="wrap-break-word max-w-[20rem]">
                  <%= for project_name <- client.project_names do %>
                    <span class="inline-flex items-center rounded-md bg-primary-50 p-1 my-0.5 text-xs font-medium ring-1 ring-inset ring-gray-500/10">
                      {project_name}
                    </span>
                  <% end %>
                </.td>
                <.td class="wrap-break-word max-w-[18rem]">
                  {client.authorization_endpoint}
                </.td>
                <.td>
                  <div class="flex justify-end items-center">
                    {render_slot(@actions, client)}
                  </div>
                </.td>
              </.tr>
            <% end %>
          </:body>
        </.table>
      <% end %>
    </div>
    """
  end

  defp credential_type(%Credential{schema: "oauth", oauth_client: client}) do
    if client do
      String.downcase(client.name)
    else
      "oauth"
    end
  end

  defp credential_type(%Credential{schema: schema}) do
    schema
  end

  defp missing_oauth_client?(credential) do
    credential.schema == "oauth" &&
      (credential.oauth_token == nil ||
         credential.oauth_token.oauth_client_id == nil)
  end

  attr :id, :string, required: true
  attr :project_files, :list, required: true

  slot :actions,
    doc: "the slot for showing user actions in the last table column"

  slot :empty_state, doc: "the slot for showing an empty state"

  def history_exports_table(assigns) do
    ~H"""
    <div id={"#{@id}-table-container"}>
      <%= if Enum.empty?(@project_files) do %>
        {render_slot(@empty_state)}
      <% else %>
        <.table id={"#{@id}-table"}>
          <:header>
            <.tr>
              <.th>Export Date</.th>
              <.th>Filename</.th>
              <.th>Export Requested By</.th>
              <.th>Status</.th>
              <.th></.th>
            </.tr>
          </:header>
          <:body>
            <%= for file <- @project_files do %>
              <.tr>
                <.td><Common.datetime datetime={file.inserted_at} /></.td>
                <.td>
                  <%= if file.path do %>
                    {Path.basename(file.path)}
                  <% else %>
                    <em>Pending</em>
                  <% end %>
                </.td>
                <.td>
                  {file.created_by.first_name <> " " <> file.created_by.last_name}
                </.td>
                <.td>{format_export_status(file.status)}</.td>
                <.td class="flex justify-end py-0.5">
                  {render_slot(@actions, file)}
                </.td>
              </.tr>
            <% end %>
          </:body>
        </.table>
      <% end %>
    </div>
    """
  end

  defp format_export_status(status) do
    status
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  attr :id, :string, required: true
  attr :collections, :list, required: true
  attr :can_create_collection, :boolean, required: true

  slot :actions,
    doc: "the slot for showing user actions in the last table column"

  slot :empty_state, doc: "the slot for showing an empty state"

  def collections_table(assigns) do
    ~H"""
    <div id={"#{@id}-table-container"}>
      <%= if Enum.empty?(@collections) do %>
        {render_slot(@empty_state)}
      <% else %>
        <.table id={"#{@id}-table"}>
          <:header>
            <.tr>
              <.th>Name</.th>
              <.th>Used Storage (MB)</.th>
              <.th><span class="sr-only">Actions</span></.th>
            </.tr>
          </:header>
          <:body>
            <%= for collection <- @collections do %>
              <.tr id={"collection-row-#{collection.id}"}>
                <.td>{collection.name}</.td>
                <.td>{div(collection.byte_size_sum, 1_000_000)}</.td>
                <.td class="flex justify-end py-0.5">
                  {render_slot(@actions, collection)}
                </.td>
              </.tr>
            <% end %>
          </:body>
        </.table>
      <% end %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :project_users, :list, required: true
  attr :current_user, :map, required: true
  attr :can_remove_project_user, :boolean, required: true
  attr :can_receive_failure_alerts, :boolean, required: true

  slot :actions,
    doc: "the slot for showing user actions in the last table column"

  slot :empty_state, doc: "the slot for showing an empty state"

  def collaborators_table(assigns) do
    ~H"""
    <div id={"#{@id}-table-container"}>
      <%= if Enum.empty?(@project_users) do %>
        {render_slot(@empty_state)}
      <% else %>
        <.table id={"#{@id}-table"}>
          <:header>
            <.tr>
              <.th>Collaborator</.th>
              <.th>Role</.th>
              <.th>Failure Alert</.th>
              <.th>Digest</.th>
              <.th><span class="sr-only">Actions</span></.th>
            </.tr>
          </:header>
          <:body>
            <%= for project_user <- @project_users do %>
              <.tr id={"project_user-#{project_user.id}"}>
                <.td>
                  <.user project_user={project_user} />
                  <div :if={project_user.user.email == @current_user.email}>
                    <small class="text-gray-400">
                      <em>Well hello, you!</em>
                    </small>
                  </div>
                </.td>
                <.td>
                  <.role project_user={project_user} />
                </.td>
                <.td>
                  <.failure_alert
                    current_user={@current_user}
                    project_user={project_user}
                    can_receive_failure_alerts={@can_receive_failure_alerts}
                  />
                </.td>
                <.td>
                  <.digest current_user={@current_user} project_user={project_user} />
                </.td>
                <.td class="flex justify-end py-0.5">
                  {render_slot(@actions, project_user)}
                </.td>
              </.tr>
            <% end %>
          </:body>
        </.table>
      <% end %>
    </div>
    """
  end

  defp user(assigns) do
    ~H"""
    <div>
      {@project_user.user.first_name} {@project_user.user.last_name}
    </div>
    <span class="text-xs">{@project_user.user.email}</span>
    """
  end

  defp role(assigns) do
    ~H"""
    {@project_user.role |> Atom.to_string() |> String.capitalize()}
    """
  end

  defp failure_alert(assigns) do
    assigns =
      assigns
      |> assign(
        can_edit_failure_alert:
          can_edit_failure_alert(assigns.current_user, assigns.project_user)
      )

    ~H"""
    <%= cond do %>
      <% @can_receive_failure_alerts && @can_edit_failure_alert -> %>
        <.form
          :let={form}
          for={%{"failure_alert" => @project_user.failure_alert}}
          phx-change="set_failure_alert"
          id={"failure-alert-#{@project_user.id}"}
        >
          <.input
            type="hidden"
            field={form[:project_user_id]}
            value={@project_user.id}
          />
          <.input
            type="select"
            field={form[:failure_alert]}
            options={[Disabled: false, Enabled: true]}
          />
        </.form>
      <% @can_receive_failure_alerts -> %>
        <span id={"failure-alert-status-#{@project_user.id}"}>
          {if @project_user.failure_alert,
            do: "Enabled",
            else: "Disabled"}
        </span>
      <% true -> %>
        <span id={"failure-alert-status-#{@project_user.id}"}>Unavailable</span>
    <% end %>
    """
  end

  def digest(assigns) do
    assigns =
      assigns
      |> assign(
        can_edit_digest_alert:
          can_edit_digest_alert(assigns.current_user, assigns.project_user)
      )

    ~H"""
    <%= if @can_edit_digest_alert do %>
      <.form
        :let={form}
        for={%{"digest" => @project_user.digest}}
        phx-change="set_digest"
        id={"digest-#{@project_user.id}"}
      >
        <.input
          type="hidden"
          field={form[:project_user_id]}
          value={@project_user.id}
        />

        <.input
          type="select"
          field={form[:digest]}
          options={[
            Never: "never",
            Daily: "daily",
            Weekly: "weekly",
            Monthly: "monthly"
          ]}
        />
      </.form>
    <% else %>
      {@project_user.digest
      |> Atom.to_string()
      |> String.capitalize()}
    <% end %>
    """
  end

  defp can_edit_digest_alert(
         %User{} = current_user,
         %ProjectUser{} = project_user
       ),
       do:
         ProjectUsers
         |> Permissions.can?(:edit_digest_alerts, current_user, project_user)

  defp can_edit_failure_alert(
         %User{} = current_user,
         %ProjectUser{} = project_user
       ),
       do:
         ProjectUsers
         |> Permissions.can?(:edit_failure_alerts, current_user, project_user)
end
