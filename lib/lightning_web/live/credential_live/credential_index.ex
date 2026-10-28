defmodule LightningWeb.CredentialLive.CredentialIndex do
  @moduledoc """
  The server half of the design system's credential index: the props it
  draws and the events it sends. A LiveView that shows the index assigns
  `current_user`, `projects` (those the viewer may share with) and
  `project` (nil on the user's own page), calls `assign_index/1`, puts
  `props/1` in its page's props and hands the index's events to
  `handle_event/3`.

  Every event looks its record up again in what the viewer may see, and the
  context asks the owner question again, whatever the page sent.

  OAuth sign-ins come back from the provider through the callback, which
  broadcasts to this LiveView: it hands `{:forward, CredentialIndex, _}` to
  `handle_info/2` and the async tasks it starts to `handle_async/3`. Each
  sign-in's token stays in this process until a save takes it; only who
  signed in reaches the page.
  """
  use LightningWeb, :verified_routes

  import LightningWeb.Components.DesignSystem, only: [reply_error: 2]
  import Phoenix.Component, only: [assign: 3, assign_new: 3]
  import Phoenix.LiveView, only: [put_flash: 3, start_async: 3]

  alias Lightning.Accounts
  alias Lightning.Adaptors
  alias Lightning.Adaptors.PackageName
  alias Lightning.AuthProviders.OauthHTTPClient
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthClient
  alias Lightning.Credentials.OauthValidation
  alias Lightning.OauthClients
  alias Lightning.Policies.Permissions
  alias Lightning.Repo
  alias LightningWeb.CredentialLive.Helpers
  alias LightningWeb.CredentialLive.OAuthErrorFormatter
  alias LightningWeb.OauthCredentialHelper

  @not_authorized "You are not authorized to perform this action"

  # The order the old form listed environments in: the primary one first.
  @primary_environments ~w(main production prod master principal primary default)

  @doc """
  Loads the credentials and OAuth clients the index shows, as the page's
  rows, so drawing the page again (a flash, a sign-in) asks nothing more.
  """
  def assign_index(socket) do
    %{current_user: user, project: project} = socket.assigns

    credentials =
      (project || user)
      |> Credentials.list_credentials()
      |> Repo.preload(:project_credentials)

    socket
    |> assign_new(:oauth_sign_ins, fn -> %{} end)
    |> assign(:credential_rows, Enum.map(credentials, &credential_row(&1, user)))
    |> assign(
      :oauth_client_rows,
      socket
      |> list_clients()
      |> Repo.preload(:user)
      |> Enum.map(&oauth_client_row(&1, user))
    )
    |> assign(:credential_types, credential_types())
  end

  @doc "The index's props (`CredentialIndexData`)."
  def props(assigns) do
    %{current_user: user, projects: projects} = assigns

    %{
      credentials: assigns.credential_rows,
      oauthClients: assigns.oauth_client_rows,
      projects: Enum.map(projects, &%{id: &1.id, name: &1.name}),
      credentialTypes: assigns.credential_types,
      oauthSignIns: sign_in_results(assigns.oauth_sign_ins),
      canCreateGlobalOauthClient: user.role == :superuser
    }
  end

  defp credential_row(credential, user) do
    can_edit = can_edit?(user, credential)

    # Only the owner, who may change the projects, is told which workflows
    # use the credential in each.
    workflows_using = if can_edit, do: workflows_using(credential), else: %{}

    %{
      id: credential.id,
      name: credential.name,
      schema: PackageName.short_name(credential.schema),
      oauthClient:
        if(credential.schema == "oauth" && credential.oauth_client,
          do: oauth_client_ref(credential.oauth_client)
        ),
      ownerEmail: credential.user.email,
      projects:
        Enum.map(credential.projects, fn project ->
          %{
            id: project.id,
            name: project.name,
            workflowsUsing: Map.get(workflows_using, project.id, [])
          }
        end),
      externalId: credential.external_id,
      environments:
        credential.credential_bodies
        |> Enum.map(& &1.name)
        |> Enum.sort_by(&sort_key/1),
      transferStatus: credential.transfer_status,
      scheduledDeletion: credential.scheduled_deletion,
      hasActivityInProjects: Credentials.has_activity_in_projects?(credential),
      canEdit: can_edit
    }
  end

  # Per credential, as the old form asked: the query answers by project.
  defp workflows_using(%Credential{project_credentials: []}), do: %{}

  defp workflows_using(credential) do
    credential.project_credentials
    |> Enum.map(& &1.id)
    |> Lightning.Workflows.project_workflows_using_credentials()
  end

  defp oauth_client_ref(client) do
    %{
      id: client.id,
      name: client.name,
      mandatoryScopes: scopes(client.mandatory_scopes),
      optionalScopes: scopes(client.optional_scopes),
      scopesDocUrl: client.scopes_doc_url || ""
    }
  end

  # A global client someone else owns is shown as GLOBAL only: its owner and
  # projects aren't the viewer's to see, as before.
  defp oauth_client_row(client, user) do
    can_edit = can_edit?(user, client)
    shown = can_edit or not client.global

    client
    |> oauth_client_ref()
    |> Map.merge(%{
      ownerEmail: if(shown, do: client.user.email, else: ""),
      global: client.global,
      projects:
        if(shown,
          do: Enum.map(client.projects, &%{id: &1.id, name: &1.name}),
          else: []
        ),
      authorizationEndpoint: client.authorization_endpoint || "",
      tokenEndpoint: client.token_endpoint || "",
      revocationEndpoint: client.revocation_endpoint || "",
      introspectionEndpoint: client.introspection_endpoint || "",
      userinfoEndpoint: client.userinfo_endpoint || "",
      canEdit: can_edit
    })
  end

  defp scopes(nil), do: []
  defp scopes(scopes), do: String.split(scopes, ",", trim: true)

  # The adaptors with a credential schema, as the old type picker offered
  # them. When the catalogue can't answer, only Raw JSON and the OAuth
  # clients are offered.
  defp credential_types do
    case Adaptors.packages() do
      {:ok, packages} ->
        packages
        |> Enum.filter(& &1.has_schema)
        |> Enum.reject(
          &(&1.name in [
              "@openfn/language-googlesheets",
              "@openfn/language-gmail"
            ])
        )
        |> Enum.map(fn %{name: name} ->
          short = PackageName.short_name(name)
          %{key: short, name: short}
        end)
        |> Enum.sort_by(&String.downcase(&1.name))

      {:error, _reason} ->
        []
    end
  end

  defp can_edit?(user, credential_or_client),
    do: Permissions.can?(:users, :edit_credential, user, credential_or_client)

  # --- Events ---

  @doc "Answers one of the index's events."
  def handle_event("create_credential", params, socket) do
    %{current_user: user} = socket.assigns

    with :ok <- may_create(socket),
         {:ok, schema} <- resolve_schema(params["schema"]),
         {:ok, client} <- oauth_client_for(socket, schema, params),
         sign_ins = sign_ins_for(socket, params, nil, client),
         {:ok, bodies} <- environment_bodies(params, schema, %{}, sign_ins) do
      params
      |> credential_attrs(%Credential{}, socket)
      |> Map.merge(%{
        "user_id" => user.id,
        "schema" => schema,
        "oauth_client_id" => client && client.id,
        "credential_bodies" => bodies
      })
      |> Credentials.create_credential(user)
      |> saved(socket, "Credential created successfully", params)
    else
      {:error, reason} -> refuse(socket, reason)
    end
  end

  def handle_event("update_credential", %{"id" => id} = params, socket) do
    with {:ok, credential} <- editable_credential(socket, id),
         stored = stored_bodies(credential),
         sign_ins =
           sign_ins_for(socket, params, credential.id, credential.oauth_client),
         {:ok, bodies} <-
           environment_bodies(params, credential.schema, stored, sign_ins) do
      attrs =
        params
        |> credential_attrs(credential, socket)
        |> Map.merge(%{
          "credential_bodies" => bodies,
          "delete_environments" =>
            Map.keys(stored) -- Enum.map(bodies, & &1["name"])
        })

      credential
      |> Credentials.update_credential(attrs, socket.assigns.current_user)
      |> saved(socket, "Credential updated successfully", params)
    else
      {:error, reason} -> refuse(socket, reason)
    end
  end

  def handle_event("load_credential_secrets", %{"id" => id}, socket) do
    with_credential(socket, id, fn credential ->
      # One without stored bodies opens on an empty "main", as before.
      environments =
        case stored_bodies(credential) do
          stored when map_size(stored) == 0 -> %{"main" => %{}}
          stored -> stored
        end
        |> Enum.sort_by(fn {name, _} -> sort_key(name) end)
        |> Enum.map(fn {name, body} ->
          %{
            name: name,
            body: body_text(credential.schema, body),
            oauth: stored_token(credential, name, body)
          }
        end)

      {:reply, %{environments: environments}, socket}
    end)
  end

  def handle_event("load_credential_schema", %{"key" => key}, socket)
      when is_binary(key) do
    case Credentials.get_schema(key) do
      {:ok, schema} ->
        {:reply, %{fields: Enum.map(schema.fields, &schema_field(schema, &1))},
         socket}

      {:error, :not_found} ->
        reply_error(socket, "This adaptor isn't in the adaptor catalogue.")

      {:error, _reason} ->
        reply_error(socket, "Couldn't load adaptors. Please try again.")
    end
  end

  def handle_event("delete_credential", %{"id" => id} = params, socket) do
    user = socket.assigns.current_user

    with_credential(socket, id, fn credential ->
      cond do
        params["now"] != true ->
          credential
          |> Credentials.schedule_credential_deletion(user)
          |> done(socket, "Credential scheduled for deletion")

        # Deleting for good skips the grace period, so only a credential
        # already scheduled may be, as before.
        is_nil(credential.scheduled_deletion) ->
          reply_error(socket, "You can't perform this action")

        Credentials.has_activity_in_projects?(credential) ->
          reply_error(
            socket,
            "Cannot delete a credential that has activities in projects"
          )

        true ->
          credential
          |> Credentials.delete_credential(user)
          |> done(socket, "Credential deleted successfully")
      end
    end)
  end

  def handle_event("cancel_credential_deletion", %{"id" => id}, socket) do
    with_credential(socket, id, fn credential ->
      credential.id
      |> Credentials.cancel_scheduled_deletion(socket.assigns.current_user)
      |> done(socket, "Credential deletion canceled")
    end)
  end

  def handle_event("transfer_credential", %{"id" => id} = params, socket) do
    owner = socket.assigns.current_user
    email = params["receiverEmail"]

    with {:ok, credential} <- editable_credential(socket, id),
         %{valid?: true} <-
           email
           |> Credentials.credential_transfer_changeset()
           |> Credentials.validate_credential_transfer(owner, credential),
         %Accounts.User{} = receiver <- Accounts.get_user_by_email(email),
         :ok <-
           Credentials.initiate_credential_transfer(owner, receiver, credential) do
      done(
        {:ok, credential},
        socket,
        "Credential transfer initiated. We've sent you a confirmation email."
      )
    else
      {:error, message} when is_binary(message) ->
        reply_error(socket, message)

      %Ecto.Changeset{} = changeset ->
        {:reply, reply, socket} = reply_error(socket, changeset)

        {:reply,
         Map.update!(reply, :fieldErrors, fn errors ->
           Map.new(errors, fn
             {"email", messages} -> {"receiverEmail", messages}
             other -> other
           end)
         end), socket}

      nil ->
        reply_error(socket, "User not found")

      {:error, %Ecto.Changeset{} = changeset} ->
        reply_error(socket, changeset)

      {:error, _reason} ->
        reply_error(socket, "Transfer failed. Please try again.")
    end
  end

  def handle_event("revoke_credential_transfer", %{"id" => id}, socket) do
    with_credential(socket, id, fn credential ->
      credential.id
      |> Credentials.revoke_transfer(socket.assigns.current_user)
      |> done(socket, "Transfer revoked successfully")
    end)
  end

  def handle_event(
        "authorize_oauth",
        %{"formId" => form_id, "signInId" => sign_in_id} = params,
        socket
      )
      when is_binary(form_id) and is_binary(sign_in_id) do
    with false <- Map.has_key?(socket.assigns.oauth_sign_ins, sign_in_id),
         {:ok, client} <-
           oauth_client_for(socket, "oauth", Map.take(params, ["oauthClientId"])),
         :ok <- sign_in_credential(socket, params["credentialId"], client) do
      # The provider's callback names this sign-in by a reference of our
      # own, not the page's id, and only this LiveView hears it.
      ref = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      scopes = requested_scopes(client, params["scopes"])

      sign_in = %{
        id: sign_in_id,
        ref: ref,
        form_id: form_id,
        credential_id: params["credentialId"],
        client: client,
        scopes: scopes,
        state: :pending,
        token: nil,
        user_info: nil,
        error: nil,
        finished: nil
      }

      if map_size(socket.assigns.oauth_sign_ins) == 0,
        do: OauthCredentialHelper.subscribe(socket.id)

      authorize_url =
        OauthHTTPClient.generate_authorize_url(client,
          state:
            OauthCredentialHelper.build_state(
              socket.id,
              __MODULE__,
              ref,
              "oauth"
            ),
          scope: Enum.join(scopes, " ")
        )

      {:reply, %{authorizeUrl: authorize_url},
       update_sign_ins(socket, &Map.put(&1, sign_in_id, sign_in))}
    else
      _refused -> reply_error(socket, @not_authorized)
    end
  end

  def handle_event("discard_oauth_sign_ins", %{"formId" => form_id}, socket) do
    {:reply, %{}, drop_sign_ins(socket, form_id)}
  end

  def handle_event("create_oauth_client", params, socket) do
    user = socket.assigns.current_user

    case may_create(socket) do
      :ok ->
        params
        |> oauth_client_attrs(%OauthClient{}, socket)
        |> Map.put("user_id", user.id)
        |> OauthClients.create_client(user,
          allow_global: user.role == :superuser
        )
        |> saved(socket, "Oauth client created successfully", params)

      {:error, message} ->
        reply_error(socket, message)
    end
  end

  def handle_event("update_oauth_client", %{"id" => id} = params, socket) do
    user = socket.assigns.current_user

    with_client(socket, id, fn client ->
      client
      |> OauthClients.update_client(
        oauth_client_attrs(params, client, socket),
        user,
        allow_global: user.role == :superuser
      )
      |> saved(socket, "Oauth client updated successfully", params)
    end)
  end

  def handle_event("load_oauth_client_secrets", %{"id" => id}, socket) do
    with_client(socket, id, fn client ->
      {:reply,
       %{
         clientId: client.client_id || "",
         clientSecret: client.client_secret || ""
       }, socket}
    end)
  end

  def handle_event("delete_oauth_client", %{"id" => id}, socket) do
    with_client(socket, id, fn client ->
      client
      |> OauthClients.delete_client(socket.assigns.current_user)
      |> done(socket, "Oauth client deleted")
    end)
  end

  # An event without the id it needs, or one the index doesn't send.
  def handle_event(_event, _params, socket),
    do: reply_error(socket, @not_authorized)

  # --- OAuth sign-in ---

  @doc """
  The provider's answer to a sign-in, broadcast by the OAuth callback: a
  code to exchange for a token, or an error. One this page isn't waiting
  for (unknown, discarded or answered already) is ignored.
  """
  def handle_info({:forward, __MODULE__, %{id: ref} = answer}, socket) do
    case Enum.find(socket.assigns.oauth_sign_ins, fn {_id, s} ->
           s.ref == ref and s.state == :pending
         end) do
      nil ->
        {:noreply, socket}

      {id, %{client: client, scopes: scopes}} ->
        socket = put_sign_in(socket, id, %{state: :fetching})

        case answer do
          %{code: code} ->
            {:noreply,
             start_async(socket, {:oauth_sign_in, id}, fn ->
               fetch_sign_in(client, code, scopes)
             end)}

          %{error: error} ->
            {:noreply,
             finish_sign_in(socket, id, {:error, {:code_exchange_failed, error}})}
        end
    end
  end

  @doc "How a sign-in's token exchange (started by `handle_info/2`) ended."
  def handle_async({:oauth_sign_in, id}, {:ok, result}, socket),
    do: {:noreply, finish_sign_in(socket, id, result)}

  def handle_async({:oauth_sign_in, id}, {:exit, reason}, socket),
    do: {:noreply, finish_sign_in(socket, id, {:error, {:task_crashed, reason}})}

  # Runs in a task: the token for the code, checked as the old form did,
  # and who signed in.
  defp fetch_sign_in(client, code, scopes) do
    expected =
      scopes
      |> Enum.map(&String.downcase/1)
      |> Enum.reject(&(&1 == "offline_access"))

    with {:ok, token} <- http(OauthHTTPClient.fetch_token(client, code)),
         token = Credentials.normalize_token_expiry(token),
         {:ok, _token} <- OauthValidation.validate_token_data(token),
         :ok <- OauthValidation.validate_scope_grant(token, expected),
         {:ok, user_info} <- user_info(client, token) do
      {:ok, token, user_info}
    end
  end

  defp http({:error, error}), do: {:error, {:http_error, error}}
  defp http(ok), do: ok

  # Who signed in, when the client has a userinfo endpoint. A token the
  # provider no longer accepts is an error; any other failure only loses
  # the name, as before.
  defp user_info(%OauthClient{userinfo_endpoint: endpoint}, _token)
       when endpoint in [nil, ""],
       do: {:ok, nil}

  defp user_info(client, token) do
    case OauthHTTPClient.fetch_userinfo(client, token) do
      {:ok, info} ->
        {:ok, %{name: info["name"], email: info["email"]}}

      {:error, %{status: 401}} ->
        {:error,
         OauthValidation.Error.new(
           :invalid_access_token,
           "The access token is no longer valid"
         )}

      {:error, _error} ->
        {:ok, nil}
    end
  end

  # A sign-in discarded while its task ran is gone: nothing to finish.
  defp finish_sign_in(socket, id, result) do
    case socket.assigns.oauth_sign_ins[id] do
      %{client: client} ->
        outcome =
          case result do
            {:ok, token, user_info} ->
              %{token: token, user_info: user_info}

            {:error, error} ->
              %{message: message, details: details} =
                OAuthErrorFormatter.format_error(error, client.name)

              %{
                error: Enum.join(Enum.reject([message, details], &is_nil/1), " ")
              }
          end

        put_sign_in(
          socket,
          id,
          Map.merge(outcome, %{
            state: :done,
            finished: System.unique_integer([:monotonic])
          })
        )

      nil ->
        socket
    end
  end

  defp put_sign_in(socket, id, changes) do
    update_sign_ins(socket, fn sign_ins ->
      Map.update!(sign_ins, id, &Map.merge(&1, changes))
    end)
  end

  defp update_sign_ins(socket, fun),
    do: assign(socket, :oauth_sign_ins, fun.(socket.assigns.oauth_sign_ins))

  defp drop_sign_ins(socket, form_id) do
    update_sign_ins(socket, fn sign_ins ->
      Map.reject(sign_ins, fn {_id, s} -> s.form_id == form_id end)
    end)
  end

  defp sign_in_results(sign_ins) do
    sign_ins
    |> Map.values()
    |> Enum.filter(&(&1.state == :done))
    |> Enum.sort_by(& &1.finished)
    |> Enum.map(&%{signInId: &1.id, error: &1.error, userInfo: &1.user_info})
  end

  # A sign-in for a credential being edited must be for that credential's
  # own client.
  defp sign_in_credential(_socket, nil, _client), do: :ok

  defp sign_in_credential(socket, id, client) do
    case editable_credential(socket, id) do
      {:ok, %Credential{schema: "oauth", oauth_client_id: client_id}}
      when client_id == client.id ->
        :ok

      _refused ->
        {:error, @not_authorized}
    end
  end

  # The client's mandatory scopes and the others the user ticked.
  defp requested_scopes(client, requested) do
    requested =
      if is_list(requested), do: Enum.filter(requested, &is_binary/1), else: []

    Enum.uniq(
      OauthValidation.normalize_scopes(client.mandatory_scopes, ",") ++
        requested
    )
  end

  # What a save may take a sign-in's token for: this form, this credential
  # (nil when new) and this client.
  defp sign_ins_for(socket, params, credential_id, client) do
    %{
      form_id: params["formId"],
      credential_id: credential_id,
      client_id: client && client.id,
      sign_ins: socket.assigns.oauth_sign_ins
    }
  end

  # An OAuth environment's stored token, as the edit form shows it. An
  # expired one is refreshed and saved first, as a run would.
  defp stored_token(%Credential{schema: "oauth"} = credential, name, body) do
    {status, token} = checked_token(credential, name, body)

    {status, user_info} =
      case status == "ready" && user_info(credential.oauth_client, token) do
        {:ok, user_info} -> {"ready", user_info}
        {:error, _invalid} -> {"reauthorize", nil}
        false -> {status, nil}
      end

    %{
      scopes: OauthValidation.normalize_scopes(token),
      status: status,
      userInfo: user_info
    }
  end

  defp stored_token(_credential, _name, _body), do: nil

  defp checked_token(credential, name, body) do
    if is_nil(credential.oauth_client) or
         not Map.has_key?(body, "access_token") do
      {"reauthorize", body}
    else
      case Credentials.resolve_credential_body(credential, name) do
        {:ok, token} -> {"ready", token}
        {:error, :reauthorization_required} -> {"reauthorize", body}
        {:error, _reason} -> {"unavailable", body}
      end
    end
  end

  # --- Lookups: only what the index shows, and only the owner may change it ---

  # Anyone may add to their own list; adding from a project's settings asks
  # the project, as its "Add new" menu did.
  defp may_create(%{assigns: %{project: nil}}), do: :ok

  defp may_create(%{assigns: %{project: project, current_user: user}}) do
    if Permissions.can?(
         :project_users,
         :create_project_credential,
         user,
         project
       ),
       do: :ok,
       else: {:error, @not_authorized}
  end

  defp with_credential(socket, id, fun) do
    case editable_credential(socket, id) do
      {:ok, credential} -> fun.(credential)
      {:error, message} -> reply_error(socket, message)
    end
  end

  defp with_client(socket, id, fun) do
    case editable_client(socket, id) do
      {:ok, client} -> fun.(client)
      {:error, message} -> reply_error(socket, message)
    end
  end

  defp editable_credential(socket, id) do
    case Enum.find(fresh_credentials(socket), &(&1.id == id)) do
      %Credential{} = credential ->
        if can_edit?(socket.assigns.current_user, credential),
          do: {:ok, credential},
          else: {:error, @not_authorized}

      nil ->
        {:error, @not_authorized}
    end
  end

  defp fresh_credentials(socket) do
    %{current_user: user, project: project} = socket.assigns
    Credentials.list_credentials(project || user)
  end

  defp list_clients(socket) do
    %{current_user: user, project: project} = socket.assigns
    OauthClients.list_clients(project || user)
  end

  defp editable_client(socket, id) do
    user = socket.assigns.current_user

    case Enum.find(list_clients(socket), &(&1.id == id)) do
      %OauthClient{} = client ->
        if can_edit?(user, client),
          do: {:ok, client},
          else: {:error, @not_authorized}

      nil ->
        {:error, @not_authorized}
    end
  end

  # --- Saving ---

  defp credential_attrs(params, credential, socket) do
    %{
      "name" => params["name"],
      "external_id" => blank_to_nil(params["externalId"]),
      "project_credentials" =>
        project_assocs(
          Credentials.change_credential(
            Repo.preload(credential, :project_credentials)
          ),
          :project_credentials,
          params["projectIds"],
          socket
        )
    }
  end

  defp oauth_client_attrs(params, client, socket) do
    %{
      "name" => params["name"],
      "authorization_endpoint" => params["authorizationEndpoint"],
      "token_endpoint" => params["tokenEndpoint"],
      "revocation_endpoint" => params["revocationEndpoint"],
      "introspection_endpoint" => params["introspectionEndpoint"],
      "userinfo_endpoint" => params["userinfoEndpoint"],
      "client_id" => params["clientId"],
      "client_secret" => params["clientSecret"],
      "mandatory_scopes" => join_scopes(params["mandatoryScopes"]),
      "optional_scopes" => join_scopes(params["optionalScopes"]),
      "scopes_doc_url" => params["scopesDocUrl"],
      "global" => params["global"] == true,
      "project_oauth_clients" =>
        project_assocs(
          OauthClients.change_client(
            Repo.preload(client, :project_oauth_clients)
          ),
          :project_oauth_clients,
          params["projectIds"],
          socket
        )
    }
  end

  defp join_scopes(scopes) when is_list(scopes), do: Enum.join(scopes, ",")
  defp join_scopes(_scopes), do: ""

  # The projects to keep are those still listed; one may only be added if
  # the viewer can share with it, whatever ids the page sent.
  defp project_assocs(changeset, key, project_ids, socket) do
    project_ids = if is_list(project_ids), do: project_ids, else: []
    shareable = MapSet.new(socket.assigns.projects, & &1.id)

    existing =
      changeset
      |> Ecto.Changeset.fetch_field!(key)
      |> MapSet.new(& &1.project_id)

    selected =
      project_ids
      |> Enum.filter(
        &(MapSet.member?(existing, &1) or MapSet.member?(shareable, &1))
      )
      |> Enum.uniq()
      |> Enum.map(&%{id: &1})

    Helpers.prepare_projects_associations(changeset, selected, key)
  end

  defp resolve_schema(schema) when is_binary(schema) do
    case Adaptors.resolve_name(schema) do
      {:ok, resolved} -> {:ok, resolved}
      {:error, _reason} -> {:error, "Couldn't load adaptors. Please try again."}
    end
  end

  defp resolve_schema(_schema), do: {:error, @not_authorized}

  defp oauth_client_for(socket, "oauth", %{"oauthClientId" => id}) do
    case Enum.find(list_clients(socket), &(&1.id == id)) do
      %OauthClient{} = client -> {:ok, client}
      nil -> {:error, @not_authorized}
    end
  end

  defp oauth_client_for(_socket, "oauth", _params),
    do: {:error, @not_authorized}

  defp oauth_client_for(_socket, _schema, _params), do: {:ok, nil}

  defp stored_bodies(credential) do
    credential
    |> Repo.preload(:credential_bodies, force: true)
    |> Map.fetch!(:credential_bodies)
    |> Map.new(&{&1.name, &1.body || %{}})
  end

  # Each environment the form sent, with its body. An OAuth environment
  # keeps the token stored under its previous name.
  defp environment_bodies(
         %{"environments" => [_ | _] = environments},
         schema,
         stored,
         sign_ins
       ) do
    named =
      environments |> Enum.map(& &1["signInId"]) |> Enum.reject(&is_nil/1)

    # A sign-in named by two environments is taken by neither.
    sign_ins =
      if named == Enum.uniq(named),
        do: sign_ins,
        else: %{sign_ins | sign_ins: %{}}

    Enum.reduce_while(environments, {:ok, []}, fn env, {:ok, acc} ->
      case environment_body(env, schema, stored, sign_ins) do
        {:ok, body} ->
          {:cont, {:ok, acc ++ [%{"name" => env["name"], "body" => body}]}}

        {:error, message} ->
          {:halt, {:error, environment_error(env["name"], message)}}
      end
    end)
  end

  defp environment_bodies(_params, _schema, _stored, _sign_ins),
    do: {:error, @not_authorized}

  # A sign-in's token, only for the form, credential and client it was
  # started with; without one, the token stored under its previous name.
  defp environment_body(env, "oauth", stored, sign_ins) do
    %{form_id: form_id, credential_id: credential_id, client_id: client_id} =
      sign_ins

    case {env["signInId"], Map.fetch(stored, env["previousName"] || "")} do
      {nil, {:ok, token}} ->
        {:ok, token}

      {nil, :error} ->
        {:error, "Sign in with the provider first."}

      {id, _stored} ->
        case sign_ins.sign_ins[id] do
          %{
            state: :done,
            token: %{} = token,
            form_id: ^form_id,
            credential_id: ^credential_id,
            client: %{id: ^client_id}
          } ->
            {:ok, token}

          _refused ->
            {:error, "Sign in with the provider first."}
        end
    end
  end

  defp environment_body(%{"body" => body}, _schema, _stored, _sign_ins)
       when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> {:error, "Invalid JSON format"}
    end
  end

  defp environment_body(_env, _schema, _stored, _sign_ins),
    do: {:error, "Invalid JSON format"}

  defp environment_error(name, message),
    do: {:field_errors, %{"environments.#{name}" => [message]}}

  defp refuse(socket, {:field_errors, errors}) do
    {:reply, %{error: "Please fix the errors below.", fieldErrors: errors},
     socket}
  end

  defp refuse(socket, message), do: reply_error(socket, message)

  # A saved form's sign-ins are used, or no longer wanted.
  defp saved({:ok, _record}, socket, message, params),
    do: done({:ok, nil}, drop_sign_ins(socket, params["formId"]), message)

  defp saved({:error, :unauthorized}, socket, _message, _params),
    do: reply_error(socket, @not_authorized)

  defp saved({:error, %Ecto.Changeset{} = changeset}, socket, _message, params),
    do: socket |> reply_error(changeset) |> environment_field_errors(params)

  # A stored OAuth token the save checks again and refuses.
  defp saved({:error, %OauthValidation.Error{message: message}}, socket, _, _),
    do: reply_error(socket, message)

  defp saved({:error, _reason}, socket, _message, _params),
    do: reply_error(socket, "Something went wrong. Please try again.")

  # A body's errors come back on `credential_bodies`, numbered from 1 in the
  # order the form sent them; the form puts them under that environment.
  defp environment_field_errors({:reply, reply, socket}, params) do
    names = Enum.map(params["environments"] || [], & &1["name"])

    errors =
      Enum.reduce(reply.fieldErrors, %{}, fn
        {"credentialBodies", messages}, acc ->
          Enum.reduce(messages, acc, fn message, acc ->
            key =
              case Regex.run(~r/^Environment (\d+): /, message) do
                [_, n] ->
                  "environments.#{Enum.at(names, String.to_integer(n) - 1)}"

                nil ->
                  "credentialBodies"
              end

            Map.update(acc, key, [message], &(&1 ++ [message]))
          end)

        {key, messages}, acc ->
          Map.put(acc, key, messages)
      end)

    {:reply, %{reply | fieldErrors: errors}, socket}
  end

  defp done({:ok, _}, socket, message) do
    {:reply, %{}, socket |> put_flash(:info, message) |> assign_index()}
  end

  defp done({:error, :unauthorized}, socket, _message),
    do: reply_error(socket, @not_authorized)

  defp done({:error, :not_owner}, socket, _message),
    do: reply_error(socket, @not_authorized)

  defp done({:error, _reason}, socket, _message),
    do: reply_error(socket, "Something went wrong. Please try again.")

  # --- Shapes ---

  defp body_text("oauth", _body), do: ""
  defp body_text(_schema, body), do: Jason.encode!(body, pretty: true)

  defp sort_key(name) do
    case Enum.find_index(@primary_environments, &(&1 == name)) do
      nil -> {1, name}
      index -> {0, index}
    end
  end

  defp schema_field(schema, field) do
    properties = Credentials.Schema.properties(schema, field)

    %{
      key: to_string(field),
      label: Map.get(properties, "title") || to_string(field),
      kind: field_kind(properties),
      required: Credentials.Schema.required?(schema, field),
      placeholder: Map.get(properties, "placeholder"),
      unrecognizedType: Credentials.Schema.warning(schema, field)
    }
  end

  # As JsonSchemaBodyComponent's input_type draws them.
  defp field_kind(%{"format" => "uri"}), do: "url"
  defp field_kind(%{"type" => "string", "writeOnly" => true}), do: "password"
  defp field_kind(%{"type" => "integer"}), do: "integer"
  defp field_kind(%{"type" => "object"}), do: "object"
  defp field_kind(%{"type" => "boolean"}), do: "boolean"
  defp field_kind(_properties), do: "text"

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
