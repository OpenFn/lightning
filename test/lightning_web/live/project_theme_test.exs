defmodule LightningWeb.ProjectThemeTest do
  use ExUnit.Case, async: true

  import Lightning.Factories
  alias LightningWeb.Live.Helpers.ProjectTheme
  alias Lightning.Projects.Project

  @stops [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]

  describe "inline_primary_scale/1" do
    test "returns nil for non-Project inputs" do
      assert ProjectTheme.inline_primary_scale(nil) == nil
      assert ProjectTheme.inline_primary_scale(%{}) == nil
      assert ProjectTheme.inline_primary_scale(:nope) == nil
    end

    test "returns nil for non-sandbox project" do
      p = build(:project, color: "#6366f1", parent: nil, parent_id: nil)
      refute Project.sandbox?(p)
      assert ProjectTheme.inline_primary_scale(p) == nil
    end

    test "returns nil for sandbox without color or blank color" do
      s1 = build(:sandbox, color: nil)
      s2 = build(:sandbox, color: "")
      s3 = build(:sandbox, color: "   ")

      assert ProjectTheme.inline_primary_scale(s1) == nil
      assert ProjectTheme.inline_primary_scale(s2) == nil
      assert ProjectTheme.inline_primary_scale(s3) == nil
    end

    test "produces 11 CSS vars for sandbox with color" do
      css =
        build(:project, parent_id: Ecto.UUID.generate(), color: "#6366f1")
        |> ProjectTheme.inline_primary_scale()

      decls = css |> String.trim() |> String.split(~r/;\s*/, trim: true)
      assert length(decls) == length(@stops)

      for {decl, stop} <- Enum.zip(decls, @stops) do
        assert Regex.match?(~r/^--color-primary-#{stop}: #[0-9a-f]{6}$/i, decl)
      end
    end

    test "emits declarations in exact @stops order" do
      css =
        build(:project, parent_id: Ecto.UUID.generate(), color: "#6366f1")
        |> ProjectTheme.inline_primary_scale()

      decls = css |> String.trim() |> String.split(~r/;\s*/, trim: true)

      got_stops =
        for <<"--color-primary-", rest::binary>> <- decls do
          [num | _] = String.split(rest, ":")
          String.to_integer(num)
        end

      assert got_stops == @stops
    end

    test "lower/upper-case input produce identical scales" do
      s1 = build(:project, parent_id: Ecto.UUID.generate(), color: "#6366F1")
      s2 = build(:project, parent_id: Ecto.UUID.generate(), color: "#6366f1")

      assert ProjectTheme.inline_primary_scale(s1) ==
               ProjectTheme.inline_primary_scale(s2)
    end

    test "supports 3/6/8-digit inputs" do
      for color <- ["#63f", "#6633ff", "#6633ffcc"] do
        s = build(:project, parent_id: Ecto.UUID.generate(), color: color)
        css = ProjectTheme.inline_primary_scale(s)
        decls = css |> String.trim() |> String.split(~r/;\s*/, trim: true)

        assert length(decls) == 11
        assert Regex.match?(~r/^--color-primary-50: #[0-9a-f]{6}$/i, hd(decls))

        assert Regex.match?(
                 ~r/^--color-primary-950: #[0-9a-f]{6}$/i,
                 List.last(decls)
               )
      end
    end

    test "short/invalid-length hex (e.g. #12) falls back but still yields 11 vars" do
      s = build(:project, parent_id: Ecto.UUID.generate(), color: "#12")
      css = ProjectTheme.inline_primary_scale(s)
      decls = css |> String.trim() |> String.split(~r/;\s*/, trim: true)
      assert length(decls) == 11
    end

    test "covers red-sector hue paths (max==r and h<60)" do
      s = build(:project, parent_id: Ecto.UUID.generate(), color: "#ff0000")
      css = ProjectTheme.inline_primary_scale(s)
      decls = css |> String.trim() |> String.split(~r/;\s*/, trim: true)
      assert length(decls) == 11
    end

    test "covers green-sector hue path (max==g)" do
      s = build(:project, parent_id: Ecto.UUID.generate(), color: "#00ff00")
      css = ProjectTheme.inline_primary_scale(s)
      decls = css |> String.trim() |> String.split(~r/;\s*/, trim: true)
      assert length(decls) == 11
    end

    test "covers magenta-sector hue path (h≥300, true branch in hsl_to_rgb)" do
      s = build(:project, parent_id: Ecto.UUID.generate(), color: "#ff00ff")
      css = ProjectTheme.inline_primary_scale(s)
      decls = css |> String.trim() |> String.split(~r/;\s*/, trim: true)
      assert length(decls) == 11
    end
  end

  describe "inline_sidebar_vars/0" do
    test "returns single-line vars, safe to append to scale" do
      s = build(:project, parent_id: Ecto.UUID.generate(), color: "#0ea5e9")
      scale = ProjectTheme.inline_primary_scale(s)
      vars = ProjectTheme.inline_sidebar_vars()

      refute String.contains?(vars, "\n")
      assert String.contains?(vars, "--primary-bg: var(--color-primary-800);")
      assert String.contains?(vars, "--primary-ring: var(--color-gray-300);")

      combo = scale <> " " <> vars
      assert String.contains?(combo, "--color-primary-600:")
      assert String.contains?(combo, "--primary-bg:")
    end
  end
end
