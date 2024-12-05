defmodule LightningWeb.CredentialLive.OauthComponent do
  @moduledoc ""
  use LightningWeb, :live_component

  import LightningWeb.OauthCredentialHelper
  import LightningWeb.Components.Oauth

  alias Lightning.AuthProviders.Common
  alias Lightning.AuthProviders.Common.TokenBody
  alias Lightning.Credentials
  alias Phoenix.LiveView.AsyncResult

  require Logger

  @oauth_states %{
    success: [:userinfo_received],
    failure: [:token_failed, :userinfo_failed, :refresh_failed]
  }

  attr :form, :map, required: true
  attr :id, :string, required: true
  attr :update_body, :any, required: true
  attr :action, :any, required: true
  attr :scopes_changed, :boolean, default: false
  attr :sandbox_changed, :boolean, default: false
  attr :schema, :string, required: true
  slot :inner_block

  def fieldset(assigns) do
    changeset = assigns.form.source

    parent_valid? = !(changeset.errors |> Keyword.drop([:body]) |> Enum.any?())

    token_body_changeset =
      Common.TokenBody.changeset(
        changeset |> Ecto.Changeset.get_field(:body) || %{}
      )

    assigns =
      assigns
      |> assign(
        update_body: assigns.update_body,
        valid?: parent_valid? and token_body_changeset.valid?,
        token_body_changeset: token_body_changeset
      )

    ~H"""
    <%= render_slot(
      @inner_block,
      {Phoenix.LiveView.TagEngine.component(
         &live_component/1,
         [
           module: __MODULE__,
           form: @form,
           action: @action,
           scopes_changed: @scopes_changed,
           sandbox_changed: @sandbox_changed,
           token_body_changeset: @token_body_changeset,
           update_body: @update_body,
           schema: @schema,
           id: "inner-form-#{@id}"
         ],
         {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
       ), @valid?}
    ) %>
    """
  end

  @impl true
  def render(%{client: nil} = assigns) do
    ~H"""
    <div id={@id} class="flex items-center place-content-center pt-2">
      <div class="text-center">
        <div class="text-base font-medium text-gray-900">
          No Client Configured
        </div>
        <span class="text-sm">
          <%= @provider %> authorization has not been set up on this instance.
        </span>
      </div>
    </div>
    """
  end

  def render(assigns) do
    display_loader = display_loader?(assigns.oauth_progress)
    display_reauthorize_banner = display_reauthorize_banner?(assigns)

    display_authorize_button =
      display_authorize_button?(assigns, display_reauthorize_banner)

    display_userinfo =
      display_userinfo?(
        assigns.oauth_progress,
        display_reauthorize_banner,
        assigns.scopes_changed,
        assigns.sandbox_changed
      )

    display_error =
      display_error?(
        assigns.oauth_progress,
        display_reauthorize_banner,
        assigns.scopes_changed,
        assigns.sandbox_changed
      )

    assigns =
      assigns
      |> update_form()
      |> assign(:display_loader, display_loader)
      |> assign(:display_reauthorize_banner, display_reauthorize_banner)
      |> assign(:display_authorize_button, display_authorize_button)
      |> assign(:display_userinfo, display_userinfo)
      |> assign(:display_error, display_error)

    ~H"""
    <fieldset id={@id}>
      <div :for={
        body_form <- Phoenix.HTML.FormData.to_form(:credential, @form, :body, [])
      }>
        <.input type="hidden" field={body_form[:scope]} />
        <.input type="hidden" field={body_form[:expires_at]} />
        <.input type="hidden" field={body_form[:access_token]} />
        <.input type="hidden" field={body_form[:instance_url]} />
        <.input type="hidden" field={body_form[:refresh_token]} />
      </div>
      <.reauthorize_banner
        :if={@display_reauthorize_banner}
        provider="provider"
        revocation_endpoint={nil}
        authorize_url={@authorize_url}
        myself={@myself}
      />
      <.text_ping_loader :if={@display_loader}>
        <%= case @oauth_progress do %>
          <% :started  -> %>
            Authenticating with <%= @provider %>
          <% _ -> %>
            Fetching user data from <%= @provider %>
        <% end %>
      </.text_ping_loader>
      <.authorize_button
        :if={@display_authorize_button}
        authorize_url={@authorize_url}
        socket={@socket}
        myself={@myself}
        provider={@provider}
      />
      <.userinfo
        :if={@display_userinfo}
        myself={@myself}
        socket={@socket}
        userinfo={@userinfo.result}
        authorize_url={@authorize_url}
      />
      <.alert_block
        :if={@display_error}
        type={@oauth_progress}
        myself={@myself}
        provider={@provider}
        revocation_endpoint={nil}
        authorize_url={@authorize_url}
      />
    </fieldset>
    """
  end

  @impl true
  def mount(socket) do
    subscribe(socket.id)

    {:ok, reset_assigns(socket)}
  end

  @impl true
  def update(
        %{
          form: _form,
          id: _id,
          action: _action,
          scopes_changed: _scopes_changed,
          sandbox_changed: _sandbox_changed,
          token_body_changeset: _changeset,
          update_body: _body,
          schema: _schema
        } = params,
        socket
      ) do
    token =
      params.token_body_changeset
      |> Ecto.Changeset.apply_changes()
      |> params_to_token()

    {:ok,
     socket
     |> reset_assigns()
     |> update_assigns(params, token)
     |> update_client()
     |> maybe_fetch_userinfo()}
  end

  def update(%{code: code}, socket) do
    %{adapter: adapter, client: client, sandbox: sandbox} = socket.assigns
    wellknown_url = adapter.wellknown_url(sandbox)

    {:ok,
     socket
     |> assign(:oauth_progress, :code_received)
     |> start_async(:token, fn ->
       fetch_token(adapter, client, code, wellknown_url)
     end)}
  end

  def update(%{scopes: scopes}, socket) do
    handle_scopes_update(scopes, socket)
  end

  def update(%{sandbox: sandbox}, socket) do
    wellknown_url = socket.assigns.adapter.wellknown_url(sandbox)

    {:ok, client} = build_client(socket, wellknown_url)
    state = build_state(socket.id, __MODULE__, socket.assigns.id)

    authorize_url =
      socket.assigns.adapter.authorize_url(client, state, socket.assigns.scopes)

    {:ok,
     socket
     |> assign(sandbox: sandbox, client: client, authorize_url: authorize_url)}
  end

  defp reset_assigns(socket) do
    socket
    |> assign_new(:scopes, fn -> [] end)
    |> assign_new(:token, fn -> %AsyncResult{} end)
    |> assign_new(:userinfo, fn -> %AsyncResult{} end)
    |> assign_new(:oauth_progress, fn -> :not_started end)
    |> assign_new(:sandbox, fn -> false end)
  end

  defp update_assigns(
         socket,
         %{
           form: form,
           id: id,
           action: action,
           scopes_changed: scopes_changed,
           sandbox_changed: sandbox_changed,
           token_body_changeset: token_body_changeset,
           update_body: update_body,
           schema: schema
         },
         token
       ) do
    adapter = Credentials.lookup_adapter(schema)

    sandbox =
      token_body_changeset
      |> Ecto.Changeset.fetch_field!(:sandbox)

    socket
    |> assign(
      form: form,
      id: id,
      token_body_changeset: token_body_changeset,
      token: AsyncResult.ok(token),
      update_body: update_body,
      adapter: adapter,
      provider: adapter.provider_name(),
      action: action,
      scopes_changed: scopes_changed,
      sandbox_changed: sandbox_changed,
      sandbox: sandbox
    )
  end

  defp update_client(socket) do
    wellknown_url =
      socket.assigns.adapter.wellknown_url(socket.assigns.sandbox)

    socket
    |> assign_new(:client, fn %{token: token} ->
      socket
      |> build_client(wellknown_url)
      |> case do
        {:ok, client} -> client |> Map.put(:token, token.result)
        {:error, _} -> nil
      end
    end)
    |> assign_new(:authorize_url, fn %{client: client} ->
      if client do
        %{optional: _optional_scopes, mandatory: mandatory_scopes} =
          socket.assigns.adapter.scopes()

        state = build_state(socket.id, __MODULE__, socket.assigns.id)

        socket.assigns.adapter.authorize_url(client, state, mandatory_scopes)
      end
    end)
  end

  defp handle_scopes_update(scopes, socket) do
    state = build_state(socket.id, __MODULE__, socket.assigns.id)

    authorize_url =
      socket.assigns.client
      |> socket.assigns.adapter.authorize_url(state, scopes)

    {:ok,
     socket |> assign(scopes: scopes) |> assign(authorize_url: authorize_url)}
  end

  @impl true
  def handle_event("authorize_click", _, socket) do
    {:noreply, socket |> assign(oauth_progress: :started)}
  end

  def handle_event("try_userinfo_again", _, socket) do
    Logger.debug("Attempting to retrieve userinfo again...")

    %{adapter: adapter, client: client, token: token, sandbox: sandbox} =
      socket.assigns

    wellknown_url = adapter.wellknown_url(sandbox)

    {:noreply,
     socket
     |> assign(:oauth_progress, :requesting_userinfo)
     |> start_async(:userinfo, fn ->
       get_userinfo(adapter, client, token.result, wellknown_url)
     end)}
  end

  defp maybe_fetch_userinfo(%{assigns: %{client: nil}} = socket) do
    socket
  end

  defp maybe_fetch_userinfo(socket) do
    if changed?(socket, :token) and socket.assigns.token_body_changeset.valid? do
      %{client: client, adapter: adapter, sandbox: sandbox, token: token} =
        socket.assigns

      wellknown_url = adapter.wellknown_url(sandbox)

      if Common.still_fresh(token.result) do
        start_async(socket, :userinfo, fn ->
          get_userinfo(adapter, client, token.result, wellknown_url)
        end)
      else
        start_async(socket, :token, fn ->
          refresh_token(adapter, client, token.result, wellknown_url)
        end)
      end
    else
      socket
    end
  end

  @impl true
  def handle_async(:token, {:ok, {:ok, token}}, socket) do
    %{
      client: client,
      adapter: adapter,
      sandbox: sandbox,
      update_body: update_body
    } = socket.assigns

    wellknown_url = adapter.wellknown_url(sandbox)

    parsed_token = token_to_params(token)

    update_body.(parsed_token)

    {:noreply,
     socket
     |> assign(:oauth_progress, :token_received)
     |> assign(token: AsyncResult.ok(parsed_token))
     |> start_async(:userinfo, fn ->
       get_userinfo(adapter, client, parsed_token, wellknown_url)
     end)}
  end

  def handle_async(:token, {:ok, {:error, {:token_failed, reason}}}, socket) do
    Logger.error("Failed retrieving token from provider:\n#{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:oauth_progress, :token_failed)
     |> assign(:scopes_changed, false)
     |> assign(:sandbox_changed, false)
     |> assign(token: AsyncResult.failed(%AsyncResult{}, reason))}
  end

  def handle_async(:token, {:ok, {:error, {:refresh_failed, reason}}}, socket) do
    Logger.error("Failed refreshing token from provider:\n#{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:oauth_progress, :refresh_failed)
     |> assign(:scopes_changed, false)
     |> assign(:sandbox_changed, false)
     |> assign(token: AsyncResult.failed(%AsyncResult{}, reason))}
  end

  def handle_async(:token, {:exit, reason}, socket) do
    Logger.error(reason)

    {:noreply,
     socket
     |> assign(:oauth_progress, :token_failed)
     |> assign(:scopes_changed, false)
     |> assign(:sandbox_changed, false)
     |> assign(token: AsyncResult.failed(%AsyncResult{}, "Network error"))}
  end

  def handle_async(:userinfo, {:ok, {:ok, userinfo}}, socket) do
    {:noreply,
     socket
     |> assign(:oauth_progress, :userinfo_received)
     |> assign(scopes_changed: false)
     |> assign(:sandbox_changed, false)
     |> assign(userinfo: AsyncResult.ok(userinfo))}
  end

  def handle_async(
        :userinfo,
        {:ok, {:error, {:userinfo_failed, reason}}},
        socket
      ) do
    Logger.error(
      "Failed retrieving user data from provider:\n#{inspect(reason)}"
    )

    {:noreply,
     socket
     |> assign(:oauth_progress, :userinfo_failed)
     |> assign(scopes_changed: false)
     |> assign(:sandbox_changed, false)
     |> assign(userinfo: AsyncResult.failed(%AsyncResult{}, reason))}
  end

  def handle_async(:userinfo, {:exit, reason}, socket) do
    Logger.error(inspect(reason))

    {:noreply,
     socket
     |> assign(:oauth_progress, :userinfo_failed)
     |> assign(:scopes_changed, false)
     |> assign(:sandbox_changed, false)
     |> assign(userinfo: AsyncResult.failed(%AsyncResult{}, "Network error"))}
  end

  defp get_userinfo(adapter, client, token, wellknown_url) do
    adapter.get_userinfo(client, token, wellknown_url)
    |> case do
      {:ok, resp} ->
        {:ok, resp.body}

      {:error, resp} ->
        {:error, {:userinfo_failed, resp}}
    end
  end

  defp refresh_token(adapter, client, token, wellknown_url) do
    adapter.refresh_token(client, token, wellknown_url)
    |> case do
      {:ok, fresh_token} ->
        {:ok, fresh_token}

      {:error, reason} ->
        {:error, {:refresh_failed, reason}}
    end
  end

  defp fetch_token(adapter, client, code, wellknown_url) do
    case adapter.get_token(client, wellknown_url, code: code) do
      {:ok, %{token: token} = _response} ->
        {:ok, token}

      {:error, %OAuth2.Response{body: body}} ->
        {:error, {:token_failed, body}}
    end
  end

  defp build_client(socket, wellknown_url) do
    socket.assigns.adapter.build_client(
      wellknown_url,
      callback_url: LightningWeb.RouteHelpers.oidc_callback_url()
    )
  end

  defp token_to_params(%OAuth2.AccessToken{} = token) do
    base = token |> Map.from_struct()

    {extra, base} =
      if Map.has_key?(base, :other_params) do
        expires_at = Map.get(base.other_params, "expires_at", "")
        scope = Map.get(base.other_params, "scope", "")
        instance_url = Map.get(base.other_params, "instance_url", "")

        {%{expires_at: expires_at, scope: scope, instance_url: instance_url},
         Map.delete(base, :other_params)}
      else
        {%{}, base}
      end

    Map.merge(base, extra, fn
      :expires_at, v1, v2 when v1 in [nil, ""] -> v2
      :expires_at, v1, v2 when v2 in [nil, ""] -> v1
      _k, _v1, v2 -> v2
    end)
  end

  defp params_to_token(%TokenBody{} = token) do
    struct!(
      OAuth2.AccessToken,
      token
      |> Map.from_struct()
      |> Map.filter(fn {k, _v} ->
        k in [:access_token, :refresh_token, :expires_at]
      end)
    )
  end

  defp display_loader?(oauth_progress) do
    oauth_progress not in List.flatten([:not_started | Map.values(@oauth_states)])
  end

  defp display_reauthorize_banner?(%{
         action: action,
         scopes_changed: scopes_changed,
         sandbox_changed: sandbox_changed,
         oauth_progress: oauth_progress
       }) do
    case action do
      :new ->
        (sandbox_changed || scopes_changed) &&
          oauth_progress in (@oauth_states.success ++
                               @oauth_states.failure)

      :edit ->
        (sandbox_changed || scopes_changed) && oauth_progress not in [:started]

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

  defp display_userinfo?(
         oauth_progress,
         display_reauthorize_banner,
         scopes_changed,
         sandbox_changed
       ) do
    oauth_progress == :userinfo_received && !display_reauthorize_banner &&
      !(scopes_changed or sandbox_changed)
  end

  defp display_error?(
         oauth_progress,
         display_reauthorize_banner,
         scopes_changed,
         sandbox_changed
       ) do
    oauth_progress in @oauth_states.failure && !display_reauthorize_banner &&
      !(scopes_changed || sandbox_changed)
  end

  defp update_form(assigns) do
    update(assigns, :form, fn form,
                              %{token_body_changeset: token_body_changeset} ->
      params = Map.put(form.params, "body", token_body_changeset.params)
      %{form | params: params}
    end)
  end
end
