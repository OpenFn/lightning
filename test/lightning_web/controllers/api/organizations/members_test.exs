defmodule LightningWeb.API.Organizations.MembersTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiOrganizationsHelpers
  import LightningWeb.ApiProjectMembersHelpers, only: [send_json: 4, role_of: 2]
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.RaceHelpers

  setup %{conn: conn} do
    [admin, member] = insert_list(2, :user)
    organization = organization_with([{admin, :admin}, {member, :member}])

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      admin: admin,
      member: member,
      organization: organization
    }
  end

  defp members_path(organization),
    do: "/api/organizations/#{organization.id}/members"

  describe "adding a member" do
    test "an admin adds someone by email, giving them no project, and it's recorded",
         %{conn: conn, admin: admin, organization: organization} do
      ada = insert(:user)
      project = insert(:project, organization: organization)

      conn =
        conn
        |> session_conn(admin)
        |> send_json(:post, members_path(organization), %{
          "email" => ada.email,
          "role" => "member"
        })

      assert json_response(conn, 201)["data"] ==
               org_member_json(
                 organization.id,
                 ada,
                 :member,
                 joined_at(organization.id, ada.id)
               )

      assert org_role_of(organization.id, ada.id) == :member
      refute role_of(project.id, ada.id)

      assert org_audit_events(organization.id) == [
               {"member_added", admin.id,
                %{
                  before: nil,
                  after: %{"email" => ada.email, "role" => "member"}
                }}
             ]
    end

    test "a body it can't apply answers 422 and adds nobody",
         %{conn: conn, admin: admin, member: member, organization: organization} do
      for {body, entries} <- [
            {%{"colour" => "red"},
             [
               %{
                 "pointer" => "#/colour",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               },
               %{
                 "pointer" => "#/email",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/role",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{"email" => "nobody@example.com", "role" => "member"},
             [
               %{
                 "pointer" => "#/email",
                 "code" => "not_found",
                 "detail" => "names nothing you can see"
               }
             ]},
            {%{"email" => member.email, "role" => "admin"},
             [
               %{
                 "pointer" => "#/email",
                 "code" => "taken",
                 "detail" => "is already a member of the organization"
               }
             ]}
          ] do
        conn
        |> with_pat(admin)
        |> send_json(:post, members_path(organization), body)
        |> assert_problem(422, :invalid, entries)
      end

      assert org_role_of(organization.id, member.id) == :member
    end
  end

  describe "changing a member's role" do
    test "an admin makes a member an admin", %{
      conn: conn,
      admin: admin,
      member: member,
      organization: organization
    } do
      conn =
        conn
        |> with_pat(admin)
        |> send_json(:patch, org_member_path(organization.id, member.id), %{
          "role" => "admin"
        })

      assert json_response(conn, 200)["data"] ==
               org_member_json(
                 organization.id,
                 member,
                 :admin,
                 joined_at(organization.id, member.id)
               )

      assert org_audit_events(organization.id) == [
               {"member_role_changed", admin.id,
                %{
                  before: %{"email" => member.email, "role" => "member"},
                  after: %{"email" => member.email, "role" => "admin"}
                }}
             ]
    end

    test "the last admin can't become a member", %{
      conn: conn,
      admin: admin,
      organization: organization
    } do
      conn
      |> with_pat(admin)
      |> send_json(:patch, org_member_path(organization.id, admin.id), %{
        "role" => "member"
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/role",
          "code" => "one_admin",
          "detail" => "would leave the organization with no admin"
        }
      ])

      assert org_role_of(organization.id, admin.id) == :admin
    end
  end

  describe "removing a member" do
    test "an admin removes a member, who keeps their projects", %{
      conn: conn,
      admin: admin,
      member: member,
      organization: organization
    } do
      project =
        insert(:project,
          organization: organization,
          project_users: [%{user: member, role: :editor}]
        )

      conn =
        conn
        |> session_conn(admin)
        |> delete(org_member_path(organization.id, member.id))

      assert conn.status == 204
      assert conn.resp_body == ""
      refute org_role_of(organization.id, member.id)
      assert role_of(project.id, member.id) == :editor

      assert org_audit_events(organization.id) == [
               {"member_removed", admin.id,
                %{
                  before: %{"email" => member.email, "role" => "member"},
                  after: nil
                }}
             ]
    end

    test "the last admin can't be removed", %{
      conn: conn,
      admin: admin,
      organization: organization
    } do
      conn
      |> with_pat(admin)
      |> delete(org_member_path(organization.id, admin.id))
      |> assert_problem(422, :invalid, [
        %{
          "path" => "user_id",
          "code" => "one_admin",
          "detail" => "would leave the organization with no admin"
        }
      ])

      assert org_role_of(organization.id, admin.id) == :admin
    end
  end

  describe "stale writes" do
    test "a member another request removes mid-write is 409, on changing their role and removing them",
         %{conn: conn, admin: admin, member: member, organization: organization} do
      for request <- [
            &send_json(
              &1,
              :patch,
              org_member_path(organization.id, member.id),
              %{
                "role" => "admin"
              }
            ),
            &delete(&1, org_member_path(organization.id, member.id))
          ] do
        unless org_role_of(organization.id, member.id),
          do:
            insert(:organization_user,
              organization: organization,
              user: member,
              role: :member
            )

        # Fires once the route has read the membership, before it writes.
        after_first_query("organization_users", member.id, fn user_id ->
          Lightning.Repo.query!(
            "DELETE FROM organization_users WHERE user_id = $1",
            [user_id]
          )
        end)

        conn
        |> with_pat(admin)
        |> request.()
        |> assert_problem(409, :concurrent_edit, [])

        refute org_role_of(organization.id, member.id)
      end
    end
  end
end
