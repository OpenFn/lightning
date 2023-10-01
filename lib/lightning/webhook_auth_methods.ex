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
    |> WebhookAuthMethod.changeset(attrs)
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
    Ecto.assoc(trigger, :webhook_auth_methods) |> Repo.all()
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
end
