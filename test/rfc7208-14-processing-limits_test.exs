defmodule Rfc7208.Section14Test do
  use ExUnit.Case

  # Generated by mix rfc7208.testsuite
  # Usage:
  # % mix test
  # % mix test --only set:14
  # % mix test --only tst:14.y where y is in [0..10]

  describe "rfc7208-14-processing-limits" do
    @tag set: "14"
    @tag tst: "14.0"
    test "14.0 false-a-limit" do
      # spec 4.6.4 - Processing limits - false-a-limit
      _cli = """
      spfcheck foo@e10.example.com -i 1.2.3.12 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-14-processing-limits.zonedata
      """

      ctx =
        Spf.check("foo@e10.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.12",
          dns: "test/zones/rfc7208-14-processing-limits.zonedata"
        )

      assert to_string(ctx.verdict) in ["pass"]
      assert ctx.explanation == ""
    end

    @tag set: "14"
    @tag tst: "14.1"
    test "14.1 include-at-limit" do
      # spec 4.6.4/1 - Processing limits - include-at-limit
      _cli = """
      spfcheck foo@e8.example.com -i 1.2.3.4 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-14-processing-limits.zonedata
      """

      ctx =
        Spf.check("foo@e8.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.4",
          dns: "test/zones/rfc7208-14-processing-limits.zonedata"
        )

      assert to_string(ctx.verdict) in ["pass"]
      assert ctx.explanation == ""
    end

    @tag set: "14"
    @tag tst: "14.2"
    test "14.2 include-loop" do
      # spec 4.6.4/1 - Processing limits - include-loop
      _cli = """
      spfcheck foo@e2.example.com -i 1.2.3.4 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-14-processing-limits.zonedata
      """

      ctx =
        Spf.check("foo@e2.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.4",
          dns: "test/zones/rfc7208-14-processing-limits.zonedata"
        )

      assert to_string(ctx.verdict) in ["permerror"]
      assert ctx.explanation == ""
    end

    @tag set: "14"
    @tag tst: "14.3"
    test "14.3 include-over-limit" do
      # spec 4.6.4/1 - Processing limits - include-over-limit
      _cli = """
      spfcheck foo@e9.example.com -i 1.2.3.4 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-14-processing-limits.zonedata
      """

      ctx =
        Spf.check("foo@e9.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.4",
          dns: "test/zones/rfc7208-14-processing-limits.zonedata"
        )

      assert to_string(ctx.verdict) in ["permerror"]
      assert ctx.explanation == ""
    end

    @tag set: "14"
    @tag tst: "14.4"
    test "14.4 mech-at-limit" do
      # spec 4.6.4/1 - Processing limits - mech-at-limit
      _cli = """
      spfcheck foo@e6.example.com -i 1.2.3.4 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-14-processing-limits.zonedata
      """

      ctx =
        Spf.check("foo@e6.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.4",
          dns: "test/zones/rfc7208-14-processing-limits.zonedata"
        )

      assert to_string(ctx.verdict) in ["pass"]
      assert ctx.explanation == ""
    end

    @tag set: "14"
    @tag tst: "14.5"
    test "14.5 mech-over-limit" do
      # spec 4.6.4/1 - Processing limits - mech-over-limit
      _cli = """
      spfcheck foo@e7.example.com -i 1.2.3.4 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-14-processing-limits.zonedata
      """

      ctx =
        Spf.check("foo@e7.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.4",
          dns: "test/zones/rfc7208-14-processing-limits.zonedata"
        )

      assert to_string(ctx.verdict) in ["permerror"]
      assert ctx.explanation == ""
    end

    @tag set: "14"
    @tag tst: "14.6"
    test "14.6 mx-limit" do
      # spec 4.6.4/2 - Processing limits - mx-limit
      _cli = """
      spfcheck foo@e4.example.com -i 1.2.3.5 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-14-processing-limits.zonedata
      """

      ctx =
        Spf.check("foo@e4.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.5",
          dns: "test/zones/rfc7208-14-processing-limits.zonedata"
        )

      assert to_string(ctx.verdict) in ["permerror"]
      assert ctx.explanation == ""
    end

    @tag set: "14"
    @tag tst: "14.7"
    test "14.7 ptr-limit" do
      # spec 4.6.4/3 - Processing limits - ptr-limit
      _cli = """
      spfcheck foo@e5.example.com -i 1.2.3.5 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-14-processing-limits.zonedata
      """

      ctx =
        Spf.check("foo@e5.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.5",
          dns: "test/zones/rfc7208-14-processing-limits.zonedata"
        )

      assert to_string(ctx.verdict) in ["neutral", "pass"]
      assert ctx.explanation == ""
    end

    @tag set: "14"
    @tag tst: "14.8"
    test "14.8 redirect-loop" do
      # spec 4.6.4/1 - Processing limits - redirect-loop
      _cli = """
      spfcheck foo@e1.example.com -i 1.2.3.4 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-14-processing-limits.zonedata
      """

      ctx =
        Spf.check("foo@e1.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.4",
          dns: "test/zones/rfc7208-14-processing-limits.zonedata"
        )

      assert to_string(ctx.verdict) in ["permerror"]
      assert ctx.explanation == ""
    end

    @tag set: "14"
    @tag tst: "14.9"
    test "14.9 void-at-limit" do
      # spec 4.6.4/7 - Processing limits - void-at-limit
      _cli = """
      spfcheck foo@e12.example.com -i 1.2.3.4 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-14-processing-limits.zonedata
      """

      ctx =
        Spf.check("foo@e12.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.4",
          dns: "test/zones/rfc7208-14-processing-limits.zonedata"
        )

      assert to_string(ctx.verdict) in ["neutral"]
      assert ctx.explanation == ""
    end

    @tag set: "14"
    @tag tst: "14.10"
    test "14.10 void-over-limit" do
      # spec 4.6.4/7 - Processing limits - void-over-limit
      _cli = """
      spfcheck foo@e11.example.com -i 1.2.3.4 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-14-processing-limits.zonedata
      """

      ctx =
        Spf.check("foo@e11.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.4",
          dns: "test/zones/rfc7208-14-processing-limits.zonedata"
        )

      assert to_string(ctx.verdict) in ["permerror"]
      assert ctx.explanation == ""
    end
  end
end
