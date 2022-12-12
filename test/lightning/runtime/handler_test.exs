defmodule MyCustomHandler do
  use Lightning.Runtime.Handler

  @impl Handler
  def on_finish(_result, ctx) do
    send(ctx, :yepper)
  end
end

defmodule Lightning.Runtime.HandlerTest do
  use ExUnit.Case, async: true

  import Lightning.Runtime.TestUtil

  test "can retain partial logs" do
    run_spec = %{
      run_spec_fixture()
      | expression_path: write_temp!(timeout_expression(2000))
    }

    result =
      MyCustomHandler.start(run_spec,
        context: self(),
        timeout: 1000,
        env: %{"PATH" => "./priv/openfn/bin:#{System.get_env("PATH")}"}
      )

    assert result.exit_reason == :killed
    assert result.log |> Enum.at(-2) == "Going on break for 2000..."
  end

  @tag timeout: 5_000
  test "calls custom callbacks" do
    run_spec = run_spec_fixture()

    result =
      MyCustomHandler.start(run_spec,
        env: %{"PATH" => "./priv/openfn/bin:#{System.get_env("PATH")}"},
        context: self()
      )

    assert result.exit_reason == :ok

    assert_received(:yepper)
  end

  @tag timeout: 5_000
  test "calls uses the env from a RunSpec" do
    run_spec =
      run_spec_fixture(
        env: %{"PATH" => "./priv/openfn/bin:#{System.get_env("PATH")}"}
      )

    result = MyCustomHandler.start(run_spec, context: self())

    assert result.exit_reason == :ok

    assert_received(:yepper)
  end
end
