defmodule SpfcheckTestSuite do
  alias Rfc7208.TestSuite
  use ExUnit.Case

  # usage:
  # mix test --only s:n, where n in 0..14
  # mix test --only t:x.y where x.y is a specific test in the test suite

  Enum.each(TestSuite.all(), fn {test, mailfrom, helo, ip, result, dns, info} ->
    @test test
    @mailfrom mailfrom
    @helo helo
    @ip ip
    @result result
    @dns dns
    @info info
    @test_set String.split(test, ".") |> List.first()
    @test_tag String.split(test, " ") |> List.first()

    @tag set: @test_set
    @tag tst: @test_tag
    test "#{@test} - #{@mailfrom}" do
      ctx =
        Spf.Context.new(@mailfrom, helo: @helo, ip: @ip)
        |> Spf.DNS.load_lines(@dns)
        |> Spf.Eval.evaluate()

      msg = "\ngot #{ctx.verdict}, expected #{@result} - #{@info}\n"
      msg = msg <> "- TEST: #{@test}\n"
      msg = msg <> "- FROM: #{@mailfrom} -> ctx.domain: #{ctx.domain}\n"
      msg = msg <> "- HELO: #{@helo} -> ctx.helo #{ctx.helo}\n"
      msg = msg <> "- IP  : #{@ip} -> ctx.ip #{inspect(ctx.ip)}\n"
      msg = msg <> "- SPF : ctx.spf #{ctx.spf}\n"
      msg = msg <> "- Atyp: ctx.atype #{ctx.atype}\n"

      list = Enum.map(ctx.msg, fn x -> inspect(x) end)
      msg = msg <> "\nMSG\n"

      msg = msg <> (Enum.reverse(list) |> Enum.join("\n"))

      msg = msg <> "\n\nTOKENS\n"

      msg =
        msg <>
          (ctx.spf_tokens
           |> Enum.map(fn x -> inspect(x) end)
           |> Enum.join("\n"))

      msg = msg <> "\n\nAST\n"

      msg =
        msg <>
          (ctx.ast
           |> Enum.map(fn x -> inspect(x) end)
           |> Enum.join("\n"))

      msg = msg <> "\n\nDNS\n"

      msg =
        msg <> (Enum.filter(@dns, fn l -> String.contains?(l, ctx.domain) end) |> Enum.join("\n"))

      # msg <> (Enum.sort(@dns) |> Enum.join("\n"))

      msg = msg <> "\n\nMAP\n"

      msg =
        msg <>
          (Enum.map(ctx.map, fn {d, n} -> "#{n} - #{d}" end) |> Enum.sort() |> Enum.join("\n"))

      assert "#{ctx.verdict}" in @result, msg
    end
  end)
end