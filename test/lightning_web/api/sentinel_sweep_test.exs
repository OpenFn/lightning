defmodule LightningWeb.API.SentinelSweepTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories

  @sentinel plant_sentinel("x")

  @query plant_sentinel(%{
           "project_id" => nil,
           "id" => nil,
           "page" => nil,
           "page_size" => nil,
           "state" => nil,
           "inserted_after" => nil,
           "days" => nil,
           "offset" => nil,
           "limit" => nil,
           "cursor" => nil,
           "email" => nil,
           "snapshots" => nil
         })

  @body plant_sentinel(%{
          "id" => nil,
          "name" => nil,
          "project_id" => nil,
          "value" => nil,
          "items" => [%{"key" => nil, "value" => nil}]
        })

  @unauthenticated {401, :unauthenticated, ["Bearer"]}
  @invalid_token {401, :invalid_token, [~s(Bearer error="invalid_token")]}
  @session {401, :unauthenticated, [~s(Session realm="Lightning")]}
  @not_found {404, :not_found, []}
  @forbidden {403, :forbidden, []}
  @malformed {400, :malformed, []}
  @invalid_id {400, :invalid_parameter, []}

  # What every in-scope route answers, by the pipelines it goes through.
  #
  # `planted` is a member with a personal token and a request whose path
  # parameters aren't ids. `array` is the same member with real ids and a JSON
  # array for a body: `real_ids` for a route whose path parameters are all the
  # real ones, `other_ids` for a route with a path id the request doesn't have.
  # A route with no path parameter has nothing planted, so it is only held to
  # answering with a problem that quotes nothing.
  @pipelines %{
    [:access_token_api] => %{
      none: @unauthenticated,
      garbage: @invalid_token,
      planted: @invalid_token,
      array: %{real_ids: @invalid_token, other_ids: @invalid_token}
    },
    [:person_or_service_account_api] => %{
      none: @unauthenticated,
      garbage: @invalid_token,
      planted: :by_parent,
      array: %{real_ids: @malformed, other_ids: :by_parent}
    },
    [:authenticated_api] => %{
      none: @unauthenticated,
      garbage: @invalid_token,
      planted: :by_parent,
      array: %{real_ids: @malformed, other_ids: :by_parent}
    },
    [:authenticated_json, :require_authenticated_user] => %{
      none: @session,
      garbage: @session,
      planted: :by_parent,
      array: nil
    }
  }

  # Routes that take no token at all, each with the reason it answers the
  # same whatever the request carries.
  @exceptions %{
    [:api] => %{
      reason: "registration takes no token, and it is switched off here",
      none: {501, :not_implemented, []},
      garbage: {501, :not_implemented, []},
      planted: {501, :not_implemented, []},
      array: %{
        real_ids: {501, :not_implemented, []},
        other_ids: {501, :not_implemented, []}
      }
    },
    [:webhook] => %{
      reason:
        "webhooks run before any token check, and no trigger has the planted path",
      none: @not_found,
      garbage: @not_found,
      planted: @not_found,
      array: %{real_ids: @not_found, other_ids: @not_found}
    },
    [] => %{
      reason: "an unmatched path is answered before any token check",
      none: @not_found,
      garbage: @not_found,
      planted: @not_found,
      array: nil
    },
    :channel_proxy => %{
      reason:
        "the proxy sits above the router and finds the channel before it reads a token",
      none: @not_found,
      garbage: @not_found,
      planted: @not_found,
      array: %{real_ids: @not_found, other_ids: @not_found}
    }
  }

  setup do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    workflow = insert(:workflow, project: project)
    token = Lightning.Accounts.generate_api_token(user)

    member =
      build_conn()
      |> log_in_user(user)
      |> put_req_header("authorization", "Bearer " <> token)

    stranger = insert(:user)

    %{
      member: member,
      stranger:
        build_conn()
        |> log_in_user(stranger)
        |> put_req_header(
          "authorization",
          "Bearer " <> Lightning.Accounts.generate_api_token(stranger)
        ),
      real: %{"project_id" => project.id, "workflow_id" => workflow.id}
    }
  end

  test "a request with no token gets the answer its pipeline promises" do
    for route <- in_scope_routes() do
      conn = request(build_conn(), route, %{})
      assert_answer(conn, route, :none)
    end
  end

  test "a garbage bearer token gets the answer its pipeline promises" do
    garbage =
      put_req_header(build_conn(), "authorization", "Bearer " <> @sentinel)

    for route <- in_scope_routes() do
      conn = request(garbage, route, %{})
      assert_answer(conn, route, :garbage)
    end
  end

  test "a member who names ids that aren't there is refused for a project, and gets not found or the token refusal elsewhere",
       %{
         member: member
       } do
    for route <- in_scope_routes() do
      conn = request(member, route, %{})

      if has_path_parameter?(route) do
        assert_answer(conn, route, :planted)
      else
        assert_any_problem(conn, route)
      end
    end
  end

  test "a member who names ids that are there gets an answer that quotes nothing",
       %{
         member: member,
         real: real
       } do
    for route <- in_scope_routes() do
      conn = request(member, route, real)
      assert_any_problem(conn, route)
    end
  end

  test "a member who sends a JSON array to a write route gets malformed, or for an id that isn't there, refused for a project and not found elsewhere",
       %{member: member, real: real} do
    for %{verb: verb} = route <- in_scope_routes(),
        verb in [:post, :put, :patch] do
      conn = request(member, route, real, [@sentinel])
      assert_answer(conn, route, :array)
    end
  end

  test "a caller with no standing who names an id that isn't a UUID is refused with 403, wherever the id is",
       %{stranger: stranger, real: real} do
    for route <- in_scope_routes(),
        planted_ids(route, :array) != [],
        refused_to_a_stranger?(route) do
      with_route(route, :stranger, fn ->
        stranger
        |> request(route, real)
        |> assert_problem(403, :forbidden, [])
      end)
    end
  end

  # Anyone holding the grant may create a credential, so a malformed id there
  # is 400 to a stranger too.
  defp refused_to_a_stranger?(%{verb: :put, path: "/api/credentials/:id"}),
    do: false

  defp refused_to_a_stranger?(%{pipeline: pipeline}),
    do: pipeline != [:access_token_api] and Map.has_key?(@pipelines, pipeline)

  defp in_scope_routes do
    routes =
      for %{verb: verb, path: path} <-
            Phoenix.Router.routes(LightningWeb.Router),
          in_scope?(path),
          do: %{verb: verb, path: path, pipeline: pipeline(verb, path)}

    # The channel proxy sits above the router.
    [
      %{
        verb: :post,
        path: "/channels/:channel_id/*path",
        pipeline: :channel_proxy
      }
      | routes
    ]
  end

  defp in_scope?("/api/oauth/" <> _), do: false
  defp in_scope?("/api/" <> _), do: true
  defp in_scope?("/collections" <> _), do: true
  defp in_scope?("/adaptors/catalogue"), do: true
  defp in_scope?("/i/" <> _), do: true
  defp in_scope?(_path), do: false

  # The router's route list doesn't carry the pipelines, so ask the router
  # which route the planted request lands on.
  defp pipeline(verb, path) do
    method =
      if verb == :*, do: "GET", else: verb |> to_string() |> String.upcase()

    case Phoenix.Router.route_info(
           LightningWeb.Router,
           method,
           planted_path(path, %{}),
           "localhost"
         ) do
      %{pipe_through: pipeline} -> pipeline
      :error -> :no_route
    end
  end

  defp has_path_parameter?(%{path: path}), do: String.contains?(path, [":", "*"])

  # `ids` names the path parameters to fill with real ids, so a request can get
  # past the lookup to the checks on its query and body. Every other parameter
  # is planted.
  defp planted_path(path, ids) do
    path
    |> String.split("/")
    |> Enum.map_join("/", fn
      ":" <> param -> Map.get(ids, param, @sentinel)
      "*" <> _param -> @sentinel
      segment -> segment
    end)
  end

  defp request(conn, route, ids, body \\ @body)

  defp request(conn, %{verb: verb, path: path}, ids, body) do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-timezone", @sentinel)

    query = Map.merge(@query, Map.take(ids, ["project_id"]))
    path = planted_path(path, ids) <> "?" <> URI.encode_query(query)

    case verb do
      verb when verb in [:get, :*] ->
        get(conn, path)

      verb ->
        conn
        |> put_req_header("content-type", "application/json")
        |> dispatch(@endpoint, verb, path, Jason.encode!(body))
    end
  end

  # Provisioning takes its project from an `id` in the query, which the sweep
  # plants. An id that isn't a UUID names no project, so the request is a create,
  # which a member may not make.
  defp expected(%{verb: :post, path: "/api/provision"}, :array),
    do: {403, :forbidden, []}

  defp expected(%{pipeline: pipeline} = route, attempt) do
    row =
      Map.get(@pipelines, pipeline) || Map.get(@exceptions, pipeline) ||
        flunk(
          "#{describe(route)} goes through #{inspect(pipeline)}, which neither " <>
            "@pipelines nor @exceptions says what to expect from"
        )

    case {Map.fetch!(row, attempt), attempt} do
      {%{real_ids: real, other_ids: other}, :array} ->
        if all_ids_real?(route), do: real, else: by_parent(other, route, :array)

      {answer, _attempt} ->
        by_parent(
          answer ||
            flunk("#{describe(route)} has no #{attempt} answer in the table"),
          route,
          attempt
        )
    end
  end

  defp by_parent(:by_parent, route, attempt) do
    cond do
      no_standing_on_parent?(route, attempt) -> @forbidden
      unseen_credential?(route) -> @forbidden
      planted_ids(route, attempt) == [] -> @not_found
      true -> @invalid_id
    end
  end

  defp by_parent(answer, _route, _attempt), do: answer

  defp no_standing_on_parent?(%{path: path}, :array),
    do: path in ["/api/projects/:id", "/api/provision"]

  defp no_standing_on_parent?(%{path: path}, :planted) do
    path in [
      "/api/projects/:id",
      "/api/provision/:id",
      "/api/workflows/:id",
      "/api/jobs/:id",
      "/api/runs/:id",
      "/api/work_orders/:id"
    ] or String.contains?(path, ":project_id")
  end

  # Only the service account may read every credential, and nobody may delete
  # every one, so a person hears 403 for any id there. A `PUT` may create, so a
  # malformed id there stays 400.
  defp unseen_credential?(%{verb: verb, path: path}),
    do: path == "/api/credentials/:id" and verb in [:get, :delete]

  # Provisioning takes the project to replace from an `id` in the query, which
  # the sweep plants, so its path has no real id to find either.
  defp all_ids_real?(%{path: "/api/provision"}), do: false

  defp all_ids_real?(%{path: path}) do
    params = for ":" <> param <- String.split(path, "/"), do: param

    Enum.all?(params, &(&1 in ["project_id", "workflow_id"])) and
      not String.contains?(path, "*")
  end

  defp assert_answer(conn, route, attempt) do
    {status, code, challenges} = expected(route, attempt)

    entries =
      if code == :invalid_parameter, do: planted_ids(route, attempt), else: []

    with_route(route, attempt, fn ->
      assert_problem(conn, status, code, entries)
      assert get_resp_header(conn, "www-authenticate") == challenges
      refute_sentinel(conn)
    end)
  end

  defp planted_ids(%{path: path}, attempt) do
    real = if attempt == :array, do: ["project_id", "workflow_id"], else: []

    for ":" <> param <- String.split(path, "/"),
        param not in real,
        param == "id" or String.ends_with?(param, "_id") do
      not_a_uuid_entry(%{"path" => param})
    end
  end

  defp assert_any_problem(conn, route) do
    with_route(route, :any, fn ->
      refute_sentinel(conn)

      if conn.status >= 400 do
        %{"code" => code} = Jason.decode!(conn.resp_body)
        assert_problem(conn, conn.status, String.to_existing_atom(code))
      end
    end)
  end

  defp with_route(route, attempt, fun) do
    fun.()
  rescue
    error in ExUnit.AssertionError ->
      reraise %{
                error
                | message:
                    "#{describe(route)}, #{attempt}: " <>
                      (error.message || "assertion failed")
              },
              __STACKTRACE__
  end

  defp describe(%{verb: verb, path: path}),
    do: "#{verb |> to_string() |> String.upcase()} #{path}"
end
