defmodule Lightning.DigestEmailWorkerTest do
  use Lightning.DataCase, async: true

  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures
  alias Lightning.DigestEmailWorker

  describe "perform/1" do
    test "all project users of different project that have a digest of :daily, :weekly, and :monthly" do
      user_1 = user_fixture()
      user_2 = user_fixture()
      user_3 = user_fixture()

      project_fixture(
        project_users: [
          %{user_id: user_1.id, digest: :daily},
          %{user_id: user_2.id, digest: :weekly},
          %{user_id: user_3.id, digest: :monthly}
        ]
      )

      project_fixture(
        project_users: [
          %{user_id: user_1.id, digest: :monthly},
          %{user_id: user_2.id, digest: :daily},
          %{user_id: user_3.id, digest: :daily}
        ]
      )

      project_fixture(
        project_users: [
          %{user_id: user_1.id, digest: :weekly},
          %{user_id: user_2.id, digest: :daily},
          %{user_id: user_3.id, digest: :weekly}
        ]
      )

      {:ok, %{project_users: daily_project_users}} =
        DigestEmailWorker.perform(%Oban.Job{
          args: %{"type" => "daily_project_digest"}
        })

      {:ok, %{project_users: weekly_project_users}} =
        DigestEmailWorker.perform(%Oban.Job{
          args: %{"type" => "weekly_project_digest"}
        })

      {:ok, %{project_users: monthly_project_users}} =
        DigestEmailWorker.perform(%Oban.Job{
          args: %{"type" => "monthly_project_digest"}
        })

      assert daily_project_users |> length() == 4
      assert weekly_project_users |> length() == 3
      assert monthly_project_users |> length() == 2
    end
  end
end
