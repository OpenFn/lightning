defmodule LightningWeb.CredentialLive.GenericOauthComponent do
  use LightningWeb, :live_component

  import LightningWeb.OauthCredentialHelper
  import LightningWeb.Components.Oauth

  alias Lightning.AuthProviders.OauthHTTPClient
  alias Lightning.Credentials
  alias LightningWeb.Components.NewInputs
  alias Phoenix.LiveView.JS

  require Logger

  @oauth_states %{
    success: [:userinfo_received, :token_received],
    failure: [:token_failed, :userinfo_failed, :code_failed, :refresh_failed]
  }

  @impl true
  def mount(socket) do
    subscribe(socket.id)

    {:ok,
     socket
     |> assign_new(:selected_client, fn -> nil end)
     |> assign_new(:selected_project, fn -> nil end)
     |> assign_new(:userinfo, fn -> nil end)
     |> assign_new(:authorize_url, fn -> nil end)
     |> assign_new(:scopes_changed, fn -> false end)
     |> assign_new(:oauth_progress, fn -> :not_started end)}
  end

  @impl true
  def update(%{selected_client: nil, action: _action} = assigns, socket) do
    selected_scopes = String.split(assigns.credential.body["scope"], ",")

    {:ok,
     build_assigns(socket, assigns,
       selected_scopes: selected_scopes,
       mandatory_scopes: [],
       optional_scopes: [],
       scopes: selected_scopes,
       allow_credential_transfer: assigns.allow_credential_transfer,
       return_to: assigns.return_to
     )}
  end

  def update(
        %{selected_client: selected_client, action: :edit} = assigns,
        socket
      ) do
    selected_scopes = process_scopes(assigns.credential.body["scope"], " ")
    mandatory_scopes = process_scopes(selected_client.mandatory_scopes, ",")
    optional_scopes = process_scopes(selected_client.optional_scopes, ",")

    scopes = Enum.uniq(mandatory_scopes ++ optional_scopes ++ selected_scopes)
    state = build_state(socket.id, __MODULE__, assigns.id)
    stringified_scopes = Enum.join(selected_scopes, " ")

    authorize_url =
      OauthHTTPClient.generate_authorize_url(
        selected_client.authorization_endpoint,
        selected_client.client_id,
        state: state,
        scope: stringified_scopes
      )

    socket = maybe_refresh_token(socket, assigns, selected_client)

    {:ok,
     build_assigns(socket, assigns,
       mandatory_scopes: mandatory_scopes,
       optional_scopes: optional_scopes,
       selected_scopes: selected_scopes,
       scopes: scopes,
       authorize_url: authorize_url,
       allow_credential_transfer: assigns.allow_credential_transfer,
       return_to: assigns.return_to
     )}
  end

  def update(%{action: :new, selected_client: selected_client} = assigns, socket) do
    mandatory_scopes = process_scopes(selected_client.mandatory_scopes, ",")
    optional_scopes = process_scopes(selected_client.optional_scopes, ",")

    state = build_state(socket.id, __MODULE__, assigns.id)
    stringified_scopes = Enum.join(mandatory_scopes, " ")

    authorize_url =
      OauthHTTPClient.generate_authorize_url(
        selected_client.authorization_endpoint,
        selected_client.client_id,
        state: state,
        scope: stringified_scopes
      )

    {:ok,
     build_assigns(socket, assigns,
       apiVersion: nil,
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
    if Map.get(socket.assigns, :code, false) do
      {:ok, socket}
    else
      client = socket.assigns.selected_client

      {:ok,
       socket
       |> assign(code: code)
       |> assign(:oauth_progress, :code_received)
       |> start_async(:token, fn ->
         OauthHTTPClient.fetch_token(client, code)
       end)}
    end
  end

  def update(%{error: error} = _assigns, socket) do
    Logger.info(
      "Failed fetching authentication code using #{socket.assigns.selected_client.name}. Received error message: #{inspect(error)}"
    )

    {:ok, assign(socket, :oauth_progress, :code_failed)}
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
      |> assign(:scopes_changed, false)
      |> assign(:changeset, changeset)
      |> assign(:credential, credential)

    if socket.assigns.selected_client.userinfo_endpoint do
      {:noreply,
       updated_socket
       |> start_async(:userinfo, fn ->
         OauthHTTPClient.fetch_userinfo(
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

  def handle_async(:token, {:ok, {:error, error}}, socket) do
    Logger.info(
      "Failed fetching token using #{socket.assigns.selected_client.name}. Received error message: #{inspect(error)}"
    )

    {:noreply, assign(socket, :oauth_progress, :token_failed)}
  end

  def handle_async(:userinfo, {:ok, {:error, error}}, socket) do
    Logger.info(
      "Failed fetching userinfo using #{socket.assigns.selected_client.name}. Received error message: #{inspect(error)}"
    )

    {:noreply, assign(socket, :oauth_progress, :userinfo_failed)}
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
        Map.put(credential_params, "schema", "oauth")
      )
      |> Map.put(:action, :validate)

    api_version = Map.get(credential_params, "apiVersion", nil)

    {:noreply,
     socket |> assign(changeset: changeset) |> assign(:apiVersion, api_version)}
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
      OauthHTTPClient.generate_authorize_url(
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

  defp maybe_refresh_token(socket, assigns, selected_client) do
    case OauthHTTPClient.still_fresh(assigns.credential.body) do
      true ->
        if selected_client.userinfo_endpoint do
          Logger.info("Fetching user info.")

          start_async(socket, :userinfo, fn ->
            OauthHTTPClient.fetch_userinfo(
              assigns.credential.body["access_token"],
              selected_client.userinfo_endpoint
            )
          end)
        else
          socket
        end

      false ->
        Logger.info("Refreshing token.")

        start_async(socket, :token, fn ->
          OauthHTTPClient.refresh_token(
            selected_client.client_id,
            selected_client.client_secret,
            assigns.credential.body["refresh_token"],
            selected_client.token_endpoint
          )
        end)

      {:error, reason} ->
        Logger.error("Error checking token freshness: #{reason}")
        socket
    end
  end

  defp process_scopes(scopes_string, delimiter) do
    scopes_string
    |> to_string()
    |> String.split(delimiter)
    |> Enum.reject(&(&1 == ""))
  end

  defp build_assigns(socket, assigns, additional_assigns) do
    assign(socket,
      id: assigns.id,
      action: assigns.action,
      selected_client: assigns.selected_client,
      changeset: assigns.changeset,
      credential: assigns.credential,
      projects: assigns.projects,
      users: assigns.users,
      apiVersion: assigns.credential.body["apiVersion"],
      parent_component: assigns.parent_component,
      available_projects: assigns.available_projects,
      selected_project: assigns.selected_project
    )
    |> assign(additional_assigns)
  end

  defp get_scopes(%{body: %{"scope" => scope}}), do: String.split(scope)
  defp get_scopes(_), do: []

  defp save_credential(socket, :new, params) do
    user_id = Ecto.Changeset.fetch_field!(socket.assigns.changeset, :user_id)
    body = Ecto.Changeset.fetch_field!(socket.assigns.changeset, :body)

    body = Map.put(body, "apiVersion", socket.assigns.apiVersion)

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
      |> Map.put("apiVersion", socket.assigns.apiVersion)

    params =
      Map.put(params, "body", body)
      |> Map.put("oauth_client_id", socket.assigns.selected_client.id)

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
    <div id={@id}>
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
              field={f[:apiVersion]}
              value={@apiVersion || nil}
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
              socket={@socket}
              authorize_url={@authorize_url}
            />
            <.error_block
              :if={@display_error}
              type={@oauth_progress}
              myself={@myself}
              provider={@selected_client.name}
              authorize_url={@authorize_url}
            />
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
                <LightningWeb.Components.Credentials.project_credentials
                  form={f}
                  available_projects={@available_projects}
                  all_projects={@projects}
                  selected={@selected_project |> IO.inspect()}
                  phx_target={@parent_component}
                />
              </div>
            </fieldset>
          </div>
          <div
            :if={@action == :edit and @allow_credential_transfer}
            class="space-y-4"
          >
            <LightningWeb.Components.Credentials.credential_transfer
              form={f}
              users={@users}
            />
          </div>
        </div>
        <.modal_footer class="mt-6 mx-4">
          <div class="flex justify-between items-center">
            <div class="flex-1 w-1/2">
              <div class="sm:flex sm:flex-row-reverse">
                <button
                  type="submit"
                  disabled={!@changeset.valid? || @scopes_changed}
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
end
