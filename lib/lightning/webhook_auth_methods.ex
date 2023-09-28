defmodule Lightning.WebhookAuthMethods do
  @moduledoc """
  The `Lightning.WebhookAuthMethods` context provides a suite of functionalities to handle and interact with Webhook Authentication Methods within the application.

  ## Overview
  This context is designed to encapsulate all the logic related to Webhook Authentication Methods, including their creation, updates, retrievals, and deletions. It serves as an API for other parts of the system to interact with Webhook Authentication Methods, ensuring that the internal implementation details are hidden, and only the necessary functionalities are exposed.

  ## Functionalities
  - `create_webhook_auth_method/1`: Allows for the creation of a new Webhook Authentication Method with given attributes.
  - `update_webhook_auth_method/2`: Facilitates the updating of an existing Webhook Authentication Method.
  - `list_auth_methods/1`: Provides a list of all Webhook Authentication Methods for a given project.
  - `get_auth_method_by_api_key/2`: Retrieves a Webhook Authentication Method by API key and project_id.
  - `get_auth_method_by_username/2`: Finds a Webhook Authentication Method by username and project_id.
  - `get_auth_method_by_username_and_password/3`: Obtains a Webhook Authentication Method by username, password, and project_id if the password is valid.
  - `get_auth_method!/2`: Fetches a Webhook Authentication Method by id and project_id, raises if it does not exist.
  - `delete_auth_method/1`: Allows for the deletion of a given Webhook Auth Method.

  ## Examples

  The examples in each function provide detailed use cases and expected outcomes, aiding developers in understanding how to utilize the functionalities provided by this context.

  ## Usage

  This module is intended to be used by other modules, contexts, or controllers that need to perform operations related to Webhook Authentication Methods, serving as a clear and consistent interface for these operations.
  """

  import Ecto.Query, warn: false
  alias Lightning.Projects.Project
  alias Lightning.Workflows.WebhookAuthMethod
  alias Lightning.Repo

  @doc """
  Creates a `WebhookAuthMethod`.

  ## Examples

      iex> create_webhook_auth_method(%{valid attributes})
      {:ok, %WebhookAuthMethod{}}

      iex> create_webhook_auth_method(%{invalid attributes})
      {:error, %Ecto.Changeset{}}

  """
  def create_webhook_auth_method(attrs) do
    %WebhookAuthMethod{}
    |> WebhookAuthMethod.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a `WebhookAuthMethod`.

  ## Examples

      iex> update_webhook_auth_method(webhook_auth_method, %{field: new_value})
      {:ok, %WebhookAuthMethod{}}

      iex> update_webhook_auth_method(webhook_auth_method, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_webhook_auth_method(
        %WebhookAuthMethod{} = webhook_auth_method,
        attrs
      ) do
    webhook_auth_method
    |> WebhookAuthMethod.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists all `WebhookAuthMethod`s for a given project.

  ## Examples

      iex> list_auth_methods(%Project{id: "existing_project_id"})
      [%WebhookAuthMethod{}, ...]

      iex> list_auth_methods(%Project{id: "non_existing_project_id"})
      []

  """
  def list_auth_methods(%Project{id: project_id}) do
    from(wam in WebhookAuthMethod, where: wam.project_id == ^project_id)
    |> Repo.all()
  end

  @doc """
  Gets a `WebhookAuthMethod` by api_key and project_id.

  ## Examples

      iex> get_auth_method_by_api_key("existing_api_key", %Project{id: "existing_project_id"})
      %WebhookAuthMethod{}

      iex> get_auth_method_by_username("non_existing_api_key", %Project{id: "existing_project_id"})
      nil

  """
  def get_auth_method_by_api_key(api_key, %Project{id: project_id})
      when is_binary(api_key) do
    Repo.get_by(WebhookAuthMethod, api_key: api_key, project_id: project_id)
  end

  @doc """
  Gets a `WebhookAuthMethod` by username and project_id.

  ## Examples

      iex> get_auth_method_by_username("existing_username", %Project{id: "existing_project_id"})
      %WebhookAuthMethod{}

      iex> get_auth_method_by_username("non_existing_username", %Project{id: "existing_project_id"})
      nil

  """
  def get_auth_method_by_username(username, %Project{id: project_id})
      when is_binary(username) do
    Repo.get_by(WebhookAuthMethod, username: username, project_id: project_id)
  end

  @doc """
  Gets a `WebhookAuthMethod` by username, password, and project_id if the password is valid.

  ## Examples

      iex> get_auth_method_by_username_and_password("existing_username", "valid_password", %Project{id: "existing_project_id"})
      %WebhookAuthMethod{}

      iex> get_auth_method_by_username_and_password("existing_username", "invalid_password", %Project{id: "existing_project_id"})
      nil

  """
  def get_auth_method_by_username_and_password(username, password, %Project{
        id: project_id
      })
      when is_binary(username) and is_binary(password) do
    auth_method =
      Repo.get_by(WebhookAuthMethod, username: username, project_id: project_id)

    if auth_method && WebhookAuthMethod.valid_password?(auth_method, password),
      do: auth_method,
      else: nil
  end

  @doc """
  Gets a `WebhookAuthMethod` by id and project_id, raises if it does not exist.

  ## Examples

      iex> get_auth_method!("existing_id", %Project{id: "existing_project_id"})
      %WebhookAuthMethod{}

      iex> get_auth_method!("non_existing_id", %Project{id: "existing_project_id"})
      ** (Ecto.NoResultsError)

  """
  def get_auth_method!(id, %Project{id: project_id}) do
    Repo.get_by!(WebhookAuthMethod, id: id, project_id: project_id)
  end

  def get_auth_methods_for_trigger(trigger) do
    query = Ecto.assoc(trigger, :webhook_auth_methods)
    Repo.all(query)
  end

  def get_auth_methods_for_trigger(nil) do
    nil
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
end
