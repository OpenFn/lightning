defmodule Lightning.Scrivener.QueryPaginaterTest do
  use Lightning.DataCase, async: true

  import Ecto.Query

  alias Lightning.Projects.Project

  describe "paginating a grouped query" do
    setup do
      for _ <- 1..3 do
        insert(:project,
          project_users: for(_ <- 1..3, do: %{user: build(:user)})
        )
      end

      :ok
    end

    test "counts groups, not joined rows" do
      page =
        from(p in Project,
          join: pu in assoc(p, :project_users),
          group_by: p.id,
          order_by: p.name
        )
        |> Repo.paginate(page: 1, page_size: 2)

      assert page.total_entries == 3
      assert page.total_pages == 2
      assert length(page.entries) == 2
    end
  end

  test "group_by builds an Ecto.Query.ByExpr" do
    assert [%Ecto.Query.ByExpr{}] = from(p in Project, group_by: p.id).group_bys
  end
end
