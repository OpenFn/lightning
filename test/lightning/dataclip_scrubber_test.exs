defmodule Lightning.DataclipScrubberTest do
  use Lightning.DataCase, async: true

  alias Lightning.DataclipScrubber

  import Lightning.Factories

  describe "scrub_dataclip_body!/1" do
    test "returns nil for nil body" do
      assert DataclipScrubber.scrub_dataclip_body!(%{
               body: nil,
               type: :http_request,
               id: Ecto.UUID.generate()
             }) == nil
    end

    test "returns body unchanged for non-sensitive dataclip types" do
      body = ~s({"data": "some value"})
      dataclip = %{body: body, type: :saved_input, id: Ecto.UUID.generate()}
      assert DataclipScrubber.scrub_dataclip_body!(dataclip) == body
    end

    test "scrubs http_request dataclip with webhook auth method values" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      webhook_auth =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic,
          username: "secretuser",
          password: "secretpass"
        )

      # Associate the webhook auth method with the trigger
      trigger
      |> Repo.preload(:webhook_auth_methods)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:webhook_auth_methods, [webhook_auth])
      |> Repo.update!()

      # Create a dataclip via work order
      dataclip =
        insert(:dataclip,
          project: project,
          type: :http_request,
          body: %{
            "data" => "test",
            "auth_header" => "Basic #{Base.encode64("secretuser:secretpass")}"
          }
        )

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip
      )

      body_json = Jason.encode!(dataclip.body)

      result =
        DataclipScrubber.scrub_dataclip_body!(%{
          body: body_json,
          type: :http_request,
          id: dataclip.id
        })

      # The username, password, and base64-encoded basic auth should be scrubbed
      refute result =~ "secretuser"
      refute result =~ "secretpass"
      refute result =~ Base.encode64("secretuser:secretpass")
      assert result =~ "***"
    end

    test "scrubs http_request dataclip with api key webhook auth" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      webhook_auth =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :api,
          api_key: "super-secret-api-key-12345"
        )

      # Associate the webhook auth method with the trigger
      trigger
      |> Repo.preload(:webhook_auth_methods)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:webhook_auth_methods, [webhook_auth])
      |> Repo.update!()

      # Create a dataclip via work order
      dataclip =
        insert(:dataclip,
          project: project,
          type: :http_request,
          body: %{
            "data" => "test",
            "api_key_header" => "super-secret-api-key-12345"
          }
        )

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip
      )

      body_json = Jason.encode!(dataclip.body)

      result =
        DataclipScrubber.scrub_dataclip_body!(%{
          body: body_json,
          type: :http_request,
          id: dataclip.id
        })

      refute result =~ "super-secret-api-key-12345"
      assert result =~ "***"
    end

    test "returns body unchanged when http_request has no webhook auth methods" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      dataclip =
        insert(:dataclip,
          project: project,
          type: :http_request,
          body: %{"data" => "test"}
        )

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip
      )

      body_json = Jason.encode!(dataclip.body)

      result =
        DataclipScrubber.scrub_dataclip_body!(%{
          body: body_json,
          type: :http_request,
          id: dataclip.id
        })

      assert result == body_json
    end
  end

  describe "scrub_dataclip_bodies!/1" do
    setup do
      [first, second] =
        for password <- ["secret-one", "secret-two"] do
          project = insert(:project)
          workflow = insert(:workflow, project: project)
          trigger = insert(:trigger, workflow: workflow, type: :webhook)

          webhook_auth =
            insert(:webhook_auth_method,
              project: project,
              auth_type: :basic,
              username: "user",
              password: password
            )

          trigger
          |> Repo.preload(:webhook_auth_methods)
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_assoc(:webhook_auth_methods, [webhook_auth])
          |> Repo.update!()

          dataclip =
            insert(:dataclip,
              project: project,
              type: :http_request,
              # The marker must not contain the secret as a substring, or the
              # scrubber - correctly - eats it too.
              body: %{
                "password" => password,
                "keep" => "kept-" <> String.replace(password, "secret-", "")
              }
            )

          insert(:workorder,
            workflow: workflow,
            trigger: trigger,
            dataclip: dataclip
          )

          %{password: password, dataclip: dataclip, project: project}
        end

      unprotected =
        insert(:dataclip,
          project: insert(:project),
          type: :http_request,
          body: %{"borrowed" => "secret-one"}
        )

      %{first: first, second: second, unprotected: unprotected}
    end

    test "scrubs each dataclip against its own secrets only", %{
      first: first,
      second: second,
      unprotected: unprotected
    } do
      scrubbed =
        [first.dataclip, second.dataclip, unprotected]
        |> Enum.map(&to_scrubbable/1)
        |> DataclipScrubber.scrub_dataclip_bodies!()

      refute scrubbed[first.dataclip.id] =~ "secret-one"
      assert scrubbed[first.dataclip.id] =~ "kept-one"

      refute scrubbed[second.dataclip.id] =~ "secret-two"
      assert scrubbed[second.dataclip.id] =~ "kept-two"

      # Nothing about this dataclip is sensitive, so batching must not pool
      # the other dataclips' samples into it.
      assert scrubbed[unprotected.id] =~ "secret-one"
    end

    test "agrees with scrub_dataclip_body!/1", %{
      first: first,
      second: second,
      unprotected: unprotected
    } do
      dataclips =
        Enum.map(
          [first.dataclip, second.dataclip, unprotected],
          &to_scrubbable/1
        )

      batched = DataclipScrubber.scrub_dataclip_bodies!(dataclips)

      for dataclip <- dataclips do
        assert batched[dataclip.id] ==
                 DataclipScrubber.scrub_dataclip_body!(dataclip)
      end
    end

    test "passes through nil bodies and types that are never scrubbed" do
      nil_body = %{id: Ecto.UUID.generate(), type: :http_request, body: nil}

      saved_input = %{
        id: Ecto.UUID.generate(),
        type: :saved_input,
        body: ~s({"data":"kept"})
      }

      scrubbed =
        DataclipScrubber.scrub_dataclip_bodies!([nil_body, saved_input])

      assert scrubbed[nil_body.id] == nil
      assert scrubbed[saved_input.id] == saved_input.body
    end

    defp to_scrubbable(dataclip) do
      %{
        id: dataclip.id,
        type: dataclip.type,
        body: Jason.encode!(dataclip.body)
      }
    end
  end

  describe "webhook_auth_methods_for_dataclip/1" do
    test "returns webhook auth methods for a dataclip" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      webhook_auth =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic,
          username: "user",
          password: "password"
        )

      trigger
      |> Repo.preload(:webhook_auth_methods)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:webhook_auth_methods, [webhook_auth])
      |> Repo.update!()

      dataclip = insert(:dataclip, project: project, type: :http_request)

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip
      )

      result = DataclipScrubber.webhook_auth_methods_for_dataclip(dataclip.id)

      assert length(result) == 1
      assert hd(result).id == webhook_auth.id
    end

    test "returns empty list when no webhook auth methods" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      dataclip = insert(:dataclip, project: project, type: :http_request)

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip
      )

      result = DataclipScrubber.webhook_auth_methods_for_dataclip(dataclip.id)

      assert result == []
    end
  end

  describe "webhook_auth_methods_for_step/1" do
    test "returns webhook auth methods for a step" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)
      job = insert(:job, workflow: workflow)

      webhook_auth =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :api,
          api_key: "test-key"
        )

      trigger
      |> Repo.preload(:webhook_auth_methods)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:webhook_auth_methods, [webhook_auth])
      |> Repo.update!()

      dataclip = insert(:dataclip, project: project, type: :http_request)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      run =
        insert(:run,
          work_order: work_order,
          dataclip: dataclip,
          starting_job: job
        )

      step = insert(:step, runs: [run], job: job)

      result = DataclipScrubber.webhook_auth_methods_for_step(step.id)

      assert length(result) == 1
      assert hd(result).id == webhook_auth.id
    end
  end
end
