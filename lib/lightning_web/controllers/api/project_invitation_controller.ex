defmodule LightningWeb.API.ProjectInvitationController do
  @moduledoc """
  Inviting someone who has no account yet to a project.

  `POST /api/projects/:project_id/invitations` takes `email`, `first_name`,
  `last_name` and `role` (`admin`, `editor` or `viewer`), all required. It
  creates the user, adds them to the project and emails them, in the inviter's
  name, a link to set their password. It answers 201 with the member, as the
  member routes show one.

  An email that already has an account is a `taken` entry at `#/email` that
  names nothing about the account; add them with
  `PUT /api/projects/:project_id/members/:user_id` instead. A new member the
  plan has no seat for is 402.

  Only owners and admins may invite, on a person's own token, since the email
  names the inviter (`:invite_project_user`).
  """
  use LightningWeb, :controller

  import Ecto.Changeset

  alias Lightning.Accounts.User
  alias Lightning.Projects
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Projects.ProjectUser
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction, {:project_users, :invite_project_user}

  @fields [:email, :first_name, :last_name, :role]
  @user_fields [:email, :first_name, :last_name]

  @one_owner {"would change who owns the project, which has exactly one owner",
              code: :one_owner}
  @taken {"has already been taken", code: :taken}

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def create(conn, _params) do
    body = conn.body_params

    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:project_users, :invite_project_user}
           ),
         :ok <- Request.check_object(body),
         {:ok, invitee} <- invitee(body),
         :ok <- ProjectLimiter.request_new_user(project.id, 1),
         {:ok, changes} <-
           invite(project, invitee, conn.assigns.current_resource),
         {:ok, member} <-
           Projects.fetch_project_user(
             project.id,
             Map.fetch!(changes, {:new_user, invitee.email}).id
           ) do
      conn
      |> put_status(:created)
      |> put_view(json: LightningWeb.API.ProjectMemberJSON)
      |> render("show.json", member: member, conn: conn)
    end
  end

  # The account is checked as registering it will check it, so a body that
  # would fail there is refused here with every problem in it.
  defp invitee(body) do
    request =
      {%{}, %{role: ProjectUser.RolesEnum}}
      |> cast(body, [:role])
      |> validate_required(:role)

    registration =
      body
      |> Map.take(Enum.map(@user_fields, &Atom.to_string/1))
      |> User.user_registration_changeset(hash_password: false)

    account_errors = Keyword.take(registration.errors, @user_fields)

    entries =
      Request.unknown_keys(body, [], @fields) ++
        Errors.from_changeset(%{registration | errors: account_errors}) ++
        Errors.from_changeset(request) ++
        owner_entries(get_field(request, :role))

    with :ok <- Errors.refuse(entries) do
      {:ok,
       registration.changes
       |> Map.take(@user_fields)
       |> Map.put(:role, get_field(request, :role))}
    end
  end

  defp owner_entries(:owner), do: [Errors.entry([:role], @one_owner)]
  defp owner_entries(_role), do: []

  # An account registered for the email since the check fails the
  # registration, and is refused as a taken email.
  defp invite(project, invitee, inviter) do
    case Projects.invite_collaborators(project, [invitee], inviter) do
      {:ok, changes} ->
        {:ok, changes}

      {:error, :user_registration_failed} ->
        Errors.refuse([Errors.entry([:email], @taken)])

      {:error, _changeset} = refused ->
        Projects.unless_deleted(refused, project)
    end
  end
end
