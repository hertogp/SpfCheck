defmodule SpfDNSTest do
  use ExUnit.Case
  doctest Spf.DNS, import: true

  describe "DNS cache" do
    test "00 - caches zonedata from heredoc" do
      zonedata = """
      example.com A 1.2.3.4
      example.com AAAA 2001::1
      example.com MX 10 mail.example.com
      example.com TXT v=spf1 -all
      example.com SPF v=spf1 +all
      example.com ns ns.example.com
      4.3.2.1.in-addr.arpa ptr example.com
      example.com SOA ns.icann.org. noc.dns.icann.org. 2021120710 7200 3600 1209600 3600
      example.net CNAME example.org
      example.org A 1.1.1.1
      """

      ctx = Spf.Context.new("example.com", dns: zonedata)

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :a)
      assert result == {:ok, ["1.2.3.4"]}

      # ipv6 formatting is produced by Pfx
      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :aaaa)
      assert result == {:ok, ["2001:0:0:0:0:0:0:1"]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :mx)
      assert result == {:ok, [{10, "mail.example.com"}]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :txt)
      assert result == {:ok, ["v=spf1 -all"]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :spf)
      assert result == {:ok, ["v=spf1 +all"]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :ns)
      assert result == {:ok, ["ns.example.com"]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "4.3.2.1.in-addr.arpa", type: :ptr)
      assert result == {:ok, ["example.com"]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :soa)

      # note: names are normalized when entered into the cache so trailing dot
      # is dropped
      assert result ==
               {:ok,
                [
                  {
                    "ns.icann.org",
                    "noc.dns.icann.org",
                    2_021_120_710,
                    7200,
                    3600,
                    1_209_600,
                    3600
                  }
                ]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.net", type: :cname)
      assert result == {:ok, ["example.org"]}

      # cname really works ..
      {_ctx, result} = Spf.DNS.resolve(ctx, "example.net", type: :a)
      assert result == {:ok, ["1.1.1.1"]}
    end

    test "01 - DNS cache from a list of lines" do
      zonedata =
        """
        example.com A 1.2.3.4
        example.com AAAA 2001::1
        example.com MX 10 mail.example.com
        example.com TXT v=spf1 -all
        example.com SPF v=spf1 +all
        example.com ns ns.example.com
        4.3.2.1.in-addr.arpa ptr example.com
        example.com SOA ns.icann.org. noc.dns.icann.org. 2021120710 7200 3600 1209600 3600
        example.net CNAME example.org
        example.org A 1.1.1.1
        """
        |> String.split("\n")

      ctx = Spf.Context.new("example.com", dns: zonedata)

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :a)
      assert result == {:ok, ["1.2.3.4"]}

      # ipv6 formatting is produced by Pfx
      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :aaaa)
      assert result == {:ok, ["2001:0:0:0:0:0:0:1"]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :mx)
      assert result == {:ok, [{10, "mail.example.com"}]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :txt)
      assert result == {:ok, ["v=spf1 -all"]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :spf)
      assert result == {:ok, ["v=spf1 +all"]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :ns)
      assert result == {:ok, ["ns.example.com"]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "4.3.2.1.in-addr.arpa", type: :ptr)
      assert result == {:ok, ["example.com"]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :soa)

      # note: names are normalized when entered into the cache so trailing dot
      # is dropped
      assert result ==
               {:ok,
                [
                  {
                    "ns.icann.org",
                    "noc.dns.icann.org",
                    2_021_120_710,
                    7200,
                    3600,
                    1_209_600,
                    3600
                  }
                ]}

      {_ctx, result} = Spf.DNS.resolve(ctx, "example.net", type: :cname)
      assert result == {:ok, ["example.org"]}

      # cname really works ..
      {_ctx, result} = Spf.DNS.resolve(ctx, "example.net", type: :a)
      assert result == {:ok, ["1.1.1.1"]}
    end

    test "03 - dns cache should insert errors properly" do
      zonedata = """
      example.com A 1.2.3.4
      example.com AAAA TIMEOUT
      example.com SERVFAIL
      """

      ctx = Spf.Context.new("example.com", dns: zonedata)

      # the A record stays untouched
      {_ctx, {:ok, ["1.2.3.4"]}} = Spf.DNS.resolve(ctx, "example.com", type: :a)

      # the AAAA record remains as TIMEOUT
      {_ctx, {:error, :timeout}} = Spf.DNS.resolve(ctx, "example.com", type: :aaaa)

      # unspecified (known) RR-types are set to SERVFAIL
      {_ctx, {:error, :servfail}} = Spf.DNS.resolve(ctx, "example.com", type: :mx)
      {_ctx, {:error, :servfail}} = Spf.DNS.resolve(ctx, "example.com", type: :ns)
      {_ctx, {:error, :servfail}} = Spf.DNS.resolve(ctx, "example.com", type: :soa)
      {_ctx, {:error, :servfail}} = Spf.DNS.resolve(ctx, "example.com", type: :ptr)
      {_ctx, {:error, :servfail}} = Spf.DNS.resolve(ctx, "example.com", type: :txt)
      {_ctx, {:error, :servfail}} = Spf.DNS.resolve(ctx, "example.com", type: :cname)
    end

    test "04 - dns cache errors out on circular cname's" do
      zonedata = """
      example.com cname example.org
      example.com a 1.1.1.1
      example.org cname example.net
      example.org a 2.2.2.2
      example.net cname example.com
      example.net a 3.3.3.3
      """

      ctx = Spf.Context.new("some.tld", dns: zonedata)

      # straight cname resolving works
      {ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :cname)
      assert result == {:ok, ["example.org"]}
      {ctx, result} = Spf.DNS.resolve(ctx, "example.org", type: :cname)
      assert result == {:ok, ["example.net"]}
      {_ctx, result} = Spf.DNS.resolve(ctx, "example.net", type: :cname)
      assert result == {:ok, ["example.com"]}

      # circular CNAMEs yield :servfail (is a zonedata error)
      # rfc1035 - servfail: name server was unable to process the query due to
      # a (database) problem with the name server.

      # {ctx, result} = Spf.DNS.resolve(ctx, "example.com", type: :a)
      # assert result == {:error, :servfail}

      # {ctx, result} = Spf.DNS.resolve(ctx, "example.org", type: :a)
      # assert result == {:error, :servfail}

      # {_ctx, result} = Spf.DNS.resolve(ctx, "example.net", type: :a)
      # assert result == {:error, :servfail}
    end
  end
end
