defmodule Lightning.ImpactTracking.WorkerTest do
  use ExUnit.Case, async: false

  alias Lightning.ImpactTracking.{Client, Worker}

  import Mock
  import Lightning.ApplicationHelpers, only: [put_temporary_env: 3]

  @host "https://foo.bar"

  describe "tracking is enabled" do
    setup do
      put_temporary_env(:lightning, :impact_tracking,
        enabled: true,
        host: @host
      )
    end

    test "sends an empty JSON object to the impact tracker" do
      with_mock Client,
        submit_metrics: fn _metrics, _host -> true end do
        Worker.perform(%{})

        assert_called(Client.submit_metrics(%{}, @host))
      end
    end

    test "indicates that processing succeeded" do
      with_mock Client,
        submit_metrics: fn _metrics, _host -> true end do
        assert :ok = Worker.perform(%{})
      end
    end
  end

  describe "tracking is disabled" do
    setup do
      put_temporary_env(:lightning, :impact_tracking,
        enabled: false,
        host: "https://foo.bar"
      )
    end

    test "does not submit metrics if tracking is not enabled" do
      with_mock Client,
        submit_metrics: fn _metrics, _host -> true end do
        Worker.perform(%{})

        assert_not_called(Client.submit_metrics(:_, :_))
      end
    end

    test "indicates that processing succeeded" do
      with_mock Client,
        submit_metrics: fn _metrics, _host -> true end do
        assert :ok = Worker.perform(%{})
      end
    end
  end
end
