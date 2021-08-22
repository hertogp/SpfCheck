defmodule Spf.TokenTest do
  use ExUnit.Case
  import NimbleParsec

  # Assertions
  # from https://elixirforum.com/t/trying-to-write-a-simple-nimble-parsec-parser/41344/4

  @mletters String.split("slodiphcrtvSLODIPHCRTV", "", trim: true)

  def charcode(charstr) when is_binary(charstr),
    do: String.to_charlist(charstr) |> List.first()

  describe "domain_spec() parses" do
    defparsecp(:domain_spec, Spf.Tokens.domain_spec())

    # a domain spec is a subtoken

    test "simple macros" do
      check = fn l, str ->
        assert domain_spec(str) ==
                 {:ok, [{:domain_spec, [{:expand, [charcode(l), 0, false, ["."]], 0..3}], 0..3}],
                  "", %{}, {1, 0}, 4}
      end

      testcases = for l <- @mletters, do: {l, "%{#{l}}"}
      Enum.map(testcases, fn {l, str} -> check.(l, str) end)
    end

    test "macros with keep" do
      check = fn l, str ->
        assert domain_spec(str) ==
                 {:ok, [{:domain_spec, [{:expand, [charcode(l), 3, false, ["."]], 0..4}], 0..4}],
                  "", %{}, {1, 0}, 5}
      end

      testcases = for l <- @mletters, do: {l, "%{#{l}3}"}
      Enum.map(testcases, fn {l, str} -> check.(l, str) end)
    end

    test "macros with reverse" do
      check = fn l, str ->
        assert domain_spec(str) ==
                 {:ok, [{:domain_spec, [{:expand, [charcode(l), 0, true, ["."]], 0..4}], 0..4}],
                  "", %{}, {1, 0}, 5}
      end

      testcases = for l <- @mletters, do: {l, "%{#{l}r}"}
      Enum.map(testcases, fn {l, str} -> check.(l, str) end)
      # also uppercase R
      testcases = for l <- @mletters, do: {l, "%{#{l}R}"}
      Enum.map(testcases, fn {l, str} -> check.(l, str) end)
    end

    test "macros with keep and reverse" do
      check = fn l, str ->
        assert domain_spec(str) ==
                 {:ok, [{:domain_spec, [{:expand, [charcode(l), 9, true, ["."]], 0..5}], 0..5}],
                  "", %{}, {1, 0}, 6}
      end

      testcases = for l <- @mletters, do: {l, "%{#{l}9r}"}
      Enum.map(testcases, fn {l, str} -> check.(l, str) end)
      # also uppercase R
      testcases = for l <- @mletters, do: {l, "%{#{l}9R}"}
      Enum.map(testcases, fn {l, str} -> check.(l, str) end)
    end

    test "macros with delimiters" do
      check = fn l, str ->
        assert domain_spec(str) ==
                 {:ok,
                  [
                    {:domain_spec,
                     [
                       {:expand, [charcode(l), 0, false, [".", "-", "+", ",", "/", "_", "="]],
                        0..10}
                     ], 0..10}
                  ], "", %{}, {1, 0}, 11}
      end

      testcases = for l <- @mletters, do: {l, "%{#{l}.-+,/_=}"}
      Enum.map(testcases, fn {l, str} -> check.(l, str) end)
    end

    test "macros with reverse and delimiters" do
      check = fn l, str ->
        assert domain_spec(str) ==
                 {:ok,
                  [
                    {:domain_spec,
                     [
                       {:expand, [charcode(l), 0, true, [".", "-", "+", ",", "/", "_", "="]],
                        0..11}
                     ], 0..11}
                  ], "", %{}, {1, 0}, 12}
      end

      testcases = for l <- @mletters, do: {l, "%{#{l}r.-+,/_=}"}
      Enum.map(testcases, fn {l, str} -> check.(l, str) end)
      # also uppercase R
      testcases = for l <- @mletters, do: {l, "%{#{l}R.-+,/_=}"}
      Enum.map(testcases, fn {l, str} -> check.(l, str) end)
    end

    test "macros with keep, reverse and delimiters" do
      check = fn l, str ->
        assert domain_spec(str) ==
                 {:ok,
                  [
                    {:domain_spec,
                     [
                       {:expand, [charcode(l), 11, true, [".", "-", "+", ",", "/", "_", "="]],
                        0..13}
                     ], 0..13}
                  ], "", %{}, {1, 0}, 14}
      end

      testcases = for l <- @mletters, do: {l, "%{#{l}11r.-+,/_=}"}
      Enum.map(testcases, fn {l, str} -> check.(l, str) end)
      # also uppercase R
      testcases = for l <- @mletters, do: {l, "%{#{l}11R.-+,/_=}"}
      Enum.map(testcases, fn {l, str} -> check.(l, str) end)
    end
  end

  describe "dual_cidr() lexes" do
    defparsecp(:cidr, Spf.Tokens.dual_cidr())

    test "/24" do
      assert cidr("/24") == {:ok, [{:dual_cidr, [24, 128], 0..2}], "", %{start: 0}, {1, 0}, 3}
    end

    test "//64" do
      assert cidr("//64") == {:ok, [{:dual_cidr, [32, 64], 0..3}], "", %{start: 0}, {1, 0}, 4}
    end

    test "/24//64" do
      assert cidr("/24//64") == {:ok, [{:dual_cidr, [24, 64], 0..6}], "", %{start: 0}, {1, 0}, 7}
    end

    test "/33//129" do
      # parser will validate prefix lengths, not the lexer
      assert cidr("/33//129") ==
               {:ok, [{:dual_cidr, [33, 129], 0..7}], "", %{start: 0}, {1, 0}, 8}
    end
  end

  describe "whitespace() lexes" do
    defparsecp(:wspace, Spf.Tokens.whitespace())

    test "1 space" do
      assert wspace(" ") ==
               {:ok, [{:whitespace, [" "], 0..0}], "", %{start: 0}, {1, 0}, 1}
    end

    test "1+ spaces" do
      assert wspace("   ") ==
               {:ok, [{:whitespace, ["   "], 0..2}], "", %{start: 0}, {1, 0}, 3}
    end

    test "1+ tabs" do
      assert wspace("\t\t") ==
               {:ok, [{:whitespace, ["\t\t"], 0..1}], "", %{start: 0}, {1, 0}, 2}
    end

    test "1+ (SP / TAB)" do
      assert wspace(" \t ") ==
               {:ok, [{:whitespace, [" \t "], 0..2}], "", %{start: 0}, {1, 0}, 3}
    end
  end

  describe "a() lexes" do
    defparsec(:a, Spf.Tokens.a())

    test "a" do
      assert a("a") ==
               {:ok, [{:a, [?+, []], 0..0}], "", %{start: 0}, {1, 0}, 1}
    end

    test "a with cidr" do
      assert a("a/24") ==
               {:ok, [{:a, [?+, [{:dual_cidr, [24, 128], 0..3}]], 0..3}], "", %{start: 0}, {1, 0},
                4}
    end

    test "a with domain_spec" do
      assert a("a:%{d}") ==
               {:ok,
                [
                  {:a, [43, [{:domain_spec, [{:expand, [100, 0, false, ["."]], 0..5}], 0..5}]],
                   0..5}
                ], "", %{start: 0}, {1, 0}, 6}
    end
  end
end
