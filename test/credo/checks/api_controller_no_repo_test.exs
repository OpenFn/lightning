Code.require_file("../../../credo/checks/api_controller_no_repo.ex", __DIR__)

defmodule Lightning.Credo.Check.ApiControllerNoRepoTest do
  use Credo.Test.Case

  alias Lightning.Credo.Check.ApiControllerNoRepo

  test "every reference to Repo or Ecto.Query in an API controller is flagged" do
    for {line, trigger} <- [
          {"alias Lightning.Repo", "Lightning.Repo"},
          {"import Ecto.Query", "Ecto.Query"},
          {"import Ecto.Query.API", "Ecto.Query.API"},
          {"require Ecto.Query", "Ecto.Query"},
          {"def show(id), do: Repo.get(Project, id)", "Repo"},
          {"def show(id), do: Lightning.Repo.get(Project, id)",
           "Lightning.Repo"},
          {"def list, do: Ecto.Query.from(p in Project)", "Ecto.Query"}
        ] do
      """
      defmodule LightningWeb.API.ThingController do
        #{line}
      end
      """
      |> to_source_file()
      |> run_check(ApiControllerNoRepo)
      |> assert_issue(fn issue ->
        assert issue.trigger == trigger, "for: #{line}"
        assert issue.line_no == 2
      end)
    end
  end

  test "an API controller using a context and Ecto.Changeset is clean" do
    """
    defmodule LightningWeb.API.ThingController do
      alias Ecto.Changeset
      alias Lightning.Projects

      def show(id), do: Projects.get_project(id)

      def check(params) do
        {%{}, %{name: :string}}
        |> Changeset.cast(params, [:name])
        |> Changeset.validate_required([:name])
      end
    end
    """
    |> to_source_file()
    |> run_check(ApiControllerNoRepo)
    |> refute_issues()
  end
end
