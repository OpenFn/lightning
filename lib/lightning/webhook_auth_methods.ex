defmodule Lightning.WebhookAuthMethods do
  @moduledoc """
  The `Lightning.WebhookAuthMethods` context provides a suite of functionalities to handle and interact with Webhook Authentication Methods within the application.

  ## Overview
  This context is designed to encapsulate all the logic related to Webhook Authentication Methods, including their creation, updates, retrievals, and deletions. It serves as an API for other parts of the system to interact with Webhook Authentication Methods, ensuring that the internal implementation details are hidden, and only the necessary functionalities are exposed.

  ## Functionalities
  - `create_auth_method/1`: Allows for the creation of a new Webhook Authentication Method with given attributes.
  - `update_auth_method/2`: Facilitates the updating of an existing Webhook Authentication Method.
  - `delete_auth_method/1`: Allows for the deletion of a given Webhook Auth Method.
  - `list_for_project/1`: Provides a list of all Webhook Authentication Methods for a given project.
  - `list_for_trigger/1`: Provides a list of all Webhook Authentication Methods for a given trigger.
  - `find_by_api_key/2`: Retrieves a Webhook Authentication Method by API key and project_id.
  - `find_by_username_and_password/3`: Obtains a Webhook Authentication Method by username, password, and project_id if the password is valid.
  - `find_by_id!/2`: Fetches a Webhook Authentication Method by id and project_id, raises if it does not exist.

  ## Examples

  The examples in each function provide detailed use cases and expected outcomes, aiding developers in understanding how to utilize the functionalities provided by this context.

  ## Usage

  This module is intended to be used by other modules, contexts, or controllers that need to perform operations related to Webhook Authentication Methods, serving as a clear and consistent interface for these operations.
  """

  import Ecto.Query, warn: false
  alias Lightning.Jobs.Trigger
  alias Lightning.Projects.Project
  alias Lightning.Workflows.WebhookAuthMethod
  alias Lightning.Repo

  @doc """
  When called with %{"type" => "purge_deleted"},
  finds webhook_auth_methods that are ready for permanent deletion,
  disassociates them from the triggers, and then deletes the webhook_auth_methods.
  """
  @impl Oban.Worker
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
    case Ecto.assoc(wam, :triggers) |> Repo.delete_all() do
      {count, _} when count > 0 ->
        :ok

      {0, _} ->
        :no_associations
    end
  end

  @doc """
  Creates a `WebhookAuthMethod`.

  ## Examples

      iex> create_auth_method(%{valid attributes})
      {:ok, %WebhookAuthMethod{}}

      iex> create_auth_method(%{invalid attributes})
      {:error, %Ecto.Changeset{}}

  """
  def create_auth_method(attrs) do
    %WebhookAuthMethod{}
    |> WebhookAuthMethod.changeset(attrs)
    |> Repo.insert()
  end

  @spec create_auth_method(Trigger.t(), map()) ::
          {:ok, WebhookAuthMethod.t()} | {:error, Ecto.Changeset.t()}
  def create_auth_method(%Trigger{} = trigger, params) do
    %WebhookAuthMethod{}
    |> WebhookAuthMethod.changeset(params)
    |> Ecto.Changeset.put_assoc(:triggers, [trigger])
    |> Repo.insert()
  end

  @doc """
  Updates a `WebhookAuthMethod`.

  ## Examples

      iex> update_auth_method(webhook_auth_method, %{field: new_value})
      {:ok, %WebhookAuthMethod{}}

      iex> update_auth_method(webhook_auth_method, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_auth_method(
        %WebhookAuthMethod{} = webhook_auth_method,
        attrs
      ) do
    webhook_auth_method
    |> WebhookAuthMethod.update_changeset(attrs)
    |> Repo.update()
  end

  @spec update_trigger_auth_methods(
          Trigger.t(),
          [WebhookAuthMethod.t(), ...] | []
        ) :: {:ok, Trigger.t()} | {:error, Ecto.Changeset.t()}
  def update_trigger_auth_methods(%Trigger{} = trigger, auth_methods) do
    trigger
    |> Repo.preload([:webhook_auth_methods])
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:webhook_auth_methods, auth_methods)
    |> Repo.update()
  end

  @doc """
  Deletes a Webhook Auth Method.

  ## Examples

      iex> delete_auth_method(%WebhookAuthMethod{id: "some_id"})
      {:ok, %WebhookAuthMethod{}}

      iex> delete_auth_method(%WebhookAuthMethod{id: "non_existing_id"})
      {:error, :conflict}

  """
  def delete_auth_method(%WebhookAuthMethod{} = auth_method) do
    Repo.delete(auth_method)
  end

  @doc """
  Lists all `WebhookAuthMethod`s for a given project.

  ## Examples

      iex> list_for_project(%Project{id: "existing_project_id"})
      [%WebhookAuthMethod{}, ...]

      iex> list_for_project(%Project{id: "non_existing_project_id"})
      []

  """
  def list_for_project(%Project{id: project_id}) do
    WebhookAuthMethod
    |> where(project_id: ^project_id)
    |> where([wam], not is_nil(wam.scheduled_deletion))
    |> Repo.all()
  end

  @doc """
  Retrieves a list of webhook_auth_methods associated with the given trigger.

  ## Parameters

  - `trigger`: The Trigger struct for which associated webhook_auth_methods are to be retrieved. If `nil`, the function will return `nil`.

  ## Returns

  - Returns a list of %WebhookAuthMethod{} associated with the given trigger.

  ## Examples

      iex> Lightning.Workflows.list_for_trigger(trigger)
      [%WebhookAuthMethod{}, ...]

  """
  def list_for_trigger(%Trigger{} = trigger) do
    Ecto.assoc(trigger, :webhook_auth_methods)
    |> where([wam], not is_nil(wam.scheduled_deletion))
    |> Repo.all()
  end

  @doc """
  Gets a `WebhookAuthMethod` by api_key and project_id.

  ## Examples

      iex> find_by_api_key("existing_api_key", %Project{id: "existing_project_id"})
      %WebhookAuthMethod{}

      iex> find_by_id_by_username("non_existing_api_key", %Project{id: "existing_project_id"})
      nil

  """
  def find_by_api_key(api_key, %Project{} = project)
      when is_binary(api_key) do
    list_for_project(project)
    |> Enum.find(fn auth_method ->
      Plug.Crypto.secure_compare(auth_method.api_key, api_key)
    end)
  end

  @doc """
  Gets a `WebhookAuthMethod` by username, password, and project_id if the password is valid.

  ## Examples

      iex> find_by_username_and_password("existing_username", "valid_password", %Project{id: "existing_project_id"})
      %WebhookAuthMethod{}

      iex> find_by_username_and_password("existing_username", "invalid_password", %Project{id: "existing_project_id"})
      nil

  """
  def find_by_username_and_password(username, password, %Project{} = project)
      when is_binary(username) and is_binary(password) do
    list_for_project(project)
    |> Enum.find(fn auth_method ->
      Plug.Crypto.secure_compare(auth_method.username, username) and
        Plug.Crypto.secure_compare(auth_method.password, password)
    end)
  end

  @doc """
  Gets a `WebhookAuthMethod` by id and project_id, raises if it does not exist.

  ## Examples

      iex> find_by_id!("existing_id", %Project{id: "existing_project_id"})
      %WebhookAuthMethod{}

      iex> find_by_id!("non_existing_id", %Project{id: "existing_project_id"})
      ** (Ecto.NoResultsError)

  """
  def find_by_id!(id) do
    Repo.get_by!(WebhookAuthMethod, id: id)
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
  def schedule_for_deletion(%WebhookAuthMethod{} = webhook_auth_method) do
    deletion_date = scheduled_deletion_date()

    WebhookAuthMethod.changeset(webhook_auth_method, %{
      "scheduled_deletion" => deletion_date
    })
    |> Repo.update()
  end

  defp scheduled_deletion_date do
    days = Application.get_env(:lightning, :purge_deleted_after_days, 0)
    DateTime.utc_now() |> Timex.shift(days: days)
  end
end
