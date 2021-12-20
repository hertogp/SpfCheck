defmodule Rfc7208.Section7Test do
  use ExUnit.Case

  # Generated by mix rfc7208.testsuite
  # usage:
  # mix test
  # mix test --only set:7
  # mix test --only tst:7.y where y is in [0..8]

  describe "rfc7208-07-include-mechanism-semantics-and-syntax" do
      @tag set: 7
  @tag tst: "7.0"
  test "7.0 include-cidr" do
    #
    # spec 5.2/1 - Include mechanism semantics and syntax - include-cidr
    #
    ctx = Spf.check("foo@e9.example.com", helo: "mail.example.com", ip: "1.2.3.4", dns: "test/zones/rfc7208-07-include-mechanism-semantics-and-syntax.zonedata")
    assert to_string(ctx.verdict) in ["permerror"], "7.0 include-cidr"
    assert ctx.explanation == "", "7.0 include-cidr"
  end

  @tag set: 7
  @tag tst: "7.1"
  test "7.1 include-empty-domain" do
    #
    # spec 5.2/1 - Include mechanism semantics and syntax - include-empty-domain
    #
    ctx = Spf.check("foo@e8.example.com", helo: "mail.example.com", ip: "1.2.3.4", dns: "test/zones/rfc7208-07-include-mechanism-semantics-and-syntax.zonedata")
    assert to_string(ctx.verdict) in ["permerror"], "7.1 include-empty-domain"
    assert ctx.explanation == "", "7.1 include-empty-domain"
  end

  @tag set: 7
  @tag tst: "7.2"
  test "7.2 include-fail" do
    #
    # spec 5.2/9 - Include mechanism semantics and syntax - include-fail
    #
    ctx = Spf.check("foo@e1.example.com", helo: "mail.example.com", ip: "1.2.3.4", dns: "test/zones/rfc7208-07-include-mechanism-semantics-and-syntax.zonedata")
    assert to_string(ctx.verdict) in ["softfail"], "7.2 include-fail"
    assert ctx.explanation == "", "7.2 include-fail"
  end

  @tag set: 7
  @tag tst: "7.3"
  test "7.3 include-neutral" do
    #
    # spec 5.2/9 - Include mechanism semantics and syntax - include-neutral
    #
    ctx = Spf.check("foo@e3.example.com", helo: "mail.example.com", ip: "1.2.3.4", dns: "test/zones/rfc7208-07-include-mechanism-semantics-and-syntax.zonedata")
    assert to_string(ctx.verdict) in ["fail"], "7.3 include-neutral"
    assert ctx.explanation == "", "7.3 include-neutral"
  end

  @tag set: 7
  @tag tst: "7.4"
  test "7.4 include-none" do
    #
    # spec 5.2/9 - Include mechanism semantics and syntax - include-none
    #
    ctx = Spf.check("foo@e7.example.com", helo: "mail.example.com", ip: "1.2.3.4", dns: "test/zones/rfc7208-07-include-mechanism-semantics-and-syntax.zonedata")
    assert to_string(ctx.verdict) in ["permerror"], "7.4 include-none"
    assert ctx.explanation == "", "7.4 include-none"
  end

  @tag set: 7
  @tag tst: "7.5"
  test "7.5 include-permerror" do
    #
    # spec 5.2/9 - Include mechanism semantics and syntax - include-permerror
    #
    ctx = Spf.check("foo@e5.example.com", helo: "mail.example.com", ip: "1.2.3.4", dns: "test/zones/rfc7208-07-include-mechanism-semantics-and-syntax.zonedata")
    assert to_string(ctx.verdict) in ["permerror"], "7.5 include-permerror"
    assert ctx.explanation == "", "7.5 include-permerror"
  end

  @tag set: 7
  @tag tst: "7.6"
  test "7.6 include-softfail" do
    #
    # spec 5.2/9 - Include mechanism semantics and syntax - include-softfail
    #
    ctx = Spf.check("foo@e2.example.com", helo: "mail.example.com", ip: "1.2.3.4", dns: "test/zones/rfc7208-07-include-mechanism-semantics-and-syntax.zonedata")
    assert to_string(ctx.verdict) in ["pass"], "7.6 include-softfail"
    assert ctx.explanation == "", "7.6 include-softfail"
  end

  @tag set: 7
  @tag tst: "7.7"
  test "7.7 include-syntax-error" do
    #
    # spec 5.2/1 - Include mechanism semantics and syntax - include-syntax-error
    #
    ctx = Spf.check("foo@e6.example.com", helo: "mail.example.com", ip: "1.2.3.4", dns: "test/zones/rfc7208-07-include-mechanism-semantics-and-syntax.zonedata")
    assert to_string(ctx.verdict) in ["permerror"], "7.7 include-syntax-error"
    assert ctx.explanation == "", "7.7 include-syntax-error"
  end

  @tag set: 7
  @tag tst: "7.8"
  test "7.8 include-temperror" do
    #
    # spec 5.2/9 - Include mechanism semantics and syntax - include-temperror
    #
    ctx = Spf.check("foo@e4.example.com", helo: "mail.example.com", ip: "1.2.3.4", dns: "test/zones/rfc7208-07-include-mechanism-semantics-and-syntax.zonedata")
    assert to_string(ctx.verdict) in ["temperror"], "7.8 include-temperror"
    assert ctx.explanation == "", "7.8 include-temperror"
  end

  end
end