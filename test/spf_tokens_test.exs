defmodule Spf.TokenTest do
  use ExUnit.Case
  import NimbleParsec
  import Spf.Tokens

  # Parsers
  defparsec(:p_macro, macro())

  # Assertions
  # from https://elixirforum.com/t/trying-to-write-a-simple-nimble-parsec-parser/41344/4

  test "macro parses expands" do
    testcases = ["%{d}", "%{d}/32", "%{d}//128", "%{d}/32//128", "%{d}.co.uk.%{i}/24"]
    Enum.map(testcases, fn testcase -> IO.inspect(p_macro(testcase), label: testcase) end)
  end
end
