defmodule Lightning.AccountsTest do
  use Lightning.DataCase, async: true

  alias Lightning.AccountsFixtures
  alias Lightning.InvocationFixtures
  alias Lightning.Credentials
  alias Lightning.Jobs
  alias Lightning.JobsFixtures
  alias Lightning.CredentialsFixtures
  alias Lightning.Projects
  alias Lightning.Accounts
  alias Lightning.Projects.ProjectUser

  alias Lightning.Accounts.{User, UserToken}
  import Lightning.AccountsFixtures

  test "has_activity_in_projects?/1 returns true if user is has activity in a project (is associated to invocation reasons) and false otherwise." do
    user = AccountsFixtures.user_fixture()
    another_user = AccountsFixtures.user_fixture()

    InvocationFixtures.reason_fixture(user_id: user.id)

    assert Accounts.has_activity_in_projects?(user)
    refute Accounts.has_activity_in_projects?(another_user)
  end

  test "list_users/0 returns all users" do
    user = user_fixture()
    assert Accounts.list_users() == [user]
  end

  test "list_api_token/1 returns all user tokens" do
    user = user_fixture()

    tokens =
      for(_ <- 1..3, do: Accounts.generate_api_token(user))
      |> Enum.sort()

    assert Accounts.list_api_tokens(user) |> Enum.map(& &1.token) |> Enum.sort() ==
             tokens
  end

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password(
               "unknown@example.com",
               "hello world!"
             )
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(
                 user.email,
                 valid_user_password()
               )
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(Ecto.UUID.generate())
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "get_token!/1" do
    test "raises if token is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_token!(Ecto.UUID.generate())
      end
    end

    test "returns the token with the given id" do
      user = user_fixture()
      token = Accounts.generate_api_token(user)
      %{id: id} = user_token = Repo.get_by(UserToken, token: token)

      assert %UserToken{id: ^id} = Accounts.get_token!(user_token.id)
    end
  end

  describe "register_user/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "requires terms and conditions to be accepted" do
      {:error, changeset} = Accounts.register_user(%{terms_accepted: false})

      assert %{
               terms_accepted: [
                 "Please accept the terms and conditions to register."
               ]
             } = errors_on(changeset)

      {:error, changeset} = Accounts.register_user(%{terms_accepted: true})

      assert %{} = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} =
        Accounts.register_user(%{email: "not valid", password: "not valid"})

      assert %{
               email: ["must have the @ sign and no spaces"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db@db.sn", 100)

      {:error, changeset} =
        Accounts.register_user(%{email: too_long, password: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} =
        Accounts.register_user(%{email: String.upcase(email)})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with a hashed password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert user.role == :user
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "register_superuser/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_superuser(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} =
        Accounts.register_superuser(%{email: "not valid", password: "not valid"})

      assert %{
               email: ["must have the @ sign and no spaces"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db@db.sn", 100)

      {:error, changeset} =
        Accounts.register_superuser(%{email: too_long, password: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "registers users with a hashed password and sets role to :superuser" do
      email = unique_user_email()

      {:ok, user} =
        Accounts.register_superuser(%{
          email: email,
          first_name: "Sizwe",
          password: valid_user_password()
        })

      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
      assert user.role == :superuser
    end
  end

  describe "change_user_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_registration()

      assert changeset.required == [:password, :email, :first_name]
    end

    test "allows fields to be set" do
      email = unique_user_email()
      password = valid_user_password()

      changeset =
        Accounts.change_user_registration(
          valid_user_attributes(email: email, password: password)
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :password) == password
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "change_superuser_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} =
               changeset = Accounts.change_superuser_registration()

      assert changeset.required == [:password, :email, :first_name]
    end

    test "allows fields to be set" do
      email = unique_user_email()
      password = valid_user_password()

      changeset =
        Accounts.change_superuser_registration(
          valid_user_attributes(email: email, password: password)
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :password) == password
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "change_user_email/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email, :first_name]
    end
  end

  describe "change_scheduled_deletion/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} =
               changeset = Accounts.change_scheduled_deletion(%User{})

      assert changeset.required == []
    end
  end

  describe "purge user" do
    test "purging a user removes that user from projects they are members of and deletes them from the system" do
      user_1 = user_fixture()
      user_2 = user_fixture()

      Lightning.Projects.create_project(%{
        name: "some-name",
        project_users: [%{user_id: user_1.id}]
      })

      Lightning.Projects.create_project(%{
        name: "some-name",
        project_users: [%{user_id: user_2.id}]
      })

      assert 2 == Repo.all(ProjectUser) |> Enum.count()
      assert 2 == Repo.all(User) |> Enum.count()

      :ok = Accounts.purge_user(user_1.id)

      assert 1 == Repo.all(ProjectUser) |> Enum.count()
      assert 1 == Repo.all(User) |> Enum.count()

      remaining_projs = Repo.all(ProjectUser)
      remaining_users = Repo.all(User)

      assert 1 == Enum.count(remaining_projs)
      assert 1 == Enum.count(remaining_users)

      assert remaining_projs
             |> Enum.any?(fn x -> x.user_id == user_2.id end)

      refute remaining_projs
             |> Enum.any?(fn x -> x.user_id == user_1.id end)

      assert remaining_users
             |> Enum.any?(fn x -> x.id == user_2.id end)

      refute remaining_users
             |> Enum.any?(fn x -> x.id == user_1.id end)
    end

    test "purging a user sets all project credentials that use their credentials to nil" do
      user = user_fixture()
      project = Lightning.ProjectsFixtures.project_fixture()

      project_credential_1 =
        CredentialsFixtures.project_credential_fixture(
          project_id: project.id,
          user_id: user.id
        )

      project_credential_2 = CredentialsFixtures.project_credential_fixture()

      job_1 =
        JobsFixtures.job_fixture(project_credential_id: project_credential_1.id)

      job_2 =
        JobsFixtures.job_fixture(project_credential_id: project_credential_2.id)

      refute job_1.project_credential_id |> is_nil()
      refute job_2.project_credential_id |> is_nil()

      :ok = Accounts.purge_user(user.id)

      # job_1 project_credential_id is now set to nil
      assert Jobs.get_job!(job_1.id).project_credential_id |> is_nil()

      # while job_2 project_credential_id remain with a value
      refute Jobs.get_job!(job_2.id).project_credential_id |> is_nil()
    end

    test "purging user deletes all project credentials that involve this user's credentials" do
      user = user_fixture()

      CredentialsFixtures.project_credential_fixture(user_id: user.id)
      CredentialsFixtures.project_credential_fixture(user_id: user.id)
      CredentialsFixtures.project_credential_fixture()

      assert count_project_credentials_for_user(user) == 2

      :ok = Accounts.purge_user(user.id)

      assert count_project_credentials_for_user(user) == 0
    end

    test "purging a user deletes all of that user's credentials" do
      user_1 = user_fixture()
      user_2 = user_fixture()

      CredentialsFixtures.credential_fixture(user_id: user_1.id)
      CredentialsFixtures.credential_fixture(user_id: user_1.id)
      CredentialsFixtures.credential_fixture(user_id: user_2.id)

      assert 3 == Repo.all(Credentials.Credential) |> Enum.count()

      :ok = Accounts.purge_user(user_1.id)

      assert 1 == Repo.all(Credentials.Credential) |> Enum.count()

      refute Repo.all(Credentials.Credential)
             |> Enum.any?(fn x -> x.user_id == user_1.id end)

      assert Repo.all(Credentials.Credential)
             |> Enum.any?(fn x -> x.user_id == user_2.id end)
    end
  end

  describe "The default Oban function Accounts.perform/1" do
    test "prevents users that are still linked to an invocation reason from being deleted" do
      user =
        user_fixture(
          scheduled_deletion: DateTime.utc_now() |> Timex.shift(seconds: -10)
        )

      InvocationFixtures.reason_fixture(user_id: user.id)

      assert 1 = Repo.all(User) |> Enum.count()

      {:ok, %{users_deleted: users_deleted}} =
        Accounts.perform(%Oban.Job{args: %{"type" => "purge_deleted"}})

      # We still have one user in database
      assert 1 == Repo.all(User) |> Enum.count()

      # No user has been deleted
      assert 0 == users_deleted |> Enum.count()
    end

    test "removes all users past deletion date when called with type 'purge_deleted'" do
      user_to_delete =
        user_fixture(
          scheduled_deletion: DateTime.utc_now() |> Timex.shift(seconds: -10)
        )

      user_fixture(
        scheduled_deletion: DateTime.utc_now() |> Timex.shift(seconds: 10)
      )

      count_before = Repo.all(User) |> Enum.count()

      {:ok, %{users_deleted: users_deleted}} =
        Accounts.perform(%Oban.Job{args: %{"type" => "purge_deleted"}})

      assert count_before - 1 == Repo.all(User) |> Enum.count()
      assert 1 == users_deleted |> Enum.count()

      assert user_to_delete.id == users_deleted |> Enum.at(0) |> Map.get(:id)
    end

    test "removes user from project users before deleting them" do
      user_to_delete =
        user_fixture(
          scheduled_deletion: DateTime.utc_now() |> Timex.shift(seconds: -10)
        )

      another_user = user_fixture()

      project =
        Lightning.ProjectsFixtures.project_fixture(
          project_users: [
            %{user_id: user_to_delete.id},
            %{user_id: another_user.id}
          ]
        )

      {:ok, %{users_deleted: users_deleted}} =
        Accounts.perform(%Oban.Job{args: %{"type" => "purge_deleted"}})

      assert 1 == users_deleted |> Enum.count()

      assert user_to_delete.id == users_deleted |> Enum.at(0) |> Map.get(:id)

      project = Projects.get_project!(project.id) |> Repo.preload(:project_users)

      refute Enum.any?(project.project_users, fn project_user ->
               project_user.user_id == user_to_delete.id
             end)

      assert Enum.any?(project.project_users, fn project_user ->
               project_user.user_id == another_user.id
             end)
    end
  end

  describe "apply_user_email/3" do
    setup do
      %{user: user_fixture()}
    end

    test "requires email to change", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{})

      assert %{email: ["did not change"]} = errors_on(changeset)
    end

    test "validates email", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{
          email: "not valid"
        })

      assert %{email: ["must have the @ sign and no spaces"]} =
               errors_on(changeset)
    end

    test "validates maximum value for email for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{user: user} do
      %{email: email} = user_fixture()

      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: email})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, "invalid", %{email: unique_user_email()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "applies the email without persisting it", %{user: user} do
      email = unique_user_email()

      {:ok, user} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: email})

      assert user.email == email
      assert Accounts.get_user!(user.id).email != email
    end
  end

  describe "deliver_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_update_email_instructions(
            user,
            "current@example.com",
            url
          )
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)

      assert user_token =
               Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))

      assert user_token.user_id == user.id
      assert user_token.sent_to == "current@example.com"
      assert user_token.context == "change:#{user.email}"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = user_fixture()
      # email = "current@example.com"
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_update_email_instructions(
            user,
            email,
            url
          )
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{
      user: user,
      token: token,
      email: email
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, changed_user} = Accounts.update_user_email(user, token)

      assert changed_user.email != user.email
      assert changed_user.email == email
      assert changed_user.confirmed_at
      assert changed_user.confirmed_at >= now
      assert changed_user.confirmed_at != user.confirmed_at

      assert Accounts.update_user_email(user, token) == :error,
             "Attempting to reuse the same token should return :error"

      refute Repo.get_by(UserToken, user_id: user.id),
             "The token should not exist after using it"
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} =
        Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} =
               changeset = Accounts.change_user_password(%User{})

      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(%User{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/3" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: too_long
        })

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, "invalid", %{
          password: valid_user_password()
        })

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "updates the password", %{user: user} do
      {:ok, user} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      assert is_nil(user.password)

      assert Accounts.get_user_by_email_and_password(
               user.email,
               "new valid password"
             )
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, _} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end
  end

  describe "generate_auth_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_auth_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "auth"

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "auth"
        })
      end
    end
  end

  describe "exchange_auth_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_auth_token(user)
      %{user: user, token: token}
    end

    test "returns a new session token", %{user: user, token: auth_token} do
      assert session_token = Accounts.exchange_auth_token(auth_token)
      assert session_user = Accounts.get_user_by_session_token(session_token)
      assert session_user.id == user.id

      refute Accounts.get_user_by_auth_token(auth_token)
    end

    test "does not return for an invalid token" do
      refute Accounts.exchange_auth_token("oops")
    end
  end

  describe "generate_api_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_api_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "api"

      Lightning.Accounts.UserToken.verify_and_validate!(token)

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "api"
        })
      end
    end
  end

  describe "get_user_by_api_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_api_token(user)

      user_token =
        token
        |> UserToken.token_and_context_query("api")
        |> Repo.one()

      %{user: user, token: token, user_token: user_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert auth_user = Accounts.get_user_by_api_token(token)
      assert auth_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_api_token("oops")
    end
  end

  describe "delete_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_api_token(user)
      %{id: id} = user_token = Repo.get_by(UserToken, token: token)

      assert {:ok, %UserToken{}} = Accounts.delete_token(user_token)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_token!(id) end
    end
  end

  describe "get_user_by_auth_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_auth_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert auth_user = Accounts.get_user_by_auth_token(token)
      assert auth_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_auth_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} =
        Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      refute Accounts.get_user_by_auth_token(token)
    end
  end

  describe "delete_auth_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_auth_token(user)
      assert Accounts.delete_auth_token(token) == :ok
      refute Accounts.get_user_by_auth_token(token)
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} =
        Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_user_confirmation_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)

      assert user_token =
               Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))

      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "confirm"
    end
  end

  describe "deliver_user_confirmation_instructions/3" do
    setup do
      %{superuser: superuser_fixture(), user: user_fixture()}
    end

    test "sends token through notification", %{superuser: superuser, user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(superuser, user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)

      assert user_token =
               Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))

      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "confirm"
    end
  end

  describe "confirm_user/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "confirms the email with a valid token", %{user: user, token: token} do
      assert {:ok, confirmed_user} = Accounts.confirm_user(token)
      assert confirmed_user.confirmed_at
      assert confirmed_user.confirmed_at != user.confirmed_at
      assert Repo.get!(User, user.id).confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm with invalid token", %{user: user} do
      assert Accounts.confirm_user("oops") == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm email if token expired", %{user: user, token: token} do
      {1, nil} =
        Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.confirm_user(token) == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)

      assert user_token =
               Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))

      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "reset_password"
    end
  end

  describe "get_user_by_reset_password_token/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "returns the user with valid token", %{user: %{id: id}, token: token} do
      assert %User{id: ^id} = Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: id)
    end

    test "does not return the user with invalid token", %{user: user} do
      refute Accounts.get_user_by_reset_password_token("oops")
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not return the user if token expired", %{user: user, token: token} do
      {1, nil} =
        Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      refute Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "reset_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.reset_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.reset_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, updated_user} =
        Accounts.reset_user_password(user, %{password: "new valid password"})

      assert is_nil(updated_user.password)

      assert Accounts.get_user_by_email_and_password(
               user.email,
               "new valid password"
             )
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, _} =
        Accounts.reset_user_password(user, %{password: "new valid password"})

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  test "delete_user/1 deletes the user" do
    user = user_fixture()
    assert {:ok, %User{}} = Accounts.delete_user(user)
    assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(user.id) end
  end

  describe "scheduling a user for deletion" do
    setup do
      prev = Application.get_env(:lightning, :purge_deleted_after_days)
      Application.put_env(:lightning, :purge_deleted_after_days, 2)

      on_exit(fn ->
        Application.put_env(:lightning, :purge_deleted_after_days, prev)
      end)
    end

    test "schedule_user_deletion/2 sets a date in the future according to the :purge_deleted_after_days env" do
      days = Application.get_env(:lightning, :purge_deleted_after_days)

      user = user_fixture()
      assert user.scheduled_deletion == nil

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, user} = Accounts.schedule_user_deletion(user, user.email)

      assert user.scheduled_deletion != nil
      assert Timex.diff(user.scheduled_deletion, now, :days) == days
      assert user.disabled
    end
  end

  describe "inspect/2" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  test "has_one_superuser?/0" do
    refute Accounts.has_one_superuser?()

    user_fixture()
    refute Accounts.has_one_superuser?()

    superuser_fixture()
    assert Accounts.has_one_superuser?()
  end

  defp count_project_credentials_for_user(user) do
    from(pc in Ecto.assoc(user, [:credentials, :project_credentials]))
    |> Repo.aggregate(:count, :id)
  end
end
