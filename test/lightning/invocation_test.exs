defmodule Lightning.InvocationTest do
  use Lightning.DataCase

  alias Lightning.Invocation
  alias Lightning.Repo
  import Lightning.InvocationFixtures

  describe "dataclips" do
    alias Lightning.Invocation.Dataclip

    @invalid_attrs %{body: nil, type: nil}

    test "list_dataclips/0 returns all dataclips" do
      dataclip = dataclip_fixture()
      assert Invocation.list_dataclips() == [dataclip]
    end

    test "get_dataclip!/1 returns the dataclip with given id" do
      dataclip = dataclip_fixture()
      assert Invocation.get_dataclip!(dataclip.id) == dataclip
    end

    test "create_dataclip/1 with valid data creates a dataclip" do
      valid_attrs = %{body: %{}, type: :http_request}

      assert {:ok, %Dataclip{} = dataclip} = Invocation.create_dataclip(valid_attrs)
      assert dataclip.body == %{}
      assert dataclip.type == :http_request
    end

    test "create_dataclip/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Invocation.create_dataclip(@invalid_attrs)
    end

    test "update_dataclip/2 with valid data updates the dataclip" do
      dataclip = dataclip_fixture()
      update_attrs = %{body: %{}, type: :global}

      assert {:ok, %Dataclip{} = dataclip} = Invocation.update_dataclip(dataclip, update_attrs)
      assert dataclip.body == %{}
      assert dataclip.type == :global
    end

    test "update_dataclip/2 with invalid data returns error changeset" do
      dataclip = dataclip_fixture()
      assert {:error, %Ecto.Changeset{}} = Invocation.update_dataclip(dataclip, @invalid_attrs)
      assert dataclip == Invocation.get_dataclip!(dataclip.id)
    end

    test "delete_dataclip/1 deletes the dataclip" do
      dataclip = dataclip_fixture()
      assert {:ok, %Dataclip{}} = Invocation.delete_dataclip(dataclip)
      assert_raise Ecto.NoResultsError, fn -> Invocation.get_dataclip!(dataclip.id) end
    end

    test "change_dataclip/1 returns a dataclip changeset" do
      dataclip = dataclip_fixture()
      assert %Ecto.Changeset{} = Invocation.change_dataclip(dataclip)
    end
  end

  describe "events" do
    alias Lightning.Invocation.Event
    import Lightning.JobsFixtures

    @invalid_attrs %{type: nil, dataclip: nil}

    test "create_event/1 with valid data creates an event" do
      dataclip = dataclip_fixture()
      job = job_fixture()
      valid_attrs = %{type: :webhook, dataclip_id: dataclip.id, job_id: job.id}

      assert {:ok, %Event{} = event} = Invocation.create_event(valid_attrs)
      event = Repo.preload(event, [:dataclip, :job])
      assert event.dataclip == dataclip
      assert event.job == job
      assert event.type == :webhook
    end

    test "create_event/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Invocation.create_event(@invalid_attrs)
    end
  end
end
