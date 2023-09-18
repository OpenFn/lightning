defmodule Lightning.Config.Stub do
  @behaviour Lightning.Config.API

  @impl true
  def attempts_adaptor() do
    Lightning.Attempts.Queue
  end

  @impl true
  def worker_token_signer() do
    Joken.Signer.create("HS256", "supersecret")
  end

  @impl true
  def attempt_token_signer() do
    Joken.Signer.create("RS256", %{
      "pem" => """
      -----BEGIN PRIVATE KEY-----
      MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCweDzCJiSYKXop
      UIUvkQzsURtXhqNcdHCcFa4LWgsEIDNeWkoXhcOVlJGVUbaKVaGUOOrLICfsfrbL
      EAbxRzBM+vGVwSV5JN0l7Zhnf9mgYTyouQieufy4oxLXnO07tyBA9sRePveKRTAM
      BOYh9g3aW8J3PwV72etaxsChLv4ytsmmwixVZt+O3JllEjsHDN+wktb7BFbATvtA
      W+RX0EnVqzcfZluW6Mx/2cL5injLAPP/sHsJxNyRPJd+ScRzZfWJYLzPMPu8CLvg
      RBpuolZ3xOn1js+3+ROLhr8AAGuq7Tpo6Ze5lTSAbyUr9tUSucAV5WeYIY6LZWLZ
      7Z8IYmVnAgMBAAECggEAG/t05vRVaStqi5KRC/HcMrzJsR9QWCC+moF1j6c/h+/z
      NUrr5L75PIbKbvr+DwF1FaPQ11TJ/9437gskjq3TIuHH3Q87efI2fwUl3YOQZrYE
      gFyW2VR0lnKFUls34vguzR5UFP23Et3VuJIuS8RQfgd+1pnPrMvpXgOWF/jzpebC
      coBD5gYDWI4NayQqycH+QvHAyOKa5cpRycrGcCkheyRR/1//RtWDwHc8LN1tz5nv
      ArVwzjPrLeR9hd8o5nZHwh78HC8Q9raW2yG9M2b0HKiQHB7bK5VdJylX0vij+wSC
      soZqBXFyufSR4T8QmcI/Ri5THRg21doxEvmM7AHqQQKBgQDo7IyMV2bfcXPq4k/6
      WAjyhchcLvQMTtbn3LmqIUW+TMF7dVHjP2XutVCr9TzQObQydSBKmatzrtg7b+x/
      SYTfSbDZAY/uZX0gdiOtLa0s9Ia+RGIshpKqduVh7ErdaNmgOXGLiqGJMINuA8m0
      ixryxWTOjvfwgDKD0ouah0eYTQKBgQDB8+KyKktyQaLeXtomU6boHl/3rW79kwpQ
      xnPov7c9lcbr20yrabiao3DutmtZz5TrZ1/RwJYfuZsP7VZnHngXBvXlGs3but4L
      T4HGAf0Onxy/YfnPRxCqM2k45/J6Q3GpxzBlweJSi3RkC5PB6ePzJGqwzC88V6Nt
      YvU8I7hOgwKBgQCXTQkjJKcrX9wHaIjBOqxdNW/oCYv37sKEjImCLOjL67oHAzd1
      ITqKa/cCLGQbclBOMm0OaHHJzHqjaVm7eTs5e/nHjM888WntSzBzjucd+50HPQ50
      k9nzpxXrnP0og7JR9N5/4UZ7AittrEI6591Sc8y+rHn8HJozrPGIKHXmRQKBgDw3
      Nuuvu+rGPAWkF0CM+iXYwFzKKMpra2l2o6fgVci2BqNVW7FgSmMgWUCTvDKPAyIu
      3w3lJ/bDjkPcoNW1HP2xOIif0MfmdWe3kIfkOCfg+HDmv0M+QgtFmOaFBMA2zkQy
      xnDhSB3uk/03pvEuZ4omhUVMr2Ghp+ifL5ozUNZ3AoGBAOEbcqX8/m7v2S6BIhJg
      AK+GA9b1zW80WPKu/tLjHHqeN30OPoQeZU42rLbPXXW4XsGP1bdSLMPZg9Ob1h8W
      pnMjCrSKFfjVHJvNtLmidLeDKtF2aF8v6PKIl/w5judqV+P268QYQUHXiWUsXOWj
      y5N6bLtW1lN10jGcbW3Sg+0R
      -----END PRIVATE KEY-----
      """
    })
  end
end

defmodule Lightning.Stub do
  @moduledoc false
  @behaviour Lightning.API

  @impl true
  def current_time(), do: Lightning.API.current_time()

  @doc """
  Resets the current time to the current time.
  """
  def reset_time() do
    Lightning.Mock
    |> Mox.stub(:current_time, fn -> DateTime.utc_now() end)
  end

  @doc """
  Freezes the current time to the given time.
  """
  def freeze_time(time) do
    Lightning.Mock
    |> Mox.stub(:current_time, fn -> time end)
  end
end
