Code.require_file("../../../credo/checks/changeset_error_code.ex", __DIR__)

defmodule Lightning.Credo.Check.ChangesetErrorCodeTest do
  use Credo.Test.Case

  alias Credo.Check.Params
  alias Lightning.Credo.Check.ChangesetErrorCode

  defp issues(source) do
    source
    |> to_source_file("lib/lightning/thing.ex")
    |> run_check(ChangesetErrorCode)
  end

  defp assert_flagged(source, expected) do
    found =
      source
      |> issues()
      |> Enum.map(&{&1.line_no, &1.trigger, &1.message})
      |> Enum.sort()

    assert Enum.map(found, fn {line, trigger, _} -> {line, trigger} end) ==
             expected

    found
  end

  describe "is flagged" do
    test "an add_error with no code:" do
      [{_, _, message}] =
        """
        defmodule Lightning.Thing do
          def check(cs) do
            add_error(cs, :owner, "must have one owner")
          end
        end
        """
        |> assert_flagged([{3, "add_error"}])

      assert message =~ "add_error has no `code:`"
    end

    test "a validate_change whose fn returns an error with no code:" do
      [{_, _, message}] =
        """
        defmodule Lightning.Thing do
          def check(cs) do
            validate_change(cs, :url, fn :url, url ->
              if ok?(url), do: [], else: [url: "is not a URL"]
            end)
          end
        end
        """
        |> assert_flagged([{3, "validate_change"}])

      assert message =~ "validate_change returns an error with no `code:`"
    end

    test "a validate_change returning errors from a function in the same file" do
      """
      defmodule Lightning.Thing do
        def check(cs) do
          Ecto.Changeset.validate_change(cs, :url, fn :url, url -> url_errors(url) end)
        end

        defp url_errors(nil), do: [url: {"can't be blank", code: :required}]
        defp url_errors(_url), do: [url: "is not a URL", url: {"bad", []}]
      end
      """
      |> assert_flagged([{3, "validate_change"}, {3, "validate_change"}])
    end

    test "a validate_change whose result it can't read" do
      for validator <- [
            "&url_errors/2",
            "fn :url, url -> Validators.url(url) end"
          ] do
        [{_, _, message}] =
          """
          defmodule Lightning.Thing do
            def check(cs) do
              validate_change(cs, :url, #{validator})
            end
          end
          """
          |> assert_flagged([{3, "validate_change"}])

        assert message =~ "Can't see the errors this validate_change returns",
               "for: #{validator}"
      end
    end
  end

  describe "is clean" do
    test "an add_error with a code:" do
      """
      defmodule Lightning.Thing do
        def check(cs) do
          cs
          |> add_error(:owner, "must have one owner", code: :one_owner)
          |> Ecto.Changeset.add_error(:name, "is taken", code: :taken, other: 1)
        end
      end
      """
      |> issues()
      |> refute_issues()
    end

    test "a validate_change returning {message, code: ...}, through branches and a local function" do
      """
      defmodule Lightning.Thing do
        def check(cs) do
          cs
          |> validate_change(:url, fn :url, url ->
            if ok?(url), do: [], else: [url: {"is not a URL", code: :format}]
          end)
          |> validate_change(:name, fn :name, name -> name_errors(name) end)
        end

        defp name_errors(name) do
          case name do
            "" -> [name: {"can't be blank", code: :required}]
            _ -> []
          end
        end
      end
      """
      |> issues()
      |> refute_issues()
    end
  end

  test "only files in lib/lightning are checked" do
    included = Params.files_included([], ChangesetErrorCode)

    assert Credo.Sources.filename_matches?("lib/lightning/thing.ex", included)
    assert Credo.Sources.filename_matches?("lib/lightning.ex", included)

    for outside <- [
          "lib/lightning_web/controllers/thing_controller.ex",
          "test/lightning/thing_test.exs",
          "credo/checks/thing.ex"
        ] do
      refute Credo.Sources.filename_matches?(outside, included),
             "for: #{outside}"
    end
  end
end
