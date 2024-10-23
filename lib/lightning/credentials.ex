defmodule Lightning.Credentials do
  @moduledoc """
  The Credentials context.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query, warn: false
  import Lightning.Helpers, only: [coerce_json_field: 2]

  alias Ecto.Multi
  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserNotifier
  alias Lightning.AuthProviders.Common
  alias Lightning.AuthProviders.OauthHTTPClient
  alias Lightning.Credentials
  alias Lightning.Credentials.Audit
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthClient
  alias Lightning.Credentials.SchemaDocument
  alias Lightning.Credentials.SensitiveValues
  alias Lightning.Projects.Project
  alias Lightning.Repo

  require Logger

  @doc """
  Perform, when called with %{"type" => "purge_deleted"}
  will find credentials that are ready for permanent deletion, set their bodies
  to null, and try to purge them.
  """

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "purge_deleted"}}) do
    credentials_to_update =
      from(c in Credential,
        where: c.scheduled_deletion <= ago(0, "second")
      )
      |> Repo.all()

    credentials_with_empty_body =
      for credential <- credentials_to_update,
          {:ok, updated_credential} <- [
            update_credential(credential, %{body: %{}})
          ],
          do: updated_credential

    credentials_to_delete =
      Enum.filter(credentials_with_empty_body, fn credential ->
        !has_activity_in_projects?(credential)
      end)

    deleted_count =
      Enum.reduce(credentials_to_delete, 0, fn credential, acc ->
        case delete_credential(credential) do
          :ok -> acc + 1
          _error -> acc
        end
      end)

    {:ok, %{deleted_count: deleted_count}}
  end

  @doc """
  Retrieves all credentials based on the given context, either a Project or a User.

  ## Parameters

    - context: The Project or User struct to retrieve credentials for.

  ## Returns

    - A list of credentials associated with the given Project or created by the given User.

  ## Examples

    When given a Project:
      iex> list_credentials(%Project{id: 1})
      [%Credential{project_id: 1}, %Credential{project_id: 1}]

    When given a User:
      iex> list_credentials(%User{id: 123})
      [%Credential{user_id: 123}, %Credential{user_id: 123}]
  """
  def list_credentials(%Project{} = project) do
    Ecto.assoc(project, :credentials)
    |> preload([:user, :project_credentials, :projects, :oauth_client])
    |> Repo.all()
  end

  def list_credentials(%User{id: user_id}) do
    from(c in Credential,
      where: c.user_id == ^user_id,
      preload: [:projects, :oauth_client]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single credential.

  Raises `Ecto.NoResultsError` if the Credential does not exist.

  ## Examples

      iex> get_credential!(123)
      %Credential{}

      iex> get_credential!(456)
      ** (Ecto.NoResultsError)

  """
  def get_credential!(id), do: Repo.get!(Credential, id)

  def get_credential_by_project_credential(project_credential_id) do
    query =
      from c in Credential,
        join: pc in assoc(c, :project_credentials),
        on: pc.id == ^project_credential_id

    Repo.one(query)
  end

  def get_credential_for_update!(id) do
    Credential
    |> Repo.get!(id)
    |> Repo.preload([:project_credentials, :projects])
  end

  @doc """
  Creates a credential.

  ## Examples

      iex> create_credential(%{field: value})
      {:ok, %Credential{}}

      iex> create_credential(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_credential(attrs \\ %{}) do
    changeset =
      %Credential{}
      |> change_credential(attrs)

    Multi.new()
    |> Multi.insert(
      :credential,
      changeset
    )
    |> derive_events(changeset)
    |> Repo.transaction()
    |> case do
      {:error, _op, changeset, _changes} ->
        {:error, changeset}

      {:ok, %{credential: credential}} ->
        {:ok, credential}
    end
  end

  @doc """
  Updates a credential.

  ## Examples

      iex> update_credential(credential, %{field: new_value})
      {:ok, %Credential{}}

      iex> update_credential(credential, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_credential(%Credential{} = credential, attrs) do
    changeset =
      credential
      |> change_credential(attrs)
      |> cast_body_change()

    Multi.new()
    |> Multi.update(:credential, changeset)
    |> derive_events(changeset)
    |> Repo.transaction()
    |> case do
      {:error, :credential, changeset, _changes} ->
        {:error, changeset}

      {:ok, %{credential: credential}} ->
        Lightning.Repo.get(Lightning.Credentials.Credential, credential.id)
        |> Map.get(:body)

        {:ok, credential}
    end
  end

  @doc """
  Creates a credential schema from credential json schema.
  """
  @spec get_schema(String.t()) :: Credentials.Schema.t()
  # false positive, it's safe file path (path from config)
  # sobelow_skip ["Traversal.FileModule"]
  def get_schema(schema_name) do
    {:ok, schemas_path} = Application.fetch_env(:lightning, :schemas_path)

    File.read("#{schemas_path}/#{schema_name}.json")
    |> case do
      {:ok, raw_json} ->
        Credentials.Schema.new(raw_json, schema_name)

      {:error, reason} ->
        raise "Error reading credential schema. Got: #{reason |> inspect()}"
    end
  end

  defp cast_body_change(
         %Ecto.Changeset{valid?: true, changes: %{body: body}} = changeset
       ) do
    schema_name = Ecto.Changeset.get_field(changeset, :schema)

    case put_typed_body(body, schema_name) do
      {:ok, updated_body} ->
        Ecto.Changeset.put_change(changeset, :body, updated_body)

      {:error, _reason} ->
        Ecto.Changeset.add_error(changeset, :body, "Invalid body types")
    end
  end

  defp cast_body_change(changeset), do: changeset

  defp put_typed_body(body, schema_name)
       when schema_name in ["raw", "salesforce_oauth", "googlesheets", "oauth"],
       do: {:ok, body}

  defp put_typed_body(body, schema_name) do
    schema = get_schema(schema_name)

    with changeset <- SchemaDocument.changeset(body, schema: schema),
         {:ok, typed_body} <- Ecto.Changeset.apply_action(changeset, :insert) do
      updated_body =
        Enum.into(typed_body, body, fn {field, typed_value} ->
          {to_string(field), typed_value}
        end)

      {:ok, updated_body}
    end
  end

  defp derive_events(
         multi,
         %Ecto.Changeset{data: %Credential{__meta__: %{state: state}}} =
           changeset
       ) do
    case changeset.changes do
      map when map_size(map) == 0 ->
        multi

      _ ->
        project_credentials_multi =
          Ecto.Changeset.get_change(changeset, :project_credentials, [])
          |> Enum.reduce(Multi.new(), fn changeset, multi ->
            derive_event(multi, changeset)
          end)

        multi
        |> Multi.insert(
          :audit,
          fn %{credential: credential} ->
            %{id: id, user: user} = credential |> Repo.preload(:user)

            Audit.event(
              if(state == :built, do: "created", else: "updated"),
              id,
              user,
              changeset
            )
          end
        )
        |> Multi.append(project_credentials_multi)
    end
  end

  defp derive_event(
         multi,
         %Ecto.Changeset{
           action: :delete,
           data: %Lightning.Projects.ProjectCredential{}
         } = changeset
       ) do
         IO.puts("HHHHHHHHHHHHHHEEEEEEEEEEEEEEERRRRRRRRREEEEEEEEEEEEEEEE!")
    Multi.insert(
      multi,
      {:audit, Ecto.Changeset.get_field(changeset, :project_id)},
      fn %{credential: credential} ->
        Audit.event(
          "removed_from_project",
          credential.id,
          credential.user,
          %{
            before: %{
              project_id: Ecto.Changeset.get_field(changeset, :project_id)
            },
            after: %{project_id: nil}
          }
        )
      end
    )
  end

  defp derive_event(
         multi,
         %Ecto.Changeset{
           action: :insert,
           data: %Lightning.Projects.ProjectCredential{}
         } = changeset
       ) do
    Multi.insert(
      multi,
      {:audit, Ecto.Changeset.get_field(changeset, :project_id)},
      fn %{credential: credential} ->
        %{id: id, user: user} = credential |> Repo.preload(:user)

        Audit.event("added_to_project", id, user, %{
          before: %{project_id: nil},
          after: %{
            project_id: Ecto.Changeset.get_field(changeset, :project_id)
          }
        })
      end
    )
  end

  defp derive_event(multi, %Ecto.Changeset{
         action: :update,
         data: %Lightning.Projects.ProjectCredential{}
       }) do
    multi
  end

  @doc """
  Deletes a credential.

  ## Examples

      iex> delete_credential(credential)
      {:ok, %Credential{}}

      iex> delete_credential(credential)
      {:error, %Ecto.Changeset{}}

  """
  def delete_credential(%Credential{} = credential) do
    Multi.new()
    |> Multi.delete(:credential, credential)
    |> Multi.insert(:audit, fn _ ->
      %{id: id, user: user} = credential |> Repo.preload(:user)

      Audit.event("deleted", id, user)
    end)
    |> Repo.transaction()
  end

  @doc """
  Schedules a given credential for deletion.

  The deletion date is determined based on the `:purge_deleted_after_days` configuration
  in the application environment. If this configuration is absent, the credential is scheduled
  for immediate deletion.

  The function will also perform necessary side effects such as:
    - Removing associations of the credential.
    - Notifying the owner of the credential about the scheduled deletion.

  ## Parameters

    - `credential`: A `Credential` struct that is to be scheduled for deletion.

  ## Returns

    - `{:ok, credential}`: Returns an `:ok` tuple with the updated credential struct if the
      update was successful.
    - `{:error, changeset}`: Returns an `:error` tuple with the changeset if the update failed.

  ## Examples

      iex> schedule_credential_deletion(%Credential{id: some_id})
      {:ok, %Credential{}}

      iex> schedule_credential_deletion(%Credential{})
      {:error, %Ecto.Changeset{}}

  """
  def schedule_credential_deletion(%Credential{} = credential) do
    date = scheduled_deletion_date()

    changeset =
      Credential.changeset(credential, %{
        "scheduled_deletion" => date
      })

    case Repo.update(changeset) do
      {:ok, updated_credential} ->
        remove_credential_associations(updated_credential)
        maybe_revoke_oauth(updated_credential)
        notify_owner(updated_credential)
        {:ok, updated_credential}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp scheduled_deletion_date do
    days = Lightning.Config.purge_deleted_after_days() || 0
    DateTime.utc_now() |> Timex.shift(days: days)
  end

  def cancel_scheduled_deletion(credential_id) do
    get_credential!(credential_id)
    |> update_credential(%{
      scheduled_deletion: nil
    })
  end

  defp maybe_revoke_oauth(%Credential{oauth_client_id: nil}), do: :ok

  defp maybe_revoke_oauth(%Credential{
         oauth_client_id: oauth_client_id,
         body: body
       }) do
    client = Repo.get(OauthClient, oauth_client_id)

    if client.revocation_endpoint do
      OauthHTTPClient.revoke_token(client, body)
    end
  end

  defp remove_credential_associations(%Credential{id: credential_id}) do
    project_credential_ids_query =
      from(pc in Lightning.Projects.ProjectCredential,
        where: pc.credential_id == ^credential_id,
        select: pc.id
      )

    project_credential_ids = Repo.all(project_credential_ids_query)

    from(j in Lightning.Workflows.Job,
      where: j.project_credential_id in ^project_credential_ids
    )
    |> Repo.update_all(set: [project_credential_id: nil])

    Ecto.assoc(%Credential{id: credential_id}, :project_credentials)
    |> Repo.delete_all()
  end

  defp notify_owner(credential) do
    credential
    |> Repo.preload(:user)
    |> Map.get(:user)
    |> UserNotifier.send_credential_deletion_notification_email(credential)
  end

  @doc """
  Checks if a given `Credential` has any associated `Step` activity.

  ## Parameters

    - `_credential`: A `Credential` struct. Only the `id` field is used by the function.

  ## Returns

    - `true` if there's at least one `Step` associated with the given `Credential`.
    - `false` otherwise.

  ## Examples

      iex> has_activity_in_projects?(%Credential{id: some_id})
      true

      iex> has_activity_in_projects?(%Credential{id: another_id})
      false

  ## Notes

  This function leverages the association between `Step` and `Credential` to
  determine if any steps exist for a given credential. It's a fast check that
  does not load any records into memory, but simply checks for their existence.

  """
  def has_activity_in_projects?(%Credential{id: id} = _credential) do
    from(step in Lightning.Invocation.Step,
      where: step.credential_id == ^id
    )
    |> Repo.exists?()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking credential changes.

  ## Examples

      iex> change_credential(credential)
      %Ecto.Changeset{data: %Credential{}}

  """
  def change_credential(%Credential{} = credential, attrs \\ %{}) do
    # dbg(credential)
    # dbg(attrs)
    Credential.changeset(
      credential,
      attrs |> coerce_json_field("body")
    )
    |> cast_body_change()
  end

  @spec sensitive_values_for(Ecto.UUID.t() | Credential.t() | nil) :: [any()]
  def sensitive_values_for(id) when is_binary(id) do
    sensitive_values_for(get_credential!(id))
  end

  def sensitive_values_for(nil), do: []

  def sensitive_values_for(%Credential{body: body}) do
    if is_nil(body) do
      []
    else
      SensitiveValues.secret_values(body)
    end
  end

  def basic_auth_for(%Credential{body: body}) when is_map(body) do
    usernames =
      body
      |> Map.take(["username", "email"])
      |> Map.values()

    password = Map.get(body, "password", "")

    usernames
    |> Enum.zip(List.duplicate(password, length(usernames)))
    |> Enum.map(fn {username, password} ->
      Base.encode64("#{username}:#{password}")
    end)
  end

  def basic_auth_for(_credential), do: []

  @doc """
  Given a credential and a user, returns a list of invalid projects—i.e., those
  that the credential is shared with but that the user does not have access to.

  This is used to generate a validation error when a credential cannot be
  transferred.

  ## Examples

      iex> can_credential_be_shared_to_user(credential_id, user_id)
      []

      iex> can_credential_be_shared_to_user(credential_id, user_id)
      ["52ea8758-6ce5-43d7-912f-6a1e1f11dc55"]
  """
  def invalid_projects_for_user(credential_id, user_id) do
    project_credentials =
      from(pc in Lightning.Projects.ProjectCredential,
        where: pc.credential_id == ^credential_id,
        select: pc.project_id
      )
      |> Repo.all()

    project_users =
      from(pu in Lightning.Projects.ProjectUser,
        where: pu.user_id == ^user_id,
        select: pu.project_id
      )
      |> Repo.all()

    project_credentials -- project_users
  end

  def maybe_refresh_token(%Credential{schema: "oauth"} = credential) do
    cond do
      # TODO: Even tho the still_fresh/1 function is in the OauthHTTPClient module, it doesn't do any HTTP call.
      # It will be moved in another module after we deprecate salesforce and googlesheets oauth
      OauthHTTPClient.still_fresh(credential.body) ->
        {:ok, credential}

      is_nil(credential.oauth_client_id) ->
        {:ok, credential}

      true ->
        %{oauth_client: oauth_client, body: rotten_token} =
          Lightning.Repo.preload(credential, :oauth_client)

        case OauthHTTPClient.refresh_token(oauth_client, rotten_token) do
          {:ok, fresh_token} ->
            update_credential(credential, %{body: fresh_token})

          {:error, error} ->
            {:error, error}
        end
    end
  end

  # TODO: Remove this function when deprecating salesforce and googlesheets oauth
  def maybe_refresh_token(%Credential{schema: schema} = credential)
      when schema in ["salesforce_oauth", "googlesheets"] do
    token = Common.TokenBody.new(credential.body)

    if Common.still_fresh(token) do
      {:ok, credential}
    else
      adapter = lookup_adapter(schema)
      wellknown_url = adapter.wellknown_url(token.sandbox)

      case adapter.refresh_token(token, wellknown_url) do
        {:ok, refreshed_token} ->
          updated_body =
            refreshed_token
            |> Common.TokenBody.from_oauth2_token()
            |> Lightning.Helpers.json_safe()

          update_credential(credential, %{body: updated_body})

        {:error, error} ->
          {:error, error}
      end
    end
  end

  def maybe_refresh_token(%Credential{} = credential) do
    {:ok, credential}
  end

  # TODO: Remove this function when deprecating salesforce and googlesheets oauth
  def lookup_adapter(schema) do
    case :ets.lookup(:adapter_lookup, schema) do
      [{^schema, adapter}] -> adapter
      [] -> nil
    end
  end
end
