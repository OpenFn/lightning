defmodule LightningWeb.API.CredentialEnvironmentController do
  @moduledoc """
  A credential's environments, at `/api/credentials/:id/environments`: one
  body per environment, such as `main` and `staging`, so a project and its
  sandboxes can use different secrets. A credential has between one and
  `Lightning.Credentials.max_environments/0` of them. Bodies are never
  returned.

  Only the owner and the service account may list or change them, so only
  the service account hears 404 `not_found` for an id that names no
  credential, or 400 `invalid_parameter` for one that isn't a UUID. Everyone
  else hears 403 `forbidden` for both. A credential scheduled for deletion
  answers 409 `scheduled_for_deletion`.
  """
  use LightningWeb, :controller

  alias Lightning.Credentials
  alias LightningWeb.API.CredentialController
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction, {:credentials, :edit_credential_environments}

  @doc """
  Lists the credential's environments by name, without their bodies.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, _params) do
    with {:ok, credential} <- target(conn) do
      render(conn, :index,
        environments: Credentials.list_environments(credential)
      )
    end
  end

  @doc """
  Creates the environment, answering 201, or replaces its body, answering
  200, with the environment. The body is `{"body": {…}}`, checked against the
  credential's schema. A sixth environment is refused with an `exceeds_limit`
  entry at the path's `name`, and a name Lightning doesn't accept with a
  `format` entry there.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, %{"name" => name}) do
    body = conn.body_params

    with {:ok, credential} <- target(conn),
         :ok <- Request.check_object(body),
         :ok <- Credentials.check_catalogue(credential.schema),
         environments = Credentials.list_environments(credential),
         creating? = not Enum.any?(environments, &(&1.name == name)),
         :ok <- Errors.refuse(body_entries(body, creating?, environments)),
         {:ok, credential} <-
           write(
             credential,
             %{
               "credential_bodies" => [%{"name" => name, "body" => body["body"]}]
             },
             conn
           ) do
      environment = Enum.find(credential.credential_bodies, &(&1.name == name))

      conn
      |> put_status(if creating?, do: :created, else: :ok)
      |> render(:show, environment: environment)
    end
  end

  @doc """
  Deletes the environment, answering 204. An environment the credential
  doesn't have answers 404 `not_found`, and its last one is refused with a
  `required` entry at the path's `name`.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, %{"name" => name}) do
    with {:ok, credential} <- target(conn),
         environments = Credentials.list_environments(credential),
         :ok <- found(environments, name),
         :ok <- Errors.refuse(last_entries(environments)),
         {:ok, _credential} <-
           write(credential, %{"delete_environments" => [name]}, conn) do
      send_resp(conn, :no_content, "")
    end
  end

  defp found(environments, name) do
    if Enum.any?(environments, &(&1.name == name)),
      do: :ok,
      else: {:error, :not_found}
  end

  defp last_entries([_last]),
    do: [
      Errors.entry(
        {:path, "name"},
        {"a credential needs at least one environment", code: :required}
      )
    ]

  defp last_entries(_environments), do: []

  defp body_entries(body, creating?, environments) do
    Request.unknown_keys(body, [], [:body]) ++
      body_value_entries(body) ++ limit_entries(creating?, environments)
  end

  defp body_value_entries(%{"body" => %{}}), do: []

  defp body_value_entries(%{"body" => nil}), do: body_required()

  defp body_value_entries(%{"body" => _other}),
    do: [Errors.entry([:body], {"must be an object", code: :type})]

  defp body_value_entries(_body), do: body_required()

  defp body_required,
    do: [Errors.entry([:body], {"can't be blank", code: :required})]

  defp limit_entries(true, environments) do
    max = Credentials.max_environments()

    if length(environments) >= max,
      do: [
        Errors.entry(
          {:path, "name"},
          {"a credential may have at most %{count} environments",
           code: :exceeds_limit, count: max}
        )
      ],
      else: []
  end

  defp limit_entries(false, _environments), do: []

  defp write(credential, attrs, conn) do
    case Credentials.update_credential(
           credential,
           attrs,
           conn.assigns.current_resource
         ) do
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Errors.problem(as_environment(changeset), %{}, path: [:name])}

      result ->
        result
    end
  end

  # The context places an error in a body at its position in the credential's
  # list of bodies. This route sends one body, named by the path, so an error
  # in it is placed at the request's `body`, or at the path's `name`.
  defp as_environment(changeset) do
    errors =
      Enum.map(changeset.errors, fn
        {field, {message, opts}} ->
          case opts[:key] do
            [:credential_bodies, _index | key] ->
              {field, {message, Keyword.put(opts, :key, key)}}

            _key ->
              {field, {message, opts}}
          end
      end)

    %{changeset | errors: errors}
  end

  defp target(conn),
    do:
      Target.record(
        conn.assigns.scope,
        Request.param(conn, "id"),
        {:credentials, :edit_credential_environments},
        &CredentialController.fetch_credential/1
      )
end
