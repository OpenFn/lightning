defmodule LightningWeb.CredentialLive.GenericOauthComponent do
  use LightningWeb, :live_component

  import LightningWeb.OauthCredentialHelper
  import LightningWeb.Components.Oauth

  alias Lightning.AuthProviders.OauthHTTPClient
  alias Lightning.Credentials
  alias Lightning.Credentials.OauthValidation

  require Logger

  @impl true
  def mount(socket) do
    subscribe(socket.id)

    {:ok,
     socket
     |> assign(
       oauth_progress: :idle,
       oauth_error: nil,
       userinfo: nil,
       code: nil,
       authorize_url: nil,
       scopes_changed: false,
       previous_oauth_state: nil,
       oauth_token: nil
     )}
  end

  @impl true
  def update(%{selected_client: nil, action: _action} = assigns, socket) do
    current_body = Map.get(assigns.credential_bodies, assigns.current_tab, %{})
    selected_scopes = OauthValidation.normalize_scopes(current_body)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       selected_scopes: selected_scopes,
       mandatory_scopes: [],
       optional_scopes: [],
       scopes: selected_scopes,
       oauth_token: current_body
     )}
  end

  def update(
        %{selected_client: selected_client, action: :edit} = assigns,
        socket
      ) do
    current_body = Map.get(assigns.credential_bodies, assigns.current_tab, %{})
    selected_scopes = OauthValidation.normalize_scopes(current_body)

    mandatory_scopes =
      OauthValidation.normalize_scopes(selected_client.mandatory_scopes, ",")

    optional_scopes =
      OauthValidation.normalize_scopes(selected_client.optional_scopes, ",")

    selected_scopes =
      if Enum.empty?(selected_scopes),
        do: mandatory_scopes,
        else: selected_scopes

    scopes = mandatory_scopes ++ optional_scopes ++ selected_scopes
    scopes = scopes |> Enum.map(&String.downcase/1) |> Enum.uniq()

    state = build_state(socket.id, __MODULE__, assigns.id, assigns.current_tab)
    stringified_scopes = Enum.join(selected_scopes, " ")

    authorize_url =
      OauthHTTPClient.generate_authorize_url(selected_client,
        state: state,
        scope: stringified_scopes
      )

    socket =
      socket
      |> assign(assigns)
      |> assign(
        mandatory_scopes: mandatory_scopes,
        optional_scopes: optional_scopes,
        selected_scopes: selected_scopes,
        scopes: scopes,
        authorize_url: authorize_url,
        oauth_token: current_body
      )
      |> refresh_token_or_fetch_userinfo(selected_client, current_body)

    {:ok, socket}
  end

  def update(%{action: :new, selected_client: selected_client} = assigns, socket) do
    mandatory_scopes =
      OauthValidation.normalize_scopes(selected_client.mandatory_scopes, ",")

    optional_scopes =
      OauthValidation.normalize_scopes(selected_client.optional_scopes, ",")

    state = build_state(socket.id, __MODULE__, assigns.id, assigns.current_tab)
    stringified_scopes = Enum.join(mandatory_scopes, " ")

    authorize_url =
      OauthHTTPClient.generate_authorize_url(selected_client,
        state: state,
        scope: stringified_scopes
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       mandatory_scopes: mandatory_scopes,
       optional_scopes: optional_scopes,
       selected_scopes: mandatory_scopes,
       scopes: mandatory_scopes ++ optional_scopes,
       authorize_url: authorize_url
     )}
  end

  def update(%{code: code, current_tab: tab} = _assigns, socket) do
    if socket.assigns.code do
      {:ok, socket}
    else
      send_update(LightningWeb.CredentialLive.CredentialFormComponent,
        id: socket.assigns.parent_id,
        current_tab: tab
      )

      client = socket.assigns.selected_client

      {:ok,
       socket
       |> assign(code: code, oauth_progress: :authenticating)
       |> start_async(:token, fn ->
         OauthHTTPClient.fetch_token(client, code)
       end)}
    end
  end

  def update(%{error: error, current_tab: tab} = _assigns, socket) do
    send_update(LightningWeb.CredentialLive.CredentialFormComponent,
      id: socket.assigns.parent_id,
      current_tab: tab
    )

    Logger.warning(
      "Failed fetching authentication code for #{socket.assigns.selected_client.name} (#{socket.assigns.current_tab}): #{inspect(error)}"
    )

    {:ok,
     socket
     |> assign(oauth_progress: :error)
     |> assign(oauth_error: {:code_exchange_failed, error})}
  end

  @impl true
  def handle_async(:token, {:ok, {:ok, token}}, socket) do
    expected_scopes =
      socket.assigns.selected_scopes
      |> Enum.map(&String.downcase/1)
      |> Enum.reject(&(&1 == "offline_access"))

    normalized_token = Credentials.normalize_token_expiry(token)

    send_update(LightningWeb.CredentialLive.CredentialFormComponent,
      id: socket.assigns.parent_id,
      credential_bodies:
        Map.put(
          socket.assigns.credential_bodies,
          socket.assigns.current_tab,
          normalized_token
        )
    )

    # Store token locally - it will be submitted via hidden input
    updated_socket =
      socket
      |> assign(oauth_token: normalized_token)
      |> assign(scopes_changed: false)

    case validate_token(normalized_token, expected_scopes) do
      :ok ->
        Logger.info(
          "Received valid token for environment '#{socket.assigns.current_tab}' from #{updated_socket.assigns.selected_client.name}"
        )

        if updated_socket.assigns.selected_client.userinfo_endpoint do
          {:noreply,
           updated_socket
           |> assign(oauth_progress: :fetching_userinfo)
           |> start_async(:userinfo, fn ->
             OauthHTTPClient.fetch_userinfo(
               updated_socket.assigns.selected_client,
               normalized_token
             )
           end)}
        else
          {:noreply, assign(updated_socket, oauth_progress: :complete)}
        end

      {:error, %OauthValidation.Error{} = error} ->
        Logger.warning(
          "Invalid token for environment '#{socket.assigns.current_tab}' from #{updated_socket.assigns.selected_client.name}: #{error.type}"
        )

        {:noreply,
         updated_socket
         |> assign(oauth_progress: :error)
         |> assign(oauth_error: error)}
    end
  end

  def handle_async(:token, {:ok, {:error, http_error}}, socket) do
    Logger.error(
      "Failed to fetch token for environment '#{socket.assigns.current_tab}' from #{socket.assigns.selected_client.name}: #{inspect(http_error)}"
    )

    {:noreply,
     socket
     |> assign(oauth_progress: :error)
     |> assign(oauth_error: {:http_error, http_error})}
  end

  def handle_async(:token, {:exit, reason}, socket) do
    Logger.error(
      "Token fetch crashed for environment '#{socket.assigns.current_tab}' for #{socket.assigns.selected_client.name}: #{inspect(reason)}"
    )

    {:noreply,
     socket
     |> assign(oauth_progress: :error)
     |> assign(oauth_error: {:task_crashed, reason})}
  end

  def handle_async(:userinfo, {:ok, {:ok, userinfo}}, socket) do
    Logger.info(
      "Successfully fetched userinfo for environment '#{socket.assigns.current_tab}' from #{socket.assigns.selected_client.name}"
    )

    {:noreply,
     socket
     |> assign(userinfo: userinfo)
     |> assign(oauth_progress: :complete)}
  end

  def handle_async(:userinfo, {:ok, {:error, error}}, socket) do
    case error do
      %{status: 401} ->
        Logger.error(
          "Token is invalid or revoked for environment '#{socket.assigns.current_tab}' for #{socket.assigns.selected_client.name}: #{inspect(error)}"
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
         |> assign(oauth_progress: :error)
         |> assign(oauth_error: oauth_error)}

      _ ->
        Logger.warning(
          "Failed to fetch userinfo for environment '#{socket.assigns.current_tab}' from #{socket.assigns.selected_client.name}, continuing anyway. Error: #{inspect(error)}"
        )

        {:noreply,
         socket
         |> assign(oauth_progress: :complete)
         |> assign(userinfo_fetch_failed: true)}
    end
  end

  def handle_async(:userinfo, {:exit, reason}, socket) do
    Logger.error(
      "User information fetch crashed for environment '#{socket.assigns.current_tab}' for #{socket.assigns.selected_client.name}: #{inspect(reason)}"
    )

    {:noreply, assign(socket, oauth_progress: :complete)}
  end

  @impl true
  def handle_event("authorize_click", _, socket) do
    {:noreply,
     socket
     |> assign(code: nil, scopes_changed: false)
     |> assign(oauth_progress: :authenticating, oauth_error: nil)
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

    state =
      build_state(
        socket.id,
        __MODULE__,
        socket.assigns.id,
        socket.assigns.current_tab
      )

    stringified_scopes = Enum.join(selected_scopes, " ")

    authorize_url =
      OauthHTTPClient.generate_authorize_url(socket.assigns.selected_client,
        state: state,
        scope: stringified_scopes
      )

    current_body = socket.assigns.oauth_token || %{}
    saved_scopes = get_scopes(current_body)
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
          oauth_progress: Map.get(previous_state, :oauth_progress, :idle),
          oauth_error: Map.get(previous_state, :oauth_error),
          userinfo: Map.get(previous_state, :userinfo),
          previous_oauth_state: nil
        )
      else
        updated_socket
      end

    {:noreply,
     final_socket
     |> assign(scopes_changed: scopes_changed)
     |> assign(selected_scopes: selected_scopes)
     |> assign(authorize_url: authorize_url)}
  end

  defp refresh_token_or_fetch_userinfo(socket, selected_client, credential_body) do
    cond do
      not Map.has_key?(credential_body, "access_token") ->
        assign(socket, oauth_progress: :idle)

      Credentials.oauth_token_expired?(credential_body) ->
        refresh_token(socket, selected_client, credential_body)

      selected_client.userinfo_endpoint ->
        fetch_userinfo(socket, selected_client, credential_body)

      true ->
        assign(socket, oauth_progress: :complete)
    end
  end

  defp refresh_token(socket, client, token) do
    Logger.info(
      "Refreshing token for environment '#{socket.assigns.current_tab}'"
    )

    socket
    |> assign(oauth_progress: :authenticating)
    |> start_async(:token, fn ->
      OauthHTTPClient.refresh_token(client, token)
    end)
  end

  defp fetch_userinfo(socket, client, token) do
    Logger.info(
      "Fetching user info for environment '#{socket.assigns.current_tab}'"
    )

    socket
    |> assign(oauth_progress: :fetching_userinfo)
    |> start_async(:userinfo, fn ->
      OauthHTTPClient.fetch_userinfo(client, token)
    end)
  end

  defp validate_token(token, expected_scopes) do
    with {:ok, _} <- OauthValidation.validate_token_data(token) do
      OauthValidation.validate_scope_grant(token, expected_scopes)
    end
  end

  defp get_scopes(%{"scope" => scope}) when is_binary(scope),
    do: String.split(scope)

  defp get_scopes(_), do: []

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-4">
      <input
        :if={@oauth_token && @oauth_token != %{}}
        type="hidden"
        id={"oauth-token-#{@current_tab}"}
        name={"credential[body][#{@current_tab}]"}
        value={Jason.encode!(@oauth_token)}
      />

      <.scopes_picklist
        :if={@scopes |> Enum.count() > 0}
        id={"scope_selection_#{@credential.id || "new"}_#{@current_tab}"}
        target={@myself}
        on_change="check_scope"
        scopes={@scopes}
        selected_scopes={@selected_scopes}
        mandatory_scopes={@mandatory_scopes}
        disabled={!@selected_client}
        doc_url={@selected_client && @selected_client.scopes_doc_url}
        provider={(@selected_client && @selected_client.name) || ""}
      />

      <div
        id={"#{@id}-oauth-status-#{@current_tab}"}
        phx-hook="OpenAuthorizeUrl"
        class="mb-6"
      >
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
    </div>
    """
  end
end
