defmodule Lightning.ProjectsTest do
  use Lightning.DataCase, async: true

  describe "import project.yaml" do
    test "import_project project and workflows if given valid object map" do
      data = %{
        name: "",
        workflows: %{
          workflow1: %{
            jobs: %{
              job1: %{
                trigger: "webhook",
                adaptor: "language-fhir",
                enabled: true,
                credential: "credential",
                body: "> fn(state => state)"
              },
              job2: %{
                trigger: "webhook",
                adaptor: "language-fhir",
                enabled: true,
                credential: "credential",
                body: "> fn(state => state)"
              }
            }
          },
          workflow2: %{
            jobs: %{
              job1: %{
                trigger: "webhook",
                adaptor: "language-fhir",
                enabled: true,
                credential: "credential",
                body: "> fn(state => state)"
              },
              job2: %{
                trigger: "webhook",
                adaptor: "language-fhir",
                enabled: true,
                credential: "credential",
                body: "> fn(state => state)"
              }
            }
          }
        }
      }

      # todo
      Lightning.Projects.import_project(data)
    end
  end
end
