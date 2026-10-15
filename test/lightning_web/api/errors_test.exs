defmodule LightningWeb.API.ErrorsTest do
  use Lightning.DataCase, async: true

  import Lightning.AdaptorTestHelpers
  import Lightning.Factories

  alias Lightning.Accounts.User
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectUser
  alias Lightning.Projects.Provisioner
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Workflow
  alias LightningWeb.API.Errors
  alias LightningWeb.API.Problem
  alias LightningWeb.API.PutRequest

  @adaptor "@openfn/language-common@latest"

  setup :isolated_adaptors

  setup do
    Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn _, _ ->
      :ok
    end)

    :ok
  end

  defp ready_catalogue(_context) do
    seed_ready_catalogue()
    ensure_adaptor(@adaptor)
    :ok
  end

  defp job(id, name) do
    %{"id" => id, "name" => name, "adaptor" => @adaptor, "body" => "fn(s => s)"}
  end

  defp provision(jobs) do
    workflow = %{"id" => Ecto.UUID.generate(), "name" => "w", "jobs" => jobs}
    %{"id" => Ecto.UUID.generate(), "name" => "p", "workflows" => [workflow]}
  end

  defp decode_pointer("#" <> path) do
    path
    |> URI.decode()
    |> String.split("/", trim: true)
    |> Enum.map(fn key ->
      key |> String.replace("~1", "/") |> String.replace("~0", "~")
    end)
  end

  describe "from_changeset/2" do
    setup :ready_catalogue

    test "counts a provisioned child's position among the items the request sent, with one marked delete: true mid-list" do
      [kept, deleted, left_out, blank, last] =
        for _ <- 1..5, do: Ecto.UUID.generate()

      document =
        provision([
          job(kept, "kept"),
          job(deleted, "deleted"),
          job(left_out, "left out")
        ])

      {:ok, project} =
        Provisioner.import_document(%Project{}, insert(:user), document)

      changeset =
        Provisioner.parse_document(
          project,
          put_in(document, ["workflows", Access.at(0), "jobs"], [
            job(kept, "kept"),
            %{"id" => deleted, "delete" => true},
            job(blank, ""),
            job(last, "last")
          ])
        )

      assert Errors.from_changeset(changeset) == [
               %{
                 pointer: "#/workflows/0/jobs/2/name",
                 code: :required,
                 detail: "job name can't be blank"
               }
             ]
    end

    test "keeps a list's own error and its items' errors: project members with no owner and a bad role" do
      changeset =
        Project.project_with_users_changeset(%Project{}, %{
          "name" => "members",
          "project_users" => [
            %{"user_id" => insert(:user).id, "role" => "editor"},
            %{"user_id" => insert(:user).id, "role" => "boss"}
          ]
        })

      assert Errors.from_changeset(changeset, %{
               project_users: :members,
               owner: :members
             }) == [
               %{
                 pointer: "#/members",
                 code: :one_owner,
                 detail:
                   "Every project must have exactly one owner. Please specify one below."
               },
               %{
                 pointer: "#/members/1/role",
                 code: :not_allowed,
                 detail: "is invalid"
               }
             ]
    end

    test "codes a value outside an ecto_enum defenum's set not_allowed, not type" do
      changeset =
        ProjectUser.changeset(%ProjectUser{}, %{
          "user_id" => Ecto.UUID.generate(),
          "role" => "boss"
        })

      assert Errors.from_changeset(changeset) == [
               %{pointer: "#/role", code: :not_allowed, detail: "is invalid"}
             ]
    end

    test "codes a value outside an Ecto.Enum's set not_allowed, not type" do
      changeset =
        Project.changeset(%Project{}, %{
          "name" => "enum",
          "retention_policy" => "keep_forever"
        })

      assert Errors.from_changeset(changeset) == [
               %{
                 pointer: "#/retention_policy",
                 code: :not_allowed,
                 detail: "is invalid"
               }
             ]
    end

    test "still codes a cast to a type that isn't an enum as type" do
      changeset =
        Project.changeset(%Project{}, %{"name" => "type", "concurrency" => "x"})

      assert Errors.from_changeset(changeset) == [
               %{pointer: "#/concurrency", code: :type, detail: "is invalid"}
             ]
    end

    test "points a duplicate at the later of two provisioned children with one id, naming the earlier" do
      id = Ecto.UUID.generate()

      changeset =
        Provisioner.parse_document(
          %Project{},
          provision([job(id, "first"), job(id, "second")])
        )

      assert Errors.from_changeset(changeset) == [
               %{
                 pointer: "#/workflows/0/jobs/1/id",
                 code: :duplicate,
                 detail: "names the same id as #/workflows/0/jobs/0"
               }
             ]
    end

    test "codes an assoc_constraint error not_found at the foreign key the request sent (plan D2)" do
      {:error, changeset} =
        %Workflow{}
        |> Workflow.changeset(%{
          name: "orphan",
          project_id: Ecto.UUID.generate()
        })
        |> Repo.insert()

      assert Errors.from_changeset(changeset) == [
               %{
                 pointer: "#/project_id",
                 code: :not_found,
                 detail: "does not exist"
               }
             ]

      assert [%{pointer: "#/parent"}] =
               Errors.from_changeset(changeset, %{project: :parent})
    end

    test "raises on an error with no code" do
      {:ok, changeset} =
        PutRequest.changeset(%{}, "not-a-uuid", {%{}, %{id: :binary_id}})

      assert_raise ArgumentError,
                   ~r/"is not a UUID" at \[:id\] has no code/,
                   fn ->
                     Errors.from_changeset(changeset)
                   end
    end
  end

  describe "pointer/1" do
    test "escapes a key holding / and ~ so a client decodes it back" do
      key = "a/b~c d%é"

      pointer = Errors.pointer([:workflows, 0, key])

      assert pointer == "#/workflows/0/a~1b~0c%20d%25%C3%A9"
      assert decode_pointer(pointer) == ["workflows", "0", key]
    end

    test "is # alone for the whole body" do
      assert Errors.pointer([]) == "#"
    end
  end

  describe "problem/2" do
    test "answers 503 not_ready, with no entries, when the adaptor catalogue isn't loaded" do
      changeset =
        Job.changeset(%Job{}, %{
          name: "waiting",
          adaptor: "@openfn/language-unseeded@1.0.0",
          body: "fn(s => s)"
        })

      assert Errors.problem(changeset) == %Problem{
               status: 503,
               code: :not_ready,
               headers: [{"retry-after", "5"}]
             }
    end

    test "answers 402 when every error is a plan limit" do
      Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
        %{type: :new_collection}, _context ->
          {:error, :exceeds_limit, %{text: "No collections left"}}

        _action, _context ->
          :ok
      end)

      changeset =
        Provisioner.parse_document(
          %Project{},
          Map.put(provision([]), "collections", [
            %{"id" => Ecto.UUID.generate(), "name" => "more"}
          ])
        )

      assert Errors.problem(changeset) ==
               Problem.new(:exceeds_limit,
                 errors: [
                   %{
                     pointer: "#/id",
                     code: :exceeds_limit,
                     detail: "No collections left"
                   }
                 ]
               )
    end

    test "answers 409 taken when every error is a unique constraint" do
      seed_ready_catalogue()
      ensure_adaptor(@adaptor)
      job = insert(:job, name: "taken", adaptor: @adaptor)

      {:error, changeset} =
        %Job{}
        |> Job.changeset(%{
          name: "taken",
          adaptor: @adaptor,
          body: "fn(s => s)",
          workflow_id: job.workflow_id
        })
        |> Repo.insert()

      assert Errors.problem(changeset) ==
               Problem.new(:taken,
                 errors: [
                   %{
                     pointer: "#/name",
                     code: :taken,
                     detail: "job name has already been taken"
                   }
                 ]
               )
    end

    test "answers 422 for a taken that an application check found, not a unique constraint" do
      user = insert(:user)

      changeset =
        User.user_registration_changeset(%{
          first_name: "Ada",
          last_name: "Lovelace",
          email: user.email,
          password: "a long enough password"
        })

      assert Errors.problem(changeset) ==
               Problem.new(:invalid,
                 errors: [
                   %{
                     pointer: "#/email",
                     code: :taken,
                     detail: "has already been taken"
                   }
                 ]
               )
    end
  end
end
