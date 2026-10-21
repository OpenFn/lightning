defmodule LightningWeb.FirstSetupLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  # The page is drawn by React from data-props (none: one empty form). Its
  # fields, its own checks before a save and how it shows the reply's field
  # errors are tested in the design system's FirstSetupPage.test.tsx; the
  # event it sends in assets/test/design-system/FirstSetupPage.test.tsx.
  @page "#first-setup-page"

  @valid %{
    "firstName" => "Test",
    "lastName" => "McTest",
    "email" => "foo@example.com",
    "password" => "1234567890ab",
    "passwordConfirmation" => "1234567890ab"
  }

  defp save(view, values),
    do: push_page_event(view, @page, "save", Map.merge(@valid, values))

  describe "First setup" do
    @tag create_initial_user: false
    test "requires a user to create an initial superuser", %{conn: conn} do
      {:ok, show_live, html} =
        live(conn, Routes.first_setup_superuser_path(conn, :show),
          on_error: :raise
        )

      assert html =~ "Setup"
      assert page_props(show_live, @page) == %{}

      # The server checks the confirmation and the length again.
      save(show_live, %{"password" => "123", "passwordConfirmation" => ""})

      assert_reply(show_live, %{
        fieldErrors: %{
          "passwordConfirmation" => ["does not match confirmation"],
          "password" => ["Password minimum length is 12 characters."]
        }
      })

      refute Lightning.Accounts.has_one_superuser?()

      {:ok, conn} =
        show_live
        |> save(%{})
        |> follow_redirect(conn)

      assert "/projects" = redirected_path = redirected_to(conn, 302)

      html =
        get(recycle(conn), redirected_path)
        |> html_response(200)

      assert html =~ "Superuser account created."
      assert html =~ "Projects"
    end

    @tag create_initial_user: false
    test "refuses a superuser without a first and last name", %{conn: conn} do
      {:ok, show_live, _html} =
        live(conn, Routes.first_setup_superuser_path(conn, :show),
          on_error: :raise
        )

      save(show_live, %{
        "firstName" => " ",
        "lastName" => "",
        "email" => "nameless@example.com"
      })

      assert_reply(show_live, %{
        fieldErrors: %{"firstName" => [first], "lastName" => [last]}
      })

      assert first =~ "can't be blank"
      assert last =~ "can't be blank"
      refute Lightning.Accounts.get_user_by_email("nameless@example.com")
      refute Lightning.Accounts.has_one_superuser?()
    end

    @tag create_initial_user: false
    test "refuses a superuser with a control character in their name", %{
      conn: conn
    } do
      {:ok, show_live, _html} =
        live(conn, Routes.first_setup_superuser_path(conn, :show),
          on_error: :raise
        )

      save(show_live, %{
        "firstName" => "Ann\u0007",
        "lastName" => "Smith",
        "email" => "bell@example.com"
      })

      assert_reply(show_live, %{fieldErrors: %{"firstName" => [message]}})
      assert message =~ "can't contain control characters"
      refute Lightning.Accounts.get_user_by_email("bell@example.com")
      refute Lightning.Accounts.has_one_superuser?()
    end

    test "will redirect with a warning when a user already exists", %{conn: conn} do
      assert {:error, {:redirect, %{flash: %{}, to: "/projects"}}} ==
               live(conn, Routes.first_setup_superuser_path(conn, :show),
                 on_error: :raise
               )
    end
  end

  describe "while a service account is registered" do
    setup do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :allow_first_setup -> false
        flag -> Lightning.Config.API.check_flag?(flag)
      end)

      :ok
    end

    @tag create_initial_user: false
    test "does not redirect to first setup", %{conn: conn} do
      refute get(conn, "/") |> redirected_to() == "/first_setup"
    end

    @tag create_initial_user: false
    test "refuses first setup when there is no superuser", %{conn: conn} do
      assert get(conn, "/first_setup") |> response(404) =~
               "First setup is disabled"
    end

    @tag create_initial_user: false
    test "refuses first setup reached by live navigation", context do
      %{conn: conn} = register_and_log_in_user(context)
      {:ok, view, _html} = live(conn, "/credentials")

      assert {:error, {:redirect, %{to: "/projects"}}} =
               live_redirect(view, to: "/first_setup")
    end

    test "refuses first setup when a superuser exists", %{conn: conn} do
      assert get(conn, "/first_setup") |> response(404) =~
               "First setup is disabled"
    end
  end
end
