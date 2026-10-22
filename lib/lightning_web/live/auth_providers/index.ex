defmodule LightningWeb.AuthProvidersLive.Index do
  @moduledoc """
  The OpenID Connect provider page: the configured provider on
  `/settings/authentication`, a blank form on `/new`. The page sends the
  form's values once per Save or Test; the secret never goes to the page.
  """
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :ensure_admin}

  alias Lightning.AuthProviders
  alias Lightning.AuthProviders.AuthConfig
  alias Lightning.AuthProviders.AuthConfigForm
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       active_menu_item: :authentication,
       page_title: "Authentication",
       auth_provider: nil,
       redirect_host: nil
     ), layout: {LightningWeb.Layouts, :settings}}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, _params) do
    if auth_provider = AuthProviders.get_existing() do
      redirect_host =
        URI.parse(auth_provider.redirect_uri)
        |> URI.merge("/")
        |> URI.to_string()

      assign(socket, auth_provider: auth_provider, redirect_host: redirect_host)
    else
      push_navigate(socket,
        to: Routes.auth_providers_index_path(socket, :new),
        replace: true
      )
    end
  end

  defp apply_action(socket, :new, _params) do
    assign(socket,
      auth_provider: AuthProviders.new(),
      redirect_host: LightningWeb.Endpoint.struct_url() |> URI.to_string()
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.design_system_page
      name="AdminAuthProvidersPage"
      props={%{provider: provider_json(@auth_provider, @redirect_host)}}
      current_user={@current_user}
    />
    """
  end

  # Save: the form's values as the old form's changeset, checked before
  # anything is written (the old form saved whatever was posted and said
  # "Something went wrong" when the row refused it). A blank secret keeps
  # the stored one; which provider is saved is the route's to know.
  @impl true
  def handle_event("save_provider", params, socket) when is_map(params) do
    with :ok <- authorize(socket),
         {:ok, changeset} <- form_changeset(socket, params) do
      attrs =
        changeset
        |> Ecto.Changeset.apply_changes()
        |> Map.from_struct()
        |> Map.take(
          ~w(name discovery_url client_id client_secret redirect_uri allow_unverified_email)a
        )

      save(socket, socket.assigns.live_action, attrs)
    end
  end

  # Test: fetches the discovery document with the values as typed and
  # answers with why it failed, which the page shows under the URL.
  def handle_event("test_provider", params, socket) when is_map(params) do
    with :ok <- authorize(socket),
         {:ok, changeset} <- form_changeset(socket, params) do
      case AuthConfigForm.validate_provider(changeset) do
        %{valid?: true} ->
          {:reply, %{}, socket}

        %{errors: errors} ->
          {message, _opts} = errors[:discovery_url]
          reply_error(socket, message)
      end
    end
  end

  def handle_event("remove_provider", _params, socket) do
    with :ok <- authorize(socket) do
      case socket.assigns.auth_provider do
        %AuthConfig{id: id} = auth_provider when is_binary(id) ->
          AuthProviders.remove_handler(auth_provider.name)
          AuthProviders.delete!(auth_provider)

          {:reply, %{},
           socket
           |> put_flash(:info, "Authentication Provider removed")
           |> push_navigate(to: Routes.auth_providers_index_path(socket, :new))}

        _none ->
          reply_error(socket, "No provider is configured")
      end
    end
  end

  def handle_event(event, _params, socket)
      when event in ["save_provider", "test_provider"],
      do: reply_error(socket, "Invalid request")

  # One provider: a second row would make the edit route raise (its lookup
  # is Repo.one), and the menu link lands on /new whether or not one exists.
  defp save(socket, :new, attrs) do
    if AuthProviders.get_existing() do
      reply_error(socket, "A provider is already configured. Edit it instead.")
    else
      create(socket, attrs)
    end
  end

  defp save(socket, :edit, attrs) do
    case AuthProviders.update(socket.assigns.auth_provider, attrs) do
      {:ok, model} ->
        {:reply, %{},
         socket
         |> assign(auth_provider: model)
         |> put_flash(:info, "Authentication Provider updated.")}

      {:error, %Ecto.Changeset{}} ->
        reply_error(socket, "Something went wrong.")
    end
  end

  defp create(socket, attrs) do
    case AuthProviders.create(attrs) do
      {:ok, _model} ->
        {:reply, %{},
         socket
         |> put_flash(:info, "Authentication Provider created.")
         |> push_navigate(to: Routes.auth_providers_index_path(socket, :edit))}

      {:error, %Ecto.Changeset{}} ->
        reply_error(socket, "Something went wrong.")
    end
  end

  # The mount gate is :ensure_admin; every event checks the same policy again.
  defp authorize(socket) do
    if Permissions.can?(
         Users,
         :access_admin_space,
         socket.assigns.current_user,
         {}
       ),
       do: :ok,
       else:
         reply_error(socket, "You are not authorized to perform this action.")
  end

  @strings ~w(name discoveryUrl clientId clientSecret redirectHost)

  # The page's camelCase values as the old form's changeset: named keys
  # only, strings and a boolean only; the redirect URI is derived here from
  # the host and the name, never taken from the payload. A host the URI
  # parser rejects is a field error, where the old form crashed.
  defp form_changeset(socket, params) do
    values =
      Map.new(@strings, fn key ->
        {Macro.underscore(key),
         if(is_binary(params[key]), do: params[key], else: "")}
      end)

    values =
      Map.put(
        values,
        "allow_unverified_email",
        params["allowUnverifiedEmail"] == true
      )

    values =
      case {socket.assigns.auth_provider, values["client_secret"]} do
        {%AuthConfig{client_secret: secret}, ""} when is_binary(secret) ->
          Map.put(values, "client_secret", secret)

        _ ->
          values
      end

    form_model = %{
      AuthConfigForm.from_auth_config(socket.assigns.auth_provider)
      | redirect_host: socket.assigns.redirect_host,
        redirect_path_func: fn name ->
          Routes.oidc_path(socket, :new, name || "")
        end
    }

    # The columns are varchar(255); the old form let a longer value raise on insert.
    changeset =
      Enum.reduce(
        ~w(name discovery_url client_id client_secret redirect_host redirect_uri)a,
        AuthConfigForm.change(form_model, values),
        &Ecto.Changeset.validate_length(&2, &1, max: 255)
      )

    if changeset.valid?,
      do: {:ok, changeset},
      else: reply_error(socket, changeset)
  rescue
    URI.Error ->
      {:reply,
       %{
         error: "Please fix the errors below.",
         fieldErrors: %{"redirectHost" => ["must be a valid URL"]}
       }, socket}
  end

  # The shape the design system's AuthProvider type expects: everything
  # the form shows, and whether a secret is stored rather than the secret.
  defp provider_json(nil, _redirect_host), do: nil

  defp provider_json(%AuthConfig{} = provider, redirect_host) do
    %{
      id: provider.id,
      name: provider.name || "",
      discoveryUrl: provider.discovery_url || "",
      clientId: provider.client_id || "",
      hasClientSecret: is_binary(provider.client_secret),
      redirectHost: redirect_host,
      allowUnverifiedEmail: provider.allow_unverified_email == true
    }
  end
end
