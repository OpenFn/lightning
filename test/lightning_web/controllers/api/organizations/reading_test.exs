defmodule LightningWeb.API.Organizations.ReadingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiOrganizationsHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  setup %{conn: conn} do
    %{conn: put_req_header(conn, "accept", "application/json")}
  end

  defp first_page(path),
    do: "#{LightningWeb.Endpoint.url()}#{path}?page=1&page_size=10"

  defp one_page(path) do
    %{
      "self" => first_page(path),
      "first" => first_page(path),
      "last" => first_page(path),
      "next" => nil,
      "prev" => nil
    }
  end

  describe "listing organizations" do
    test "a person sees the organizations they belong to, by name, with their role",
         %{conn: conn} do
      person = insert(:user)
      zeta = organization_with([{person, :admin}], name: "Zeta")
      alpha = organization_with([{person, :member}], name: "Alpha")
      _other = organization_with([], name: "Beta")

      conn = conn |> session_conn(person) |> get(~p"/api/organizations")

      assert json_response(conn, 200) == %{
               "data" => [
                 organization_json(alpha, :member),
                 organization_json(zeta, :admin)
               ],
               "included" => [],
               "links" => one_page("/api/organizations")
             }
    end

    test "a superuser sees every organization, with a null role where they aren't in it",
         %{conn: conn} do
      superuser = insert(:user, role: :superuser)
      theirs = organization_with([{superuser, :admin}], name: "Alpha")
      other = organization_with([], name: "Beta")

      conn = conn |> with_pat(superuser) |> get(~p"/api/organizations")

      assert json_response(conn, 200)["data"] == [
               organization_json(theirs, :admin),
               organization_json(other, nil)
             ]
    end

    test "pages, with links carrying the page size applied", %{conn: conn} do
      organizations =
        for name <- ~w(Alpha Beta Gamma), do: organization_with([], name: name)

      {conn, _account} = with_service_account(conn, ["organizations:write"])

      response =
        conn
        |> get(~p"/api/organizations?page=2&page_size=1&foo=bar")
        |> json_response(200)

      link =
        &"#{LightningWeb.Endpoint.url()}/api/organizations?page=#{&1}&page_size=1"

      assert response["data"] == [
               organization_json(Enum.at(organizations, 1), nil)
             ]

      assert response["links"] == %{
               "self" => link.(2),
               "first" => link.(1),
               "last" => link.(3),
               "next" => link.(3),
               "prev" => link.(1)
             }
    end
  end

  describe "reading an organization" do
    test "a member reads it with their role", %{conn: conn} do
      member = insert(:user)
      organization = organization_with([{member, :member}])

      conn =
        conn
        |> session_conn(member)
        |> get(~p"/api/organizations/#{organization.id}")

      assert json_response(conn, 200) == %{
               "data" => organization_json(organization, :member),
               "included" => [],
               "links" => %{
                 "self" =>
                   "#{LightningWeb.Endpoint.url()}/api/organizations/#{organization.id}"
               }
             }
    end
  end

  describe "listing members" do
    test "a member lists everyone in it, by first name", %{conn: conn} do
      ada = insert(:user, first_name: "Ada")
      grace = insert(:user, first_name: "Grace")
      organization = organization_with([{grace, :member}, {ada, :admin}])
      path = "/api/organizations/#{organization.id}/members"

      conn = conn |> session_conn(grace) |> get(path)

      assert json_response(conn, 200) == %{
               "data" => [
                 org_member_json(
                   organization.id,
                   ada,
                   :admin,
                   joined_at(organization.id, ada.id)
                 ),
                 org_member_json(
                   organization.id,
                   grace,
                   :member,
                   joined_at(organization.id, grace.id)
                 )
               ],
               "included" => [],
               "links" => one_page(path)
             }
    end
  end

  describe "a project's organization" do
    test "a project carries the organization it belongs to", %{conn: conn} do
      owner = insert(:user)
      organization = organization_with([{owner, :admin}])

      project =
        insert(:project,
          organization: organization,
          project_users: [%{user: owner, role: :owner}]
        )

      conn = conn |> with_pat(owner) |> get(~p"/api/projects/#{project.id}")

      assert json_response(conn, 200)["data"]["attributes"]["organization_id"] ==
               organization.id
    end
  end
end
