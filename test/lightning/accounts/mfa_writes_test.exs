defmodule Lightning.Accounts.MfaWritesTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Accounts
  alias Lightning.Accounts.UserBackupCode
  alias Lightning.Accounts.UserTOTP
  alias Lightning.RaceHelpers

  defp mfa_user do
    user = insert(:user, mfa_enabled: true)
    totp = insert(:user_totp, user: user)
    {:ok, user} = Accounts.regenerate_user_backup_codes(user)
    {user, totp}
  end

  describe "upsert_user_totp/2" do
    test "saves a new secret over an existing one" do
      {user, totp} = mfa_user()
      secret = NimbleTOTP.secret()
      code = NimbleTOTP.verification_code(secret)

      assert {:ok, _totp} =
               Accounts.upsert_user_totp(%{totp | secret: secret}, %{code: code})

      assert %UserTOTP{secret: ^secret} = Accounts.get_user_totp(user)
    end

    test "answers :concurrent_edit when another request deleted the TOTP" do
      {user, totp} = mfa_user()
      secret = NimbleTOTP.secret()
      Repo.delete!(totp)

      assert {:error, :concurrent_edit} =
               Accounts.upsert_user_totp(%{totp | secret: secret}, %{
                 code: NimbleTOTP.verification_code(secret)
               })

      refute Accounts.get_user_totp(user)
    end
  end

  describe "delete_user_totp/1" do
    test "answers :concurrent_edit when another request deleted it first, and leaves MFA as it left it" do
      {user, totp} = mfa_user()
      Repo.delete!(totp)

      assert {:error, :concurrent_edit} = Accounts.delete_user_totp(totp)
      assert Repo.reload!(user).mfa_enabled
    end
  end

  describe "regenerate_user_backup_codes/1" do
    test "replaces every code and returns the user with the new ones" do
      {user, _totp} = mfa_user()
      old = Accounts.list_user_backup_codes(user)

      assert {:ok, %{backup_codes: new}} =
               Accounts.regenerate_user_backup_codes(user)

      assert length(new) == 10

      assert Enum.sort(Enum.map(new, & &1.id)) ==
               Enum.sort(
                 Enum.map(Accounts.list_user_backup_codes(user), & &1.id)
               )

      assert MapSet.disjoint?(
               MapSet.new(old, & &1.code),
               MapSet.new(new, & &1.code)
             )
    end

    test "answers :concurrent_edit, and changes nothing, when another request replaced the codes after they were read" do
      {user, _totp} = mfa_user()

      RaceHelpers.after_first_query("user_backup_codes", user.id, fn id ->
        Repo.query!("DELETE FROM user_backup_codes WHERE user_id = $1", [id])
      end)

      assert {:error, :concurrent_edit} =
               Accounts.regenerate_user_backup_codes(user)

      assert Repo.all(UserBackupCode) == []
    end
  end
end
