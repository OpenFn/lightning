defmodule LightningWeb.CredentialLive.GenericOauthComponent do
  use LightningWeb, :live_component

  import Ecto.Changeset, only: [fetch_field!: 2, put_assoc: 3]
  import LightningWeb.OauthCredentialHelper

  alias Lightning.Credentials
  alias Lightning.OauthClients
  alias LightningWeb.Components.NewInputs
  alias Phoenix.LiveView.JS
  alias Tesla

  @impl true
  def mount(socket) do
    subscribe(socket.id)

    {:ok,
     socket
     |> assign_new(:scopes, fn -> ["offline_access"] end)
     |> assign_new(:selected_client, fn -> nil end)
     |> assign_new(:selected_project, fn -> nil end)
     |> assign_new(:authorize_url, fn -> nil end)
     |> assign_new(:userinfo, fn -> nil end)}
  end

  @impl true
  def update(
        %{
          id: id,
          action: action,
          oauth_clients: oauth_clients,
          changeset: changeset,
          credential: credential,
          projects: projects,
          users: users,
          allow_credential_transfer: allow_credential_transfer,
          return_to: return_to
        } = _assigns,
        socket
      ) do
    updated_socket =
      if action === :edit do
        selected_client =
          OauthClients.get_client!(credential.oauth_client_id)

        scopes = Map.get(credential.body, "scope", "") |> String.split(" ")

        if !still_fresh(credential.body) do
          start_async(socket, :token, fn ->
            refresh_token(
              selected_client.client_id,
              selected_client.client_secret,
              credential.body["refresh_token"],
              selected_client.token_endpoint
            )
          end)
        else
          if selected_client.userinfo_endpoint do
            start_async(socket, :userinfo, fn ->
              fetch_userinfo(
                credential.body["access_token"],
                selected_client.userinfo_endpoint
              )
            end)
          else
            socket
          end
        end
        |> assign(:selected_client, selected_client)
        |> assign(:scopes, scopes)
      else
        socket
      end

    {:ok,
     updated_socket
     |> assign(
       id: id,
       action: action,
       oauth_clients: oauth_clients,
       changeset: changeset,
       credential: credential,
       projects: projects,
       users: users,
       allow_credential_transfer: allow_credential_transfer,
       return_to: return_to
     )}
  end

  def update(%{code: code} = _assigns, socket) do
    if !Map.get(socket.assigns, :code, false) do
      client = socket.assigns.selected_client

      {:ok,
       socket
       |> assign(code: code)
       |> start_async(:token, fn ->
         fetch_token(client, code)
       end)}
    else
      {:ok, socket}
    end
  end

  defp fetch_token(client, code) do
    %{
      client_id: client_id,
      client_secret: client_secret,
      token_endpoint: token_endpoint
    } = client

    # headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    # URI.encode_query(
    body =
      %{
        client_id: client_id,
        client_secret: client_secret,
        code: code,
        grant_type: "authorization_code",
        redirect_uri: LightningWeb.RouteHelpers.oidc_callback_url()
      }

    case Tesla.client([Tesla.Middleware.FormUrlencoded])
         |> Tesla.post(token_endpoint, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        Jason.decode(response_body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_userinfo(token, userinfo_endpoint) do
    headers = [
      {"Authorization", "Bearer #{token}"}
    ]

    case Tesla.get(userinfo_endpoint, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: user_info}} ->
        Jason.decode(user_info)

      {:ok, %Tesla.Env{status: status, body: body}} when status in 400..599 ->
        {:error, "Failed to fetch user info: #{body}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  def refresh_token(client_id, client_secret, refresh_token, token_endpoint) do
    body =
      %{
        client_id: client_id,
        client_secret: client_secret,
        refresh_token: refresh_token,
        grant_type: "refresh_token"
      }

    case Tesla.client([Tesla.Middleware.FormUrlencoded])
         |> Tesla.post(token_endpoint, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        Jason.decode(response_body)

      {:ok, %Tesla.Env{status: _status, body: response_body}} ->
        {:error, "Failed to refresh token: #{response_body}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def handle_async(:token, {:ok, {:ok, token}}, socket) do
    params = Map.put(socket.assigns.changeset.params, "body", token)
    changeset = Credentials.change_credential(socket.assigns.credential, params)

    assigns = Map.delete(socket.assigns, :code)
    socket = Map.update!(socket, :assigns, fn _existing -> assigns end)

    updated_socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(authorize_url: nil)

    if socket.assigns.selected_client.userinfo_endpoint do
      {:noreply,
       updated_socket
       |> start_async(:userinfo, fn ->
         fetch_userinfo(
           token["access_token"],
           socket.assigns.selected_client.userinfo_endpoint
         )
       end)}
    else
      {:noreply, updated_socket}
    end
  end

  def handle_async(:userinfo, {:ok, {:ok, userinfo}}, socket) do
    {:noreply,
     socket |> assign(authorize_url: nil) |> assign(userinfo: userinfo)}
  end

  @impl true
  def handle_event(
        "validate",
        %{"credential" => credential_params} = _params,
        socket
      ) do
    changeset =
      Credentials.change_credential(
        socket.assigns.credential,
        Map.put(credential_params, "schema", "generic_oauth")
      )
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(changeset: changeset) |> hande_client_change()}
  end

  def handle_event(
        "save",
        %{"credential" => credential_params} = _params,
        socket
      ) do
    save_credential(socket, socket.assigns.action, credential_params)
  end

  def handle_event("add_scope", params, socket) do
    new_scopes = scopes_from_params(params)

    if new_scopes != [] do
      new_scopes = Enum.reverse(new_scopes ++ socket.assigns.scopes)

      # Always update scopes and handle state regardless of client presence

      updated_socket =
        socket
        |> assign(:scopes, new_scopes)
        |> push_event("clear_input", %{})

      # Only generate authorize_url if client is not nil
      updated_socket =
        if socket.assigns.selected_client != nil do
          state = build_state(socket.id, __MODULE__, socket.assigns.id)
          stringified_scopes = Enum.join(new_scopes, " ")

          authorize_url =
            generate_authorize_url(
              socket.assigns.selected_client.authorization_endpoint,
              socket.assigns.selected_client.client_id,
              state: state,
              scope: stringified_scopes
            )

          assign(updated_socket, :authorize_url, authorize_url)
        else
          updated_socket
        end

      {:noreply, updated_socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_scope", %{"scope" => scope_to_remove}, socket) do
    new_scopes =
      Enum.reject(socket.assigns.scopes, fn scope ->
        scope == scope_to_remove
      end)

    updated_socket =
      cond do
        socket.assigns.action === :edit and
            not scopes_changed?(socket, new_scopes) ->
          assign(socket, :authorize_url, nil)

        socket.assigns.selected_client != nil ->
          state = build_state(socket.id, __MODULE__, socket.assigns.id)
          stringified_scopes = Enum.join(new_scopes, " ")

          authorize_url =
            generate_authorize_url(
              socket.assigns.selected_client.authorization_endpoint,
              socket.assigns.selected_client.client_id,
              state: state,
              scope: stringified_scopes
            )

          assign(socket, :authorize_url, authorize_url)

        true ->
          socket
      end

    {:noreply, assign(updated_socket, scopes: new_scopes)}
  end

  def handle_event(
        "select_project",
        %{"project" => %{"id" => project_id}} = _params,
        socket
      ) do
    {:noreply, assign(socket, selected_project: project_id)}
  end

  def handle_event(
        "select_item",
        %{"selected_project" => %{"id" => project_id}},
        socket
      ) do
    {:noreply, socket |> assign(selected_project: project_id)}
  end

  def handle_event("add_new_project", %{"projectid" => project_id}, socket) do
    project_credentials =
      fetch_field!(socket.assigns.changeset, :project_credentials)

    project_credentials =
      if Enum.find(project_credentials, fn pu -> pu.project_id == project_id end) do
        Enum.map(project_credentials, fn pu ->
          if pu.project_id == project_id do
            Ecto.Changeset.change(pu, %{delete: false})
          else
            pu
          end
        end)
      else
        Enum.concat(project_credentials, [
          %Lightning.Projects.ProjectCredential{project_id: project_id}
        ])
      end

    changeset =
      socket.assigns.changeset
      |> put_assoc(:project_credentials, project_credentials)
      |> Map.put(:action, :validate)

    available_projects =
      filter_available_projects(changeset, socket.assigns.all_projects)

    {:noreply,
     socket
     |> assign(
       changeset: changeset,
       available_projects: available_projects,
       selected_project: nil
     )}
  end

  def handle_event("delete_project", %{"projectid" => project_id}, socket) do
    project_credentials =
      fetch_field!(socket.assigns.changeset, :project_credentials)

    project_credentials =
      Enum.reduce(project_credentials, [], fn pc, project_credentials ->
        if pc.project_id == project_id do
          if is_nil(pc.id) do
            project_credentials
          else
            project_credentials ++ [Ecto.Changeset.change(pc, %{delete: true})]
          end
        else
          project_credentials ++ [pc]
        end
      end)

    changeset =
      socket.assigns.changeset
      |> put_assoc(:project_credentials, project_credentials)
      |> Map.put(:action, :validate)

    available_projects =
      filter_available_projects(changeset, socket.assigns.all_projects)

    {:noreply,
     socket
     |> assign(changeset: changeset, available_projects: available_projects)}
  end

  def still_fresh(token_body, threshold \\ 5, time_unit \\ :minute)

  def still_fresh(%{"expires_at" => nil} = _token_body, _threshold, _time_unit),
    do: false

  def still_fresh(%{"expires_in" => nil} = _token_body, _threshold, _time_unit),
    do: false

  def still_fresh(%{"expires_at" => expires_at}, threshold, time_unit) do
    current_time = DateTime.utc_now()
    expiration_time = DateTime.from_unix!(expires_at)
    time_remaining = DateTime.diff(expiration_time, current_time, time_unit)
    time_remaining >= threshold
  end

  def still_fresh(%{"expires_in" => expires_at}, threshold, time_unit) do
    current_time = DateTime.utc_now()
    expiration_time = DateTime.from_unix!(expires_at)
    time_remaining = DateTime.diff(expiration_time, current_time, time_unit)
    time_remaining >= threshold
  end

  defp save_credential(socket, :new, params) do
    user_id = Ecto.Changeset.fetch_field!(socket.assigns.changeset, :user_id)
    body = Ecto.Changeset.fetch_field!(socket.assigns.changeset, :body)

    body = Map.put(body, "api_version", Map.get(params, "api_version", nil))

    params
    |> Map.put("user_id", user_id)
    |> Map.put("schema", "generic_oauth")
    |> Map.put("body", body)
    |> Credentials.create_credential()
    |> case do
      {:ok, _credential} ->
        {:noreply,
         socket
         |> put_flash(:info, "Credential created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_credential(socket, :edit, params) do
    case Credentials.update_credential(socket.assigns.credential, params) do
      {:ok, _credential} ->
        {:noreply,
         socket
         |> put_flash(:info, "Credential updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp hande_client_change(socket) do
    client =
      Ecto.Changeset.get_change(socket.assigns.changeset, :oauth_client_id)
      |> get_oauth_client()

    if client do
      state = build_state(socket.id, __MODULE__, socket.assigns.id)

      authorize_url =
        generate_authorize_url(
          client.authorization_endpoint,
          client.client_id,
          state: state
        )

      assign(socket, authorize_url: authorize_url, selected_client: client)
    else
      socket
    end
  end

  defp scopes_changed?(socket, new_scopes) do
    existing_scopes =
      socket.assigns.credential.body
      |> Map.get("scope", "")
      |> String.split(" ")

    Enum.sort(new_scopes) != Enum.sort(existing_scopes)
  end

  defp filter_available_projects(changeset, all_projects) do
    existing_ids =
      fetch_field!(changeset, :project_credentials)
      |> Enum.reject(fn pu -> pu.delete end)
      |> Enum.map(fn pu -> pu.credential_id end)

    all_projects
    |> Enum.reject(fn {_, credential_id} -> credential_id in existing_ids end)
  end

  defp generate_authorize_url(base_url, client_id, params) do
    default_params = [
      access_type: "offline",
      client_id: client_id,
      prompt: "consent",
      redirect_uri: LightningWeb.RouteHelpers.oidc_callback_url(),
      response_type: "code",
      scope: "",
      state: ""
    ]

    # Merge params into default_params, with params taking precedence in case of conflicts
    merged_params = Keyword.merge(default_params, params)

    # Encode the parameters into a query string
    encoded_params = URI.encode_query(merged_params)
    "#{base_url}?#{encoded_params}"
  end

  defp get_oauth_client(nil), do: nil

  defp get_oauth_client(client_id), do: OauthClients.get_client!(client_id)

  defp scopes_from_params(%{"key" => _any_other_key} = _params), do: []

  defp scopes_from_params(%{"value" => value} = _params),
    do: value |> String.trim_trailing(",") |> String.split(",")

  defp scopes_from_params(_any_other_params), do: []

  # TODO: When there is no client, do not render the generic oauth credential type

  attr :form, :map, required: true
  attr :clients, :list, required: true
  slot :inner_block

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        :let={f}
        for={@changeset}
        id={"credential-form-#{@credential.id || "new"}"}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="bg-white px-4">
          <div class="space-y-4">
            <div>
              <NewInputs.input
                type="text"
                field={f[:name]}
                label="Name"
                required="true"
              />
            </div>
            <div>
              <LightningWeb.Components.Form.check_box form={f} field={:production} />
            </div>
          </div>
          <div class="space-y-4 mt-5">
            <NewInputs.input
              type="select"
              field={f[:oauth_client_id]}
              label="Select a client"
              prompt=""
              required="true"
              options={Enum.map(@oauth_clients, &{&1.name, &1.id})}
            />
          </div>
          <div class="text-xs italic py-2">
            <span class="font-medium underline">Authorization URL</span>:
            <span :if={@selected_client}>
              <%= @selected_client.authorization_endpoint %>
            </span>
          </div>

          <.scopes_input id="new" scopes={@scopes} phx_target={@myself} />

          <div class="space-y-4 mt-5">
            <NewInputs.input type="text" field={f[:api_version]} label="API Version" />
          </div>

          <div class="space-y-4">
            <div class="hidden sm:block" aria-hidden="true">
              <div class="mb-6"></div>
            </div>
            <fieldset>
              <legend class="contents text-base font-medium text-gray-900">
                Project Access
              </legend>
              <p class="text-sm text-gray-500">
                Control which projects have access to this credentials
              </p>
              <div class="mt-4">
                <.project_credentials
                  form={f}
                  projects={@projects}
                  selected={@selected_project}
                  phx_target={@myself}
                />
              </div>
            </fieldset>
          </div>
          <div
            :if={@action == :edit and @allow_credential_transfer}
            class="space-y-4"
          >
            <.credential_transfer form={f} users={@users} />
          </div>
        </div>
        <.modal_footer class="mt-6 mx-4">
          <div class="flex justify-between items-center">
            <div class="flex-1 w-1/2">
              <div :if={@userinfo} class="flex items-center">
                <img
                  src={@userinfo["picture"]}
                  class="h-14 w-14 rounded-full"
                  alt="User profile picture"
                />
                <div class="ml-4 flex flex-col justify-center">
                  <div class="text-base font-semibold leading-6 text-gray-900">
                    <%= @userinfo["name"] %>
                  </div>
                  <div class="text-sm text-gray-500">
                    <a href="#"><%= @userinfo["email"] %></a>
                  </div>
                </div>
              </div>
            </div>
            <div class="flex-1 w-1/2">
              <div class="sm:flex sm:flex-row-reverse">
                <.link
                  :if={@authorize_url}
                  href={@authorize_url}
                  id="authorize-button"
                  target="_blank"
                  class="inline-flex justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3"
                >
                  Authorize
                </.link>
                <button
                  :if={!@authorize_url}
                  type="submit"
                  disabled={!@changeset.valid?}
                  class="inline-flex justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3"
                >
                  Save
                </button>
                <button
                  type="button"
                  phx-click={JS.navigate(@return_to)}
                  class="inline-flex justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </.modal_footer>
      </.form>
    </div>
    """
  end

  defp project_name(projects, id) do
    Enum.find_value(projects, fn {name, project_id} ->
      if project_id == id, do: name
    end)
  end

  attr :id, :string, required: true
  attr :scopes, :list, required: true
  attr :phx_target, :any, required: true

  defp scopes_input(assigns) do
    ~H"""
    <div id={"generic-oauth-scopes-#{@id}"} class="space-y-2 mt-5">
      <NewInputs.label>Scopes</NewInputs.label>
      <span>Separate multiple scopes with a comma</span>
      <div class="flex flex-wrap items-center border border-gray-300 rounded-lg px-2">
        <div class="flex flex-wrap gap-2">
          <span
            :for={scope <- @scopes}
            class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10"
          >
            <%= scope %>
            <button
              type="button"
              phx-click="remove_scope"
              phx-value-scope={scope}
              phx-target={@phx_target}
              class="group relative -mr-1 h-3.5 w-3.5 rounded-sm hover:bg-gray-500/20"
            >
              <span class="sr-only">Remove</span>
              <svg
                viewBox="0 0 14 14"
                class="h-3.5 w-3.5 stroke-gray-600/50 group-hover:stroke-gray-600/75"
              >
                <path d="M4 4l6 6m0-6l-6 6" />
              </svg>
              <span class="absolute -inset-1"></span>
            </button>
          </span>
        </div>
        <input
          id={"scopes-input-#{@id}"}
          form={:scopes}
          type="text"
          class="flex-1 border-none focus:ring-0"
          name="scope"
          phx-window-keyup="add_scope"
          phx-target={@phx_target}
          phx-hook="ClearInput"
        />
      </div>
    </div>
    """
  end

  attr :projects, :list, required: true
  attr :selected, :map, required: true
  attr :phx_target, :any, default: nil
  attr :form, :map, required: true

  defp project_credentials(assigns) do
    ~H"""
    <div class="col-span-3">
      <%= Phoenix.HTML.Form.label(@form, :project_credentials, "Project Access",
        class: "block text-sm font-medium text-secondary-700"
      ) %>

      <div class="flex w-full items-center gap-2 pb-3 mt-1">
        <div class="grow">
          <LightningWeb.Components.Form.select_field
            form={:project}
            name={:id}
            values={@projects}
            value={@selected}
            prompt=""
            phx-change="select_project"
            phx-target={@phx_target}
            id={"project_credentials_list_for_#{@form[:id].value}"}
          />
        </div>
        <div class="grow-0 items-right">
          <.button
            id={"add-new-project-button-to-#{@form[:id].value}"}
            disabled={@selected == ""}
            phx-target={@phx_target}
            phx-value-projectid={@selected}
            phx-click="add_new_project"
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

  defp credential_transfer(assigns) do
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
end
