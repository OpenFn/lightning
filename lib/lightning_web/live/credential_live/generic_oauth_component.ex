defmodule LightningWeb.CredentialLive.GenericOauthComponent do
  use LightningWeb, :live_component

  import LightningWeb.OauthCredentialHelper
  import LightningWeb.Components.Oauth

  alias Lightning.AuthProviders.OauthHTTPClient
  alias Lightning.Credentials
  alias Lightning.Credentials.OauthToken
  alias Lightning.Credentials.OauthValidation
  alias LightningWeb.Components.NewInputs
  alias LightningWeb.CredentialLive.Helpers
  alias Phoenix.LiveView.JS

  require Logger

  @impl true
  def mount(socket) do
    subscribe(socket.id)

    {:ok,
     socket
     |> assign(
       selected_client: nil,
       selected_project: nil,
       userinfo: nil,
       authorize_url: nil,
       scopes_changed: false,
       available_projects: [],
       selected_projects: [],
       oauth_progress: :idle,
       oauth_error: nil,
       previous_oauth_state: nil
     )}
  end

  @impl true
  def update(%{selected_client: nil, action: _action} = assigns, socket) do
    selected_scopes =
      OauthValidation.normalize_scopes(assigns.credential.oauth_token)

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
    selected_scopes =
      OauthValidation.normalize_scopes(assigns.credential.oauth_token)

    mandatory_scopes =
      OauthValidation.normalize_scopes(selected_client.mandatory_scopes, ",")

    optional_scopes =
      OauthValidation.normalize_scopes(selected_client.optional_scopes, ",")

    scopes = mandatory_scopes ++ optional_scopes ++ selected_scopes
    scopes = scopes |> Enum.map(&String.downcase/1) |> Enum.uniq()
    state = build_state(socket.id, __MODULE__, assigns.id)
    stringified_scopes = Enum.join(selected_scopes, " ")

    authorize_url =
      OauthHTTPClient.generate_authorize_url(selected_client,
        state: state,
        scope: stringified_scopes
      )

    socket = refresh_token_or_fetch_userinfo(socket, assigns, selected_client)

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
    mandatory_scopes =
      OauthValidation.normalize_scopes(selected_client.mandatory_scopes, ",")

    optional_scopes =
      OauthValidation.normalize_scopes(selected_client.optional_scopes, ",")

    state = build_state(socket.id, __MODULE__, assigns.id)
    stringified_scopes = Enum.join(mandatory_scopes, " ")

    authorize_url =
      OauthHTTPClient.generate_authorize_url(selected_client,
        state: state,
        scope: stringified_scopes
      )

    {:ok,
     build_assigns(socket, assigns,
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
    if Map.get(socket.assigns, :code) do
      {:ok, socket}
    else
      client = socket.assigns.selected_client

      {:ok,
       socket
       |> assign(code: code)
       |> assign(:oauth_progress, :authenticating)
       |> start_async(:token, fn ->
         OauthHTTPClient.fetch_token(client, code)
       end)}
    end
  end

  def update(%{error: error} = _assigns, socket) do
    Logger.warning(
      "Failed fetching authentication code for #{socket.assigns.selected_client.name}: #{inspect(error)}"
    )

    {:ok,
     socket
     |> assign(:oauth_progress, :error)
     |> assign(:oauth_error, {:code_exchange_failed, error})}
  end

  @impl true
  def handle_async(:token, {:ok, {:ok, token}}, socket) do
    expected_scopes =
      socket.assigns.selected_scopes
      |> Enum.map(&String.downcase/1)
      |> Enum.reject(&(&1 == "offline_access"))

    params =
      socket.assigns.changeset.params
      |> Map.put("oauth_token", token)
      |> Map.put("expected_scopes", expected_scopes)

    changeset = Credentials.change_credential(socket.assigns.credential, params)

    updated_socket =
      socket
      |> assign(:scopes_changed, false)
      |> assign(:changeset, changeset)

    case validate_token(token, updated_socket.assigns.selected_scopes) do
      :ok ->
        Logger.info(
          "Received valid token from #{updated_socket.assigns.selected_client.name}"
        )

        if updated_socket.assigns.selected_client.userinfo_endpoint do
          {:noreply,
           updated_socket
           |> assign(:oauth_progress, :fetching_userinfo)
           |> start_async(:userinfo, fn ->
             OauthHTTPClient.fetch_userinfo(
               updated_socket.assigns.selected_client,
               token
             )
           end)}
        else
          {:noreply, assign(updated_socket, :oauth_progress, :complete)}
        end

      {:error, %OauthValidation.Error{} = error} ->
        Logger.warning(
          "Invalid token from #{updated_socket.assigns.selected_client.name}: #{error.type}"
        )

        {:noreply,
         updated_socket
         |> assign(:oauth_progress, :error)
         |> assign(:oauth_error, error)}
    end
  end

  def handle_async(:token, {:ok, {:error, http_error}}, socket) do
    Logger.error(
      "Failed to fetch token from #{socket.assigns.selected_client.name}: #{inspect(http_error)}"
    )

    {:noreply,
     socket
     |> assign(:oauth_progress, :error)
     |> assign(:oauth_error, {:http_error, http_error})}
  end

  def handle_async(:token, {:exit, reason}, socket) do
    Logger.error(
      "Token fetch crashed for #{socket.assigns.selected_client.name}: #{inspect(reason)}"
    )

    {:noreply,
     socket
     |> assign(:oauth_progress, :error)
     |> assign(:oauth_error, {:task_crashed, reason})}
  end

  def handle_async(:userinfo, {:ok, {:ok, userinfo}}, socket) do
    Logger.info(
      "Successfully fetched userinfo from #{socket.assigns.selected_client.name}"
    )

    {:noreply,
     socket
     |> assign(:userinfo, userinfo)
     |> assign(:oauth_progress, :complete)}
  end

  def handle_async(:userinfo, {:ok, {:error, error}}, socket) do
    case error do
      %{status: 401} ->
        Logger.error(
          "Token is invalid or revoked for #{socket.assigns.selected_client.name}: #{inspect(error)}"
        )

        oauth_error = %OauthValidation.Error{
          type: :invalid_access_token,
          message: "The access token is no longer valid",
          details: %{
            reason:
              "Token may have been revoked when you authorized another credential for the same account"
          }
        }

        {:noreply,
         socket
         |> assign(:oauth_progress, :error)
         |> assign(:oauth_error, oauth_error)}

      _ ->
        Logger.warning(
          "Failed to fetch userinfo from #{socket.assigns.selected_client.name}, continuing anyway. Error: #{inspect(error)}"
        )

        {:noreply,
         socket
         |> assign(:oauth_progress, :complete)
         |> assign(:userinfo_fetch_failed, true)}
    end
  end

  def handle_async(:userinfo, {:exit, reason}, socket) do
    Logger.error(
      "User informations fetch crashed for #{socket.assigns.selected_client.name}: #{inspect(reason)}"
    )

    {:noreply, assign(socket, :oauth_progress, :complete)}
  end

  @impl true
  def handle_event(
        "validate",
        %{"credential" => credential_params} = _params,
        socket
      ) do
    params =
      socket.assigns.changeset.params
      |> Map.merge(credential_params)
      |> Map.put("body", %{"apiVersion" => credential_params["api_version"]})

    changeset =
      Credentials.change_credential(socket.assigns.credential, params)
      |> Map.put(:action, :validate)

    available_projects =
      Helpers.filter_available_projects(
        socket.assigns.projects,
        socket.assigns.selected_projects
      )

    {:noreply,
     assign(socket,
       changeset: changeset,
       available_projects: available_projects,
       selected_project: nil
     )}
  end

  def handle_event("authorize_click", _, socket) do
    {:noreply,
     socket
     |> assign(code: nil)
     |> assign(scopes_changed: false)
     |> assign(oauth_progress: :authenticating)
     |> assign(oauth_error: nil)
     |> push_event("open_authorize_url", %{url: socket.assigns.authorize_url})}
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
      OauthHTTPClient.generate_authorize_url(socket.assigns.selected_client,
        state: state,
        scope: stringified_scopes
      )

    saved_scopes = get_scopes(socket.assigns.credential.oauth_token)
    scopes_changed = Enum.sort(selected_scopes) != Enum.sort(saved_scopes)

    updated_socket =
      if scopes_changed and not socket.assigns.scopes_changed do
        socket
        |> assign(:previous_oauth_state, %{
          oauth_progress: socket.assigns.oauth_progress,
          oauth_error: socket.assigns.oauth_error,
          userinfo: socket.assigns.userinfo
        })
      else
        socket
      end

    final_socket =
      if not scopes_changed and socket.assigns.scopes_changed do
        previous_state = socket.assigns.previous_oauth_state || %{}

        updated_socket
        |> assign(
          :oauth_progress,
          Map.get(previous_state, :oauth_progress, :idle)
        )
        |> assign(:oauth_error, Map.get(previous_state, :oauth_error, nil))
        |> assign(:userinfo, Map.get(previous_state, :userinfo, nil))
        |> assign(:previous_oauth_state, nil)
      else
        updated_socket
      end

    {:noreply,
     final_socket
     |> assign(:scopes_changed, scopes_changed)
     |> assign(:selected_scopes, selected_scopes)
     |> assign(:authorize_url, authorize_url)}
  end

  def handle_event(
        "save",
        %{"credential" => credential_params} = _params,
        socket
      ) do
    project_credentials =
      Helpers.prepare_projects_associations(
        socket.assigns.changeset,
        socket.assigns.selected_projects,
        :project_credentials
      )

    credential_params =
      Map.put(credential_params, "project_credentials", project_credentials)

    save_credential(socket, socket.assigns.action, credential_params)
  end

  def handle_event("select_project", %{"project_id" => project_id}, socket) do
    {:noreply, assign(socket, selected_project: project_id)}
  end

  def handle_event("add_selected_project", %{"project_id" => project_id}, socket) do
    {:noreply,
     socket
     |> assign(
       Helpers.select_project(
         project_id,
         socket.assigns.projects,
         socket.assigns.available_projects,
         socket.assigns.selected_projects
       )
     )
     |> assign(selected_project: nil)}
  end

  def handle_event(
        "remove_selected_project",
        %{"project_id" => project_id},
        socket
      ) do
    {:noreply,
     assign(
       socket,
       Helpers.unselect_project(
         project_id,
         socket.assigns.projects,
         socket.assigns.selected_projects
       )
     )}
  end

  defp refresh_token_or_fetch_userinfo(socket, assigns, selected_client) do
    cond do
      not OauthToken.still_fresh?(assigns.credential.oauth_token) ->
        refresh_token(
          socket,
          selected_client,
          assigns.credential.oauth_token.body
        )

      selected_client.userinfo_endpoint ->
        fetch_userinfo(
          socket,
          selected_client,
          assigns.credential.oauth_token.body
        )

      true ->
        assign(socket, :oauth_progress, :complete)
    end
  end

  defp refresh_token(socket, client, token) do
    Logger.info("Refreshing token")

    socket
    |> assign(:oauth_progress, :authenticating)
    |> start_async(:token, fn ->
      OauthHTTPClient.refresh_token(
        client,
        token
      )
    end)
  end

  defp fetch_userinfo(socket, client, token) do
    Logger.info("Fetching user info")

    socket
    |> assign(:oauth_progress, :fetching_userinfo)
    |> start_async(:userinfo, fn ->
      OauthHTTPClient.fetch_userinfo(
        client,
        token
      )
    end)
  end

  defp validate_token(token, expected_scopes) do
    with {:ok, _} <- OauthValidation.validate_token_data(token) do
      OauthValidation.validate_scope_grant(token, expected_scopes)
    end
  end

  defp build_assigns(socket, assigns, additional_assigns) do
    selected_projects =
      assigns.changeset
      |> Ecto.Changeset.get_assoc(:project_credentials, :struct)
      |> Lightning.Repo.preload(:project)
      |> Enum.map(fn poc -> poc.project end)

    available_projects =
      Helpers.filter_available_projects(assigns.projects, selected_projects)

    client_id = assigns.selected_client && assigns.selected_client.id

    params = Map.put(assigns.changeset.params, "oauth_client_id", client_id)
    changeset = Credentials.change_credential(assigns.credential, params)

    assign(socket,
      id: assigns.id,
      action: assigns.action,
      selected_client: assigns.selected_client,
      changeset: changeset,
      credential: assigns.credential,
      projects: assigns.projects,
      users: assigns.users,
      selected_projects: selected_projects,
      available_projects: available_projects,
      on_save: assigns.on_save
    )
    |> assign(additional_assigns)
  end

  defp get_scopes(%{body: %{"scope" => scope}}), do: String.split(scope)
  defp get_scopes(_), do: []

  defp save_credential(socket, :new, params) do
    if socket.assigns.changeset.valid? do
      user_id = Ecto.Changeset.fetch_field!(socket.assigns.changeset, :user_id)

      socket.assigns.changeset.params
      |> Map.merge(params)
      |> Map.put("user_id", user_id)
      |> Credentials.create_credential()
      |> case do
        {:ok, credential} ->
          {:noreply, Helpers.handle_save_response(socket, credential)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :changeset, changeset)}
      end
    else
      {:noreply, socket |> put_flash(:error, "Can't save invalid credential")}
    end
  end

  defp save_credential(socket, :edit, params) do
    if socket.assigns.changeset.valid? do
      user_id = Ecto.Changeset.fetch_field!(socket.assigns.changeset, :user_id)

      update_params =
        socket.assigns.changeset.params
        |> Map.merge(params)
        |> Map.put("user_id", user_id)

      case Credentials.update_credential(
             socket.assigns.credential,
             update_params
           ) do
        {:ok, _credential} ->
          {:noreply,
           socket
           |> put_flash(:info, "Credential updated successfully")
           |> push_navigate(to: socket.assigns.return_to)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :changeset, changeset)}
      end
    else
      {:noreply, socket |> put_flash(:error, "Can't save invalid credential")}
    end
  end

  @impl true
  def render(assigns) do
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
            :if={@scopes |> Enum.count() > 0}
            id={"scope_selection_#{@credential.id || "new"}"}
            target={@myself}
            on_change="check_scope"
            scopes={@scopes}
            selected_scopes={@selected_scopes}
            mandatory_scopes={@mandatory_scopes}
            disabled={!@selected_client}
            doc_url={@selected_client && @selected_client.scopes_doc_url}
            provider={(@selected_client && @selected_client.name) || ""}
          />

          <div class="space-y-4 mt-5">
            <NewInputs.input
              type="text"
              field={f[:api_version]}
              value={Ecto.Changeset.get_field(@changeset, :body)["apiVersion"]}
              label="API Version"
            />
          </div>

          <div id={"#{@id}-oauth-status"} phx-hook="OpenAuthorizeUrl" class="my-10">
            <.oauth_status
              state={@oauth_progress}
              error={@oauth_error}
              userinfo={@userinfo}
              provider={@selected_client && @selected_client.name}
              authorize_url={@authorize_url}
              myself={@myself}
              scopes_changed={@scopes_changed}
              socket={@socket}
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
                <LightningWeb.Components.Credentials.projects_picker
                  id={@credential.id || "new"}
                  type={:credential}
                  available_projects={@available_projects}
                  selected_projects={@selected_projects}
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
            <LightningWeb.Components.Credentials.credential_transfer
              form={f}
              users={@users}
            />
          </div>
        </div>

        <.modal_footer class="mt-6 mx-4">
          <div class="flex justify-between items-center">
            <div class="flex-1 w-1/2">
              <div class="sm:flex sm:flex-row-reverse gap-3">
                <.button
                  id={"save-credential-button-#{@credential.id || "new"}"}
                  type="submit"
                  theme="primary"
                  disabled={
                    !@changeset.valid? || @scopes_changed ||
                      @oauth_progress == :error
                  }
                >
                  Save
                </.button>
                <.button
                  type="button"
                  phx-click={JS.navigate(@return_to)}
                  theme="secondary"
                >
                  Cancel
                </.button>
              </div>
            </div>
          </div>
        </.modal_footer>
      </.form>
    </div>
    """
  end
end
