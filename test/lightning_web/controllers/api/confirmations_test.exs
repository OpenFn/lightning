defmodule LightningWeb.API.ConfirmationsTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Swoosh.TestAssertions

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserToken
  alias Lightning.Config.API, as: ConfigAPI
  alias Lightning.Credentials
  alias Lightning.Repo

  @session_challenge [~s(Session realm="Lightning")]

  defp json_conn do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
  end

  defp email_token(user, context, sent_to) do
    {encoded, user_token} = UserToken.build_email_token(user, context, sent_to)
    Repo.insert!(user_token)
    encoded
  end

  defp shut_out_user do
    Mox.stub(Lightning.MockConfig, :check_flag?, fn
      :require_email_verification -> true
      flag -> ConfigAPI.check_flag?(flag)
    end)

    insert(:user,
      confirmed_at: nil,
      inserted_at: DateTime.add(DateTime.utc_now(), -49, :hour)
    )
  end

  defp confirmed?(user), do: not is_nil(Repo.reload!(user).confirmed_at)

  describe "resending by email" do
    test "sends the confirmation email and answers 202 with no body" do
      user = insert(:user, confirmed_at: nil)

      conn =
        post(json_conn(), ~p"/api/confirmations", %{"email" => user.email})

      assert conn.status == 202
      assert conn.resp_body == ""
      assert_email_sent(fn email -> assert [{_name, to}] = email.to end)
      assert [%UserToken{context: "confirm"}] = Repo.all(UserToken)
    end

    test "answers an unknown or confirmed email the same way, and sends nothing" do
      confirmed = insert(:user, confirmed_at: DateTime.utc_now())

      for email <- ["nobody@example.com", confirmed.email] do
        conn = post(json_conn(), ~p"/api/confirmations", %{"email" => email})

        assert conn.status == 202
        assert conn.resp_body == ""
      end

      assert_no_email_sent()
    end

    test "refuses a body that isn't an object with malformed" do
      json_conn()
      |> post(~p"/api/confirmations", "[1]")
      |> assert_problem(400, :malformed, [])
    end

    test "refuses a missing or mistyped email without a session, and any other key, with invalid" do
      for {body, entries} <- [
            {%{},
             [
               %{
                 "pointer" => "#/email",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{"email" => 7, "name" => "Ada"},
             [
               %{
                 "pointer" => "#/email",
                 "code" => "type",
                 "detail" => "is invalid"
               },
               %{
                 "pointer" => "#/name",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               }
             ]}
          ] do
        json_conn()
        |> post(~p"/api/confirmations", body)
        |> assert_problem(422, :invalid, entries)
      end

      assert_no_email_sent()
    end
  end

  describe "resending to the signed-in person" do
    test "sends to an account shut out until it confirms, and answers 202" do
      user = shut_out_user()

      conn = build_conn() |> session_conn(user) |> post(~p"/api/confirmations")

      assert conn.status == 202
      assert conn.resp_body == ""
      assert_email_sent(fn email -> assert [{_name, to}] = email.to end)
    end

    test "answers 202 and sends nothing when the account is already confirmed" do
      conn =
        build_conn()
        |> session_conn(insert(:user, confirmed_at: DateTime.utc_now()))
        |> post(~p"/api/confirmations")

      assert conn.status == 202
      assert_no_email_sent()
    end

    test "answers too_many_requests after three in 15 minutes" do
      conn = session_conn(build_conn(), insert(:user, confirmed_at: nil))

      for _attempt <- 1..3 do
        assert post(conn, ~p"/api/confirmations").status == 202
      end

      conn
      |> post(~p"/api/confirmations")
      |> assert_problem(429, :too_many_requests, [])
    end

    test "needs the session's CSRF token" do
      build_conn()
      |> session_conn(insert(:user, confirmed_at: nil), csrf: false)
      |> post(~p"/api/confirmations")
      |> assert_problem(400, :invalid_header, [
        %{
          "header" => "x-csrf-token",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])

      assert_no_email_sent()
    end
  end

  describe "confirming" do
    test "confirms the person's own account" do
      user = shut_out_user()
      token = email_token(user, "confirm", user.email)

      conn =
        build_conn()
        |> session_conn(user)
        |> put(~p"/api/confirmations/#{token}")

      assert json_response(conn, 200) == %{"data" => %{"confirmed" => "account"}}
      assert confirmed?(user)
    end

    test "confirms a new email address, which replaces the old one" do
      user = insert(:user)
      token = email_token(user, "change:#{user.email}", "new@example.com")

      conn =
        build_conn()
        |> session_conn(user)
        |> put(~p"/api/confirmations/#{token}")

      assert json_response(conn, 200) == %{"data" => %{"confirmed" => "email"}}
      assert %User{email: "new@example.com"} = Repo.reload!(user)
    end

    test "confirms a credential transfer, which moves the credential to its recipient" do
      owner = insert(:user)
      receiver = insert(:user)
      credential = insert(:credential, user: owner)
      :ok = Credentials.initiate_credential_transfer(owner, receiver, credential)
      assert_received {:email, email}

      [token] =
        Regex.run(~r{/transfer/([^\s\n/]+)}, email.text_body,
          capture: :all_but_first
        )

      conn =
        build_conn()
        |> session_conn(owner)
        |> put(~p"/api/confirmations/#{token}")

      assert json_response(conn, 200) == %{
               "data" => %{"confirmed" => "credential_transfer"}
             }

      assert Repo.reload!(credential).user_id == receiver.id
    end

    test "answers a used, unknown or someone else's token with not_found, and confirms nothing" do
      user = insert(:user, confirmed_at: nil)
      other = insert(:user, confirmed_at: nil)
      used = email_token(user, "confirm", user.email)
      {:ok, _user} = Accounts.confirm_user(used)

      user =
        user
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.force_change(:confirmed_at, nil)
        |> Repo.update!()

      theirs = email_token(other, "confirm", other.email)

      theirs_change =
        email_token(other, "change:#{other.email}", "taken@example.com")

      for token <- [used, theirs, theirs_change, "not-a-token"] do
        build_conn()
        |> session_conn(user)
        |> put(~p"/api/confirmations/#{token}")
        |> assert_problem(404, :not_found, [])
      end

      refute confirmed?(user)
      refute confirmed?(other)
      assert Repo.reload!(other).email == other.email
    end

    test "answers no session, or one from another site, with unauthenticated" do
      user = insert(:user, confirmed_at: nil)
      token = email_token(user, "confirm", user.email)

      for conn <- [
            from_own_page(build_conn()),
            session_conn(build_conn(), user, origin: :cross)
          ] do
        conn
        |> put(~p"/api/confirmations/#{token}")
        |> assert_unauthenticated(:unauthenticated, @session_challenge)
      end

      refute confirmed?(user)
    end

    test "needs the session's CSRF token" do
      user = insert(:user, confirmed_at: nil)
      token = email_token(user, "confirm", user.email)

      build_conn()
      |> session_conn(user, csrf: false)
      |> put(~p"/api/confirmations/#{token}")
      |> assert_problem(400, :invalid_header, [
        %{
          "header" => "x-csrf-token",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])

      refute confirmed?(user)
    end
  end
end
