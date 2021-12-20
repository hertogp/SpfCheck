defmodule Rfc7208.Section4Test do
  use ExUnit.Case

  # Generated by mix rfc7208.testsuite
  # Usage:
  # % mix test
  # % mix test --only set:4
  # % mix test --only tst:4.y where y is in [0..4]

  describe "rfc7208-04-all-mechanism-syntax" do
      @tag set: 4
  @tag tst: "4.0"
  test "4.0 all-arg" do
    # spec 5.1/1 - ALL mechanism syntax - all-arg

    ctx =
      Spf.check("foo@e2.example.com",
        helo: "mail.example.com",
        ip: "1.2.3.4",
        dns: "test/zones/rfc7208-04-all-mechanism-syntax.zonedata"
      )

    assert to_string(ctx.verdict) in ["permerror"], "4.0 all-arg"
    assert ctx.explanation == "", "4.0 all-arg"
  end

  @tag set: 4
  @tag tst: "4.1"
  test "4.1 all-cidr" do
    # spec 5.1/1 - ALL mechanism syntax - all-cidr

    ctx =
      Spf.check("foo@e3.example.com",
        helo: "mail.example.com",
        ip: "1.2.3.4",
        dns: "test/zones/rfc7208-04-all-mechanism-syntax.zonedata"
      )

    assert to_string(ctx.verdict) in ["permerror"], "4.1 all-cidr"
    assert ctx.explanation == "", "4.1 all-cidr"
  end

  @tag set: 4
  @tag tst: "4.2"
  test "4.2 all-dot" do
    # spec 5.1/1 - ALL mechanism syntax - all-dot

    ctx =
      Spf.check("foo@e1.example.com",
        helo: "mail.example.com",
        ip: "1.2.3.4",
        dns: "test/zones/rfc7208-04-all-mechanism-syntax.zonedata"
      )

    assert to_string(ctx.verdict) in ["permerror"], "4.2 all-dot"
    assert ctx.explanation == "", "4.2 all-dot"
  end

  @tag set: 4
  @tag tst: "4.3"
  test "4.3 all-double" do
    # spec 5.1/1 - ALL mechanism syntax - all-double

    ctx =
      Spf.check("foo@e5.example.com",
        helo: "mail.example.com",
        ip: "1.2.3.4",
        dns: "test/zones/rfc7208-04-all-mechanism-syntax.zonedata"
      )

    assert to_string(ctx.verdict) in ["pass"], "4.3 all-double"
    assert ctx.explanation == "", "4.3 all-double"
  end

  @tag set: 4
  @tag tst: "4.4"
  test "4.4 all-neutral" do
    # spec 5.1/1 - ALL mechanism syntax - all-neutral

    ctx =
      Spf.check("foo@e4.example.com",
        helo: "mail.example.com",
        ip: "1.2.3.4",
        dns: "test/zones/rfc7208-04-all-mechanism-syntax.zonedata"
      )

    assert to_string(ctx.verdict) in ["neutral"], "4.4 all-neutral"
    assert ctx.explanation == "", "4.4 all-neutral"
  end

  end
end
