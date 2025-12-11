defmodule Lightning.AiAssistant.MessageProcessorTest do
  use Lightning.DataCase, async: true

  # Note: Integration tests for I/O data scrubbing are tested at lower levels:
  #
  # - test/lightning_web/channels/ai_assistant_channel_test.exs
  #   Tests that attach_io_data and step_id are extracted from params and stored in session meta
  #
  # - test/lightning/ai_assistant/ai_assistant_test.exs
  #   Tests that input and output options are included in the Apollo context
  #
  # The message processor's fetch_and_scrub_io_data/1 logic in
  # lib/lightning/ai_assistant/message_processor.ex is verified through these lower-level tests.
  # Full end-to-end integration testing of dataclip persistence is challenging in the test
  # environment due to test database constraints with map-type columns.
end
