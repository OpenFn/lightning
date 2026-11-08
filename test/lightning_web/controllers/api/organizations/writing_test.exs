defmodule LightningWeb.API.Organizations.WritingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiOrganizationsHelpers
  import LightningWeb.ApiProjectMembersHelpers, only: [send_json: 4]
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.Organizations.Organization
  alias Lightning.Repo

  setup %{conn: conn} do
    %{conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "creating an organization" do
    test "a superuser creates one with members, joins it as its admin, and it's recorded",
         %{conn: conn} do
      superuser = insert(:user, role: :superuser)
      ada = insert(:user)

      conn =
        conn
        |> with_pat(superuser)
        |> send_json(:post, "/api/organizations", %{
          "name" => "  Ministry of Health ",
          "members" => [
            %{"email" => String.upcase(ada.email), "role" => "member"}
          ]
        })

      assert %{"data" => %{"id" => id} = data} = json_response(conn, 201)
      organization = Repo.get!(Organization, id)

      assert data == organization_json(organization, :admin)
      assert organization.name == "Ministry of Health"
      assert org_role_of(id, superuser.id) == :admin
      assert org_role_of(id, ada.id) == :member

      assert org_audit_events(id) ==
               Enum.sort([
                 {"created", superuser.id,
                  %{before: nil, after: %{"name" => "Ministry of Health"}}},
                 {"member_added", superuser.id,
                  %{
                    before: nil,
                    after: %{"email" => superuser.email, "role" => "admin"}
                  }},
                 {"member_added", superuser.id,
                  %{
                    before: nil,
                    after: %{"email" => ada.email, "role" => "member"}
                  }}
               ])
    end

    test "the service account creates one with the admin it names", %{conn: conn} do
      ada = insert(:user)
      {conn, _account} = with_service_account(conn, ["organizations:write"])

      conn =
        send_json(conn, :post, "/api/organizations", %{
          "name" => "Ministry of Health",
          "members" => [%{"email" => ada.email, "role" => "admin"}]
        })

      assert %{"data" => %{"id" => id, "attributes" => %{"role" => nil}}} =
               json_response(conn, 201)

      assert org_role_of(id, ada.id) == :admin
    end

    test "a body it can't apply answers 422 with every problem and creates nothing",
         %{conn: conn} do
      ada = insert(:user)

      {service_conn, _account} =
        with_service_account(conn, ["organizations:write"])

      for {body, entries} <- [
            {%{"colour" => "red"},
             [
               %{
                 "pointer" => "#/colour",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               },
               %{
                 "pointer" => "#/name",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/members",
                 "code" => "one_admin",
                 "detail" => "needs at least one admin"
               }
             ]},
            {%{
               "name" => String.duplicate("a", 161),
               "members" => [
                 %{"email" => "nobody@example.com", "role" => "admin"},
                 %{"email" => ada.email, "role" => "admin"},
                 %{"email" => ada.email, "role" => "chief"}
               ]
             },
             [
               %{
                 "pointer" => "#/name",
                 "code" => "too_long",
                 "detail" => "should be at most 160 character(s)"
               },
               %{
                 "pointer" => "#/members/0/email",
                 "code" => "not_found",
                 "detail" => "names nothing you can see"
               },
               %{
                 "pointer" => "#/members/2/role",
                 "code" => "not_allowed",
                 "detail" => "is invalid"
               }
             ]},
            {%{
               "name" => "Twice",
               "members" => [
                 %{"email" => ada.email, "role" => "admin"},
                 %{"email" => ada.email, "role" => "member"}
               ]
             },
             [
               %{
                 "pointer" => "#/members/1/email",
                 "code" => "duplicate",
                 "detail" => "names the same user as #/members/0"
               }
             ]}
          ] do
        service_conn
        |> send_json(:post, "/api/organizations", body)
        |> assert_problem(422, :invalid, entries)
      end

      assert Repo.aggregate(Organization, :count) == 0
    end

    test "only a superuser or the service account may create one", %{conn: conn} do
      person = insert(:user)
      organization_with([{person, :admin}])

      conn
      |> with_pat(person)
      |> send_json(:post, "/api/organizations", %{"name" => "Mine"})
      |> assert_problem(403, :forbidden, [])

      assert Repo.aggregate(Organization, :count) == 1
    end
  end

  describe "renaming an organization" do
    test "an admin renames it, and it's recorded", %{conn: conn} do
      admin = insert(:user)
      organization = organization_with([{admin, :admin}], name: "Old")

      conn =
        conn
        |> session_conn(admin)
        |> send_json(:patch, "/api/organizations/#{organization.id}", %{
          "name" => "New"
        })

      renamed = Repo.reload!(organization)

      assert json_response(conn, 200)["data"] ==
               organization_json(renamed, :admin)

      assert renamed.name == "New"

      assert org_audit_events(organization.id) == [
               {"updated", admin.id,
                %{before: %{"name" => "Old"}, after: %{"name" => "New"}}}
             ]
    end

    test "the same name again changes nothing and records nothing", %{conn: conn} do
      admin = insert(:user)
      organization = organization_with([{admin, :admin}], name: "Same")

      conn =
        conn
        |> with_pat(admin)
        |> send_json(:patch, "/api/organizations/#{organization.id}", %{
          "name" => "Same"
        })

      assert json_response(conn, 200)["data"] ==
               organization_json(organization, :admin)

      assert org_audit_events(organization.id) == []
    end

    test "a body it can't apply answers 422 and renames nothing", %{conn: conn} do
      admin = insert(:user)
      organization = organization_with([{admin, :admin}], name: "Kept")

      for {body, entries} <- [
            {%{},
             [
               %{
                 "pointer" => "#/name",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{"name" => " ", "id" => "x"},
             [
               %{
                 "pointer" => "#/id",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               },
               %{
                 "pointer" => "#/name",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]}
          ] do
        conn
        |> with_pat(admin)
        |> send_json(:patch, "/api/organizations/#{organization.id}", body)
        |> assert_problem(422, :invalid, entries)
      end

      assert Repo.reload!(organization).name == "Kept"
    end
  end
end
