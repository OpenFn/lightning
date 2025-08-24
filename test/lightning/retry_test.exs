defmodule Lightning.RetryTest do
  use ExUnit.Case, async: true
  import Mox

  alias Lightning.Retry

  @moduletag capture_log: true

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "with_retry/2 non-retryable raises" do
    test "bubbles non-DB exceptions (reraise path)" do
      assert_raise RuntimeError, "boom", fn ->
        Retry.with_retry(fn -> raise "boom" end,
          initial_delay_ms: 0,
          jitter: false
        )
      end
    end
  end

  describe "option parsing fallbacks (:error branches)" do
    test "string parse failures fall back to safe defaults" do
      attempts = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(attempts, 1, 1)
            {:error, %DBConnection.ConnectionError{message: "x"}}
          end,
          max_attempts: "not-a-number",
          initial_delay_ms: "nope",
          max_delay_ms: "nah",
          backoff_factor: "??",
          timeout_ms: "zzz",
          jitter: true
        )

      assert {:error, %DBConnection.ConnectionError{}} = result
      assert :counters.get(attempts, 1) == 1
    end

    test "non-numeric atoms hit generic to_int/to_float fallbacks" do
      attempts = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(attempts, 1, 1)
            {:error, %DBConnection.ConnectionError{message: "y"}}
          end,
          max_attempts: :foo,
          backoff_factor: :bar,
          timeout_ms: :baz,
          initial_delay_ms: :qux,
          jitter: false
        )

      assert {:error, %DBConnection.ConnectionError{}} = result
      assert :counters.get(attempts, 1) == 1
    end
  end

  describe "calculate_next_delay/2 with jitter but zero base delay" do
    test "falls back to base delay when base_delay == 0" do
      attempts = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(attempts, 1, 1)
            {:error, %DBConnection.ConnectionError{message: "z"}}
          end,
          max_attempts: 2,
          initial_delay_ms: 0,
          jitter: true,
          timeout_ms: 50
        )

      assert {:error, %DBConnection.ConnectionError{}} = result
      assert :counters.get(attempts, 1) == 2
    end
  end

  describe "retriable_error?/1" do
    test "returns true for {:error, %DBConnection.ConnectionError{}}" do
      assert Retry.retriable_error?({:error, %DBConnection.ConnectionError{}})
    end

    test "returns false for non-DB errors" do
      refute Retry.retriable_error?({:error, :nope})
      refute Retry.retriable_error?(:anything)
    end
  end

  describe "with_retry/2 timeout branch" do
    test "hits :timeout when timeout_ms is 0" do
      attempts = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(attempts, 1, 1)
            {:error, %DBConnection.ConnectionError{message: "slow"}}
          end,
          timeout_ms: 0,
          max_attempts: 5,
          initial_delay_ms: 0,
          jitter: false
        )

      assert {:error, %DBConnection.ConnectionError{}} = result
      assert :counters.get(attempts, 1) == 1
    end
  end

  describe "with_retry/2 rescue path" do
    test "wraps raised DBConnection.ConnectionError into {:error, e}" do
      attempts = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(attempts, 1, 1)
            raise DBConnection.ConnectionError, message: "boom"
          end,
          max_attempts: 1,
          initial_delay_ms: 0,
          jitter: false
        )

      assert {:error, %DBConnection.ConnectionError{}} = result
      assert :counters.get(attempts, 1) == 1
    end
  end

  describe "with_retry/2 jitter path" do
    test "executes jittered delay when jitter: true and base_delay > 0" do
      attempts = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(attempts, 1, 1)
            {:error, %DBConnection.ConnectionError{message: "flaky"}}
          end,
          max_attempts: 2,
          initial_delay_ms: 8,
          jitter: true,
          timeout_ms: 1_000
        )

      assert {:error, %DBConnection.ConnectionError{}} = result
      assert :counters.get(attempts, 1) == 2
    end
  end

  describe "with_retry/2 option coercions and clamps" do
    test "string options are coerced (to_int/to_float) and respected" do
      attempts = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(attempts, 1, 1)
            {:error, %DBConnection.ConnectionError{message: "nope"}}
          end,
          max_attempts: "2",
          initial_delay_ms: "0",
          max_delay_ms: "0",
          backoff_factor: "1.5",
          timeout_ms: "50",
          jitter: false
        )

      assert {:error, %DBConnection.ConnectionError{}} = result
      assert :counters.get(attempts, 1) == 2
    end

    test "invalid numeric options are clamped to safe mins" do
      attempts = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(attempts, 1, 1)
            {:error, %DBConnection.ConnectionError{message: "still no"}}
          end,
          max_attempts: 0,
          initial_delay_ms: -10,
          max_delay_ms: -5,
          backoff_factor: 0.0,
          timeout_ms: -1,
          jitter: false
        )

      assert {:error, %DBConnection.ConnectionError{}} = result
      assert :counters.get(attempts, 1) == 1
    end
  end

  describe "with_retry/2" do
    test "returns success immediately when function succeeds" do
      assert {:ok, "success"} = Retry.with_retry(fn -> {:ok, "success"} end)
    end

    test "retries on DB connection errors and eventually succeeds" do
      attempts = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(attempts, 1, 1)

            case :counters.get(attempts, 1) do
              n when n < 3 ->
                {:error, %DBConnection.ConnectionError{message: "lost"}}

              n ->
                {:ok, "success after #{n} attempts"}
            end
          end,
          max_attempts: 5,
          initial_delay_ms: 5,
          jitter: false
        )

      assert {:ok, "success after 3 attempts"} = result
      assert :counters.get(attempts, 1) == 3
    end

    test "stops after max attempts" do
      attempts = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(attempts, 1, 1)
            {:error, %DBConnection.ConnectionError{message: "lost"}}
          end,
          max_attempts: 3,
          initial_delay_ms: 5,
          jitter: false
        )

      assert {:error, %DBConnection.ConnectionError{}} = result
      assert :counters.get(attempts, 1) == 3
    end

    test "does not retry non-retryable errors" do
      attempts = :counters.new(1, [])

      assert {:error, "nope"} =
               Retry.with_retry(fn ->
                 :counters.add(attempts, 1, 1)
                 {:error, "nope"}
               end)

      assert :counters.get(attempts, 1) == 1
    end

    test "supports custom retry_on predicate" do
      attempts = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(attempts, 1, 1)

            if :counters.get(attempts, 1) < 2,
              do: {:error, :custom},
              else: {:ok, :ok}
          end,
          retry_on: fn
            {:error, :custom} -> true
            _ -> false
          end,
          initial_delay_ms: 5,
          jitter: false
        )

      assert {:ok, :ok} = result
      assert :counters.get(attempts, 1) == 2
    end
  end

  describe "with_webhook_retry/2" do
    test "uses library defaults when Config returns []" do
      stub(Lightning.MockConfig, :webhook_retry, fn -> [] end)

      attempts = :counters.new(1, [])

      result =
        Retry.with_webhook_retry(fn ->
          :counters.add(attempts, 1, 1)

          if :counters.get(attempts, 1) < 3,
            do: {:error, %DBConnection.ConnectionError{}},
            else: {:ok, :ok}
        end)

      assert {:ok, :ok} = result
      assert :counters.get(attempts, 1) == 3
    end

    test "merges Config values" do
      stub(Lightning.MockConfig, :webhook_retry, fn ->
        [max_attempts: 2, initial_delay_ms: 0, jitter: false]
      end)

      attempts = :counters.new(1, [])

      result =
        Retry.with_webhook_retry(fn ->
          :counters.add(attempts, 1, 1)
          {:error, %DBConnection.ConnectionError{}}
        end)

      assert {:error, %DBConnection.ConnectionError{}} = result
      assert :counters.get(attempts, 1) == 2
    end

    test "user opts override Config + defaults" do
      stub(Lightning.MockConfig, :webhook_retry, fn -> [max_attempts: 2] end)

      attempts = :counters.new(1, [])

      result =
        Retry.with_webhook_retry(
          fn ->
            :counters.add(attempts, 1, 1)
            {:error, %DBConnection.ConnectionError{}}
          end,
          max_attempts: 4,
          initial_delay_ms: 0,
          jitter: false
        )

      assert {:error, %DBConnection.ConnectionError{}} = result
      assert :counters.get(attempts, 1) == 4
    end
  end
end
