defmodule Lightning.ImportProjectsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects
  # alias Lightning.Projects.Project
  import Lightning.AccountsFixtures

  describe "import project.yaml" do
    test "import_project project and workflows if given valid object map" do
      user = user_fixture()

      project_data = %{
        name: "myproject",
        credentials: [
          %{
            key: "abc",
            name: "first credential",
            schema: "raw",
            body: %{"password" => "xxx"}
          },
          %{
            key: "xyz",
            name: "MY credential",
            schema: "raw",
            body: %{"password" => "xxx"}
          }
        ],
        workflows: [
          %{
            key: "workflow1",
            name: "workflow1",
            jobs: [
              %{
                name: "job1",
                key: "job1",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "xyz",
                body: "fn(state => state)"
              },
              %{
                name: "job2",
                key: "job2",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "abc",
                body: "fn(state => state)"
              }
            ]
          },
          %{
            name: "workflow2",
            jobs: [
              %{
                name: "job1",
                key: "job3",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "xyz",
                body: "fn(state => state)"
              },
              %{
                name: "job2",
                key: "job4",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "xyz",
                body: "fn(state => state)"
              }
            ]
          }
        ]
      }

      {:ok, %{project: project}} = Projects.import_project(project_data, user)

      project = Repo.preload(project, workflows: [jobs: [:trigger, :credential]])

      assert project.name == project_data.name
      assert length(project.workflows) == length(project_data.workflows)

      %{workflows: [expected_w1, expected_w2]} = project_data

      workflow1 = Enum.find(project.workflows, fn w -> w.name == "workflow1" end)
      workflow2 = Enum.find(project.workflows, fn w -> w.name == "workflow2" end)

      assert_workflow(workflow1, expected_w1, project_data)
      assert_workflow(workflow2, expected_w2, project_data)
    end

    test "import_project missing workflows key" do
      user = user_fixture()

      project_data = %{
        name: "myproject"
      }

      {:ok, %{project: project}} = Projects.import_project(project_data, user)

      project = Repo.preload(project, :workflows)

      assert length(project.workflows) == 0
    end

    test "import_project missing project name" do
      user = user_fixture()

      project_data = %{
        workflows: []
      }

      {:error, :project, project_changeset, _} =
        Projects.import_project(project_data, user)

      Ecto.Changeset.traverse_errors(project_changeset, fn {msg, _opts} ->
        assert msg == "can't be blank"
      end)
    end

    test "import_project missing credentials key" do
      user = user_fixture()

      project_data = %{
        name: "myproject",
        workflows: [
          %{
            key: "workflow1",
            name: "workflow1",
            jobs: [
              %{
                name: "job1",
                key: "job1",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "abc",
                body: "fn(state => state)"
              }
            ]
          },
          %{
            key: "workflow2",
            name: "workflow2",
            jobs: [
              %{
                name: "job222",
                key: "job2",
                trigger: %{type: "webhook"},
                adaptor: "language-fhir",
                enabled: true,
                credential: "abc",
                body: "fn(state => state)"
              }
            ]
          }
        ]
      }

      {:error, _, workflow_changeset, items} =
        Projects.import_project(project_data, user)

      IO.inspect(items)

      Ecto.Changeset.traverse_errors(workflow_changeset, fn {msg, _opts} ->
        msg
      end)
      |> IO.inspect()

      IO.inspect(workflow_changeset)

      Ecto.Changeset.traverse_errors(workflow_changeset, fn {msg, _opts} ->
        assert msg == "not found in project input"
      end)
    end
  end

  defp assert_workflow(expected, actual, project_data) do
    %{jobs: [expected_j1, expected_j2]} = expected

    job1 = Enum.find(actual.jobs, fn j -> j.name == "job1" end)
    job2 = Enum.find(actual.jobs, fn j -> j.name == "job2" end)

    refute is_nil(actual)
    assert expected.name == actual.name

    assert_job(job1, expected_j1, project_data)
    assert_job(job2, expected_j2, project_data)
  end

  defp assert_job(expected, actual, project_data) do
    expected_credential = get_expected_credential(project_data, expected)
    refute is_nil(actual)
    assert expected.name == actual.name
    assert expected.adaptor == actual.adaptor
    assert expected_credential.schema == actual.credential.schema
    assert expected_credential.name == actual.credential.name
    assert expected_credential.body == actual.credential.body
    assert expected.body == actual.body
    assert String.to_existing_atom(expected.trigger.type) == actual.trigger.type
  end

  defp get_expected_credential(project_data, job) do
    Enum.find(project_data.credentials, fn credential ->
      job.credential == credential.key
    end)
  end

  test "new test" do
    # user = user_fixture()

    # project_data =
    #   %{
    #     name: "myproject",
    #     credentials: [
    #       %{
    #         key: "abc",
    #         name: "first credential",
    #         schema: "raw",
    #         body: %{"password" => "xxx"}
    #       },
    #       %{
    #         key: "xyz",
    #         name: "MY credential",
    #         schema: "raw",
    #         body: %{"password" => "xxx"}
    #       }
    #     ],
    #     workflows: [
    #       %{
    #         key: "workflow1",
    #         name: "workflow1",
    #         jobs: [
    #           %{
    #             name: "job1",
    #             trigger: %{type: "webhook"},
    #             adaptor: "language-fhir",
    #             enabled: true,
    #             credential: "xyz",
    #             body: "fn(state => state)"
    #           },
    #           %{
    #             name: "job2",
    #             trigger: %{type: "webhook"},
    #             adaptor: "language-fhir",
    #             enabled: true,
    #             credential: "abc",
    #             body: "fn(state => state)"
    #           }
    #         ]
    #       },
    #       %{
    #         name: "workflow2",
    #         jobs: [
    #           %{
    #             name: "job1",
    #             trigger: %{type: "webhook"},
    #             adaptor: "language-fhir",
    #             enabled: true,
    #             credential: "xyz",
    #             body: "fn(state => state)"
    #           },
    #           %{
    #             name: "job2",
    #             trigger: %{type: "webhook"},
    #             adaptor: "language-fhir",
    #             enabled: true,
    #             credential: "xyz",
    #             body: "fn(state => state)"
    #           }
    #         ]
    #       }
    #     ]
    #   }
    #   |> Lightning.Helpers.stringify_keys()

    # # create or update project by id
    # # create or update project credential by id and project id

    # credentials =
    #   project_data["credentials"]
    #   |> Enum.map(fn credential ->
    #     key = credential["key"]
    #     id = credential["id"]

    #     {key, id, credential |> Lightning.Credentials.Credential.changeset()}
    #   end)

    # {:ok, %{project: project}} = Projects.import_project(project_data, user)

    # project = Repo.preload(project, workflows: [jobs: [:trigger, :credential]])

    # assert project.name == project_data.name
    # assert length(project.workflows) == length(project_data.workflows)

    # %{workflows: [expected_w1, expected_w2]} = project_data

    # workflow1 = Enum.find(project.workflows, fn w -> w.name == "workflow1" end)
    # workflow2 = Enum.find(project.workflows, fn w -> w.name == "workflow2" end)

    # assert_workflow(workflow1, expected_w1, project_data)
    # assert_workflow(workflow2, expected_w2, project_data)
  end
end
