defmodule Lightning.RetryTest do
  use ExUnit.Case, async: true
  import Mox

  alias Lightning.Retry

  setup :set_mox_from_context
  setup :verify_on_exit!

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
