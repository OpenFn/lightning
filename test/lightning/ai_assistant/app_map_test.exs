defmodule Lightning.AiAssistant.AppMapTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Lightning.AiAssistant.AppMap

  describe "load/1" do
    test "decodes the committed artifact into a list of pages" do
      pages = AppMap.load(Application.app_dir(:lightning, "priv/app_map.json"))

      assert is_list(pages) and pages != []

      for page <- pages do
        assert %{"id" => id, "path" => path, "description" => description} =
                 page

        assert is_binary(id) and is_binary(path) and is_binary(description)
      end
    end

    test "returns nil and warns when the file is missing" do
      {result, log} =
        with_log(fn -> AppMap.load("/nonexistent/app_map.json") end)

      assert result == nil
      assert log =~ "Could not load the app map"
      assert log =~ "mix lightning.gen.app_map"
    end

    @tag :tmp_dir
    test "returns nil and warns when the file is malformed", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "app_map.json")
      File.write!(path, "not json {")

      {result, log} = with_log(fn -> AppMap.load(path) end)

      assert result == nil
      assert log =~ "Could not load the app map"
    end

    @tag :tmp_dir
    test "returns nil and warns when the JSON is not a list", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "app_map.json")
      File.write!(path, ~s({"id": "login"}))

      {result, log} = with_log(fn -> AppMap.load(path) end)

      assert result == nil
      assert log =~ "Could not load the app map"
    end
  end

  describe "fetch/0" do
    test "returns the pages from priv/app_map.json and memoizes them" do
      pages = AppMap.fetch()

      assert is_list(pages) and pages != []
      assert Enum.all?(pages, &match?(%{"id" => _, "path" => _}, &1))

      # memoized: a second call returns the identical term
      assert AppMap.fetch() == pages
      assert :persistent_term.get({AppMap, :app_map}) == pages
    end
  end
end
