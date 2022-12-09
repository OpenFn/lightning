defmodule OpenFn.CrashTest do
  use LightningWeb.ConnCase, async: false
  use Oban.Testing, repo: Lightning.Repo

  alias Lightning.{TestUtil, Repo, ObanQuery}

  setup do
    initial_env = %{
      init_run_duration: Application.get_env(:lightning, :max_run_duration),
      init_long_run_duration:
        Application.get_env(:lightning, :max_long_run_duration),
      init_grace_period: Application.get_env(:lightning, :run_exit_grace_period)
    }

    setup =
      TestUtil.users_and_conns([:owner, :supportable_project])
      |> Map.put(:initial_env, initial_env)

    {:ok, setup}
  end

  defp restore_env(init) do
    Application.put_env(:open_fn, :max_run_duration, init.init_run_duration)

    Application.put_env(
      :open_fn,
      :max_long_run_duration,
      init.init_long_run_duration
    )

    Application.put_env(:open_fn, :run_exit_grace_period, init.init_grace_period)
  end

  describe "rambo" do
    test "kills a job that's running too long", %{
      owner: owner,
      supportable_project: supportable_project,
      initial_env: initial_env
    } do
      Application.put_env(:open_fn, :max_run_duration, "1")

      receipt = insert(:receipt, project: supportable_project)

      job =
        insert(:job,
          project: supportable_project,
          adaptor: "http",
          expression: "alterState(state => {
            return new Promise((resolve, reject) => {
              setTimeout(() => {
                resolve(state);
              }, 1500);
            });
          });"
        )

      run = %{"job_id" => job.id, "receipt_id" => receipt.id}
      response = owner.conn |> post(run_path(owner.conn, :create), run)
      assert response.status == 200

      assert :ok == TestUtil.drain_all(Repo)
      run = Repo.get_by!(OpenFn.Run, job_id: job.id)

      assert run.exit_code == 2

      assert Enum.at(run.log, 5) |> String.starts_with?("==== TIMEOUT =")
      assert run.receipt_id == receipt.id
      assert run.project_id == supportable_project.id

      restore_env(initial_env)
    end

    test "doesn't kill a job running longer than normal if it's set to long run",
         %{
           owner: owner,
           supportable_project: supportable_project,
           initial_env: initial_env
         } do
      Application.put_env(:open_fn, :max_run_duration, "1")
      Application.put_env(:open_fn, :max_long_run_duration, "5")

      receipt = insert(:receipt, project: supportable_project)

      job =
        insert(:job,
          project: supportable_project,
          adaptor: "http",
          long_run: true,
          expression: "alterState(state => {
            return new Promise((resolve, reject) => {
              setTimeout(() => {
                resolve(state);
              }, 1500);
            });
          });"
        )

      run = %{"job_id" => job.id, "receipt_id" => receipt.id}
      response = owner.conn |> post(run_path(owner.conn, :create), run)
      assert response.status == 200

      TestUtil.drain_all(Repo)
      run = Repo.get_by!(OpenFn.Run, job_id: job.id)

      assert run.exit_code == 0

      restore_env(initial_env)
    end
  end

  describe "the oban manager" do
    test "kills a job that's running too long and won't quit", %{
      owner: owner,
      supportable_project: supportable_project,
      initial_env: initial_env
    } do
      Application.put_env(:open_fn, :max_run_duration, "3")
      Application.put_env(:open_fn, :run_exit_grace_period, "-2")

      receipt = insert(:receipt, project: supportable_project)

      job =
        insert(:job,
          project: supportable_project,
          adaptor: "http",
          expression: "alterState(state => {
            return new Promise((resolve, reject) => {
              setTimeout(() => {
                resolve(state);
              }, 5000);
            });
          });"
        )

      run = %{"job_id" => job.id, "receipt_id" => receipt.id}

      response = owner.conn |> post(run_path(owner.conn, :create), run)
      assert response.status == 200

      assert :ok == TestUtil.drain_all(Repo)
      :timer.sleep(100)

      run = Repo.get_by!(OpenFn.Run, job_id: job.id)

      assert run.exit_code == 4
      assert Enum.at(run.log, 0) |> String.starts_with?("==== TIMEOUT")
      assert run.receipt_id == receipt.id
      assert run.project_id == supportable_project.id

      :timer.sleep(100)
      discards = ObanQuery.timeouts_for_run(run.id) |> Repo.aggregate(:count)
      assert discards == 0

      restore_env(initial_env)
    end
  end
end
