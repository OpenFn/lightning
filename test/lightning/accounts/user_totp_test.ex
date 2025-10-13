defmodule Lightning.Accounts.UserTOTPTest do
  use Lightning.DataCase, async: true

  alias Ecto.Changeset
  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserTOTP
  alias Lightning.Repo

  describe "changeset/2" do
    setup do
      insert(:user_totp, user: build(:user))

      %{
        user_totp: Repo.one!(UserTOTP)
      }
    end

    test "creates a valid changeset if given a valid code", %{
      user_totp: user_totp
    } do
      valid_code = NimbleTOTP.verification_code(user_totp.secret)

      assert %Changeset{valid?: true, changes: %{code: ^valid_code}} =
               UserTOTP.changeset(user_totp, %{code: valid_code})
    end

    test "invalidates the changeset if not given a code", %{
      user_totp: user_totp
    } do
      assert %Changeset{valid?: false, errors: errors} =
               UserTOTP.changeset(user_totp, %{})

      assert errors == [
               {:code, {"invalid code", []}},
               {:code, {"can't be blank", [validation: :required]}}
             ]
    end

    test "invalidates the changeset if struct does not have a secret set", %{
      user_totp: %{user_id: user_id}
    } do
      assert %Changeset{valid?: false, errors: errors} =
               UserTOTP.changeset(%UserTOTP{user_id: user_id}, %{code: "123456"})

      assert errors == [
               {:code, {"invalid code", []}},
               {:secret, {"can't be blank", [validation: :required]}}
             ]
    end

    test "invalidates the changeset if the code is not a 6-digit string", %{
      user_totp: user_totp
    } do
      valid_code = NimbleTOTP.verification_code(user_totp.secret)
      provided_code = String.slice(valid_code, 0..4)

      assert %Changeset{valid?: false, errors: errors} =
               UserTOTP.changeset(user_totp, %{code: provided_code})

      assert errors == [
               {:code, {"invalid code", []}},
               {:code, {"should be a 6 digit number", [validation: :format]}}
             ]
    end

    test "invalidates the changeset for a well-formed, invalid code", %{
      user_totp: user_totp
    } do
      invalid_code =
        case NimbleTOTP.verification_code(user_totp.secret) do
          "000000" -> "000001"
          _code -> "000000"
        end

      assert %Changeset{valid?: false, errors: errors} =
               UserTOTP.changeset(user_totp, %{code: invalid_code})

      assert errors == [code: {"invalid code", []}]
    end
  end

  describe "valid_totp" do
    setup do
      insert(:user_totp, user: build(:user))

      %{
        totp_time: System.os_time(:second),
        user_totp: Repo.one!(UserTOTP)
      }
    end

    test "returns true for a valid code", %{
      user_totp: user_totp,
      totp_time: totp_time
    } do
      valid_code =
        NimbleTOTP.verification_code(user_totp.secret, time: totp_time)

      assert UserTOTP.valid_totp?(user_totp, valid_code)
    end

    test "returns false for an invalid code", %{
      totp_time: totp_time,
      user_totp: user_totp
    } do
      stale_time = totp_time - 120

      invalid_code =
        NimbleTOTP.verification_code(user_totp.secret, time: stale_time)

      refute UserTOTP.valid_totp?(user_totp, invalid_code)
    end

    test "returns false if not passed an instance of UserTOTP", %{
      totp_time: totp_time,
      user_totp: user_totp
    } do
      not_a_user_totp = %{secret: user_totp.secret}

      valid_code =
        NimbleTOTP.verification_code(user_totp.secret, time: totp_time)

      refute UserTOTP.valid_totp?(not_a_user_totp, valid_code)
    end

    test "returns false for a code that is not binary", %{
      user_totp: user_totp
    } do
      refute UserTOTP.valid_totp?(user_totp, 123_456)
    end

    test "returns false for a code that does not have byte_size of 6", %{
      totp_time: totp_time,
      user_totp: user_totp
    } do
      valid_code =
        NimbleTOTP.verification_code(user_totp.secret, time: totp_time)

      provided_code = String.slice(valid_code, 0..4)

      refute UserTOTP.valid_totp?(user_totp, provided_code)
    end

    test "uses the passed in time when validating the code", %{
      totp_time: totp_time,
      user_totp: user_totp
    } do
      stale_time = totp_time - 120

      valid_code =
        NimbleTOTP.verification_code(user_totp.secret, time: totp_time)

      refute UserTOTP.valid_totp?(user_totp, valid_code, time: stale_time)
    end

    test "rejects valid code if TOTP was last validated within window", %{
      totp_time: totp_time,
      user_totp: user_totp
    } do
      set_last_totp_at(user_totp.user_id, totp_time)

      valid_code =
        NimbleTOTP.verification_code(user_totp.secret, time: totp_time)

      refute UserTOTP.valid_totp?(user_totp, valid_code, time: totp_time)
    end

    test "allows valid code reuse if TOTP was last validated outside window", %{
      totp_time: totp_time,
      user_totp: user_totp
    } do
      set_last_totp_at(user_totp.user_id, totp_time - 60)

      valid_code =
        NimbleTOTP.verification_code(user_totp.secret, time: totp_time)

      assert UserTOTP.valid_totp?(user_totp, valid_code, time: totp_time)
    end

    test "allows use of valid code if last_totp_at has not been set", %{
      totp_time: totp_time,
      user_totp: user_totp
    } do
      set_last_totp_at(user_totp.user_id, nil)

      valid_code =
        NimbleTOTP.verification_code(user_totp.secret, time: totp_time)

      assert UserTOTP.valid_totp?(user_totp, valid_code, time: totp_time)
    end

    defp set_last_totp_at(user_id, last_totp_at_unix) do
      last_totp_at =
        case last_totp_at_unix do
          nil -> nil
          unix -> DateTime.from_unix!(unix * 1_000_000, :microsecond)
        end

      User
      |> Repo.get!(user_id)
      |> Ecto.Changeset.change(%{last_totp_at: last_totp_at})
      |> Repo.update!()
    end
  end
end
