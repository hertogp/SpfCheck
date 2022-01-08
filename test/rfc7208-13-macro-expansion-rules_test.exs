defmodule Rfc7208.Section13Test do
  use ExUnit.Case

  # Generated by mix rfc7208.testsuite
  # Usage:
  # % mix test
  # % mix test --only set:13
  # % mix test --only tst:13.y where y is in [0..23]

  describe "rfc7208-13-macro-expansion-rules" do
    @tag set: "13"
    @tag tst: "13.0"
    test "13.0 domain-name-truncation" do
      # spec 7.1/25 - Macro expansion rules - domain-name-truncation
      _cli = """
      spfcheck test@somewhat.long.exp.example.com -i 192.168.218.40 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@somewhat.long.exp.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]
      assert ctx.explanation == "Congratulations!  That was tricky."
    end

    @tag set: "13"
    @tag tst: "13.1"
    test "13.1 exp-only-macro-char" do
      # spec 7.1/8 - Macro expansion rules - exp-only-macro-char
      _cli = """
      spfcheck test@e2.example.com -i 192.168.218.40 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e2.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["permerror"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.2"
    test "13.2 exp-txt-macro-char" do
      # spec 7.1/20 - Macro expansion rules - exp-txt-macro-char
      _cli = """
      spfcheck test@e3.example.com -i 192.168.218.40 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e3.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]
      assert ctx.explanation == "Connections from 192.168.218.40 not authorized."
    end

    @tag set: "13"
    @tag tst: "13.3"
    test "13.3 hello-domain-literal" do
      # spec 7.1/2 - Macro expansion rules - hello-domain-literal
      _cli = """
      spfcheck test@e9.example.com -i 192.168.218.40 -h [192.168.218.40] -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e9.example.com",
          helo: "[192.168.218.40]",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.4"
    test "13.4 hello-macro" do
      # spec 7.1/6 - Macro expansion rules - hello-macro
      _cli = """
      spfcheck test@e9.example.com -i 192.168.218.40 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e9.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["pass"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.5"
    test "13.5 invalid-embedded-macro-char" do
      # spec 7.1/9 - Macro expansion rules - invalid-embedded-macro-char
      _cli = """
      spfcheck test@e1e.example.com -i 192.168.218.40 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e1e.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["permerror"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.6"
    test "13.6 invalid-hello-macro" do
      # spec 7.1/2 - Macro expansion rules - invalid-hello-macro
      _cli = """
      spfcheck test@e9.example.com -i 192.168.218.40 -h JUMPIN' JUPITER -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e9.example.com",
          helo: "JUMPIN' JUPITER",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.7"
    test "13.7 invalid-macro-char" do
      # spec 7.1/9 - Macro expansion rules - invalid-macro-char
      _cli = """
      spfcheck test@e1.example.com -i 192.168.218.40 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e1.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["permerror"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.8"
    test "13.8 invalid-trailing-macro-char" do
      # spec 7.1/9 - Macro expansion rules - invalid-trailing-macro-char
      _cli = """
      spfcheck test@e1t.example.com -i 192.168.218.40 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e1t.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["permerror"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.9"
    test "13.9 macro-mania-in-domain" do
      # spec 7.1/3, 7.1/4 - Macro expansion rules - macro-mania-in-domain
      _cli = """
      spfcheck test@e1a.example.com -i 1.2.3.4 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e1a.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.4",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["pass"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.10"
    test "13.10 macro-multiple-delimiters" do
      # spec 7.1/15, 7.1/16 - Macro expansion rules - macro-multiple-delimiters
      _cli = """
      spfcheck foo-bar+zip+quux@e12.example.com -i 1.2.3.4 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("foo-bar+zip+quux@e12.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.4",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["pass"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.11"
    test "13.11 macro-reverse-split-on-dash" do
      # spec 7.1/15, 7.1/16, 7.1/17, 7.1/18 - Macro expansion rules - macro-reverse-split-on-dash
      _cli = """
      spfcheck philip-gladstone-test@e11.example.com -i 1.2.3.4 -h mail.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("philip-gladstone-test@e11.example.com",
          helo: "mail.example.com",
          ip: "1.2.3.4",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["pass"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.12"
    test "13.12 p-macro-ip4-novalid" do
      # spec 7.1/22 - Macro expansion rules - p-macro-ip4-novalid
      _cli = """
      spfcheck test@e6.example.com -i 192.168.218.40 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e6.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]
      assert ctx.explanation == "connect from unknown"
    end

    @tag set: "13"
    @tag tst: "13.13"
    test "13.13 p-macro-ip4-valid" do
      # spec 7.1/22 - Macro expansion rules - p-macro-ip4-valid
      _cli = """
      spfcheck test@e6.example.com -i 192.168.218.41 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e6.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.41",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]
      assert ctx.explanation == "connect from mx.example.com"
    end

    @tag set: "13"
    @tag tst: "13.14"
    test "13.14 p-macro-ip6-novalid" do
      # spec 7.1/22 - Macro expansion rules - p-macro-ip6-novalid
      _cli = """
      spfcheck test@e6.example.com -i CAFE:BABE::1 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e6.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "CAFE:BABE::1",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]
      assert ctx.explanation == "connect from unknown"
    end

    @tag set: "13"
    @tag tst: "13.15"
    test "13.15 p-macro-ip6-valid" do
      # spec 7.1/22 - Macro expansion rules - p-macro-ip6-valid
      _cli = """
      spfcheck test@e6.example.com -i CAFE:BABE::3 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e6.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "CAFE:BABE::3",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]
      assert ctx.explanation == "connect from mx.example.com"
    end

    @tag set: "13"
    @tag tst: "13.16"
    test "13.16 p-macro-multiple" do
      # spec 7.1/22 - Macro expansion rules - p-macro-multiple
      _cli = """
      spfcheck test@e7.example.com -i 192.168.218.42 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e7.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.42",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["pass", "softfail"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.17"
    test "13.17 require-valid-helo" do
      # spec 7.1/6 - Macro expansion rules - require-valid-helo
      _cli = """
      spfcheck test@e10.example.com -i 1.2.3.4 -h OEMCOMPUTER -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e10.example.com",
          helo: "OEMCOMPUTER",
          ip: "1.2.3.4",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.18"
    test "13.18 trailing-dot-domain" do
      # spec 7.1/16 - Macro expansion rules - trailing-dot-domain
      _cli = """
      spfcheck test@example.com -i 192.168.218.40 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["pass"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.19"
    test "13.19 trailing-dot-exp" do
      # spec 7.1 - Macro expansion rules - trailing-dot-exp
      _cli = """
      spfcheck test@exp.example.com -i 192.168.218.40 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@exp.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]
      assert ctx.explanation == "This is a test."
    end

    @tag set: "13"
    @tag tst: "13.20"
    test "13.20 undef-macro" do
      # spec 7.1/6 - Macro expansion rules - undef-macro
      _cli = """
      spfcheck test@e5.example.com -i CAFE:BABE::192.168.218.40 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e5.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "CAFE:BABE::192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["permerror"]
      assert ctx.explanation == ""
    end

    @tag set: "13"
    @tag tst: "13.21"
    test "13.21 upper-macro" do
      # spec 7.1/26 - Macro expansion rules - upper-macro
      _cli = """
      spfcheck ~jack&jill=up-a_b3.c@e8.example.com -i 192.168.218.42 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("~jack&jill=up-a_b3.c@e8.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.42",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]
      assert ctx.explanation == "http://example.com/why.html?l=~jack%26jill%3Dup-a_b3.c"
    end

    @tag set: "13"
    @tag tst: "13.22"
    test "13.22 v-macro-ip4" do
      # spec 7.1/6 - Macro expansion rules - v-macro-ip4
      _cli = """
      spfcheck test@e4.example.com -i 192.168.218.40 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e4.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "192.168.218.40",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]
      assert ctx.explanation == "192.168.218.40 is queried as 40.218.168.192.in-addr.arpa"
    end

    @tag set: "13"
    @tag tst: "13.23"
    test "13.23 v-macro-ip6" do
      # spec 7.1/6 - Macro expansion rules - v-macro-ip6
      _cli = """
      spfcheck test@e4.example.com -i CAFE:BABE::1 -h msgbas2x.cos.example.com -v 5 \
       -d test/zones/rfc7208-13-macro-expansion-rules.zonedata
      """

      ctx =
        Spf.check("test@e4.example.com",
          helo: "msgbas2x.cos.example.com",
          ip: "CAFE:BABE::1",
          dns: "test/zones/rfc7208-13-macro-expansion-rules.zonedata"
        )

      assert to_string(ctx.verdict) in ["fail"]

      assert ctx.explanation ==
               "cafe:babe::1 is queried as 1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.E.B.A.B.E.F.A.C.ip6.arpa"
    end
  end
end
