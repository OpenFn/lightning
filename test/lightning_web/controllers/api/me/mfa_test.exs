defmodule LightningWeb.API.Me.MfaTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  alias Lightning.Accounts
  alias Lightning.Accounts.UserBackupCode
  alias Lightning.Accounts.UserTOTP
  alias Lightning.Repo
  alias Lightning.RaceHelpers

  defp mfa_user do
    user = insert(:user, mfa_enabled: true)
    insert(:user_totp, user: user)
    Accounts.regenerate_user_backup_codes(user)
    user
  end

  defp codes(user) do
    for code <- Accounts.list_user_backup_codes(user),
        do: %{"code" => code.code, "used_at" => nil}
  end

  defp new_secret, do: Base.encode32(NimbleTOTP.secret(), padding: false)

  defp code_for(secret),
    do:
      secret |> Base.decode32!(padding: false) |> NimbleTOTP.verification_code()

  describe "reading" do
    test "shows whether MFA is on, and no backup codes to a session that hasn't stepped up" do
      user = mfa_user()

      conn = build_conn() |> session_conn(user) |> get(~p"/api/me/mfa")

      assert json_response(conn, 200) == %{
               "data" => %{"enabled" => true, "backup_codes" => nil}
             }
    end

    test "shows the backup codes, and when each was used, to a stepped-up session" do
      user = mfa_user()
      [first | _rest] = Accounts.list_user_backup_codes(user)
      assert Accounts.valid_user_backup_code?(user, first.code)

      conn =
        build_conn()
        |> session_conn(user, stepped_up: true)
        |> get(~p"/api/me/mfa")

      assert %{"data" => %{"enabled" => true, "backup_codes" => shown}} =
               json_response(conn, 200)

      assert length(shown) == 10

      assert [%{"code" => code, "used_at" => used_at}] =
               Enum.reject(shown, &is_nil(&1["used_at"]))

      assert code == first.code
      assert {:ok, _at, 0} = DateTime.from_iso8601(used_at)
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end
  end

  describe "starting set-up" do
    test "answers a new secret and its otpauth URI, and saves nothing" do
      user = insert(:user)

      conn = build_conn() |> session_conn(user) |> post(~p"/api/me/mfa")

      assert %{"data" => %{"secret" => secret, "otpauth_uri" => uri}} =
               json_response(conn, 201)

      assert byte_size(Base.decode32!(secret, padding: false)) == 20

      assert uri ==
               "otpauth://totp/OpenFn:#{URI.encode(user.email)}?secret=#{secret}&issuer=OpenFn"

      refute Accounts.get_user_totp(user)
    end
  end

  describe "turning on" do
    test "turns MFA on, makes ten backup codes and steps the session up to show them" do
      user = insert(:user)
      secret = new_secret()
      conn = session_conn(build_conn(), user)

      answer =
        put(conn, ~p"/api/me/mfa", %{
          "secret" => secret,
          "code" => code_for(secret)
        })

      user = Repo.reload!(user)
      assert user.mfa_enabled

      assert json_response(answer, 200) == %{
               "data" => %{"enabled" => true, "backup_codes" => codes(user)}
             }

      assert length(codes(user)) == 10

      assert %UserTOTP{secret: saved} = Accounts.get_user_totp(user)
      assert saved == Base.decode32!(secret, padding: false)

      assert {:ok, sudo_token} =
               answer |> get_session(:sudo_token) |> Base.decode64()

      assert Accounts.sudo_session_token_valid?(user, sudo_token)
    end

    test "replaces the authenticator when MFA is on, keeping the backup codes, and doesn't step up" do
      user = mfa_user()
      before = codes(user)
      secret = new_secret()

      conn =
        build_conn()
        |> session_conn(user)
        |> put(~p"/api/me/mfa", %{"secret" => secret, "code" => code_for(secret)})

      assert json_response(conn, 200) == %{
               "data" => %{"enabled" => true, "backup_codes" => nil}
             }

      assert Accounts.get_user_totp(user).secret ==
               Base.decode32!(secret, padding: false)

      assert codes(user) == before
    end

    test "refuses a body that isn't an object with malformed" do
      build_conn()
      |> session_conn(insert(:user))
      |> put(~p"/api/me/mfa", "[1]")
      |> assert_problem(400, :malformed, [])
    end

    test "refuses a code that doesn't match the secret with a mismatch entry, and saves nothing" do
      user = insert(:user)
      secret = new_secret()
      other = code_for(new_secret())

      build_conn()
      |> session_conn(user)
      |> put(~p"/api/me/mfa", %{"secret" => secret, "code" => other})
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/code",
          "code" => "mismatch",
          "detail" => "invalid code"
        }
      ])

      refute Accounts.get_user_totp(user)
      refute Repo.reload!(user).mfa_enabled
    end

    test "refuses a missing or bad secret, a missing or mistyped code, and any other key" do
      user = insert(:user)
      conn = session_conn(build_conn(), user)

      for {body, entries} <- [
            {%{},
             [
               %{
                 "pointer" => "#/secret",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/code",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{"secret" => "TOOSHORT", "code" => 123_456, "name" => "x"},
             [
               %{
                 "pointer" => "#/secret",
                 "code" => "format",
                 "detail" => "is not a secret POST /api/me/mfa gives"
               },
               %{
                 "pointer" => "#/code",
                 "code" => "type",
                 "detail" => "is invalid"
               },
               %{
                 "pointer" => "#/name",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               }
             ]},
            {%{"secret" => 7, "code" => "123456"},
             [
               %{
                 "pointer" => "#/secret",
                 "code" => "type",
                 "detail" => "is invalid"
               }
             ]}
          ] do
        conn
        |> put(~p"/api/me/mfa", body)
        |> assert_problem(422, :invalid, entries)
      end

      refute Accounts.get_user_totp(user)
    end
  end

  describe "turning off" do
    test "turns MFA off on a stepped-up session, keeping the backup codes" do
      user = mfa_user()
      before = codes(user)

      conn =
        build_conn()
        |> session_conn(user, stepped_up: true)
        |> delete(~p"/api/me/mfa")

      assert conn.status == 204
      assert conn.resp_body == ""
      refute Repo.reload!(user).mfa_enabled
      refute Accounts.get_user_totp(user)
      assert codes(user) == before
    end

    test "answers 204 when MFA is already off" do
      user = insert(:user)

      conn =
        build_conn()
        |> session_conn(user, stepped_up: true)
        |> delete(~p"/api/me/mfa")

      assert conn.status == 204
    end

    test "answers a session that hasn't stepped up with step_up_required, and keeps MFA on" do
      user = mfa_user()

      build_conn()
      |> session_conn(user)
      |> delete(~p"/api/me/mfa")
      |> assert_problem(403, :step_up_required, [])

      assert Repo.reload!(user).mfa_enabled
    end
  end

  describe "making new backup codes" do
    test "replaces every backup code on a stepped-up session" do
      user = mfa_user()
      before = codes(user)

      conn =
        build_conn()
        |> session_conn(user, stepped_up: true)
        |> post(~p"/api/me/mfa/backup_codes")

      assert json_response(conn, 201) == %{
               "data" => %{"enabled" => true, "backup_codes" => codes(user)}
             }

      assert length(codes(user)) == 10
      assert MapSet.disjoint?(MapSet.new(codes(user)), MapSet.new(before))
      refute Accounts.valid_user_backup_code?(user, hd(before)["code"])
    end

    test "refuses a session that hasn't stepped up, and a person without MFA" do
      user = mfa_user()
      before = codes(user)

      build_conn()
      |> session_conn(user)
      |> post(~p"/api/me/mfa/backup_codes")
      |> assert_problem(403, :step_up_required, [])

      no_mfa = insert(:user)

      build_conn()
      |> session_conn(no_mfa, stepped_up: true)
      |> post(~p"/api/me/mfa/backup_codes")
      |> assert_problem(403, :forbidden, [])

      assert codes(user) == before
      assert Accounts.list_user_backup_codes(no_mfa) == []
    end
  end

  describe "stale writes" do
    test "replacing the authenticator while another request turns MFA off answers concurrent_edit" do
      user = mfa_user()
      secret = new_secret()

      RaceHelpers.after_first_query("user_totps", user.id, fn id ->
        Repo.query!("DELETE FROM user_totps WHERE user_id = $1", [id])
      end)

      build_conn()
      |> session_conn(user)
      |> put(~p"/api/me/mfa", %{"secret" => secret, "code" => code_for(secret)})
      |> assert_problem(409, :concurrent_edit, [])

      refute Accounts.get_user_totp(user)
    end

    test "turning MFA off after another request did answers concurrent_edit" do
      user = mfa_user()

      RaceHelpers.after_first_query("user_totps", user.id, fn id ->
        Repo.query!("DELETE FROM user_totps WHERE user_id = $1", [id])
      end)

      build_conn()
      |> session_conn(user, stepped_up: true)
      |> delete(~p"/api/me/mfa")
      |> assert_problem(409, :concurrent_edit, [])

      refute Accounts.get_user_totp(user)
    end

    test "making backup codes while another request makes them answers concurrent_edit" do
      user = mfa_user()
      theirs = UserBackupCode.generate_backup_code()

      RaceHelpers.after_first_query("user_backup_codes", user.id, fn id ->
        Repo.query!("DELETE FROM user_backup_codes WHERE user_id = $1", [id])

        Repo.query!(
          "INSERT INTO user_backup_codes (id, user_id, code, inserted_at, updated_at) VALUES ($1, $2, $3, now(), now())",
          [
            Ecto.UUID.dump!(Ecto.UUID.generate()),
            id,
            Lightning.Encrypted.Binary.dump(theirs) |> elem(1)
          ]
        )
      end)

      build_conn()
      |> session_conn(user, stepped_up: true)
      |> post(~p"/api/me/mfa/backup_codes")
      |> assert_problem(409, :concurrent_edit, [])

      assert [%{"code" => ^theirs}] = codes(user)
    end
  end
end
