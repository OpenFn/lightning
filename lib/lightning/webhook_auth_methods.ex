defmodule Lightning.WebhookAuthMethods do
  @moduledoc """
  Provides functionality for managing webhook authentication methods.

  This module contains functions to create, update, list, and delete authentication methods
  for webhooks. It supports operations such as scheduling authentication methods for deletion,
  purging them, associating them with triggers, and handling their life cycle within the system.

  The main responsibilities of this module include:

  - Creating new webhook authentication methods with `create_auth_method/2`.
  - Associating and disassociating authentication methods with triggers.
  - Updating existing webhook authentication methods with `update_auth_method/3`.
  - Listing webhook authentication methods for a given project or trigger.
  - Finding a webhook authentication method by various identifiers, like API key or username and password.
  - Scheduling webhook authentication methods for deletion and purging them accordingly.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Lightning.Accounts.User
  alias Lightning.Workflows.Trigger
  alias Lightning.Projects.Project
  alias Lightning.Workflows.WebhookAuthMethod
  alias Lightning.Workflows.WebhookAuthMethodAudit
  alias Lightning.Repo

  @doc """
  Performs cleanup of `WebhookAuthMethod` records that are marked for permanent deletion.

  ## Details
  This function, when invoked with a job argument containing `%{"type" => "purge_deleted"}`, performs the following operations:

  1. It queries all `WebhookAuthMethod` records that are scheduled for deletion (i.e., their `scheduled_deletion` timestamp is in the past).
  2. It then disassociates each of these records from any associated triggers.
  3. Finally, it deletes the `WebhookAuthMethod` records from the database.

  The function operates within the context of an Oban job, utilizing the `perform/1` callback expected by the Oban.Worker behaviour.

  ## Parameters
  - A `%Oban.Job{args: %{"type" => "purge_deleted"}}` struct, indicating the job should perform a purge operation.

  ## Returns
  A tuple `{:ok, %{disassociated_count: integer(), deleted_count: integer()}}` where:
  - `:ok` indicates the operation was successful.
  - `disassociated_count` is the number of `WebhookAuthMethod` records successfully disassociated from triggers.
  - `deleted_count` is the number of `WebhookAuthMethod` records successfully deleted.

  ## Example
  ```elixir
  %Oban.Job{
  args: %{"type" => "purge_deleted"}
  }
  |> MyModule.perform()
  # => {:ok, %{disassociated_count: 2, deleted_count: 2}}
  ```
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) ::
          {:ok, %{deleted_count: any(), disassociated_count: any()}}
  def perform(%Oban.Job{args: %{"type" => "purge_deleted"}}) do
    webhook_auth_methods_to_delete =
      from(wam in WebhookAuthMethod,
        where: wam.scheduled_deletion <= ago(0, "second")
      )
      |> Repo.all()

    disassociated_count =
      Enum.reduce(webhook_auth_methods_to_delete, 0, fn wam, acc ->
        case disassociate_from_triggers(wam) do
          :ok -> acc + 1
          :no_associations -> acc
        end
      end)

    deleted_count =
      Enum.reduce(webhook_auth_methods_to_delete, 0, fn wam, acc ->
        case delete_auth_method(wam) do
          {:ok, _} -> acc + 1
          _error -> acc
        end
      end)

    {:ok,
     %{disassociated_count: disassociated_count, deleted_count: deleted_count}}
  end

  defp disassociate_from_triggers(wam) do
    wam_uuid = Ecto.UUID.dump!(wam.id)

    from(j in "trigger_webhook_auth_methods",
      where: j.webhook_auth_method_id == ^wam_uuid
    )
    |> Repo.delete_all()
    |> case do
      {count, _} when count > 0 ->
        :ok

      {0, _} ->
        :no_associations
    end
  end

  @doc """
  Creates a new `WebhookAuthMethod` and associated audit records.

  This function supports creating a `WebhookAuthMethod` either standalone or associated with a `Trigger`. It performs a database transaction that includes creating the auth method and its audit trail.

  ## Parameters

    - `attrs`: A map of attributes used to create the `WebhookAuthMethod`.
    - `actor`: The user performing the action, provided as a `%User{}` struct.

  ## Overloads

    - When called with a map of attributes, it creates a `WebhookAuthMethod` without associating it to a trigger.
    - When called with a `Trigger` struct and a map of attributes, it creates a `WebhookAuthMethod` and associates it with the provided trigger.

  ## Returns

    - `{:ok, %WebhookAuthMethod{}}`: A tuple containing `:ok` and the newly created `WebhookAuthMethod` struct if the creation was successful.
    - `{:error, %Ecto.Changeset{}}`: A tuple containing `:error` and the changeset with errors if the creation failed.

  ## Examples

    - Creating a `WebhookAuthMethod` without an associated trigger:

      ```elixir
      iex> create_auth_method(%{valid_attributes}, actor: %User{})
      {:ok, %WebhookAuthMethod{}}

      iex> create_auth_method(%{invalid_attributes}, actor: %User{})
      {:error, %Ecto.Changeset{}}
      ```

    - Creating a `WebhookAuthMethod` with an associated trigger:

      ```elixir
      iex> create_auth_method(%Trigger{}, %{valid_attributes}, actor: %User{})
      {:ok, %WebhookAuthMethod{}}

      iex> create_auth_method(%Trigger{}, %{invalid_attributes}, actor: %User{})
      {:error, %Ecto.Changeset{}}
      ```

  ## Notes

    - This function starts a `Repo.transaction` to ensure that all database operations are atomic. If any part of the transaction fails, all changes will be rolled back.
    - Audit events are created for both the creation of the `WebhookAuthMethod` and its association with a trigger, if applicable.

  """
  @spec create_auth_method(map(), actor: User.t()) ::
          {:ok, WebhookAuthMethod.t()} | {:error, Ecto.Changeset.t()}
  def create_auth_method(attrs, actor: %User{} = user) do
    changeset = WebhookAuthMethod.changeset(%WebhookAuthMethod{}, attrs)

    Multi.new()
    |> Multi.insert(:auth_method, changeset)
    |> Multi.insert(:audit, fn %{auth_method: auth_method} ->
      WebhookAuthMethodAudit.event("created", auth_method.id, user.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{auth_method: auth_method}} ->
        {:ok, auth_method}

      {:error, :auth_method, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @spec create_auth_method(Trigger.t(), map(), actor: User.t()) ::
          {:ok, WebhookAuthMethod.t()} | {:error, Ecto.Changeset.t()}
  def create_auth_method(%Trigger{} = trigger, params, actor: %User{} = user) do
    Multi.new()
    |> Multi.insert(:auth_method, fn _changes ->
      %WebhookAuthMethod{}
      |> WebhookAuthMethod.changeset(params)
      |> Ecto.Changeset.put_assoc(:triggers, [trigger])
    end)
    |> Multi.insert(:created_audit, fn %{auth_method: auth_method} ->
      WebhookAuthMethodAudit.event("created", auth_method.id, user.id)
    end)
    |> Multi.insert(:add_to_trigger_audit, fn %{auth_method: auth_method} ->
      WebhookAuthMethodAudit.event(
        "added_to_trigger",
        auth_method.id,
        user.id,
        %{before: %{trigger_id: nil}, after: %{trigger_id: trigger.id}}
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{auth_method: auth_method}} ->
        {:ok, auth_method}

      {:error, :auth_method, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates an existing `WebhookAuthMethod` with the provided attributes and creates an audit event.

  This function applies the given changes to the specified `WebhookAuthMethod` and records the update action in the audit log. It wraps the operations within a database transaction to ensure data integrity.

  ## Parameters

    - `webhook_auth_method`: The `WebhookAuthMethod` struct to be updated.
    - `attrs`: A map containing the updated values for the fields of the `WebhookAuthMethod`.
    - `actor`: The user performing the update, represented by a `%User{}` struct.

  ## Returns

    - `{:ok, %WebhookAuthMethod{}}`: A tuple containing `:ok` and the updated `WebhookAuthMethod` struct if the update is successful.
    - `{:error, %Ecto.Changeset{}}`: A tuple containing `:error` and the changeset with errors if the update fails.

  ## Examples

    - Successful update:

      ```elixir
      iex> update_auth_method(webhook_auth_method, %{field: new_value}, actor: %User{})
      {:ok, %WebhookAuthMethod{}}
      ```

    - Update fails due to invalid data:

      ```elixir
      iex> update_auth_method(webhook_auth_method, %{field: bad_value}, actor: %User{})
      {:error, %Ecto.Changeset{}}
      ```

  ## Notes

    - The function uses `Ecto.Multi` to perform a transaction, ensuring that either all changes apply successfully, or none do if there's an error.
    - An audit event is recorded with the `Lightning.WebhookAuthMethodAudit.event/4` function, capturing the details of the update and the acting user.

  """
  @spec update_auth_method(WebhookAuthMethod.t(), map(), actor: User.t()) ::
          {:ok, WebhookAuthMethod.t()} | {:error, Ecto.Changeset.t()}
  def update_auth_method(
        %WebhookAuthMethod{} = webhook_auth_method,
        attrs,
        actor: %User{} = user
      ) do
    changeset = WebhookAuthMethod.update_changeset(webhook_auth_method, attrs)

    Multi.new()
    |> Multi.update(:auth_method, changeset)
    |> Multi.insert(
      :audit,
      fn %{auth_method: auth_method} ->
        WebhookAuthMethodAudit.event(
          "updated",
          auth_method.id,
          user.id,
          changeset
        )
      end
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{auth_method: auth_method}} ->
        {:ok, auth_method}

      {:error, :auth_method, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates the association of `WebhookAuthMethod`s for a given `Trigger` and logs the changes as audit events.

  This function replaces the current `WebhookAuthMethod` associations of a `Trigger` with the provided list of `WebhookAuthMethod`s. It creates audit events for each added and removed `WebhookAuthMethod`, ensuring full traceability of changes.

  ## Parameters

    - `trigger`: The `Trigger` struct whose associated `WebhookAuthMethod`s are to be updated.
    - `auth_methods`: A list of `WebhookAuthMethod` structs to be associated with the `Trigger`.
    - `actor`: The user performing the update, represented by a `%User{}` struct.

  ## Returns

    - `{:ok, %Trigger{}}`: A tuple containing `:ok` and the updated `Trigger` struct if the associations are updated successfully.
    - `{:error, %Ecto.Changeset{}}`: A tuple containing `:error` and the changeset with errors if the update fails.

  ## Examples

    - Successful association update:

      ```elixir
      iex> update_trigger_auth_methods(trigger, [webhook_auth_method], actor: %User{})
      {:ok, %Trigger{}}
      ```

    - Update fails due to an invalid changeset:

      ```elixir
      iex> update_trigger_auth_methods(trigger, [invalid_webhook_auth_method], actor: %User{})
      {:error, %Ecto.Changeset{}}
      ```

  ## Notes

    - The function uses `Ecto.Multi` to perform a transaction, which ensures either all changes are applied or none at all if an error occurs.
    - Audit events for the additions and removals of `WebhookAuthMethod`s are recorded using `WebhookAuthMethodAudit.event/4`.
    - The function preloads the existing `webhook_auth_methods` of the `Trigger` before performing updates.

  """
  @spec update_trigger_auth_methods(
          Trigger.t(),
          [WebhookAuthMethod.t()] | [],
          actor: User.t()
        ) :: {:ok, Trigger.t()} | {:error, Ecto.Changeset.t()}
  def update_trigger_auth_methods(%Trigger{} = trigger, auth_methods,
        actor: %User{} = user
      ) do
    trigger = Repo.preload(trigger, [:webhook_auth_methods])

    Multi.new()
    |> Multi.update(:trigger, fn _changes ->
      trigger
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:webhook_auth_methods, auth_methods)
    end)
    |> Multi.merge(fn %{trigger: updated_trigger} ->
      prev_auth_ids =
        Enum.map(trigger.webhook_auth_methods, fn auth_method ->
          auth_method.id
        end)

      new_auth_ids =
        Enum.map(updated_trigger.webhook_auth_methods, fn auth_method ->
          auth_method.id
        end)

      added_auth_ids = new_auth_ids -- prev_auth_ids
      removed_auth_ids = prev_auth_ids -- new_auth_ids

      added_auth_multi =
        Enum.reduce(added_auth_ids, Multi.new(), fn auth_id, multi ->
          changeset =
            WebhookAuthMethodAudit.event(
              "added_to_trigger",
              auth_id,
              user.id,
              %{before: %{trigger_id: nil}, after: %{trigger_id: trigger.id}}
            )

          Multi.insert(multi, "audit_#{auth_id}", changeset)
        end)

      Enum.reduce(removed_auth_ids, added_auth_multi, fn auth_id, multi ->
        changeset =
          WebhookAuthMethodAudit.event(
            "removed_from_trigger",
            auth_id,
            user.id,
            %{before: %{trigger_id: trigger.id}, after: %{trigger_id: nil}}
          )

        Multi.insert(multi, "audit_#{auth_id}", changeset)
      end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{trigger: trigger}} ->
        {:ok, trigger}

      {:error, :trigger, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Deletes a given `WebhookAuthMethod` from the database.

  The function takes a `WebhookAuthMethod` struct and attempts to delete it. If the deletion is successful, it returns an `:ok` tuple with the deleted `WebhookAuthMethod` struct. If the deletion fails due to a constraint, such as a foreign key reference, it returns an error tuple.

  ## Parameters

    - `auth_method`: The `WebhookAuthMethod` struct to delete.

  ## Returns

    - `{:ok, struct}`: A tuple containing `:ok` and the deleted `WebhookAuthMethod` struct if the deletion succeeds.
    - `{:error, reason}`: A tuple containing `:error` and the reason for failure if the deletion fails.

  ## Examples

    - Successful deletion:

      ```elixir
      iex> delete_auth_method(%WebhookAuthMethod{id: "some_id"})
      {:ok, %WebhookAuthMethod{}}
      ```

    - Deletion fails due to the item not existing or other conflict:

      ```elixir
      iex> delete_auth_method(%WebhookAuthMethod{id: "non_existing_id"})
      {:error, reason}
      ```

  ## Notes

    - It is important to ensure that the `WebhookAuthMethod` is not being referenced by other entities before attempting deletion to avoid conflicts.
    - This function will return an error tuple if the `WebhookAuthMethod` struct passed to it does not exist in the database.
  """
  @spec delete_auth_method(WebhookAuthMethod.t()) ::
          {:ok, WebhookAuthMethod.t()} | {:error, Ecto.Changeset.t()}
  def delete_auth_method(%WebhookAuthMethod{} = auth_method) do
    Repo.delete(auth_method)
  end

  @doc """
  Retrieves a list of `WebhookAuthMethod`s associated with a specific `Project`.

  The function filters `WebhookAuthMethod`s by the provided `Project`'s ID and excludes any methods that are scheduled for deletion.

  ## Parameters

    - `project`: The `Project` struct containing the ID of the project for which to list the authentication methods.

  ## Returns

    - A list of `WebhookAuthMethod` structs. This can be an empty list if no methods are associated with the project or if the project does not exist.

  ## Examples

    - When the project exists and has associated auth methods:

      ```elixir
      iex> list_for_project(%Project{id: "existing_project_id"})
      [%WebhookAuthMethod{}, ...]
      ```

    - When the project does not exist or has no associated auth methods:

      ```elixir
      iex> list_for_project(%Project{id: "non_existing_project_id"})
      []
      ```

  """
  @spec list_for_project(Project.t()) :: [WebhookAuthMethod.t()]
  def list_for_project(%Project{id: project_id}) do
    WebhookAuthMethod
    |> where(project_id: ^project_id)
    |> where([wam], is_nil(wam.scheduled_deletion))
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  Retrieves a list of `WebhookAuthMethod`s associated with the specified `Trigger`.

  This function filters out `WebhookAuthMethod`s that are scheduled for deletion, ensuring that only active methods are returned.

  ## Parameters

    - `trigger`: A `Trigger` struct whose associated `WebhookAuthMethod`s are to be retrieved.

  ## Returns

    - A list of `WebhookAuthMethod` structs associated with the `Trigger`. If the `Trigger` has no associated methods or if they are all scheduled for deletion, the list will be empty.

  ## Examples

    - When the `Trigger` has associated `WebhookAuthMethod`s not scheduled for deletion:

      ```elixir
      iex> Lightning.Workflows.list_for_trigger(%Trigger{id: "existing_trigger_id"})
      [%WebhookAuthMethod{}, ...]
      ```

    - When the `Trigger` has no associated `WebhookAuthMethod`s or they are all scheduled for deletion:

      ```elixir
      iex> Lightning.Workflows.list_for_trigger(%Trigger{id: "trigger_without_methods"})
      []
      ```

  """
  @spec list_for_trigger(Trigger.t()) :: [WebhookAuthMethod.t()]
  def list_for_trigger(%Trigger{} = trigger) do
    Ecto.assoc(trigger, :webhook_auth_methods)
    |> where([wam], is_nil(wam.scheduled_deletion))
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  Retrieves a `WebhookAuthMethod` that matches the given API key for a specified project.

  It uses a secure comparison to match the API key, ensuring that timing attacks are mitigated.

  ## Parameters

    - `api_key`: The API key as a binary string to match against existing `WebhookAuthMethod` records.
    - `project`: The `Project` struct to scope the search within its associated `WebhookAuthMethod`s.

  ## Returns

    - A `WebhookAuthMethod` struct if a matching API key is found within the given project's scope.
    - `nil` if there is no `WebhookAuthMethod` with the given API key for the project.

  ## Examples

    - When a matching `WebhookAuthMethod` is found:

      ```elixir
      iex> Lightning.Workflows.find_by_api_key("existing_api_key", %Project{id: "existing_project_id"})
      %WebhookAuthMethod{}
      ```

    - When there is no matching `WebhookAuthMethod`:

      ```elixir
      iex> Lightning.Workflows.find_by_api_key("non_existing_api_key", %Project{id: "existing_project_id"})
      nil
      ```

  """
  @spec find_by_api_key(String.t(), Project.t()) :: WebhookAuthMethod.t() | nil
  def find_by_api_key(api_key, %Project{} = project)
      when is_binary(api_key) do
    list_for_project(project)
    |> Enum.find(fn auth_method ->
      Plug.Crypto.secure_compare(auth_method.api_key, api_key)
    end)
  end

  @doc """
  Retrieves a `WebhookAuthMethod` that matches the given username and password within the scope of a specified project.

  The function checks if the provided password is correct for the given username and project. If the password is valid, the corresponding `WebhookAuthMethod` is returned. It is important to handle password comparison securely to prevent timing attacks.

  ## Parameters

    - `username`: The username as a string to match against the `WebhookAuthMethod` records.
    - `password`: The plaintext password as a string which will be securely compared to the stored password.
    - `project`: The `Project` struct to scope the search for the `WebhookAuthMethod`.

  ## Returns

    - Returns the matching `WebhookAuthMethod` struct if the username and password are correct within the given project's scope.
    - Returns `nil` if no matching record is found or if the password is invalid.

  ## Examples

    - When a matching `WebhookAuthMethod` is found and the password is valid:

      ```elixir
      iex> Lightning.Workflows.find_by_username_and_password("existing_username", "valid_password", %Project{id: "existing_project_id"})
      %WebhookAuthMethod{}
      ```

    - When the username is found but the password is invalid or no matching record is found:

      ```elixir
      iex> Lightning.Workflows.find_by_username_and_password("existing_username", "invalid_password", %Project{id: "existing_project_id"})
      nil
      ```

  """
  @spec find_by_username_and_password(String.t(), String.t(), Project.t()) ::
          WebhookAuthMethod.t() | nil
  def find_by_username_and_password(username, password, %Project{} = project)
      when is_binary(username) and is_binary(password) do
    list_for_project(project)
    |> Enum.find(fn auth_method ->
      Plug.Crypto.secure_compare(auth_method.username, username) and
        Plug.Crypto.secure_compare(auth_method.password, password)
    end)
  end

  @doc """
  Retrieves a `WebhookAuthMethod` by its ID, raising an exception if not found.

  This function is intended for situations where the `WebhookAuthMethod` is expected to exist, and not finding one is an exceptional case that should halt normal flow with an error.

  ## Parameter

    - `id`: The ID of the `WebhookAuthMethod` to retrieve.

  ## Returns

    - Returns the `WebhookAuthMethod` struct if found.

  ## Errors

    - Raises `Ecto.NoResultsError` if there is no `WebhookAuthMethod` with the given ID.

  ## Examples

    - When a `WebhookAuthMethod` with the given ID exists:

      ```elixir
      iex> Lightning.Workflows.find_by_id!("existing_id")
      %WebhookAuthMethod{}
      ```

    - When there is no `WebhookAuthMethod` with the given ID:

      ```elixir
      iex> Lightning.Workflows.find_by_id!("non_existing_id")
      ** (Ecto.NoResultsError)
      ```

  """
  @spec find_by_id!(binary()) :: WebhookAuthMethod.t() | no_return()
  def find_by_id!(id) do
    Repo.get_by!(WebhookAuthMethod, id: id)
  end

  @doc """
  Schedules a `WebhookAuthMethod` for deletion by setting its `scheduled_deletion` date.

  This function does not delete the record immediately. Instead, it sets the `scheduled_deletion` field to a date in the future as defined by the application's environment settings.
  The default behavior, in the absence of environment configuration, is to schedule the deletion for the current date and time, effectively marking it for immediate deletion.

  The scheduled deletion date is determined by the `:purge_deleted_after_days` configuration in the application environment.
  If this configuration is not present, the function defaults to 0 days, which schedules the deletion for the current date and time.

  ## Parameters

    - `webhook_auth_method`: A `WebhookAuthMethod` struct that is to be scheduled for deletion.

  ## Returns

    - `{:ok, webhook_auth_method}`: Returns an `:ok` tuple with the updated webhook auth method struct if the
        update was successful.
    - `{:error, changeset}`: Returns an `:error` tuple with the changeset if the update failed.

  ## Examples

    - When a webhook auth method is successfully scheduled for deletion:

      ```elixir
      iex> Lightning.Workflows.schedule_for_deletion(%WebhookAuthMethod{id: some_id})
      {:ok, %WebhookAuthMethod{scheduled_deletion: deletion_date}}
      ```

    - When scheduling for deletion fails due to validation errors:

      ```elixir
      iex> Lightning.Workflows.schedule_for_deletion(%WebhookAuthMethod{})
      {:error, %Ecto.Changeset{}}
      ```
  """

  @spec schedule_for_deletion(WebhookAuthMethod.t(), actor: User.t()) ::
          {:ok, WebhookAuthMethod.t()} | {:error, Ecto.Changeset.t()}
  def schedule_for_deletion(%WebhookAuthMethod{} = webhook_auth_method,
        actor: %User{} = user
      ) do
    # Check if the webhook_auth_method is already scheduled for deletion
    if webhook_auth_method.scheduled_deletion do
      changeset =
        WebhookAuthMethod.changeset(webhook_auth_method, %{})
        |> Ecto.Changeset.add_error(
          :scheduled_deletion,
          "already scheduled for deletion"
        )

      {:error, changeset}
    else
      deletion_date = scheduled_deletion_date()

      Multi.new()
      |> Multi.update(
        :auth_method,
        WebhookAuthMethod.changeset(webhook_auth_method, %{
          "scheduled_deletion" => deletion_date
        })
      )
      |> Multi.insert(:audit, fn %{auth_method: auth_method} ->
        WebhookAuthMethodAudit.event(
          "deleted",
          auth_method.id,
          user.id,
          %{
            before: %{scheduled_deletion: nil},
            after: %{scheduled_deletion: deletion_date}
          }
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{auth_method: auth_method}} ->
          {:ok, auth_method}

        {:error, :auth_method, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  defp scheduled_deletion_date do
    days = Application.get_env(:lightning, :purge_deleted_after_days, 0)
    DateTime.utc_now() |> Timex.shift(days: days)
  end

  @doc """
  Creates a changeset for a `WebhookAuthMethod` struct, which can include special handling based on the authentication type.

  This function prepares a changeset for the creation or update of a `WebhookAuthMethod`. If the `auth_type` is `:api`, it generates a new API key and includes it in the returned structure.

  ## Parameters

    - `webhook_auth_method`: The `WebhookAuthMethod` struct to be updated.
    - `params`: A map containing the parameters with which to update the `webhook_auth_method`.

  ## Returns

    - Returns the updated `WebhookAuthMethod` struct with changes applied. If `auth_type` is `:api`, an API key is generated and included.

  ## Examples

    - Creating a changeset for an API type auth method:

      ```elixir
      iex> Lightning.Workflows.create_changeset(%WebhookAuthMethod{auth_type: :api}, %{})
      %WebhookAuthMethod{api_key: some_new_api_key}
      ```

    - Creating a changeset for a non-API type auth method:

      ```elixir
      iex> Lightning.Workflows.create_changeset(%WebhookAuthMethod{auth_type: :other}, %{})
      %WebhookAuthMethod{}
      ```
  """
  @spec create_changeset(WebhookAuthMethod.t(), map()) :: WebhookAuthMethod.t()
  def create_changeset(%WebhookAuthMethod{} = webhook_auth_method, params) do
    auth_method =
      webhook_auth_method
      |> WebhookAuthMethod.changeset(params)
      |> Ecto.Changeset.apply_changes()

    if auth_method.auth_type == :api do
      api_key = WebhookAuthMethod.generate_api_key()
      %{auth_method | api_key: api_key}
    else
      auth_method
    end
  end
end
