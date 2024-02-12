defmodule Lightning.UsageTracking.WorkerTest do
  use Lightning.DataCase, async: false

  alias Lightning.UsageTracking.{Client, Configuration, Report, Worker}

  import Mock
  import Lightning.ApplicationHelpers, only: [put_temporary_env: 3]

  @host "https://foo.bar"
  @metrics %{}

  describe "tracking is enabled" do
    setup do
      put_temporary_env(:lightning, :usage_tracking,
        enabled: true,
        host: @host
      )
    end

    test "creates a configuration record" do
      with_mock Client,
        submit_metrics: &mock_submit_metrics_ok/2 do
        Worker.perform(%{})

        assert [%Configuration{}] = Repo.all(Configuration)
      end
    end

    test "uses existing Configuration if one exists" do
      {:ok, %Configuration{instance_id: instance_id}} =
        %Configuration{} |> Repo.insert()

      with_mock Client,
        submit_metrics: &mock_submit_metrics_ok/2 do
        Worker.perform(%{})

        assert [%Configuration{instance_id: ^instance_id}] =
                 Repo.all(Configuration)
      end
    end

    test "sends an empty JSON object to the usage tracker" do
      with_mock Client,
        submit_metrics: &mock_submit_metrics_ok/2 do
        Worker.perform(%{})

        assert_called(Client.submit_metrics(@metrics, @host))
      end
    end

    test "persists a report indicating successful submission" do
      metrics = @metrics

      with_mock Client,
        submit_metrics: &mock_submit_metrics_ok/2 do
        Worker.perform(%{})
      end

      report = Report |> Repo.one()

      assert %Report{submitted: true, data: ^metrics} = report
      assert DateTime.diff(DateTime.utc_now(), report.submitted_at, :second) < 1
    end

    test "persists a report indicating unsuccessful submission" do
      metrics = @metrics

      with_mock Client,
        submit_metrics: &mock_submit_metrics_error/2 do
        Worker.perform(%{})
      end

      report = Report |> Repo.one()

      assert %Report{submitted: false, data: ^metrics, submitted_at: nil} =
               report
    end

    test "indicates that processing succeeded" do
      with_mock Client,
        submit_metrics: &mock_submit_metrics_ok/2 do
        assert :ok = Worker.perform(%{})
      end
    end
  end

  describe "tracking is disabled" do
    setup do
      put_temporary_env(:lightning, :usage_tracking,
        enabled: false,
        host: "https://foo.bar"
      )
    end

    test "does not create a configuration record" do
      with_mock Client,
        submit_metrics: &mock_submit_metrics_ok/2 do
        Worker.perform(%{})

        assert [] = Repo.all(Configuration)
      end
    end

    test "uses existing Configuration if one exists" do
      {:ok, %Configuration{instance_id: instance_id}} =
        %Configuration{} |> Repo.insert()

      with_mock Client,
        submit_metrics: &mock_submit_metrics_ok/2 do
        Worker.perform(%{})

        assert [%Configuration{instance_id: ^instance_id}] =
                 Repo.all(Configuration)
      end
    end

    test "does not submit metrics if tracking is not enabled" do
      with_mock Client,
        submit_metrics: &mock_submit_metrics_ok/2 do
        Worker.perform(%{})

        assert_not_called(Client.submit_metrics(:_, :_))
      end
    end

    test "indicates that processing succeeded" do
      with_mock Client,
        submit_metrics: &mock_submit_metrics_ok/2 do
        assert :ok = Worker.perform(%{})
      end
    end
  end

  def mock_submit_metrics_ok(_metrics, _host), do: :ok

  def mock_submit_metrics_error(_metrics, _host), do: :error
end
