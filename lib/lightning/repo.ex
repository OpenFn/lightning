defmodule Lightning.Repo do
  use Ecto.Repo,
    otp_app: :lightning,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query

  use Scrivener, page_size: 10

  alias Lightning.Credentials.OauthClient
  alias Lightning.Projects.{Project, ProjectOauthClient}

  def insert_with_global_oauth_clients(changeset) do
    case insert(changeset) do
      {:ok, project} ->
        associate_global_oauth_clients(project)
        {:ok, project}

      error ->
        error
    end
  end

  defp associate_global_oauth_clients(%Project{id: project_id}) do
    # Fetch global OAuth clients
    global_clients = all(from c in OauthClient, where: c.global)

    # Associate each global OAuth client with the new project
    Enum.each(global_clients, fn %OauthClient{id: oauth_client_id} ->
      %ProjectOauthClient{
        oauth_client_id: oauth_client_id,
        project_id: project_id
      }
      |> insert()
    end)
  end

  @doc """
  A small wrapper around `Repo.transaction/2`.

  Commits the transaction if the lambda returns `:ok` or `{:ok, result}`,
  rolling it back if the lambda returns `:error` or `{:error, reason}`. In both
  cases, the function returns the result of the lambda.

  Example:

      Repo.transact(fn ->
        with {:ok, user} <- Accounts.create_user(params),
            {:ok, _log} <- Logs.log_action(:user_registered, user),
            {:ok, _job} <- Mailer.enqueue_email_confirmation(user) do
          {:ok, user}
        end
      end)

  From blog post found [here](https://tomkonidas.com/repo-transact/)
  """
  @spec transact((-> any()), keyword()) :: {:ok, any()} | {:error, any()}
  def transact(fun, opts \\ []) do
    transaction(
      fn ->
        case fun.() do
          {:ok, value} -> value
          :ok -> :transaction_commited
          {:error, reason} -> rollback(reason)
          :error -> rollback(:transaction_rollback_error)
        end
      end,
      opts
    )
  end
end
