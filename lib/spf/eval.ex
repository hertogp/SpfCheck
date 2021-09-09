defmodule Spf.Eval do
  @moduledoc """
  Functions to evaluate an SPF context
  """

  alias Spf.DNS
  import Spf.Context

  # Helpers

  defp evalmx(ctx, domain, dual, value) do
    {ctx, dns} = DNS.resolve(ctx, domain, :mx)

    case dns do
      {:error, reason} ->
        log(ctx, :warn, "DNS error for #{domain}: #{inspect(reason)}")

      {:ok, rrs} ->
        Enum.map(rrs, fn {_, name} -> List.to_string(name) end)
        |> Enum.reduce(ctx, fn name, acc -> evalname(acc, name, dual, value) end)
    end
  end

  defp evalname(ctx, domain, dual, value) do
    {ctx, dns} = DNS.resolve(ctx, domain, ctx.atype)

    case dns do
      {:error, reason} -> log(ctx, :warn, "DNS error for #{domain}: #{inspect(reason)}")
      {:ok, rrs} -> addip(ctx, rrs, dual, value)
    end
  end

  defp explain(ctx) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-6.2
    if ctx.verdict == :fail and ctx.explain do
      {_token, [domain], _range} = ctx.explain
      {ctx, dns} = DNS.resolve(ctx, domain, :txt)

      case dns do
        {:error, reason} ->
          log(ctx, :warn, ctx.explain, "DNS error #{reason}")

        {:ok, []} ->
          log(ctx, :warn, ctx.explain, "DNS void lookup (0 answers)")

        {:ok, list} when length(list) > 1 ->
          log(ctx, :error, ctx.explain, "too many explain txt records")

        {:ok, [explain]} ->
          log(ctx, :info, ctx.explain, "'#{explain}'")
          |> Map.put(:explanation, explainp(ctx, explain))
      end
    else
      ctx
    end
  end

  defp explainp(ctx, explain) do
    IO.inspect(explain, label: :explainp_explain)

    case Spf.exp_tokens(explain) do
      {:error, _, _, _, _, _} -> ""
      {:ok, [{:exp_str, tokens, _range}], _, _, _, _} -> expand(ctx, tokens)
    end
  end

  defp expand(ctx, {:domain_spec, _, _} = spec),
    do: Spf.Parser.domain(ctx, spec)

  defp expand(_ctx, {:whitespace, [str], _}),
    do: str

  defp expand(_ctx, {:unknown, [str], _}),
    do: str

  defp expand(ctx, tokens) when is_list(tokens) do
    for token <- tokens do
      expand(ctx, token)
    end
    |> Enum.join()
  end

  defp match(ctx, term, tail) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-4.6.2
    # see if ctx's current state is a match (i.e. <ip> is a match now)
    # TODO:
    # - add prechecks, such as ctx.num_dnsq <= ctx.max_dnsq etc..
    # - store matching term in ctx as :matched_term {term, ctx.nth}
    {_pfx, qlist} = Iptrie.lookup(ctx.ipt, ctx.ip) || {nil, nil}

    if qlist do
      log(ctx, :note, term, "matches #{ctx.ip}")
      |> tick(:num_checks)
      |> Map.put(:verdict, verdict(qlist, ctx.nth))
      |> Map.put(:match, {term, ctx.nth})
    else
      log(ctx, :info, term, "no match")
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
  defp validated(ctx, {:ptr, [_, domain], _} = term, {:error, reason}),
    do: log(ctx, :error, term, "DNS error for #{domain}: #{inspect(reason)}")

  defp validated(ctx, term, {:ok, rrs}),
    do: Enum.reduce(rrs, ctx, fn name, acc -> validate(name, acc, term) end)

  defp validate(name, ctx, {:ptr, [q, domain], _} = term) do
    {ctx, dns} = DNS.resolve(ctx, name, ctx.atype)

    case validate?(dns, ctx.ip, name, domain) do
      true ->
        addip(ctx, [ctx.ip], [32, 128], {q, ctx.nth, term})
        |> log(:info, term, "validated: #{name}, #{ctx.ip} for #{domain}")

      false ->
        log(ctx, :info, term, "not validated: #{name}, #{ctx.ip} for #{domain}")
    end
  end

  # validate name has an ip == <ip> and is (sub)domain of domain
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

    verdict(qualifier)
  end

  # API

  def eval(ctx) do
    log(ctx, :note, "SPF, got: #{inspect(ctx.spf)}")
    |> evalp(ctx.ast)
    |> explain()
    |> Map.put(:duration, (DateTime.utc_now() |> DateTime.to_unix()) - ctx.macro[?t])
  end

  # A
  # TODO: check if we've seen {domain, dual} before
  defp evalp(ctx, [{:a, [q, domain, dual], _range} = term | tail]) do
    evalname(ctx, domain, dual, {q, ctx.nth, term})
    |> match(term, tail)
  end

  # EXISTS
  # https://www.rfc-editor.org/rfc/rfc7208.html#section-5.7
  defp evalp(ctx, [{:exists, [q, domain], _range} = term | tail]) do
    if ctx.map[domain] do
      log(ctx, :error, term, "domain seen before")
    else
      {ctx, dns} = DNS.resolve(ctx, domain, :a)

      ctx =
        case dns do
          {:error, reason} ->
            log(ctx, :info, term, "DNS error #{reason}")

          {:ok, rrs} ->
            log(ctx, :info, term, "DNS #{inspect(rrs)}")
            |> addip(ctx.ip, [32, 128], {q, ctx.nth, term})
        end

      match(ctx, term, tail)
    end
  end

  # All
  defp evalp(ctx, [{:all, [q], _range} = term | tail]) do
    if ctx.f_include do
      evalp(ctx, tail)
    else
      log(ctx, :info, term, "SPF match by #{List.to_string([q])}all")
      |> tick(:num_checks)
      |> addip(ctx.ip, [32, 128], {q, ctx.nth, term})
      # |> Map.put(:verdict, verdict(q))
      |> match(term, tail)
    end
  end

  # MX
  # TODO: check if we've seen {domain, dual} before
  defp evalp(ctx, [{:mx, [q, domain, dual], _range} = term | tail]) do
    evalmx(ctx, domain, dual, {q, ctx.nth, term})
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
    {ctx, dns} = DNS.resolve(ctx, Pfx.dns_ptr(ctx.ip), :ptr)

    validated(ctx, term, dns)
    |> match(term, tail)
  end

  # INCLUDE
  defp evalp(ctx, [{:include, [q, domain], _range} = term | tail]) do
    if ctx.map[domain] do
      log(ctx, :error, term, "ignored: seen before")
    else
      ctx =
        log(ctx, :note, term, "recurse")
        |> push(domain)
        |> Spf.grep()
        |> Spf.parse()
        |> eval()

      case ctx.verdict do
        v when v in [:neutral, :fail, :softfail] ->
          pop(ctx)
          |> log(:info, term, "no match")
          |> evalp(tail)

        :pass ->
          Map.put(ctx, :verdict, verdict(q))
          |> pop()
          |> log(:info, term, "match")

        v when v in [:none, :permerror] ->
          Map.put(ctx, :verdict, :permerror)
          |> pop()
          |> log(:error, term, :permerror)

        :temperror ->
          ctx
      end
    end
  end

  # REDIRECT
  defp evalp(ctx, [{:redirect, [domain], _range} = term | tail]) do
    if ctx.map[domain] do
      log(ctx, :error, term, "domain seen before")
    else
      nth = ctx.cnt

      test(ctx, :error, term, length(tail) > 0, "terms after redirect?")
      |> log(:note, term, "redirect")
      |> tick(:cnt)
      |> Map.put(:map, Map.merge(ctx.map, %{nth => domain, domain => nth}))
      |> Map.put(:domain, domain)
      |> Map.put(:f_include, false)
      |> Map.put(:f_redirect, false)
      |> Map.put(:f_all, false)
      |> Map.put(:nth, nth)
      |> Map.put(:macro, macros(domain, ctx.ip, ctx.sender))
      |> Map.put(:ast, [])
      |> Map.put(:spf, "")
      |> Spf.grep()
      |> Spf.parse()
      |> eval()
    end
  end

  # TERM?
  defp evalp(ctx, [term | tail]) do
    log(ctx, :error, term, "eval is missing a handler")
    |> evalp(tail)
  end

  # NO AST due to no SPF
  defp evalp(ctx, []),
    do: ctx
end
