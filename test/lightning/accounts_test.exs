defmodule Lightning.AccountsTest do
  use Lightning.DataCase, async: true

  alias Lightning.AccountsFixtures
  alias Lightning.Credentials
  alias Lightning.Jobs
  alias Lightning.JobsFixtures
  alias Lightning.CredentialsFixtures
  alias Lightning.Projects
  alias Lightning.Accounts
  alias Lightning.Projects.ProjectUser

  alias Lightning.Accounts.{User, UserBackupCode, UserToken, UserTOTP}
  import Lightning.AccountsFixtures
  import Lightning.Factories

  test "has_activity_in_projects?/1 returns true if user has activity in a project (is associated with an attempt) and false otherwise." do
    user = AccountsFixtures.user_fixture()
    another_user = AccountsFixtures.user_fixture()

    workflow = insert(:workflow)
    trigger = insert(:trigger, workflow: workflow)
    dataclip = insert(:dataclip)

    work_order =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip
      )

    _attempt =
      insert(:attempt,
        created_by: user,
        work_order: work_order,
        starting_trigger: trigger,
        dataclip: dataclip
      )

    assert Accounts.has_activity_in_projects?(user)
    refute Accounts.has_activity_in_projects?(another_user)
  end

  test "list_users/0 returns all users" do
    user = user_fixture()
    assert user in Accounts.list_users()
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

  describe "get_user_totp/1" do
    setup do
      user = user_fixture()
      [user: user]
    end

    test "returns nil if the User has no TOTP", %{user: user} do
      assert Accounts.get_user_totp(user) |> is_nil()
    end

    test "returns the TOTP of the user if present", %{user: user} do
      %{id: id} =
        Repo.insert!(%UserTOTP{user_id: user.id, secret: "some secret"})

      assert %UserTOTP{id: ^id} = Accounts.get_user_totp(user)
    end
  end

  describe "upsert_user_totp/2" do
    setup do
      user = user_fixture()
      [user: user]
    end

    test "errors if the provided code is invalid", %{user: user} do
      user_totp = %UserTOTP{secret: NimbleTOTP.secret(), user_id: user.id}
      valid_code = NimbleTOTP.verification_code(user_totp.secret)

      invalid_code =
        valid_code
        |> String.to_integer()
        |> Kernel.+(1)
        |> Integer.mod(999_999)
        |> Integer.to_string()
        |> String.pad_leading(6, "0")

      {:error, changeset} =
        Accounts.upsert_user_totp(user_totp, %{code: invalid_code})

      assert %{code: ["invalid code"]} = errors_on(changeset)
    end

    test "creates the UserTOTP successfully with a valid code", %{user: user} do
      user_totp = %UserTOTP{secret: NimbleTOTP.secret(), user_id: user.id}
      valid_code = NimbleTOTP.verification_code(user_totp.secret)
      refute user.mfa_enabled

      assert {:ok, _totp} =
               Accounts.upsert_user_totp(user_totp, %{code: valid_code})

      updated_user = Repo.get(User, user.id)
      assert updated_user.mfa_enabled
    end

    test "generates backup codes", %{user: user} do
      assert Repo.preload(user, [:backup_codes]).backup_codes == []

      user_totp = %UserTOTP{secret: NimbleTOTP.secret(), user_id: user.id}
      valid_code = NimbleTOTP.verification_code(user_totp.secret)

      assert {:ok, _totp} =
               Accounts.upsert_user_totp(user_totp, %{code: valid_code})

      assert Repo.preload(user, [:backup_codes]).backup_codes |> Enum.count() ==
               10
    end

    test "backup codes are not regenerated if there are existing ones" do
      user =
        insert(:user,
          mfa_enabled: true,
          user_totp: build(:user_totp),
          backup_codes: build_list(10, :backup_code)
        )

      user_totp = %{user.user_totp | secret: NimbleTOTP.secret()}
      valid_code = NimbleTOTP.verification_code(user_totp.secret)

      assert {:ok, _totp} =
               Accounts.upsert_user_totp(user_totp, %{code: valid_code})

      query = from b in UserBackupCode, where: b.user_id == ^user.id
      backup_codes = Repo.all(query)
      assert Enum.count(backup_codes) == 10

      for backup_code <- backup_codes do
        assert backup_code in user.backup_codes
      end
    end
  end

  describe "regenerate_user_backup_codes/1" do
    setup do
      user =
        insert(:user,
          mfa_enabled: true,
          user_totp: build(:user_totp),
          backup_codes: build_list(10, :backup_code)
        )

      %{user: user}
    end

    test "generates new user backup codes", %{user: user} do
      {:ok, updated_user} = Accounts.regenerate_user_backup_codes(user)
      assert Enum.count(updated_user.backup_codes) == 10

      query = from b in UserBackupCode, where: b.user_id == ^user.id
      updated_backup_codes = Repo.all(query)

      for backup_code <- user.backup_codes do
        refute backup_code in updated_backup_codes
      end
    end
  end

  describe "list_user_backup_codes/1" do
    setup do
      user =
        insert(:user,
          mfa_enabled: true,
          user_totp: build(:user_totp),
          backup_codes: build_list(8, :backup_code)
        )

      %{user: user}
    end

    test "lists all backup codes for the user", %{user: user} do
      backup_codes = Accounts.list_user_backup_codes(user)
      assert Enum.count(backup_codes) == Enum.count(user.backup_codes)
    end
  end

  describe "valid_user_totp?/2" do
    setup do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      %{totp: Accounts.get_user_totp(user), user: user}
    end

    test "returns false if the code is not valid", %{user: user} do
      assert Accounts.valid_user_totp?(user, "invalid") == false
    end

    test "returns true for valid totp", %{user: user, totp: totp} do
      code = NimbleTOTP.verification_code(totp.secret)
      assert Accounts.valid_user_totp?(user, code) == true
    end
  end

  describe "valid_user_backup_code?/2" do
    setup do
      user =
        insert(:user,
          mfa_enabled: true,
          user_totp: build(:user_totp),
          backup_codes: build_list(10, :backup_code)
        )

      %{user: user}
    end

    test "returns false if the code is not valid", %{user: user} do
      assert Accounts.valid_user_backup_code?(user, "invalid") == false
    end

    test "returns true for valid code", %{user: user} do
      backup_code = Enum.random(user.backup_codes)
      assert Accounts.valid_user_backup_code?(user, backup_code.code) == true

      # backup code accanot be used again
      assert Accounts.valid_user_backup_code?(user, backup_code.code) == false

      for another_backup_code <- user.backup_codes -- [backup_code] do
        assert Accounts.valid_user_backup_code?(user, another_backup_code.code) ==
                 true
      end
    end
  end

  describe "delete_user_totp/1" do
    test "successfully deletes the given user TOTP and disables the mfa_flag" do
      user = user_fixture()
      user_totp = %UserTOTP{secret: NimbleTOTP.secret(), user_id: user.id}
      valid_code = NimbleTOTP.verification_code(user_totp.secret)
      {:ok, totp} = Accounts.upsert_user_totp(user_totp, %{code: valid_code})
      assert Repo.get(User, user.id).mfa_enabled
      {:ok, _} = Accounts.delete_user_totp(totp)
      refute Repo.get(User, user.id).mfa_enabled
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

      assert changeset.required == [:password, :email]
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

      assert changeset.required == [:password, :email]
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
      assert changeset.required == [:email]
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
      %{project_users: [proj_user1]} =
        insert(:project,
          project_users: [%{user: build(:user), failure_alert: true}]
        )

      %{project_users: [proj_user2]} =
        insert(:project,
          project_users: [%{user: build(:user), failure_alert: true}]
        )

      assert Repo.get(ProjectUser, proj_user1.id)
      assert Repo.get(User, proj_user1.user_id)

      :ok = Accounts.purge_user(proj_user1.user_id)

      refute Repo.get(ProjectUser, proj_user1.id)
      refute Repo.get(User, proj_user1.user_id)

      assert Repo.get(ProjectUser, proj_user2.id)
      assert Repo.get(User, proj_user2.user_id)
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

      assert count_for(Credentials.Credential) == 3

      :ok = Accounts.purge_user(user_1.id)

      assert count_for(Credentials.Credential) == 1

      refute Repo.all(Credentials.Credential)
             |> Enum.any?(fn x -> x.user_id == user_1.id end)

      assert Repo.all(Credentials.Credential)
             |> Enum.any?(fn x -> x.user_id == user_2.id end)
    end
  end

  describe "The default Oban function Accounts.perform/1" do
    test "prevents users that are still linked to an attempt from being deleted" do
      user =
        user_fixture(
          scheduled_deletion: DateTime.utc_now() |> Timex.shift(seconds: -10)
        )

      workflow = insert(:workflow)
      trigger = insert(:trigger, workflow: workflow)
      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      _attempt =
        insert(:attempt,
          created_by: user,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip
        )

      assert count_for(User) >= 1

      {:ok, %{users_deleted: users_deleted}} =
        Accounts.perform(%Oban.Job{args: %{"type" => "purge_deleted"}})

      assert Repo.get(User, user.id)

      refute user.id in Enum.map(users_deleted, & &1.id)
    end

    test "removes all users past deletion date when called with type 'purge_deleted'" do
      %{id: id_of_deleted} =
        user_fixture(
          scheduled_deletion: DateTime.utc_now() |> Timex.shift(seconds: -10)
        )

      user_fixture(
        scheduled_deletion: DateTime.utc_now() |> Timex.shift(seconds: 10)
      )

      {:ok, %{users_deleted: [%{id: ^id_of_deleted}]}} =
        Accounts.perform(%Oban.Job{args: %{"type" => "purge_deleted"}})
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
        Repo.update_all(UserToken, set: [inserted_at: ~U[2020-01-01 00:00:00Z]])

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
        Repo.update_all(UserToken, set: [inserted_at: ~U[2020-01-01 00:00:00Z]])

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
        Repo.update_all(UserToken, set: [inserted_at: ~U[2020-01-01 00:00:00Z]])

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
        Repo.update_all(UserToken, set: [inserted_at: ~U[2020-01-01 00:00:00Z]])

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
        Repo.update_all(UserToken, set: [inserted_at: ~U[2020-01-01 00:00:00Z]])

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

  describe "delete_user/1" do
    test "delete_user/1 deletes the user" do
      user = user_fixture()
      assert {:ok, %User{}} = Accounts.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(user.id) end
    end

    test "removes any associated Attempt and AttemptRun records" do
      user_1 = user_fixture()
      user_2 = user_fixture()

      attempt_1 = insert_attempt(user_1)
      attempt_2 = insert_attempt(user_1)
      attempt_3 = insert_attempt(user_2)

      _attempt_run_1_1 = insert_attempt_run(attempt_1)
      _attempt_run_1_2 = insert_attempt_run(attempt_1)
      _attempt_run_2_1 = insert_attempt_run(attempt_2)
      attempt_run_3_1 = insert_attempt_run(attempt_3)

      Accounts.delete_user(user_1)

      assert only_record_for_type?(attempt_3)

      assert only_record_for_type?(attempt_run_3_1)
    end

    test "removes any associated LogLine records" do
      user_1 = user_fixture()
      user_2 = user_fixture()

      insert_attempt(user_1, build_list(2, :log_line))
      insert_attempt(user_1, build_list(2, :log_line))

      attempt_3 = insert_attempt(user_2)
      log_line_3_1 = insert(:log_line, attempt: attempt_3)

      Accounts.delete_user(user_1)

      assert only_record_for_type?(log_line_3_1)
    end

    defp insert_attempt(user, log_lines \\ []) do
      insert(:attempt,
        created_by: user,
        work_order: build(:workorder),
        dataclip: build(:dataclip),
        starting_job: build(:job),
        log_lines: log_lines
      )
    end

    defp insert_attempt_run(attempt) do
      insert(:attempt_run, attempt: attempt, run: build(:step))
    end
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

  describe "SUDO mode" do
    setup do
      %{user: user_fixture()}
    end

    test "generates sudo session token", %{user: user} do
      token = Accounts.generate_sudo_session_token(user)

      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "sudo_session"

      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "sudo_session"
        })
      end
    end

    test "validates sudo session token", %{user: user} do
      token = Accounts.generate_sudo_session_token(user)
      assert Accounts.sudo_session_token_valid?(user, token)

      user2 = user_fixture()
      refute Accounts.sudo_session_token_valid?(user2, token)
      token_schema = Repo.get_by(UserToken, token: token)
      query = "update user_tokens set inserted_at=$1 where token=$2"

      Ecto.Adapters.SQL.query(Repo, query, [
        Timex.shift(token_schema.inserted_at, minutes: -5),
        token
      ])

      refute Accounts.sudo_session_token_valid?(user, token)
    end

    test "deletes sudo session token", %{user: user} do
      token = Accounts.generate_sudo_session_token(user)
      assert Repo.get_by(UserToken, token: token)
      Accounts.delete_sudo_session_token(token)
      refute Repo.get_by(UserToken, token: token)
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
