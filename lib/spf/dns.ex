defmodule Spf.DNS do
  @moduledoc """
  DNS helper functions
  """

  import Spf.Context

  @rrtypes %{
    "txt" => :txt,
    "a" => :a,
    "aaaa" => :aaaa,
    "ptr" => :ptr,
    "mx" => :mx,
    "cname" => :cname,
    "soa" => :soa,
    "spf" => :spf
  }
  # https://www.rfc-editor.org/rfc/rfc6895.html
  # https://erlang.org/doc/man/inet_res.html

  # TODO:
  ## DNS RESOLVE -> {:error, reason} | {:ok, []}
  # - inet_res.lookup -> list of rrdatas only:
  #   :inet_res.lookup('yahoo.com', :in, :a)  
  #   [
  #     {98, 137, 11, 163},
  #     {74, 6, 143, 26},
  #     {74, 6, 231, 20},
  #     {74, 6, 143, 25},
  #     {98, 137, 11, 164},
  #     {74, 6, 231, 21}
  #   ]
  #   in case of any type of error, you get a [] which could mean
  #   nxdomain, servfail or timeout etc ...  This also hides any
  ##  CNAME's that might be in play...  So we use :inet_res.resolve()
  #
  # :inet_res.resolve('mlzopendata.cbs.nl', :in, :mx) -> {:ok, :zero_answer}
  # {:ok,
  # {:dns_rec, {:dns_header, 20, true, :query, false, false, true, true, false, 0},
  #  [{:dns_query, 'mlzopendata.cbs.nl', :mx, :in}],
  #  [
  #    {:dns_rr, 'mlzopendata.cbs.nl', :cname, :in, 0, 2724, 'adc4.cbs.nl',
  #     :undefined, [], false}
  #  ], [], []}}
  #
  # :inet_res.resolve('380kv.nl', :in, :mx) -> {:error, :servfail}
  # {:error,
  # {:servfail,
  #  {:dns_rec,
  #   {:dns_header, 21, true, :query, false, false, true, true, false, 2},
  #   [{:dns_query, '380kv.nl', :mx, :in}], [], [], []}}}
  # - :inet_res.resolve('yahoo.com', :in, :a) 
  # {:ok,
  #   {:dns_rec,
  #     {:dns_header, 18, true, :query, false, false, true, true, false, 0},            # header
  #     [{:dns_query, 'yahoo.com', :a, :in}],                                           # qdlist
  #     [
  #       {:dns_rr, 'yahoo.com', :a, :in, 0, 330, {74, 6, 231, 20}, :undefined, [],
  #        false},
  #       {:dns_rr, 'yahoo.com', :a, :in, 0, 330, {98, 137, 11, 164}, :undefined, [],
  #        false},
  #       {:dns_rr, 'yahoo.com', :a, :in, 0, 330, {74, 6, 143, 25}, :undefined, [],
  #        false},
  #       {:dns_rr, 'yahoo.com', :a, :in, 0, 330, {98, 137, 11, 163}, :undefined, [],
  #        false},
  #       {:dns_rr, 'yahoo.com', :a, :in, 0, 330, {74, 6, 143, 26}, :undefined, [],
  #        false},
  #       {:dns_rr, 'yahoo.com', :a, :in, 0, 330, {74, 6, 231, 21}, :undefined, [],
  #        false}
  #     ],                                                                              # anlist
  #     [],                                                                             # nslist
  #     []                                                                              # arlist
  #    }
  #  }
  #  now we need to:
  #  - get RCODE from dns msg's header
  #    {:ok, msg} = :inet_resolve('domain', :in, :type)
  #    hdr = :inet_dns.header(msg) -> {:dns_header, 18, true, :query, false, false, true, true, false, 0}
  #    rcode = :inet_dns.msg(msg, :header) |> :inet_dns.header(:rcode)
  #  - RR's from dns msg's answer list
  #    :inet_dns.msg(msg, :anlist)                            
  #    [
  #      {:dns_rr, 'yahoo.com', :a, :in, 0, 1664, {74, 6, 143, 26}, :undefined, [], false},
  #      {:dns_rr, 'yahoo.com', :a, :in, 0, 1664, {74, 6, 143, 25}, :undefined, [], false},
  #      {:dns_rr, 'yahoo.com', :a, :in, 0, 1664, {98, 137, 11, 164}, :undefined, [], false},
  #      {:dns_rr, 'yahoo.com', :a, :in, 0, 1664, {74, 6, 231, 21}, :undefined, [], false},
  #      {:dns_rr, 'yahoo.com', :a, :in, 0, 1664, {98, 137, 11, 163}, :undefined, [], false},
  #      {:dns_rr, 'yahoo.com', :a, :in, 0, 1664, {74, 6, 231, 20}, :undefined, [], false}
  #    ]
  #  - convert for each rr in the list of rrs, eg
  #    :inet_dns.msg(msg, :anlist) |> hd() |> :inet_dns.rr(:domain) -> 'yahoo.com'
  #    :inet_dns.msg(msg, :anlist) |> hd() |> :inet_dns.rr(:type)  -> :a
  #    :inet_dns.msg(msg, :anlist) |> hd() |> :inet_dns.rr(:class)   -> :in
  #    :inet_dns.msg(msg, :anlist) |> hd() |> :inet_dns.rr(:ttl)  -> 1664
  #    :inet_dns.msg(msg, :anlist) |> hd() |> :inet_dns.rr(:data) -> {74, 6, 143, 26}
  #    where we charlists_tostr
  #    - domain and 
  #    - data (which might be an address tuple, 'domain name', {pref, 'domain name'} etc ...
  #  and put all that in an easy map:
  #  %{ rcode => int,
  #     ncode => String.t  (see https://www.iana.org/assignments/dns-parameters/dns-parameters.xhtml)
  #     domain => String.t
  #     ttl => integer
  #     expires => ttl + now()
  #     class => :class
  #     type => :type
  #     data => {int, String.t} | String.t | ...
  #   }
  # - Note that in order to fully be able to use the testcases from
  #
  ## DNS cache
  # {domain, type} -> [{:error, reason}] | [{:ok, :nodata}] | [rrdata, rrdata, ..]
  #
  # - Cache & Timeout
  #   if http://www.open-spf.org/svn/project/test-suite/ (the rfc7208 suite) is
  #   to be used to its fullest extend, the cache needs to be able to handle 
  ##   TTL's and timeout's of a DNS server.
  #   
  @doc """
  Normalize a domain name: lowercase and no trailing dot.

  The DNS cache should only see lowercase names. Domain spec's should be
  normalized after expansion.

  """
  @spec normalize(String.t() | list) :: String.t()
  def normalize(domain) when is_binary(domain) do
    domain
    |> String.trim()
    |> String.replace(~r/\.$/, "")
    |> String.downcase()
  end

  def normalize(domain) when is_list(domain),
    do: List.to_string(domain) |> normalize()

  @doc """
  Checks validity of a domain name, Returns {:ok, name} or {:error, reason}

  Checks the domain name:
  - is an ascii string
  - is less than 254 chars long
  - has labels less than 64 chars long, and
  - has at least 2 labels
  """
  @spec valid?(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def valid?(domain) do
    with {:ascii, true} <- {:ascii, validp?(domain, :ascii)},
         {:length, true} <- {:length, validp?(domain, :length)},
         {:labels, true} <- {:labels, validp?(domain, :labels)},
         {:multi, true} <- {:multi, validp?(domain, :multi)} do
      {:ok, domain}
    else
      {:ascii, false} -> {:error, "name contains non-ascii characters"}
      {:length, false} -> {:error, "name too long (> 254 chars long)"}
      {:labels, false} -> {:error, "name has either an empty label or label > 63 chars long"}
      {:multi, false} -> {:error, "name not multi-label"}
      {reason, _} -> {:error, "name error: #{inspect(reason)}"}
    end
  end

  defp validp?(domain, :length),
    do: String.length(domain) < 254

  defp validp?(domain, :labels),
    do: String.split(domain, ".") |> Enum.all?(fn label -> String.length(label) in 1..63 end)

  defp validp?(domain, :multi),
    do: length(String.split(domain, ".")) > 1

  defp validp?(domain, :ascii),
    do: domain == for(<<c <- domain>>, c in 0..127, into: "", do: <<c>>)

  @doc """
  Resolves a query and returns a {`ctx`, results}-tuple.

  Returns:
  - `{ctx, {:error, reason}}` if a DNS error occurred, or
  - `{ctx, {:ok, [rrs]}}` where rrs is a list of rrdata's

  Although, technically a result with ZERO answers is not a DNS error, it
  will be reported as `{:error, :zero_answers}`.

  """
  @spec resolve(map, binary, atom) :: {map, any}
  def resolve(ctx, name, type \\ :a) when is_map(ctx) do
    name = normalize(name)

    case valid?(name) do
      {:ok, name} -> do_resolve(ctx, name, type)
      {:error, reason} -> {log(ctx, :dns, :error, "#{reason}"), {:error, :illegal_name}}
    end
  end

  defp do_resolve(ctx, name, type) do
    case from_cache(ctx, name, type) do
      {:error, :cache_miss} ->
        query(ctx, name, type)

      result ->
        do_stats(ctx, name, type, result, cached: true)
    end
  end

  defp query(ctx, name, type) do
    # returns either {ctx, {:error, reason}} or {ctx, {:ok, [rrs]}}
    timeout = Map.get(ctx, :dns_timeout, 2000)

    ctx =
      name
      |> String.to_charlist()
      |> :inet_res.resolve(:in, type, [{:timeout, timeout}])
      |> rrentries()
      |> cache(ctx, name, type)
      |> tick(:num_dnsq)

    result = from_cache(ctx, name, type)
    do_stats(ctx, name, type, result)
  rescue
    x in CaseClauseError ->
      error = {:error, Exception.message(x)}

      ctx =
        update(ctx, {name, type, error})
        |> log(:dns, :error, "DNS error!: #{name} #{type}: #{inspect(error)}")

      {ctx, error}

    x in FunctionClauseError ->
      error = {:error, :illegal_name}

      ctx =
        update(ctx, {name, type, error})
        |> log(:dns, :error, "DNS ILLEGAL name: #{name} #{Exception.message(x)}")

      {ctx, error}
  end

  defp do_stats(ctx, name, type, result, opts \\ []) do
    # return ctx with updated stats and possibly updated result
    qry =
      case Keyword.get(opts, :cached, false) do
        true -> "DNS QUERY (#{ctx.num_dnsq}) [cache] #{type} #{name}"
        false -> "DNS QUERY (#{ctx.num_dnsq}) #{type} #{name}"
      end

    case result do
      {:error, :cache_miss} ->
        # result didn't include an answer for given `type`
        result = {:error, :zero_answers}

        {update(ctx, {name, type, result})
         |> tick(:num_dnsv)
         |> log(:dns, :warn, "#{qry} - ZERO answers"), result}

      {:error, :zero_answers} ->
        # result didn't include any answers
        {tick(ctx, :num_dnsv)
         |> log(:dns, :warn, "#{qry} - ZERO answers"), result}

      {:error, :nxdomain} ->
        {tick(ctx, :num_dnsv)
         |> log(:dns, :warn, "#{qry} - NXDOMAIN"), result}

      {:error, reason} ->
        # any other error, like :servfail
        err = String.upcase("#{inspect(reason)}")
        {log(ctx, :dns, :warn, "#{qry} - #{err}"), result}

      {:ok, res} ->
        {log(ctx, :dns, :info, "#{qry} - #{inspect(res)}"), result}
    end
  end

  defp rrentries(msg) do
    # given a dns_msg {:dns_rec, ...} or error-tuple
    # -> return either: {:ok, [{domain, type, value}, ...]} | {:error, reason}
    case msg do
      {:error, reason} -> {:error, reason}
      {:ok, record} -> {:ok, rrdata(record)}
    end
  end

  defp rrdata(record) do
    # turn dns record into list of simple rrdata entries: [{domain, type, data}]
    # see https://erlang.org/doc/man/inet_res.html#type-dns_data
    record
    |> :inet_dns.msg(:anlist)
    |> Enum.map(fn x -> rrentry(x) end)
  end

  defp rrentry(answer) do
    # {:dns_rr, :domain, :type, :in, _, _, :data, :undefined, [], false}
    # -> {domain, type, data}, where shape of data depends on type
    # .e.g :mx -> {10, name}, :a -> {1, 1, 1, 1}, etc ..
    domain = :inet_dns.rr(answer, :domain) |> charlists_tostr()
    type = :inet_dns.rr(answer, :type)
    data = :inet_dns.rr(answer, :data) |> charlists_tostr(type)
    {domain, type, data}
  end

  @doc """
  Returns a cache hit or miss for given `name` and `type` from cache `ctx.dns`.

  - `{:ok, []}` is a cache miss.
  - `{:error, reason}` is a cache hit for a previous negative result
  - `{:ok, rrs}` is a cache hit where `rrs` is a list of rrdata's.

  """
  @spec from_cache(map, binary, atom) :: {:error, atom} | {:ok, list}
  def from_cache(ctx, name, type) do
    # returns either {:error, reason} or {:ok, [rrs]}
    {ctx, name} = cname(ctx, name)
    cache = Map.get(ctx, :dns, %{})

    case cache[{name, type}] do
      nil -> {:error, :cache_miss}
      [{:error, reason}] -> {:error, reason}
      res -> {:ok, res}
    end
  end

  defp cname(ctx, name, seen \\ %{}) do
    # return canonical name if present, name otherwise, must follow CNAME's
    name = charlists_tostr(name) |> String.trim() |> String.trim(".")
    cache = Map.get(ctx, :dns, %{})

    if seen[name] do
      ctx =
        log(ctx, :dns, :error, "circular CNAMEs: #{inspect(seen)}")
        |> log(:dns, :info, "DNS CNAME: using #{name} to break circular reference")

      {ctx, name}
    else
      case cache[{name, :cname}] do
        nil -> {ctx, name}
        [realname] -> cname(ctx, realname, Map.put(seen, name, realname))
      end
    end
  end

  # cache an {:error, reason} or data entry for given `name` and `type`
  # note that `name` and `type` come from the {:dns_rr, ..}-record itself.
  defp cache({:error, {:servfail, _reason}} = _result, ctx, name, type),
    do: update(ctx, {name, type, {:error, :servfail}})

  defp cache({:error, _reason} = result, ctx, name, type),
    do: update(ctx, {name, type, result})

  defp cache({:ok, []}, ctx, name, type),
    do: update(ctx, {name, type, {:error, :zero_answers}})

  defp cache({:ok, entries}, ctx, _name, _type),
    do: Enum.reduce(entries, ctx, fn entry, acc -> update(acc, entry) end)

  defp update(ctx, {domain, type, data}) do
    # update ctx.dns with a (single) `data` for given `domain` and `type`
    # note: donot use from_cache since that unrolls cnames
    domain = charlists_tostr(domain) |> String.trim() |> String.trim_trailing(".")
    cache = Map.get(ctx, :dns, %{})
    cached = cache[{domain, type}] || []
    data = charlists_tostr(data, type)

    case data in cached do
      true -> ctx
      false -> Map.put(ctx, :dns, Map.put(cache, {domain, type}, [data | cached]))
    end
  end

  # charlists_tostr -> turn any charlists *inside* rrdata into a string.
  # note:
  # - empty list should turn into {:error, :zero_answers}, and NOT ""
  # - {:error, _} should stay an error-tuple
  defp charlists_tostr([]),
    do: {:error, :zero_answers}

  defp charlists_tostr(rrdata) when is_list(rrdata) do
    # turn a single (non-empty) charlist or list of charlists into single string
    # this glues the strings together without spaces.
    IO.iodata_to_binary(rrdata)
  end

  defp charlists_tostr(rrdata) do
    # catch all, keep it as it is
    rrdata
  end

  # no charlist in error situations
  defp charlists_tostr({:error, reason}, _),
    do: {:error, reason}

  # mta name to string
  defp charlists_tostr({pref, domain}, :mx),
    do: {pref, charlists_tostr(domain)}

  # txt value to string
  defp charlists_tostr(txt, :txt) do
    charlists_tostr(txt)
  end

  # domain name of ptr record to string
  defp charlists_tostr(domain, :ptr),
    do: charlists_tostr(domain)

  # address tuple to string (or keep {:error,_}-tuple)
  defp charlists_tostr(ip, :a) do
    "#{Pfx.new(ip)}"
  rescue
    _ -> ip
  end

  # address tuple to string (or keep {:error,_}-tuple)
  defp charlists_tostr(ip, :aaaa) do
    "#{Pfx.new(ip)}"
  rescue
    _ -> ip
  end

  # primary nameserver and admin contact to string
  defp charlists_tostr({mname, rname, serial, refresh, retry, expiry, min_ttl}, :soa),
    do: {charlists_tostr(mname), charlists_tostr(rname), serial, refresh, retry, expiry, min_ttl}

  defp charlists_tostr(data, _) when is_list(data),
    do: charlists_tostr(data)

  defp charlists_tostr(data, _),
    do: data

  @doc """
  Return all acquired DNS RR's in a flat list of printable lines.

  Note that RR's with multiple entries in their rrdata are listed individually,
  so the output can be copy/paste'd into a local dns.txt pre-cache to facilitate
  experimentation with RR records.

  """
  def to_list(ctx, opts \\ []) do
    valid = Keyword.get(opts, :valid, true)
    cache = Map.get(ctx, :dns, %{})

    cache
    |> Enum.map(fn {{domain, type}, data} -> rr_flatten(domain, type, data) end)
    |> List.flatten()
    |> rrs_sort()
    |> Enum.filter(fn {_domain, _type, data} -> valid != rr_is_error(data) end)
    |> Enum.map(fn {domain, type, data} -> rr_tostr(domain, type, data) end)
  end

  defp rr_flatten(domain, type, data) do
    for rrdata <- data do
      {domain, type, rrdata}
    end
  end

  defp rrs_sort(rrs) do
    # keeps related records close to each other in report output
    Enum.sort(rrs, fn {domain1, _type, _data}, {domain2, _type1, _data2} ->
      String.reverse(domain1) <= String.reverse(domain2)
    end)
  end

  defp rr_is_error(data) do
    case data do
      {:error, _} -> true
      _ -> false
    end
  end

  defp rr_tostr(domain, type, data) do
    domain = String.pad_trailing(domain, 25)
    rrtype = String.upcase("#{type}") |> String.pad_trailing(7)
    data = rr_data_tostr(type, data)
    Enum.join([domain, rrtype, data], " ")
  end

  @spec rr_data_tostr(atom, any) :: String.t()
  defp rr_data_tostr(_, {:error, _} = error),
    do: "#{inspect(error)}"

  defp rr_data_tostr(type, ip) when type in [:a, :aaaa] and is_tuple(ip) do
    "#{Pfx.new(ip)}"
  rescue
    # since dns errors are cached as well:
    _ -> ip
  end

  defp rr_data_tostr(:mx, {pref, domain}) do
    "#{pref} #{domain}"
  end

  defp rr_data_tostr(:txt, txt) do
    inspect(txt)
  end

  defp rr_data_tostr(_type, data) do
    "#{inspect(data)}" |> no_quotes()
  end

  @doc """
  Keep only the rrdata from `rrdatas` where `fun` returns truthy.

  ## Example

      iex> DNS.resolve("www.example.com", :txt)
      ...> |> DNS.grep(fn x -> String.lower(x) |> String.contains?("v=spf1") end)
      ["v=spf1 -all"]

  """
  def grep({:ok, rrdatas}, fun),
    do: grep(rrdatas, fun)

  def grep({:error, reason}, _fun),
    do: {:error, reason}

  def grep(rrdatas, fun) when is_function(fun, 1),
    do: {:ok, Enum.filter(rrdatas, fn rrdata -> fun.(rrdata) end)}

  def load_file(ctx, nil), do: ctx

  def load_file(ctx, fpath) when is_binary(fpath) do
    ctx =
      File.stream!(fpath)
      |> Enum.map(fn x -> String.trim(x) end)
      |> Enum.reduce(ctx, &read_rr/2)

    ctx
    |> log(:dns, :debug, "cached #{map_size(ctx.dns)} entries from #{fpath}")
  rescue
    err -> log(ctx, :dns, :error, "failed to read #{fpath}: #{Exception.message(err)}")
  end

  defp read_rr("#" <> _, ctx),
    # this is why str must be trimmed already
    do: ctx

  defp read_rr("", ctx),
    do: ctx

  defp read_rr(str, ctx) do
    case String.split(str, ~r/ +/, parts: 3) do
      [domain, type, data] ->
        type = rr_type(type)
        update(ctx, {domain, type, mimic_dns(type, data)})

      _ ->
        # ignore malformed, TODO: log this as error/warning
        ctx
    end
  end

  defp rr_type(type),
    do: @rrtypes[String.downcase(type)] || String.upcase(type)

  defp no_quotes(str) do
    str
    |> String.replace(~r/^\"/, "")
    |> String.replace(~r/\"$/, "")
  end

  # TODO: mimic_dns
  # - check validity of supplied data (e.g. IP addresses)
  # - support error entries, e.g. like <domain> <type> :nxdomain
  #   -> this would also mean <domain> <other_type> should be :error :nxdomain (!)
  #   -> same goes for :servfail and maybe others ...
  #   -> but not for e.g. :error :zero_answers or :timeout (!)
  defp mimic_dns(:mx, value) do
    {pref, name} =
      value
      |> no_quotes()
      |> String.split(~r/\s+/, parts: 2)
      |> List.to_tuple()

    pref =
      case Integer.parse(pref) do
        {n, ""} -> n
        _ -> pref
      end

    {pref, charlists_tostr(name)}
  end

  defp mimic_dns(_, value) do
    no_quotes(value)
  end
end
