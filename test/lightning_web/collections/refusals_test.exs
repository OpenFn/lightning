defmodule LightningWeb.API.CollectionsRefusalsTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiCollectionsHelpers

  alias Lightning.Accounts
  alias Lightning.Collections
  alias Lightning.Extensions.Message

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "who may reach it" do
    setup :member_with_collection

    test "answers 404 for a name in no project the token can see, on every route, and changes nothing",
         %{conn: conn, collection: collection} do
      insert(:collection_item, collection: collection, key: "k", value: "kept")
      outsider = Accounts.generate_api_token(insert(:user))

      for {_verb, request} <- routes_for(collection.name) do
        conn
        |> assign_bearer(outsider)
        |> request.()
        |> assert_problem(404, :not_found, [])
      end

      unseen =
        for token <- [outsider, run_token()],
            path <- [
              ~p"/collections/#{collection.name}",
              ~p"/collections/#{collection.name}?project_id=#{collection.project_id}"
            ],
            do: {assign_bearer(conn, token), path}

      for {conn, path} <- [{conn, ~p"/collections/no-such-collection"} | unseen] do
        conn |> get(path) |> assert_problem(404, :not_found, [])
      end

      conn =
        conn
        |> assign_bearer(run_token())
        |> put(
          ~p"/collections/#{collection.name}/k?project_id=#{collection.project_id}",
          value: "v"
        )

      assert_problem(conn, 404, :not_found, [])
      assert Collections.get(collection, "k").value == "kept"
    end

    test "answers 401 to a token that was deleted, or to a disabled user",
         %{conn: conn, user: user, collection: collection} do
      token = Accounts.generate_api_token(user)
      user_token = Repo.get_by(Accounts.UserToken, token: token)
      {:ok, _} = Accounts.delete_token(user_token)

      deleted =
        conn |> assign_bearer(token) |> get(~p"/collections/#{collection.name}")

      assert_problem(deleted, 401, :invalid_token, [])

      # A plain disable revokes sessions but not personal access tokens, so the
      # blocked-user check is what refuses this one.
      token = Accounts.generate_api_token(user)
      {:ok, _user} = Accounts.update_user(user, %{disabled: true})

      disabled =
        conn |> assign_bearer(token) |> get(~p"/collections/#{collection.name}")

      assert_problem(disabled, 401, :invalid_token, [])
    end

    test "checks the role before the query parameters", %{conn: conn} do
      collection = insert(:collection, project: insert(:project))

      conn = get(conn, ~p"/collections/#{collection.name}", limit: "ten")

      assert_problem(conn, 404, :not_found, [])
    end

    test "answers 409 to a member of a project scheduled for deletion", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      project
      |> Ecto.Changeset.change(
        scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      conn = put(conn, ~p"/collections/#{collection.name}/k", value: "v")

      assert_problem(conn, 409, :scheduled_for_deletion, [])
    end
  end

  describe "who may reach it, by role" do
    setup %{conn: conn} do
      for role <- [:viewer, :editor, :admin, :owner] do
        user = insert(:user)
        project = insert(:project, project_users: [%{user: user, role: role}])

        collection =
          insert(:collection,
            project: project,
            items: [
              %{key: "foo", value: "bar"},
              %{key: "baz", value: "qux"}
            ]
          )

        token = Lightning.Accounts.generate_api_token(user)
        conn = assign_bearer(conn, token)

        {role, %{conn: conn, collection: collection}}
      end
      |> Map.new()
      |> then(&{:ok, &1})
    end

    test "viewers may read but not write", ctx do
      %{conn: conn, collection: collection} = ctx.viewer

      assert conn
             |> get(~p"/collections/#{collection.name}/foo")
             |> json_response(200)

      assert conn
             |> get(~p"/collections/#{collection.name}")
             |> json_response(200)

      writes =
        for {verb, request} <- routes_for(collection.name),
            verb != :get,
            do: request

      for request <- [
            &delete(&1, ~p"/collections/#{collection.name}/foo"),
            (&delete(&1, ~p"/collections/#{collection.name}/missing")) | writes
          ] do
        assert_problem(request.(conn), 403, :forbidden, [])
      end

      assert Collections.get(collection, "foo")
      refute Collections.get(collection, "k")
    end

    test "editors may read and write but not delete every item", ctx do
      %{conn: conn, collection: collection} = ctx.editor

      assert conn
             |> put(~p"/collections/#{collection.name}/new", value: "v")
             |> json_response(200) == %{"upserted" => 1, "error" => nil}

      assert %{"upserted" => 1} =
               conn
               |> post(~p"/collections/#{collection.name}", %{
                 items: [%{key: "another", value: "v"}]
               })
               |> json_response(200)

      assert %{"deleted" => 1} =
               conn
               |> delete(~p"/collections/#{collection.name}/foo")
               |> json_response(200)

      for path <- [
            ~p"/collections/#{collection.name}",
            ~p"/collections/#{collection.name}?key=nomatch*"
          ] do
        conn |> delete(path) |> assert_problem(403, :forbidden, [])
      end

      assert Collections.get(collection, "baz")
    end

    test "a member short of the project's MFA requirement may not write", %{
      conn: conn
    } do
      user = insert(:user, mfa_enabled: false)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: user, role: :owner}]
        )

      collection = insert(:collection, project: project)
      insert(:collection_item, collection: collection, key: "k", value: "kept")
      conn = assign_bearer(conn, Lightning.Accounts.generate_api_token(user))

      for {verb, request} <- routes_for(collection.name), verb != :get do
        assert_problem(request.(conn), 403, :forbidden, [])
      end

      assert Collections.get(collection, "k").value == "kept"
    end

    for role <- [:admin, :owner] do
      test "#{role}s may delete every item", ctx do
        %{conn: conn, collection: collection} = ctx[unquote(role)]

        assert %{"deleted" => 2} =
                 conn
                 |> delete(~p"/collections/#{collection.name}")
                 |> json_response(200)

        refute Collections.get(collection, "foo")
      end
    end
  end

  describe "refusing a body or a key" do
    setup :member_with_collection

    test "PUT answers 400 malformed for a body that is not a JSON object, even with a key too long to store",
         %{conn: conn, collection: collection} do
      key = String.duplicate("k", 256)

      conn
      |> put_req_header("content-type", "application/json")
      |> put(~p"/collections/#{collection.name}/#{key}", Jason.encode!(["v"]))
      |> assert_problem(400, :malformed, [])

      assert Collections.get(collection, key) == nil
    end

    test "POST answers 400 malformed for a body that is not a JSON object", %{
      conn: conn,
      collection: collection
    } do
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/collections/#{collection.name}",
        Jason.encode!([%{key: "k", value: "v"}])
      )
      |> assert_problem(400, :malformed, [])

      assert Collections.get(collection, "k") == nil
    end

    test "PUT answers 422 for a value it cannot take", %{
      conn: conn,
      collection: collection
    } do
      for {body, entry} <- [
            {%{},
             %{
               "pointer" => "#/value",
               "code" => "required",
               "detail" => "can't be blank"
             }},
            {%{value: String.duplicate("x", 1_000_001)},
             %{
               "pointer" => "#/value",
               "code" => "too_long",
               "detail" => "should be at most 1000000 character(s)"
             }}
          ] do
        conn = put(conn, ~p"/collections/#{collection.name}/key", body)

        assert_problem(conn, 422, :invalid, [entry])
        assert Collections.get(collection, "key") == nil
      end
    end

    test "POST answers 422 for items it cannot take", %{
      conn: conn,
      collection: collection
    } do
      for {body, entry} <- [
            {%{},
             %{
               "pointer" => "#/items",
               "code" => "required",
               "detail" => "can't be blank"
             }},
            {%{
               items: [
                 %{key: "foo1", value: "bar1"},
                 %{key: "foo1", value: "bar1"}
               ]
             },
             %{
               "pointer" => "#/items/1/key",
               "code" => "duplicate",
               "detail" => "names the same key as #/items/0"
             }}
          ] do
        conn = post(conn, ~p"/collections/#{collection.name}", body)

        assert_problem(conn, 422, :invalid, [entry])
      end
    end

    test "PUT with a key too long to store answers 422 with an entry naming the key's path segment",
         %{conn: conn, collection: collection} do
      key = String.duplicate("k", 256)

      conn = put(conn, ~p"/collections/#{collection.name}/#{key}", value: "v")

      assert_problem(conn, 422, :invalid, [
        %{
          "path" => "key",
          "code" => "too_long",
          "detail" => "key is too long, please use a shorter one"
        }
      ])

      assert Collections.get(collection, key) == nil
    end

    test "PUT with a bad key and a bad value answers both entries, the value's first",
         %{conn: conn, collection: collection} do
      conn =
        put(
          conn,
          ~p"/collections/#{collection.name}/#{String.duplicate("k", 256)}",
          value: %{"not" => "a string"}
        )

      entries = [
        %{
          "pointer" => "#/value",
          "code" => "type",
          "detail" => "is invalid"
        },
        %{
          "path" => "key",
          "code" => "too_long",
          "detail" => "key is too long, please use a shorter one"
        }
      ]

      body = assert_problem(conn, 422, :invalid, entries)

      assert body["errors"] == entries
    end
  end

  describe "refusing query parameters" do
    setup :member_with_collection

    test "GET answers 400 naming every bad parameter, quoting none", %{
      conn: conn,
      collection: collection
    } do
      for {params, entries} <- [
            {[limit: "-5"],
             [
               %{
                 "parameter" => "limit",
                 "code" => "out_of_range",
                 "detail" => "must be greater than or equal to 0"
               }
             ]},
            {[
               limit: "ten",
               cursor: "not-a-cursor",
               colour: "red",
               updated_after: "2025-01-01"
             ],
             [
               %{
                 "parameter" => "colour",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               },
               %{
                 "parameter" => "cursor",
                 "code" => "type",
                 "detail" => "is invalid"
               },
               %{
                 "parameter" => "limit",
                 "code" => "type",
                 "detail" => "is invalid"
               },
               %{
                 "parameter" => "updated_after",
                 "code" => "type",
                 "detail" => "is invalid"
               }
             ]}
          ] do
        conn = get(conn, ~p"/collections/#{collection.name}", params)

        assert_problem(conn, 400, :invalid_parameter, entries)
      end
    end
  end

  describe "the plan limit" do
    setup :member_with_collection

    test "answers 402 when a write would pass it", %{
      conn: conn,
      collection: collection
    } do
      Mox.stub(
        Lightning.Extensions.MockCollectionHook,
        :handle_put_items,
        fn _collection, _size ->
          {:error, :exceeds_limit, %Message{text: "some limit error message"}}
        end
      )

      for request <- [
            &put(&1, ~p"/collections/#{collection.name}/foo2", value: "bar22"),
            &post(&1, ~p"/collections/#{collection.name}",
              items: [
                %{key: "foo4", value: "bar4"},
                %{key: "foo5", value: "bar5"}
              ]
            )
          ] do
        assert_problem(request.(conn), 402, :exceeds_limit, [])
      end
    end

    test "an invalid PUT or POST over the limit answers 422, not 402",
         %{conn: conn, collection: collection} do
      Mox.stub(Lightning.Extensions.MockCollectionHook, :handle_put_items, fn _c,
                                                                              _s ->
        {:error, :exceeds_limit, %Message{text: "limit"}}
      end)

      too_long = String.duplicate("x", 1_000_001)

      for {request, pointer} <- [
            {&put(&1, ~p"/collections/#{collection.name}/k", value: too_long),
             "#/value"},
            {&post(&1, ~p"/collections/#{collection.name}",
               items: [%{key: "k", value: too_long}]
             ), "#/items/0/value"}
          ] do
        assert_problem(request.(conn), 422, :invalid, [
          %{
            "pointer" => pointer,
            "code" => "too_long",
            "detail" => "should be at most 1000000 character(s)"
          }
        ])
      end
    end
  end

  describe "never quoting a request value" do
    setup :member_with_collection

    test "no answer quotes a value from the request",
         %{conn: conn, collection: collection} do
      sentinel = plant_sentinel(%{"x" => 1})["x"]

      conn
      |> get(
        ~p"/collections/#{collection.name}?#{plant_sentinel(%{"limit" => 1, "cursor" => 1, "updated_after" => 1})}"
      )
      |> refute_sentinel()
      |> assert_problem(400, :invalid_parameter, [
        %{"parameter" => "cursor", "code" => "type", "detail" => "is invalid"},
        %{"parameter" => "limit", "code" => "type", "detail" => "is invalid"},
        %{
          "parameter" => "updated_after",
          "code" => "type",
          "detail" => "is invalid"
        }
      ])

      conn
      |> put(
        ~p"/collections/#{collection.name}/#{String.duplicate(sentinel, 20)}",
        plant_sentinel(%{"value" => 1})
      )
      |> refute_sentinel()
      |> assert_problem(422, :invalid, [
        %{
          "path" => "key",
          "code" => "too_long",
          "detail" => "key is too long, please use a shorter one"
        }
      ])

      conn
      |> post(
        ~p"/collections/#{collection.name}",
        plant_sentinel(%{
          "items" => [%{"key" => 1, "value" => 1}, %{"key" => 1, "value" => 1}]
        })
      )
      |> refute_sentinel()
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/items/1/key",
          "code" => "duplicate",
          "detail" => "names the same key as #/items/0"
        }
      ])

      conn
      |> post(
        ~p"/collections/#{collection.name}",
        %{"items" => [%{"key" => 1, "value" => %{"a" => 1}}]}
        |> plant_sentinel()
        |> put_in(["items", Access.at(0), "value"], %{"a" => sentinel})
      )
      |> refute_sentinel()
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/items/0/value",
          "code" => "type",
          "detail" => "is invalid"
        }
      ])

      conn
      |> get(~p"/collections/#{collection.name}?#{%{project_id: sentinel}}")
      |> refute_sentinel()
      |> assert_problem(404, :not_found, [])
    end
  end
end
