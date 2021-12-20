defmodule Rfc7208.Section1Test do
  use ExUnit.Case

  # Generated by mix rfc7208.testsuite
  # Usage:
  # % mix test
  # % mix test --only set:1
  # % mix test --only tst:1.y where y is in [0..6]

  describe "rfc7208-01-record-lookup" do
      @tag set: 1
  @tag tst: "1.0"
  test "1.0 alltimeout" do
    # spec 4.4/2 - Record lookup - alltimeout

    ctx =
      Spf.check("foo@alltimeout.example.net",
        helo: "mail.example.net",
        ip: "1.2.3.4",
        dns: "test/zones/rfc7208-01-record-lookup.zonedata"
      )

    assert to_string(ctx.verdict) in ["temperror"], "1.0 alltimeout"
    assert ctx.explanation == "", "1.0 alltimeout"
  end

  @tag set: 1
  @tag tst: "1.1"
  test "1.1 both" do
    # spec 4.4/1 - Record lookup - both

    ctx =
      Spf.check("foo@both.example.net",
        helo: "mail.example.net",
        ip: "1.2.3.4",
        dns: "test/zones/rfc7208-01-record-lookup.zonedata"
      )

    assert to_string(ctx.verdict) in ["fail"], "1.1 both"
    assert ctx.explanation == "", "1.1 both"
  end

  @tag set: 1
  @tag tst: "1.2"
  test "1.2 nospftxttimeout" do
    # spec 4.4/1 - Record lookup - nospftxttimeout

    ctx =
      Spf.check("foo@nospftxttimeout.example.net",
        helo: "mail.example.net",
        ip: "1.2.3.4",
        dns: "test/zones/rfc7208-01-record-lookup.zonedata"
      )

    assert to_string(ctx.verdict) in ["temperror"], "1.2 nospftxttimeout"
    assert ctx.explanation == "", "1.2 nospftxttimeout"
  end

  @tag set: 1
  @tag tst: "1.3"
  test "1.3 spfonly" do
    # spec 4.4/1 - Record lookup - spfonly

    ctx =
      Spf.check("foo@spfonly.example.net",
        helo: "mail.example.net",
        ip: "1.2.3.4",
        dns: "test/zones/rfc7208-01-record-lookup.zonedata"
      )

    assert to_string(ctx.verdict) in ["none"], "1.3 spfonly"
    assert ctx.explanation == "", "1.3 spfonly"
  end

  @tag set: 1
  @tag tst: "1.4"
  test "1.4 spftimeout" do
    # spec 4.4/1 - Record lookup - spftimeout

    ctx =
      Spf.check("foo@spftimeout.example.net",
        helo: "mail.example.net",
        ip: "1.2.3.4",
        dns: "test/zones/rfc7208-01-record-lookup.zonedata"
      )

    assert to_string(ctx.verdict) in ["fail"], "1.4 spftimeout"
    assert ctx.explanation == "", "1.4 spftimeout"
  end

  @tag set: 1
  @tag tst: "1.5"
  test "1.5 txtonly" do
    # spec 4.4/1 - Record lookup - txtonly

    ctx =
      Spf.check("foo@txtonly.example.net",
        helo: "mail.example.net",
        ip: "1.2.3.4",
        dns: "test/zones/rfc7208-01-record-lookup.zonedata"
      )

    assert to_string(ctx.verdict) in ["fail"], "1.5 txtonly"
    assert ctx.explanation == "", "1.5 txtonly"
  end

  @tag set: 1
  @tag tst: "1.6"
  test "1.6 txttimeout" do
    # spec 4.4/1 - Record lookup - txttimeout

    ctx =
      Spf.check("foo@txttimeout.example.net",
        helo: "mail.example.net",
        ip: "1.2.3.4",
        dns: "test/zones/rfc7208-01-record-lookup.zonedata"
      )

    assert to_string(ctx.verdict) in ["temperror"], "1.6 txttimeout"
    assert ctx.explanation == "", "1.6 txttimeout"
  end

  end
end
