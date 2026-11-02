defmodule LightningWeb.API.WebhooksChannelsHelpers do
  @moduledoc """
  Requests and setup shared by the tests of a project's webhook auth methods,
  channels and channel requests on the API.
  """
  import Lightning.Factories
  import Plug.Conn

  alias Lightning.Accounts

  @endpoint LightningWeb.Endpoint

  @doc "`conn` carrying `user`'s personal access token, accepting JSON."
  def with_pat(conn, user) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header(
      "authorization",
      "Bearer " <> Accounts.generate_api_token(user)
    )
  end

  @doc "An error entry at a body pointer, as decoded JSON."
  def entry(pointer, code, detail),
    do: %{"pointer" => pointer, "code" => code, "detail" => detail}

  @doc "Now, to the second, for a `scheduled_deletion`."
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc "Sends `body` to `path` as JSON with `verb`."
  def send_json(conn, verb, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> Phoenix.ConnTest.dispatch(@endpoint, verb, path, Jason.encode!(body))
  end

  @doc """
  The callers of a project route family, in a project with one member in each
  role, a project that requires MFA its owner hasn't set up, and a project
  scheduled for deletion. `stranger` belongs to none of them.
  """
  def callers do
    [owner, admin, editor, viewer, stranger, short_of_mfa] =
      insert_list(6, :user)

    project =
      insert(:project,
        project_users: [
          %{user: owner, role: :owner},
          %{user: admin, role: :admin},
          %{user: editor, role: :editor},
          %{user: viewer, role: :viewer}
        ]
      )

    %{
      owner: owner,
      admin: admin,
      editor: editor,
      viewer: viewer,
      stranger: stranger,
      short_of_mfa: short_of_mfa,
      superuser: insert(:user, role: :superuser),
      project: project,
      mfa_project:
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: short_of_mfa, role: :owner}]
        ),
      scheduled: insert(:project, scheduled_deletion: now())
    }
  end
end
