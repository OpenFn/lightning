defmodule LightningWeb.API.Credentials.PagingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "paging" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    setup %{user: user, project: project} do
      for n <- 1..11 do
        insert(:credential,
          user: user,
          name: "cred-#{String.pad_leading("#{n}", 2, "0")}",
          project_credentials: [%{project_id: project.id}]
        )
      end

      :ok
    end

    test "each list reads the number a page param starts with", %{
      conn: conn,
      project: project
    } do
      for path <- [
            "/api/credentials?",
            "/api/credentials?project_id=#{project.id}&",
            "/api/projects/#{project.id}/credentials?"
          ],
          {query, names, page} <- [
            {"", Enum.map(1..10, &"cred-#{String.pad_leading("#{&1}", 2, "0")}"),
             %{"page" => "1", "page_size" => "10"}},
            {"page=5abc&page_size=2.0", ["cred-09", "cred-10"],
             %{"page" => "5", "page_size" => "2"}},
            {"page=6&page_size=2", ["cred-11"],
             %{"page" => "6", "page_size" => "2"}}
          ] do
        assert %{"credentials" => credentials, "links" => %{"self" => self}} =
                 conn |> get(path <> query) |> json_response(200)

        query_params =
          self |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

        assert {Enum.map(credentials, & &1["name"]),
                Map.take(query_params, ["page", "page_size"])} ==
                 {names, page},
               path <> query
      end
    end

    test "pagination links carry the project filter applied and nothing else",
         %{conn: conn, project: project} do
      for {path, request_path, query} <- [
            {~p"/api/credentials?#{%{project_id: project.id, page_size: 1, foo: "bar"}}",
             "/api/credentials", %{"project_id" => project.id}},
            {~p"/api/projects/#{project.id}/credentials?page_size=1&foo=bar",
             "/api/projects/#{project.id}/credentials", %{}},
            {~p"/api/credentials?page_size=1&foo=bar", "/api/credentials", %{}}
          ] do
        %{"links" => links} = conn |> get(path) |> json_response(200)

        for {key, page} <- [
              {"self", "1"},
              {"first", "1"},
              {"next", "2"},
              {"last", "11"}
            ] do
          uri = URI.parse(links[key])

          assert {uri.path, URI.decode_query(uri.query)} ==
                   {request_path,
                    Map.merge(query, %{"page" => page, "page_size" => "1"})},
                 "#{path} #{key}"
        end

        assert links["prev"] == nil
      end
    end
  end

  describe "paging a project's credentials" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "keeps two owners' same-named credentials in order across a page boundary",
         %{conn: conn, project: project} do
      ids =
        for owner <- insert_list(2, :user) do
          insert(:credential,
            user: owner,
            name: "Same name",
            project_credentials: [%{project_id: project.id}]
          ).id
        end

      for {id, page} <- Enum.with_index(Enum.sort(ids), 1) do
        assert %{"credentials" => [%{"id" => ^id}]} =
                 conn
                 |> get(
                   ~p"/api/projects/#{project.id}/credentials?page=#{page}&page_size=1"
                 )
                 |> json_response(200)
      end
    end
  end
end
