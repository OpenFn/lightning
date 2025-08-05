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

    test "handles multiple control characters", %{run: run} do
      changeset =
        LogLine.new(
          run,
          %{
            message: "Start\x00\x01\x02\x03\x04\x05\x06\x07\x08End",
            timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond),
            level: :info
          },
          nil
        )

      assert {:ok, log_line} = Repo.insert(changeset)
      assert log_line.message == "Start���������End"
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

    test "handles JSON messages with null bytes", %{run: run} do
      json_message = %{
        "error" => "Failed to process\x00",
        "code" => 500,
        "details" => ["step1", "step2\x01"]
      }

      changeset =
        LogLine.new(
          run,
          %{
            message: json_message,
            timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond),
            level: :error
          },
          nil
        )

      assert {:ok, log_line} = Repo.insert(changeset)

      # JSON will be encoded and control chars replaced with �
      assert log_line.message =~ "Failed to process�"
      assert log_line.message =~ "step2�"
      assert log_line.message =~ "500"

      # The message should be valid JSON with � characters
      assert {:ok, decoded} = Jason.decode(log_line.message)
      assert decoded["error"] == "Failed to process�"
      assert decoded["details"] == ["step1", "step2�"]
    end

    test "handles list messages with null bytes", %{run: run} do
      list_message = ["Processing", "Found\x00null", "Continuing"]

      changeset =
        LogLine.new(
          run,
          %{
            message: list_message,
            timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond),
            level: :debug
          },
          nil
        )

      assert {:ok, log_line} = Repo.insert(changeset)
      assert log_line.message == "Processing Found�null Continuing"
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

    test "simulates the exact error case from SQL line 1096", %{run: run} do
      attrs = %{
        message: "lib/ecto/adapters/sql.ex\x00 error occurred",
        timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond),
        level: :error,
        source: "adapter"
      }

      changeset = LogLine.new(run, attrs, nil)

      assert {:ok, log_line} = Repo.insert(changeset)
      assert log_line.message == "lib/ecto/adapters/sql.ex� error occurred"
    end
  end
end
