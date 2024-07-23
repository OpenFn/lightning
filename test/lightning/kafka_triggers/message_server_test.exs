defmodule Lightning.KafkaTriggers.MessageServerTest do
  use Lightning.DataCase

  alias Lightning.KafkaTriggers.MessageServer

  describe ".start_link/1" do
    test "successfully starts the server" do
      pid = start_supervised!(MessageServer)

      assert GenServer.whereis(MessageServer) == pid
    end

    test "initialises with an empty list" do
      assert pid = start_supervised!(MessageServer)

      assert :sys.get_state(pid) == []
    end
  end

end
