defmodule Spf.Eval do
  @moduledoc """
  Functions to evaluate an SPF context
  """

  alias Spf.DNS
  import Spf.Context

  # Helpers

  defp evalname(ctx, domain, dual, value) do
    {ctx, dns} = DNS.resolve(ctx, domain, type: ctx.atype)

    case dns do
      {:error, reason} ->
        log(ctx, :eval, :warn, "#{ctx.atype} #{domain} - DNS error #{inspect(reason)}")

      {:ok, []} ->
        log(ctx, :eval, :warn, "#{ctx.atype} #{domain} - ZERO answers")

      {:ok, rrs} ->
        addip(ctx, rrs, dual, value)
    end
  end

  defp explain(ctx) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-6.2
    if ctx.verdict == :fail and ctx.explain do
      {_token, [domain], _range} = ctx.explain
      {ctx, dns} = DNS.resolve(ctx, domain, type: :txt, stats: false)
      ctx = tick(ctx, :num_dnsq, -1)

      case dns do
        {:error, reason} ->
          log(ctx, :dns, :warn, "txt #{domain} - DNS error #{reason}")

        {:ok, []} ->
          log(ctx, :dns, :warn, "txt #{domain} - DNS void lookup (0 answers)")

        {:ok, list} when length(list) > 1 ->
          log(ctx, :dns, :error, "txt #{domain} - too many explain txt records #{inspect(list)}")

        {:ok, [explain]} ->
          log(ctx, :dns, :info, "txt #{domain} -> '#{explain}'")
          |> Map.put(:explanation, explainp(ctx, explain))
      end
    else
      ctx
    end
  end

  defp explainp(ctx, explain) do
    case Spf.exp_tokens(explain) do
      {:error, _, _, _, _, _} ->
        ""

      {:ok, [{:exp_str, _tokens, _range} = exp_str], _, _, _, _} ->
        Spf.Parser.expand(ctx, exp_str)
    end
  end

  defp check_limits(ctx) do
    # only check for original SPF record, so we donot prematurely stop
    # processing
    if ctx.nth == 0 do
      ctx =
        if ctx.num_dnsm > ctx.max_dnsm do
          Map.put(ctx, :error, :too_many_dnsm)
          |> Map.put(:reason, "too many DNS mechanisms used #{ctx.num_dnsm}")
          |> Map.put(:verdict, :permerror)
          |> then(fn ctx -> log(ctx, :eval, :error, ctx.reason) end)
        else
          ctx
        end

      # NB: there is no overall limit on actual DNS lookups, just on:
      # - DNS mechanisms: max 10 of a, mx, ptr, include, redirect or exists
      # - DNS lookup per mx record (max again 10, else permerror)
      # - DNS lookup per ptr mech (max again 10, else ignore 11+ names)

      if ctx.num_dnsv > ctx.max_dnsv do
        Map.put(ctx, :error, :too_many_dnsv)
        |> Map.put(:reason, "too many VOID DNS queries seen #{ctx.num_dnsv}")
        |> Map.put(:verdict, :permerror)
        |> then(fn ctx -> log(ctx, :eval, :error, ctx.reason) end)
      else
        ctx
      end
    else
      ctx
    end
  end

  defp match(%{error: error} = ctx, _term, _tail) when error != nil,
    do: eval(ctx)

  defp match(ctx, {_m, _token, range} = _term, tail) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-4.6.2
    # see if ctx's current state is a match (i.e. <ip> is a match now)
    # TODO:
    # - add prechecks, such as ctx.num_dnsv <= ctx.max_dnsv etc..
    # - store matching term in ctx as :matched_term {term, ctx.nth}
    {_pfx, qlist} = Iptrie.lookup(ctx.ipt, ctx.ip) || {nil, nil}

    if qlist do
      log(ctx, :eval, :note, "#{String.slice(ctx.spf, range)} - matches #{ctx.ip}")
      |> tick(:num_checks)
      |> Map.put(:verdict, verdict(qlist, ctx.nth))
      |> Map.put(:reason, "spf[#{ctx.nth}] #{String.slice(ctx.spf, range)}")
    else
      log(ctx, :eval, :info, "#{String.slice(ctx.spf, range)} - no match")
      |> tick(:num_checks)
      |> evalp(tail)
    end
  end

  # https://www.rfc-editor.org/rfc/rfc7208.html#section-5.5
  # ptr - mechanism
  # 1. resolve PTR RR for <ip> -> names
  # 2. resolve names -> their ip's
  # 3. keep names that have <ip> among their ip's
  # 4. add <ip> if such a (validated) name is (sub)domain of <domain>
  defp validated(ctx, {:ptr, [_, domain], _} = _term, {:error, reason}),
    do: log(ctx, :eval, :warn, "DNS error for #{domain}: #{inspect(reason)}")

  defp validated(ctx, term, {:ok, rrs}) do
    # limit to the first 10 rrs, ignore the rest
    Enum.take(rrs, 10)
    |> Enum.reduce(ctx, fn name, acc -> validate(name, acc, term) end)
  end

  defp validate(name, ctx, {:ptr, [q, domain], _} = term) do
    {ctx, dns} = DNS.resolve(ctx, name, type: ctx.atype)

    case validate?(dns, ctx.ip, name, domain) do
      true ->
        addip(ctx, [ctx.ip], [32, 128], {q, ctx.nth, term})
        |> log(:eval, :info, "validated: #{name}, #{ctx.ip} for #{domain}")

      false ->
        log(ctx, :eval, :info, "not validated: #{name}, #{ctx.ip} for #{domain}")
    end
  end

  # a name is validated iff it's ip == <ip> && name endswith? domain
  defp validate?({:error, _}, _ip, _name, _domain),
    do: false

  defp validate?({:ok, rrs}, ip, name, domain) do
    pfx = Pfx.new(ip)

    if Enum.any?(rrs, fn ip -> Pfx.member?(ip, pfx) end) do
      String.downcase(name)
      |> String.ends_with?(String.downcase(domain))
    else
      false
    end
  end

  def set_p_macro(ctx) do
    # ctx.macro[?p] = shortest validated name possible, or "unknown"
    # TODO: refactor this abomination!
    {ctx, dns} = DNS.resolve(ctx, Pfx.dns_ptr(ctx.ip), type: :ptr, stats: false)

    domain = Spf.DNS.normalize(ctx.domain)

    pvalue =
      case dns do
        {:error, _reason} ->
          "unknown"

        {:ok, rrs} ->
          Enum.take(rrs, 10)
          |> Enum.map(fn name -> Spf.DNS.normalize(name) end)
          |> Enum.filter(fn name -> String.ends_with?(name, domain) end)
          |> Enum.map(fn name ->
            {name, Spf.DNS.resolve(ctx, name, type: ctx.atype, stats: false) |> elem(1)}
          end)
          |> Enum.filter(fn {name, dns} -> validate?(dns, ctx.ip, name, domain) end)
          |> Enum.map(fn {name, _dns} -> name end)
          |> Enum.sort(&(byte_size(&1) <= byte_size(&2)))
          |> List.first()
      end

    pvalue =
      case pvalue do
        nil -> "unknown"
        str -> str
      end

    put_in(ctx, [:macro, ?p], pvalue)
  end

  defp verdict(qualifier) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-4.6.2
    case qualifier do
      ?+ -> :pass
      ?- -> :fail
      ?~ -> :softfail
      ?? -> :neutral
      _ -> :qualifier_error
    end
  end

  defp verdict(qlist, nth) do
    {{qualifier, _nth, _term}, _} = List.keytake(qlist, nth, 1) || {{:error, nth, nil}, qlist}

    case verdict(qualifier) do
      :qualifier_error -> :qerror
      q -> q
    end
  end

  defp check_domain(ctx) do
    # check validity of domain
    if ctx.error do
      ctx
    else
      case Spf.DNS.valid?(ctx.domain) do
        {:ok, _domain} ->
          ctx

        {:error, reason} ->
          log(ctx, :name, :error, "domain error: #{reason}")
          |> Map.put(:error, :illegal_name)
          |> Map.put(:reason, reason)
      end
    end
  end

  defp check_spf(ctx) do
    # either set :error, or set :spf to single spf string

    if ctx.error do
      ctx
    else
      case ctx.spf do
        [] ->
          Map.put(ctx, :error, :no_spf)
          |> Map.put(:reason, "no SPF record found")
          |> then(fn ctx -> log(ctx, :check, :note, "no SPF record found") end)

        [spf] ->
          if Spf.is_ascii?(spf) do
            Map.put(ctx, :spf, spf)
          else
            Map.put(ctx, :error, :non_ascii_spf)
            |> Map.put(:reason, "SPF contains non-ascii characters")
            |> then(fn ctx -> log(ctx, :error, :check, ctx.reason) end)
          end

        list ->
          Map.put(ctx, :error, :many_spf)
          |> Map.put(:reason, "too many SPF records found (#{length(list)})")
          |> then(fn ctx -> log(ctx, :check, :error, ctx.reason) end)
      end
    end
  end

  # API

  def evaluate(ctx) do
    ctx
    |> check_domain()
    |> Spf.grep()
    |> check_spf()
    |> Spf.Parser.parse()
    |> eval()
  end

  defp eval(%{error: error} = ctx) when error != nil do
    # TODO: potential for looping here, rename this eval func to
    # verdict/bail or something ...
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-4.3
    # - malformed domain -> none
    # - result is nxdomain -> none
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-4.4
    # - timeout -> temperror
    # - servfail (or any RCODE not in [0, 3]) -> temperror
    # - nxdomain -> none
    case error do
      :no_spf -> Map.put(ctx, :verdict, :none)
      :many_spf -> Map.put(ctx, :verdict, :permerror)
      :no_redir_domain -> Map.put(ctx, :verdict, :permerror)
      :no_redir_spf -> Map.put(ctx, :verdict, :permerror)
      :illegal_name -> Map.put(ctx, :verdict, :none)
      :zero_answers -> Map.put(ctx, :verdict, :none)
      :nxdomain -> Map.put(ctx, :verdict, :none)
      :timeout -> Map.put(ctx, :verdict, :temperror)
      :servfail -> Map.put(ctx, :verdict, :temperror)
      :non_ascii_spf -> Map.put(ctx, :verdict, :permerror)
      :syntax_error -> Map.put(ctx, :verdict, :permerror)
      :too_many_dnsv -> Map.put(ctx, :verdict, :permerror)
      :too_many_dnsm -> Map.put(ctx, :verdict, :permerror)
      :include_loop -> Map.put(ctx, :verdict, :permerror)
      :redirect_loop -> Map.put(ctx, :verdict, :permerror)
      :repeated_modifier -> Map.put(ctx, :verdict, :permerror)
    end
  end

  defp eval(ctx) do
    evalp(ctx, ctx.ast)
    |> explain()
    |> Map.put(:duration, (DateTime.utc_now() |> DateTime.to_unix()) - ctx.macro[?t])
    |> check_limits()
  end

  # HELPERS

  # NOMORE TERMs
  defp evalp(ctx, []),
    do: ctx

  # A
  # TODO:
  # - check if we've seen {domain, dual} before
  # - permerror is domain is invalid
  defp evalp(ctx, [{:a, [q, domain, dual], _range} = term | tail]) do
    evalname(ctx, domain, dual, {q, ctx.nth, term})
    |> match(term, tail)
  end

  # EXISTS
  # https://www.rfc-editor.org/rfc/rfc7208.html#section-5.7
  defp evalp(ctx, [{:exists, [q, domain], _range} = term | tail]) do
    # TODO: 
    # - domain should be normalized when checking
    # - skipping evaluation is probably not correct!
    if ctx.map[domain] do
      log(ctx, :eval, :warn, "domain '#{domain}' seen before")
    else
      {ctx, dns} = DNS.resolve(ctx, domain, type: :a)

      ctx =
        case dns do
          {:error, :timeout} ->
            Map.put(ctx, :error, :timeout)
            |> Map.put(:reason, "DNS error #{domain} TIMEOUT")
            |> then(fn ctx -> log(ctx, :eval, :warn, ctx.reason) end)

          {:error, reason} ->
            log(ctx, :eval, :warn, "DNS error #{domain} #{reason}")

          {:ok, []} ->
            log(ctx, :dns, :warn, "A #{domain} - ZERO answers")

          {:ok, rrs} ->
            log(ctx, :eval, :info, "DNS #{inspect(rrs)}")
            |> addip(ctx.ip, [32, 128], {q, ctx.nth, term})
        end

      match(ctx, term, tail)
    end
  end

  # All
  defp evalp(ctx, [{:all, [q], _range} = term | tail]) do
    log(ctx, :eval, :info, "SPF match by #{List.to_string([q])}all")
    |> tick(:num_checks)
    |> addip(ctx.ip, [32, 128], {q, ctx.nth, term})
    |> match(term, tail)
  end

  # MX
  defp evalp(ctx, [{:mx, [q, domain, dual], _range} = term | tail]) do
    # TODO: check if we've seen {domain, dual} before
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-5.4
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-4.6.4
    # - lookup MX <target-name> -> list of MTA names
    # - lookup A/AAAA for MTA names (max 10 A/AAAA lookups -> otherwise permerror)
    # - <ip> matches an MTA's ip -> match, otherwise no match
    {ctx, dns} = DNS.resolve(ctx, domain, type: :mx)

    case dns do
      {:error, :timeout} ->
        Map.put(ctx, :error, :timeout)
        |> Map.put(:reason, "DNS error #{domain} TIMEOUT")
        |> then(fn ctx -> log(ctx, :eval, :warn, ctx.reason) end)

      {:error, reason} ->
        log(ctx, :eval, :warn, "mx #{domain} - DNS error #{inspect(reason)}")

      {:ok, []} ->
        log(ctx, :eval, :warn, "mx #{domain} - ZERO answers")

      {:ok, rrs} ->
        # TODO: change logic so we impose a max of 10 A/AAAA lookups and error
        # out if we need to do more that 10 ...
        Enum.map(rrs, fn {_pref, name} -> name end)
        |> Enum.reduce(ctx, fn name, acc -> evalname(acc, name, dual, {q, ctx.nth, term}) end)
        |> log(:dns, :debug, "MX #{domain} #{inspect({q, ctx.nth, term})} added")
    end
    |> match(term, tail)
  end

  # IP4/6
  defp evalp(ctx, [{ip, [q, pfx], _range} = term | tail]) when ip in [:ip4, :ip6] do
    addip(ctx, [pfx], [32, 128], {q, ctx.nth, term})
    |> match(term, tail)
  end

  # PTR
  # TODO: check is we've seen domain before
  defp evalp(ctx, [{:ptr, [_q, _domain], _range} = term | tail]) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-5.5
    # - see also Errata, 
    # - limit to the first 10 names ...
    {ctx, dns} = DNS.resolve(ctx, Pfx.dns_ptr(ctx.ip), type: :ptr)

    validated(ctx, term, dns)
    |> match(term, tail)
  end

  # INCLUDE
  defp evalp(ctx, [{:include, [q, domain], range} = _term | tail]) do
    if ctx.map[domain] do
      Map.put(ctx, :error, :include_loop)
      |> Map.put(:reason, "included #{domain} seen before in spf #{ctx.map[domain]}")
      |> then(fn ctx -> log(ctx, :eval, :warn, ctx.reason) end)
      |> eval()
    else
      ctx =
        log(ctx, :eval, :note, "#{String.slice(ctx.spf, range)} - recurse")
        |> push(domain)
        |> evaluate()

      case ctx.verdict do
        v when v in [:neutral, :fail, :softfail] ->
          ctx = pop(ctx)

          log(ctx, :eval, :info, "#{String.slice(ctx.spf, range)} - no match")
          |> evalp(tail)

        :pass ->
          ctx = pop(ctx)

          ctx
          |> Map.put(:verdict, verdict(q))
          |> log(:eval, :info, "#{String.slice(ctx.spf, range)} - match")
          |> Map.put(:reason, "spf[#{ctx.nth}] #{String.slice(ctx.spf, range)} - matched")

        v when v in [:none, :permerror] ->
          ctx = pop(ctx)

          ctx
          |> Map.put(:verdict, :permerror)
          |> log(:eval, :error, "#{String.slice(ctx.spf, range)} - permanent error")
          |> Map.put(:reason, "#{String.slice(ctx.spf, range)} - permerror")

        :temperror ->
          ctx = pop(ctx)

          ctx
          |> log(:eval, :warn, "#{String.slice(ctx.spf, range)} - temp error")
      end
    end
  end

  # REDIRECT
  defp evalp(ctx, [{:redirect, [:einvalid], range} | _tail]) do
    Map.put(ctx, :error, :no_redir_domain)
    |> Map.put(:reason, "invalid domain in #{String.slice(ctx.spf, range)}")
    |> then(fn ctx -> log(ctx, :eval, :error, ctx.reason) end)
    |> eval()
  end

  defp evalp(ctx, [{:redirect, [domain], _range} = term | tail]) do
    # spec 6.1
    # - if redirect domain has no SPF -> permerror
    # - if redirect domain is mailformed -> permerror
    # - otherwise its result is the result for this SPF
    if ctx.map[domain] do
      Map.put(ctx, :error, :redirect_loop)
      |> Map.put(:reason, "redirect #{domain} seen before in spf #{ctx.map[domain]}")
      |> then(fn ctx -> log(ctx, :eval, :warn, ctx.reason) end)
      |> eval()
    else
      nth = ctx.num_spf

      ctx =
        test(ctx, :error, term, length(tail) > 0, "terms after redirect?")
        |> log(:eval, :note, "redirecting to #{domain}")
        |> tick(:num_spf)
        |> Map.put(:map, Map.merge(ctx.map, %{nth => domain, domain => nth}))
        |> Map.put(:domain, domain)
        |> Map.put(:f_include, ctx.f_include)
        |> Map.put(:f_redirect, false)
        |> Map.put(:f_all, false)
        |> Map.put(:nth, nth)
        |> Map.put(:macro, macros(domain, ctx.ip, ctx.sender, ctx.helo))
        |> Map.put(:ast, [])
        |> Map.put(:spf, "")
        |> Map.put(:explain, nil)
        |> evaluate()

      if ctx.error in [:no_spf, :nxdomain] do
        Map.put(ctx, :error, :no_redir_spf)
        |> Map.put(:reason, "no SPF found for #{domain}")
        |> then(fn ctx -> log(ctx, :eval, :error, ctx.reason) end)
        |> eval()
      else
        ctx
      end
    end
  end

  # TERM?
  defp evalp(ctx, [term | tail]) do
    log(ctx, :eval, :error, "internal error, eval is missing a handler for #{inspect(term)}")
    |> evalp(tail)
  end
end
