defmodule LightningWeb.API.UserDeletionController do
  @moduledoc """
  Schedules a user's deletion and cancels it, for the service account only.

      DELETE /api/users/:id
      DELETE /api/users/:id/scheduled_deletion

  Scheduling disables the user, ends every session and revokes every token
  straight away, and emails them. Lightning removes them after the instance's
  retention period, unless they have created runs. A user already scheduled
  answers 409 `scheduled_for_deletion`, so a retry never turns into anything
  more. A superuser can't be scheduled and answers 409 `superuser`, since the
  refusal is about the user the path names; changing their role first clears
  it.

  Cancelling re-enables the user and answers 200 with them. A user who isn't
  scheduled answers 404 `not_found`.
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:users, :write_users}
       when action in [:delete, :cancel]

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    with {:ok, user} <- fetch_user(Request.param(conn, "id")),
         :ok <- not_scheduled(user),
         {:ok, _user} <- schedule(user, conn.assigns.current_resource) do
      send_resp(conn, :no_content, "")
    end
  end

  @spec cancel(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def cancel(conn, _params) do
    with {:ok, user} <- fetch_user(Request.param(conn, "id")),
         %User{scheduled_deletion: %DateTime{}} <- user,
         {:ok, user} <-
           Accounts.update_user(
             user,
             %{"scheduled_deletion" => nil, "disabled" => false},
             conn.assigns.current_resource
           ) do
      conn
      |> put_view(LightningWeb.API.UserJSON)
      |> render("show.json", user: user, conn: conn)
    else
      %User{scheduled_deletion: nil} -> {:error, :not_found}
      error -> error
    end
  end

  defp not_scheduled(%User{scheduled_deletion: nil}), do: :ok
  defp not_scheduled(%User{}), do: {:error, :scheduled_for_deletion}

  # The app asks for the user's email as a confirmation. The route names the
  # user by id, so it confirms with their own. The context refuses a
  # superuser with a `not_allowed` error.
  defp schedule(user, actor) do
    case Accounts.schedule_user_deletion(user, user.email, actor) do
      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Enum.any?(errors, &match?({_, {_, [code: :not_allowed]}}, &1)),
          do: {:error, :superuser},
          else: {:error, changeset}

      result ->
        result
    end
  end

  defp fetch_user(id) do
    with {:ok, id} <- Request.id(id) do
      case Accounts.get_user(id) do
        nil -> {:error, :not_found}
        user -> {:ok, user}
      end
    end
  end
end
