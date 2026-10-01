defmodule Lightning.Projects.AdminSearchParamsValidationTest do
  # The `page=abc` raise happens before any database connection, so this suite
  # stays pure and async.
  use ExUnit.Case, async: true

  alias Lightning.Projects.AdminSearchParams

  describe "malformed numeric params" do
    test "non-numeric page falls back to default instead of raising" do
      params = AdminSearchParams.new(%{"page" => "abc"})
      assert params.page == AdminSearchParams.new().page
    end

    test "non-numeric page_size falls back to default instead of raising" do
      params = AdminSearchParams.new(%{"page_size" => "abc"})
      assert params.page_size == AdminSearchParams.new().page_size
    end

    test "float page string falls back to default" do
      params = AdminSearchParams.new(%{"page" => "1.5"})
      assert params.page == 1
    end

    test "list-valued page param falls back to default" do
      params = AdminSearchParams.new(%{"page" => ["1", "2"]})
      assert params.page == 1
    end
  end
end
