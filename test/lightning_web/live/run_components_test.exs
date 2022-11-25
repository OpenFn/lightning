defmodule LightningWeb.RunComponentsTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LightningWeb.RunLive.Components
  import Lightning.InvocationFixtures

  test "log_view component" do
    log_lines = ["First line", "Second line"]

    html =
      render_component(&Components.log_view/1,
        log: log_lines
      )
      |> Floki.parse_fragment!()

    assert html |> Floki.find("div[data-line-number]") |> length() == 2

    # Check that the log lines are present.
    # Replace the resulting utf-8 &nbsp; back into a regular space.
    assert html
           |> Floki.find("div[data-log-line]")
           |> Floki.text(sep: "\n")
           |> String.replace(<<160::utf8>>, " ") ==
             log_lines |> Enum.join("\n")
  end

  describe "run_details component" do
    test "with finished run" do
      now = Timex.now()

      started_at = now |> Timex.shift(seconds: -25)
      finished_at = now |> Timex.shift(seconds: -1)

      run = run_fixture(started_at: started_at, finished_at: finished_at)

      html =
        render_component(&Components.run_details/1, run: run)
        |> Floki.parse_fragment!()

      assert html
             |> Floki.find("div#finished-at-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               Calendar.strftime(finished_at, "%c")

      assert html
             |> Floki.find("div#ran-for-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "24000 ms"

      assert html
             |> Floki.find("div#exit-code-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "?"
    end

    test "with pending run" do
      now = Timex.now()

      started_at = now |> Timex.shift(seconds: -25)
      run = run_fixture(started_at: started_at)

      html =
        render_component(&Components.run_details/1, run: run)
        |> Floki.parse_fragment!()

      assert html
             |> Floki.find("div#finished-at-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "Running..."

      assert html
             |> Floki.find("div#ran-for-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               ~r/25\d\d\d ms/

      assert html
             |> Floki.find("div#exit-code-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "?"
    end

    test "with unstarted run" do
      run = run_fixture()

      html =
        render_component(&Components.run_details/1, run: run)
        |> Floki.parse_fragment!()

      assert html
             |> Floki.find("div#finished-at-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "Not started."

      assert html
             |> Floki.find("div#ran-for-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "Not started."

      assert html
             |> Floki.find("div#exit-code-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "?"
    end
  end
end
