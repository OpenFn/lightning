defmodule Lightning.Accounts.UserTOTPTEst do
  use Lightning.DataCase, async: true

  alias Ecto.Changeset
  alias Lightning.Accounts.UserTOTP

  describe "changeset/2" do
    setup do
      %{
        user_totp: %UserTOTP{secret: NimbleTOTP.secret()}
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

    test "invalidates the changeset if struct does not have a secret set" do
      assert %Changeset{valid?: false, errors: errors} =
               UserTOTP.changeset(%UserTOTP{}, %{code: "123456"})

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
      %{
        user_totp: %UserTOTP{secret: NimbleTOTP.secret()}
      }
    end

    test "returns true for a valid code", %{
      user_totp: user_totp
    } do
      valid_code = NimbleTOTP.verification_code(user_totp.secret)

      assert UserTOTP.valid_totp?(user_totp, valid_code)
    end

    test "returns false for an invalid code", %{
      user_totp: user_totp
    } do
      invalid_code =
        case NimbleTOTP.verification_code(user_totp.secret) do
          "000000" -> "000001"
          _code -> "000000"
        end

      refute UserTOTP.valid_totp?(user_totp, invalid_code)
    end

    test "returns false if not passed an instance of UserTOTP", %{
      user_totp: user_totp
    } do
      not_a_user_totp = %{secret: user_totp.secret}
      valid_code = NimbleTOTP.verification_code(user_totp.secret)

      refute UserTOTP.valid_totp?(not_a_user_totp, valid_code)
    end

    test "returns false for a code that is not binary", %{
      user_totp: user_totp
    } do
      refute UserTOTP.valid_totp?(user_totp, 123_456)
    end

    test "returns false for a code that does not have byte_size of 6", %{
      user_totp: user_totp
    } do
      valid_code = NimbleTOTP.verification_code(user_totp.secret)

      provided_code = String.slice(valid_code, 0..4)

      refute UserTOTP.valid_totp?(user_totp, provided_code)
    end
  end
end
