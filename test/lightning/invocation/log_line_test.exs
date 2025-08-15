defmodule Lightning.Invocation.LogLineTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Invocation.LogLine

  describe "new/2" do
    setup do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip
        )

      {:ok, run: run}
    end

    test "creates valid changeset with message", %{run: run} do
      log_line =
        LogLine.new(
          run,
          %{message: "Hello, World!", timestamp: DateTime.utc_now()},
          nil
        )

      assert log_line.valid?
    end

    test "allows empty message", %{run: run} do
      log_line =
        LogLine.new(
          run,
          %{message: "", timestamp: DateTime.utc_now()},
          nil
        )

      assert log_line.valid?, "should be able to have an empty message"
    end

    test "requires message to be present", %{run: run} do
      log_line =
        LogLine.new(
          run,
          %{message: nil, timestamp: DateTime.utc_now()},
          nil
        )

      assert {:message, {"can't be blank", []}} in log_line.errors
      refute log_line.valid?
    end
  end

  describe "PostgreSQL UTF-8 compatibility (issue #3090)" do
    setup do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip
        )

      {:ok, run: run}
    end

    test "handles null bytes without PostgreSQL error", %{run: run} do
      # This is the exact scenario from issue #3090
      # Without the fix, this would raise:
      # ** (Postgrex.Error) ERROR 22021 (character_not_in_repertoire)
      #    invalid byte sequence for encoding "UTF8": 0x00

      changeset =
        LogLine.new(
          run,
          %{
            message: "Error occurred: \x00 null byte in log",
            timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond),
            level: :error
          },
          nil
        )

      assert {:ok, log_line} = Repo.insert(changeset)
      assert log_line.message == "Error occurred: � null byte in log"
    end

    test "preserves valid whitespace characters", %{run: run} do
      changeset =
        LogLine.new(
          run,
          %{
            message: "Line 1\nLine 2\tTabbed\rCarriage",
            timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond),
            level: :info
          },
          nil
        )

      assert {:ok, log_line} = Repo.insert(changeset)
      assert log_line.message == "Line 1\nLine 2\tTabbed\rCarriage"
    end

    test "works with scrubber for sensitive data and null bytes", %{run: run} do
      {:ok, scrubber} =
        Lightning.Scrubber.start_link(samples: ["secret_key", "password123"])

      changeset =
        LogLine.new(
          run,
          %{
            message: "User logged in with password123\x00and secret_key",
            timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond),
            level: :info
          },
          scrubber
        )

      assert {:ok, log_line} = Repo.insert(changeset)

      # Both sensitive data and null byte should be handled
      # Note: Scrubber runs AFTER LogMessage type casting, so � is already there
      assert log_line.message == "User logged in with ***�and ***"
    end

    test "handles very long messages with scattered null bytes", %{run: run} do
      long_message =
        Enum.reduce(1..50, "", fn i, acc ->
          acc <> "Section #{i}: " <> String.duplicate("A", 90) <> "\x00\n"
        end)

      changeset =
        LogLine.new(
          run,
          %{
            message: long_message,
            timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond),
            level: :info
          },
          nil
        )

      assert {:ok, log_line} = Repo.insert(changeset)

      refute String.contains?(log_line.message, <<0>>)
      assert String.contains?(log_line.message, "�")

      assert String.contains?(log_line.message, "Section 1:")
      assert String.contains?(log_line.message, "Section 50:")
    end
  end
end
