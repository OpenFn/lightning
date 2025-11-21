defmodule LightningWeb.BookDemoBannerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Mox
  import Phoenix.LiveViewTest

  setup :verify_on_exit!
  setup :register_and_log_in_user
  setup :create_project_for_current_user

  test "by default the banner is not shown", %{conn: conn, project: project} do
    for route <- routes_with_banner(project) do
      {:ok, view, html} = live(conn, route)
      refute html =~ "What problem are you trying to solve with OpenFn?"
      refute has_element?(view, "#book-demo-banner")
    end
  end

  test "the banner is shown when enabled in the config", %{
    conn: conn,
    project: project
  } do
    stub(Lightning.MockConfig, :book_demo_banner_enabled?, fn ->
      true
    end)

    for route <- routes_with_banner(project) do
      {:ok, view, html} = live(conn, route)
      assert has_element?(view, "#book-demo-banner")
      assert html =~ "What problem are you trying to solve with OpenFn?"
    end
  end

  test "the banner is not shown when the user has already dismissed it", %{
    conn: conn,
    project: project,
    user: user
  } do
    stub(Lightning.MockConfig, :book_demo_banner_enabled?, fn ->
      true
    end)

    user
    |> Ecto.Changeset.change(%{
      preferences: %{"demo_banner.dismissed_at" => 12_345_678}
    })
    |> Lightning.Repo.update!()

    for route <- routes_with_banner(project) do
      {:ok, view, html} = live(conn, route)
      refute has_element?(view, "#book-demo-banner")
      refute html =~ "What problem are you trying to solve with OpenFn?"
    end
  end

  test "user can dismiss the banner", %{
    conn: conn,
    project: project,
    user: user
  } do
    stub(Lightning.MockConfig, :book_demo_banner_enabled?, fn ->
      true
    end)

    refute user.preferences["demo_banner.dismissed_at"]

    route = routes_with_banner(project) |> hd()

    {:ok, view, _html} = live(conn, route)
    assert has_element?(view, "#book-demo-banner")
    assert has_element?(view, "#dismiss-book-demo-banner")

    view |> element("#dismiss-book-demo-banner") |> render_click()

    updated_user = Lightning.Repo.reload(user)
    assert updated_user.preferences["demo_banner.dismissed_at"]
  end

  test "user can successfully book for demo", %{
    conn: conn,
    project: project,
    user: user
  } do
    stub(Lightning.MockConfig, :book_demo_banner_enabled?, fn ->
      true
    end)

    workflow_url = "http://localhost:4001/i/1234"
    calendly_url = "https://calendly.com"

    stub(Lightning.MockConfig, :book_demo_calendly_url, fn ->
      calendly_url
    end)

    stub(Lightning.MockConfig, :book_demo_openfn_workflow_url, fn ->
      workflow_url
    end)

    expected_message = "Hello world"

    expected_body =
      %{
        "name" => "#{user.first_name} #{user.last_name}",
        "email" => user.email,
        "message" => expected_message
      }

    expected_redirect_url =
      calendly_url
      |> URI.parse()
      |> URI.append_query(URI.encode_query(expected_body))
      |> URI.to_string()

    expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{method: :post, url: ^workflow_url, body: ^expected_body}, _opts ->
        {:ok, %Tesla.Env{status: 200}}
      end
    )

    route = routes_with_banner(project) |> hd()

    {:ok, view, _html} = live(conn, route)
    assert has_element?(view, "#book-demo-banner")
    assert has_element?(view, "#book-demo-banner-modal")

    form = view |> form("#book-demo-banner-modal form")

    assert render_change(form, demo: %{email: nil, message: expected_message}) =~
             "This field can&#39;t be blank"

    assert render_submit(form) =~ "This field can&#39;t be blank"

    assert {:error, {:redirect, %{to: redirect_to}}} =
             render_submit(form,
               demo: %{email: user.email, message: expected_message}
             )

    assert redirect_to == expected_redirect_url
  end

  defp routes_with_banner(project) do
    [
      # projects page
      ~p"/projects",
      # workflows page
      ~p"/projects/#{project.id}/w",
      # history page
      ~p"/projects/#{project.id}/history",
      # settings page
      ~p"/projects/#{project.id}/settings",
      # profile page
      ~p"/profile",
      # personal access tokens page
      ~p"/profile/tokens",
      # credentials page
      ~p"/credentials"
    ]
  end
end
