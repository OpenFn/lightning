defmodule LightningWeb.CredentialLive.GenericOauthComponent do
  use LightningWeb, :live_component

  import Ecto.Changeset, only: [fetch_field!: 2, put_assoc: 3]
  import LightningWeb.OauthCredentialHelper

  alias Lightning.Credentials
  alias LightningWeb.Components.NewInputs
  alias Phoenix.LiveView.JS
  alias Tesla

  @oauth_states %{
    success: [:userinfo_received, :token_received],
    failure: [:token_failed, :userinfo_failed, :refresh_failed]
  }

  @impl true
  def mount(socket) do
    subscribe(socket.id)

    {:ok,
     socket
     |> assign_new(:selected_client, fn -> nil end)
     |> assign_new(:selected_project, fn -> nil end)
     |> assign_new(:authorize_url, fn -> nil end)
     |> assign_new(:oauth_progress, fn -> :not_started end)
     |> assign_new(:scopes_changed, fn -> false end)
     |> assign_new(:userinfo, fn -> nil end)}
  end

  @impl true
  def update(%{selected_client: nil, action: action} = assigns, socket) do
    selected_scopes = assigns.credential.body["scope"] |> String.split(",")
    api_version = assigns.credential.body["api_version"]

    {:ok,
     socket
     |> assign(
       id: assigns.id,
       action: action,
       selected_client: assigns.selected_client,
       changeset: assigns.changeset,
       credential: assigns.credential,
       projects: assigns.projects,
       users: assigns.users,
       selected_scopes: selected_scopes,
       mandatory_scopes: [],
       optional_scopes: [],
       scopes: selected_scopes,
       api_version: api_version,
       allow_credential_transfer: assigns.allow_credential_transfer,
       return_to: assigns.return_to
     )}
  end

  def update(
        %{selected_client: selected_client, action: :edit} = assigns,
        socket
      ) do
    assigns.credential.body
    |> IO.inspect(label: "Save Credential Params")

    selected_scopes = assigns.credential.body["scope"] |> String.split(" ")

    mandatory_scopes =
      selected_client.mandatory_scopes
      |> to_string
      |> String.split(",")
      |> Enum.reject(fn value -> value === "" end)

    optional_scopes =
      selected_client.optional_scopes
      |> to_string
      |> String.split(",")
      |> Enum.reject(fn value -> value === "" end)

    scopes = Enum.uniq(mandatory_scopes ++ optional_scopes ++ selected_scopes)

    state = build_state(socket.id, __MODULE__, assigns.id)
    stringified_scopes = Enum.join(selected_scopes, " ")

    authorize_url =
      generate_authorize_url(
        selected_client.authorization_endpoint,
        selected_client.client_id,
        state: state,
        scope: stringified_scopes
      )

    socket =
      if !still_fresh(assigns.credential.body) do
        start_async(socket, :token, fn ->
          refresh_token(
            selected_client.client_id,
            selected_client.client_secret,
            assigns.credential.body["refresh_token"],
            selected_client.token_endpoint
          )
        end)
      else
        if selected_client.userinfo_endpoint do
          start_async(socket, :userinfo, fn ->
            fetch_userinfo(
              assigns.credential.body["access_token"],
              selected_client.userinfo_endpoint
            )
          end)
        end
      end

    api_version = assigns.credential.body["api_version"]

    changeset =
      Ecto.Changeset.put_change(
        assigns.changeset,
        :body,
        assigns.credential.body
      )
      |> Map.put(
        :action,
        :validate
      )

    {:ok,
     socket
     |> assign(
       id: assigns.id,
       action: assigns.action,
       selected_client: selected_client,
       changeset: changeset,
       credential: assigns.credential,
       projects: assigns.projects,
       users: assigns.users,
       mandatory_scopes: mandatory_scopes,
       optional_scopes: optional_scopes,
       selected_scopes: selected_scopes,
       scopes: scopes,
       api_version: api_version,
       authorize_url: authorize_url,
       allow_credential_transfer: assigns.allow_credential_transfer,
       return_to: assigns.return_to
     )}
  end

  def update(
        %{action: :new, selected_client: selected_client} = assigns,
        socket
      ) do
    mandatory_scopes =
      selected_client.mandatory_scopes
      |> to_string
      |> String.split(",")
      |> Enum.reject(fn value -> value === "" end)

    optional_scopes =
      selected_client.optional_scopes
      |> to_string
      |> String.split(",")
      |> Enum.reject(fn value -> value === "" end)

    state = build_state(socket.id, __MODULE__, assigns.id)
    stringified_scopes = Enum.join(mandatory_scopes, " ")

    authorize_url =
      generate_authorize_url(
        selected_client.authorization_endpoint,
        selected_client.client_id,
        state: state,
        scope: stringified_scopes
      )

    {:ok,
     socket
     |> assign(
       id: assigns.id,
       action: assigns.action,
       selected_client: assigns.selected_client,
       changeset: assigns.changeset,
       credential: assigns.credential,
       projects: assigns.projects,
       users: assigns.users,
       api_version: nil,
       mandatory_scopes: mandatory_scopes,
       optional_scopes: optional_scopes,
       selected_scopes: mandatory_scopes,
       scopes: mandatory_scopes ++ optional_scopes,
       authorize_url: authorize_url,
       allow_credential_transfer: assigns.allow_credential_transfer,
       return_to: assigns.return_to
     )}
  end

  def update(%{code: code} = _assigns, socket) do
    if !Map.get(socket.assigns, :code, false) do
      client = socket.assigns.selected_client

      {:ok,
       socket
       |> assign(code: code)
       |> assign(:oauth_progress, :code_received)
       |> assign(:scopes_changed, false)
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
    token =
      Map.put_new(
        token,
        "refresh_token",
        socket.assigns.credential.body["refresh_token"]
      )

    params = Map.put(socket.assigns.changeset.params, "body", token)
    changeset = Credentials.change_credential(socket.assigns.credential, params)
    credential = Ecto.Changeset.apply_changes(changeset)

    updated_socket =
      socket
      |> assign(:oauth_progress, :token_received)
      |> assign(:changeset, changeset)
      |> assign(:credential, credential)

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
     socket
     |> assign(userinfo: userinfo)
     |> assign(:oauth_progress, :userinfo_received)}
  end

  @impl true

  def handle_event(
        "validate",
        %{
          "_target" => ["credential", "api_version"],
          "credential" => %{"api_version" => api_version}
        },
        socket
      ) do
    {:noreply, assign(socket, :api_version, api_version)}
  end

  def handle_event(
        "validate",
        %{"credential" => credential_params} = _params,
        socket
      ) do
    changeset =
      Credentials.change_credential(
        socket.assigns.credential,
        Map.put(credential_params, "schema", "oauth")
      )
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(changeset: changeset)}
  end

  @impl true
  def handle_event("authorize_click", _, socket) do
    {:noreply, socket |> assign(oauth_progress: :started)}
  end

  def handle_event("check_scope", %{"_target" => [scope]}, socket) do
    selected_scopes =
      if Enum.member?(socket.assigns.selected_scopes, scope) do
        Enum.reject(socket.assigns.selected_scopes, fn value ->
          value == scope
        end)
      else
        [scope | socket.assigns.selected_scopes]
      end

    state = build_state(socket.id, __MODULE__, socket.assigns.id)
    stringified_scopes = Enum.join(selected_scopes, " ")

    authorize_url =
      generate_authorize_url(
        socket.assigns.selected_client.authorization_endpoint,
        socket.assigns.selected_client.client_id,
        state: state,
        scope: stringified_scopes
      )

    saved_scopes = get_scopes(socket.assigns.credential)
    diff_scopes = Enum.sort(selected_scopes) == Enum.sort(saved_scopes)

    {:noreply,
     socket
     |> assign(scopes_changed: !diff_scopes)
     |> assign(selected_scopes: selected_scopes)
     |> assign(:authorize_url, authorize_url)}
  end

  def handle_event(
        "save",
        %{"credential" => credential_params} = _params,
        socket
      ) do
    save_credential(socket, socket.assigns.action, credential_params)
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

  defp get_scopes(%{body: %{"scope" => scope}}), do: String.split(scope)
  defp get_scopes(_), do: []

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

    IO.inspect(body, label: "ON CREATE")

    body = Map.put(body, "api_version", socket.assigns.api_version)

    params
    |> Map.put("user_id", user_id)
    |> Map.put("schema", "oauth")
    |> Map.put("body", body)
    |> Map.put("oauth_client_id", socket.assigns.selected_client.id)
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
    body =
      Ecto.Changeset.fetch_field!(socket.assigns.changeset, :body)
      |> Map.put("api_version", socket.assigns.api_version)

    IO.inspect(body, label: "ON UPDATE")

    params =
      Map.put(params, "body", body)
      |> Map.put("oauth_client_id", socket.assigns.selected_client.id)

    IO.inspect(params, label: "Save Credential Params")

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

  # defp scopes_changed?(socket, new_scopes) do
  #   existing_scopes =
  #     socket.assigns.credential.body
  #     |> Map.get("scope", "")
  #     |> String.split(" ")

  #   Enum.sort(new_scopes) != Enum.sort(existing_scopes)
  # end

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

  attr :form, :map, required: true
  attr :clients, :list, required: true
  slot :inner_block

  @impl true
  def render(assigns) do
    display_loader =
      display_loader?(assigns.oauth_progress)

    display_reauthorize_banner = display_reauthorize_banner?(assigns)

    display_authorize_button =
      display_authorize_button?(assigns, display_reauthorize_banner)

    display_userinfo =
      display_userinfo?(assigns.oauth_progress, display_reauthorize_banner)

    display_error =
      display_error?(assigns.oauth_progress, display_reauthorize_banner)

    assigns =
      assigns
      |> assign(:display_loader, display_loader)
      |> assign(:display_reauthorize_banner, display_reauthorize_banner)
      |> assign(:display_authorize_button, display_authorize_button)
      |> assign(:display_userinfo, display_userinfo)
      |> assign(:display_error, display_error)

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

          <.scopes_picklist
            id={"scope_selection_#{@credential.id || "new"}"}
            target={@myself}
            on_change="check_scope"
            scopes={@scopes}
            selected_scopes={@selected_scopes}
            mandatory_scopes={@mandatory_scopes}
            doc_url={@selected_client.scopes_doc_url}
            provider={(@selected_client && @selected_client.name) || ""}
          />

          <div class="space-y-4 mt-5">
            <NewInputs.input
              type="text"
              field={f[:api_version]}
              value={@api_version || nil}
              label="API Version"
            />
          </div>

          <div class="space-y-4 my-10">
            <.reauthorize_banner
              :if={@display_reauthorize_banner}
              authorize_url={@authorize_url}
              myself={@myself}
            />
            <.text_ping_loader :if={@display_loader}>
              <%= case @oauth_progress do %>
                <% :started  -> %>
                  Authenticating with <%= @selected_client.name %>
                <% _ -> %>
                  Fetching user data from <%= @selected_client.name %>
              <% end %>
            </.text_ping_loader>
            <.authorize_button
              :if={@display_authorize_button}
              authorize_url={@authorize_url}
              provider={@selected_client.name}
              myself={@myself}
            />
            <.userinfo
              :if={@display_userinfo}
              myself={@myself}
              userinfo={@userinfo}
              authorize_url={@authorize_url}
            />
            <%!-- <.error_block
              type={@oauth_progress}
              myself={@myself}
              provider={@provider}
              authorize_url={@authorize_url}
            /> --%>
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
              <div class="sm:flex sm:flex-row-reverse">
                <button
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

  defp authorize_button(assigns) do
    ~H"""
    <.link
      href={@authorize_url}
      id="authorize-button"
      phx-click="authorize_click"
      phx-target={@myself}
      target="_blank"
      class="rounded-md bg-indigo-600 px-3.5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
    >
      <span class="text-normal">Sign in with <%= @provider %></span>
    </.link>
    """
  end

  def userinfo(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between sm:flex-nowrap mt-5">
      <div class="flex items-center">
        <img
          src={@userinfo["picture"]}
          class="h-14 w-14 rounded-full"
          alt={@userinfo["name"]}
        />
        <div class="ml-4">
          <h3 class="text-base font-semibold leading-6 text-gray-900">
            <%= @userinfo["name"] %>
          </h3>
          <p class="text-sm text-gray-500">
            <a href="#"><%= @userinfo["email"] %></a>
          </p>
          <div class="text-sm mt-1">
            Not working?
            <.link
              href={@authorize_url}
              target="_blank"
              phx-target={@myself}
              phx-click="authorize_click"
              class="hover:underline text-primary-900"
            >
              Reauthorize.
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def error_block(%{type: :token_failed} = assigns) do
    ~H"""
    <div class="rounded-md bg-yellow-50 border border-yellow-200 p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <svg
            class="h-5 w-5 text-yellow-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800">Something went wrong.</h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p class="text-sm mt-2">
              Failed retrieving the token from the provider. Please try again
              <.link
                href={@authorize_url}
                target="_blank"
                phx-target={@myself}
                phx-click="authorize_click"
                class="hover:underline text-primary-900"
              >
                here
                <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />.
              </.link>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def error_block(%{type: :refresh_failed} = assigns) do
    ~H"""
    <div class="rounded-md bg-yellow-50 border border-yellow-200 p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <svg
            class="h-5 w-5 text-yellow-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800">Something went wrong.</h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p class="text-sm mt-2">
              Failed renewing your access token. Please try again
              <.link
                href={@authorize_url}
                target="_blank"
                phx-target={@myself}
                phx-click="authorize_click"
                class="hover:underline text-primary-900"
              >
                here
                <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />.
              </.link>
            </p>
            <p class="text-sm mt-2"></p>
            <.helpblock provider={@provider} type={@type} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  def error_block(%{type: :userinfo_failed} = assigns) do
    ~H"""
    <div class="rounded-md bg-yellow-50 border border-yellow-200 p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <svg
            class="h-5 w-5 text-yellow-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800">Something went wrong.</h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p class="text-sm mt-2">
              Failed retrieving your information. Please
              <a
                href="#"
                phx-click="try_userinfo_again"
                phx-target={@myself}
                class="hover:underline text-primary-900"
              >
                try again.
              </a>
            </p>
            <.helpblock provider={@provider} type={@type} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  def error_block(%{type: :no_refresh_token} = assigns) do
    ~H"""
    <div class="rounded-md bg-yellow-50 border border-yellow-200 p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <svg
            class="h-5 w-5 text-yellow-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800">Something went wrong.</h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p class="text-sm mt-2">
              The token is missing it's
              <code class="bg-gray-200 rounded-md p-1">refresh_token</code>
              value. Please reauthorize <.link
                href={@authorize_url}
                target="_blank"
                phx-target={@myself}
                phx-click="authorize_click"
                class="hover:underline text-primary-900"
              >
            here
            <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />.
          </.link>.
            </p>
            <.helpblock provider={@provider} type={@type} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  def helpblock(
        %{type: :userinfo_failed} =
          assigns
      ) do
    ~H"""
    <p class="text-sm mt-2">
      If the issue persists, please follow the "Remove third-party account access"
      instructions on the
      <a
        class="text-indigo-600 underline"
        href="https://support.google.com/accounts/answer/3466521"
        target="_blank"
      >
        Manage third-party apps & services with access to your account
      </a>
      <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />
      page.
    </p>
    """
  end

  def reauthorize_banner(assigns) do
    ~H"""
    <div
      id="re-authorize-banner"
      class="rounded-md bg-blue-50 border border-blue-100 p-2 mt-5"
    >
      <div class="flex">
        <div class="flex-shrink-0">
          <svg
            class="h-5 w-5 text-blue-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a.75.75 0 000 1.5h.253a.25.25 0 01.244.304l-.459 2.066A1.75 1.75 0 0010.747 15H11a.75.75 0 000-1.5h-.253a.25.25 0 01-.244-.304l.459-2.066A1.75 1.75 0 009.253 9H9z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
        <div class="ml-3 flex-1 md:flex md:justify-between">
          <p class="text-sm text-slate-700">
            Please re-authenticate to save your credential with the updated scopes
          </p>
          <p class="mt-3 text-sm md:ml-6 md:mt-0">
            <.link
              href={@authorize_url}
              id="re-authorize-button"
              target="_blank"
              class="whitespace-nowrap font-medium text-blue-700 hover:text-blue-600"
              phx-click="authorize_click"
              phx-target={@myself}
            >
              Re-authenticate <span aria-hidden="true"> &rarr;</span>
            </.link>
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp display_loader?(oauth_progress) do
    oauth_progress not in List.flatten([
      :not_started | Map.values(@oauth_states)
    ])
  end

  defp display_reauthorize_banner?(%{
         action: action,
         scopes_changed: scopes_changed,
         oauth_progress: oauth_progress
       }) do
    case action do
      :new ->
        scopes_changed &&
          oauth_progress in (@oauth_states.success ++
                               @oauth_states.failure)

      :edit ->
        scopes_changed && oauth_progress not in [:started]

      _ ->
        false
    end
  end

  defp display_authorize_button?(
         %{action: action, oauth_progress: oauth_progress},
         display_reauthorize_banner
       ) do
    action == :new && oauth_progress == :not_started &&
      !display_reauthorize_banner
  end

  defp display_userinfo?(oauth_progress, display_reauthorize_banner) do
    oauth_progress == :userinfo_received && !display_reauthorize_banner
  end

  defp display_error?(oauth_progress, display_reauthorize_banner) do
    oauth_progress in @oauth_states.failure && !display_reauthorize_banner
  end

  attr :id, :string, required: true
  attr :on_change, :any, required: true
  attr :target, :any, required: true
  attr :selected_scopes, :any, required: true
  attr :mandatory_scopes, :any, required: true
  attr :scopes, :any, required: true
  attr :provider, :string, required: true
  attr :doc_url, :any, default: nil

  def scopes_picklist(assigns) do
    ~H"""
    <div id={@id} class="mt-5">
      <h3 class="leading-6 text-slate-800 pb-2 mb-2">
        <div class="flex flex-row text-sm font-semibold">
          Select permissions
          <LightningWeb.Components.Common.tooltip
            id={"#{@id}-tooltip"}
            title="Select permissions associated to your OAuth2 Token"
          />
        </div>
        <div :if={@doc_url} class="flex flex-row text-xs mt-1">
          Learn more about <%= @provider %> permissions
          <a
            target="_blank"
            href={@doc_url |> IO.inspect(label: "Doc URL")}
            class="whitespace-nowrap font-medium text-blue-700 hover:text-blue-600"
          >
            &nbsp;here
          </a>
        </div>
      </h3>
      <div class="flex flex-wrap gap-1">
        <%= for scope <- @scopes do %>
          <.input
            id={"#{@id}_#{scope}"}
            type="checkbox"
            name={scope}
            value={scope}
            checked={scope in @selected_scopes}
            disabled={scope in @mandatory_scopes}
            phx-change={@on_change}
            phx-target={@target}
            label={scope}
          /> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
        <% end %>
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
