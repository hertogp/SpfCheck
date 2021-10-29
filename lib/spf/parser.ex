defmodule Spf.Parser do
  @moduledoc """
  Functions to parse an SPF string or explain string for a given SPF context.

  This module provides two functions:
  - [`explain`](`Spf.Parser.explain/2`) parses an explain, expands it and returns an explanation-string.
  - [`parse`](`Spf.Parser.parse/1`) parses an SPF record in an AST

  """
  import NimbleParsec
  import Spf.Context
  alias Spf.DNS
  alias Spf.Eval

  # LEXERs

  defparsecp(:tokenize_spf, Spf.Tokens.tokenize_spf())
  defparsecp(:tokenize_exp, Spf.Tokens.tokenize_exp())

  # HELPERS

  defp ast(ctx, {_type, _tokval, _range} = token) do
    # add a token to the AST if possible, otherwise put in an :error
    case token do
      {:all, _tokval, _range} ->
        Map.update(ctx, :ast, [token], fn tokens -> tokens ++ [token] end)

      {:redirect, _tokval, _range} ->
        Map.update(ctx, :ast, [token], fn tokens -> tokens ++ [token] end)

      {:exp, _tokval, range} ->
        term = spf_term(ctx, range)

        if length(ctx.stack) > 0 do
          log(ctx, :parse, :info, "#{term} - ignored (included explain)")
        else
          if ctx.explain do
            error(ctx, :repeated_modifier, "repeated modifier #{term}", :permerror)
          else
            Map.put(ctx, :explain, token)
          end
        end

      token ->
        Map.update(ctx, :ast, [token], fn tokens -> tokens ++ [token] end)
    end
  end

  defp cidr([]),
    do: [32, 128]

  defp cidr({:dual_cidr, [len4, len6], _range}) do
    if len4 in 0..32 and len6 in 0..128,
      do: [len4, len6],
      else: :einvalid
  end

  defp drop_labels(domain) do
    # drop leftmost labels if name exceeds 253 characters
    case String.split_at(domain, -253) do
      {"", name} -> name
      {_, name} -> String.replace(name, ~r/^[^.]*./, "")
    end
  end

  defp expand(ctx, []),
    do: ctx.domain

  defp expand(_ctx, {:domspec, [:einvalid], _range}),
    do: :einvalid

  defp expand(ctx, {toktype, tokens, _range}) when toktype in [:domspec, :exp_str] do
    for {token, args, _range} <- tokens do
      expand(ctx, token, args)
    end
    |> Enum.join()
    |> drop_labels()
  end

  defp expand(ctx, :expand, [ltr, keep, reverse, delimiters]) do
    macro(ctx, ltr)
    |> String.split(delimiters)
    |> (fn x -> if reverse, do: Enum.reverse(x), else: x end).()
    |> (fn x -> if keep in 1..length(x), do: Enum.slice(x, -keep, keep), else: x end).()
    |> Enum.join(".")
  end

  defp expand(_ctx, :expand, ["%"]),
    do: "%"

  defp expand(_ctx, :expand, ["-"]),
    do: "%20"

  defp expand(_ctx, :expand, ["_"]),
    do: " "

  defp expand(_ctx, token_type, [str])
       when token_type in [:literal, :toplabel, :whitespace, :unknown],
       do: str

  defp macro(ctx, letter) when ?A <= letter and letter <= ?Z,
    do: macro(ctx, letter + 32) |> URI.encode_www_form()

  defp macro(ctx, letter) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-7.3
    case letter do
      ?d -> ctx.domain
      ?h -> ctx.helo
      ?s -> ctx.sender
      ?l -> split(ctx.sender) |> elem(0)
      ?o -> split(ctx.sender) |> elem(1)
      ?v -> if ctx.atype == :a, do: "in-addr", else: "ip6"
      ?r -> "unknown"
      ?c -> macro_c(ctx.ip)
      ?i -> macro_i(ctx.ip)
      ?p -> macro_p(ctx)
    end
  end

  defp macro_c(ip) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-7.3
    # - use inet.ntoa to get shorthand ip6 (appease v-macro-ip6 test)
    addr = Pfx.new(ip) |> Pfx.marshall({1, 2, 3, 4, 5, 6, 7, 8})

    :inet.ntoa(addr)
    |> List.to_string()
  end

  defp macro_i(ip) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-7.3
    # - upcase reversed ip address (appease v-macro-ip6 test)
    pfx = Pfx.new(ip)

    case pfx.maxlen do
      32 -> "#{pfx}"
      _ -> Pfx.format(pfx, width: 4, base: 16) |> String.upcase()
    end
  end

  defp macro_p(ctx) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-7.3
    # "p" macro expands to the validated domain name of <ip>
    # - perform a DNS reverse-mapping for <ip>
    # - for name returned lookup its IP addresses
    # - if <ip> is among the IP addresses, then that domain name is validated
    # - if the <domain> is present as a validated domain, it SHOULD be used
    # - otherwise, if a subdomain of the <domain> is present, it SHOULD be used
    # - otherwise, *any* name from the list can be used
    # - if there are no validated domain names use "unknown"
    # - if a DNS error occurs, the string "unknown" is used.
    {ctx, dns} = DNS.resolve(ctx, Pfx.dns_ptr(ctx.ip), type: :ptr, stats: false)

    domain = DNS.normalize(ctx.domain)

    pvalue =
      case dns do
        {:error, _reason} ->
          {:ok, "unknown"}

        {:ok, rrs} ->
          Enum.take(rrs, 10)
          |> Enum.map(fn name -> DNS.normalize(name) end)
          |> Enum.map(fn name ->
            {name, DNS.resolve(ctx, name, type: ctx.atype, stats: false) |> elem(1)}
          end)
          |> Enum.filter(fn {name, dns} -> Eval.validate?(dns, ctx.ip, name, domain, false) end)
          |> Enum.map(fn {name, _dns} -> {String.bag_distance(name, domain), name} end)
          |> Enum.sort(fn {x0, s0}, {x1, s1} -> x0 > x1 || s0 < s1 end)
          |> List.first()
      end

    case pvalue do
      nil -> "unknown"
      {_, str} -> str
    end
  end

  @spec pfxparse(binary, atom) :: {:ok, Pfx.t()} | {:error, binary}
  defp pfxparse(pfx, :ip4) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-5.6
    leadzero = String.match?(pfx, ~r/(^|[\.\/])0[0-9]/)
    fournums = String.match?(pfx, ~r/^\d+\.\d+\.\d+\.\d+/)

    if fournums and not leadzero,
      do: {:ok, Pfx.new(pfx)},
      else: {:error, pfx}
  rescue
    _ -> {:error, pfx}
  end

  defp pfxparse(pfx, :ip6) do
    {:ok, Pfx.new(pfx)}
  rescue
    _ -> {:error, pfx}
  end

  defp taketok(args, toktype) do
    case List.keytake(args, toktype, 0) do
      nil -> {[], args}
      {token, args} -> {token, args}
    end
  end

  # API

  @doc """
  Parses an `explain`-string, expands it for given `context` and returns the
  explanation-string.

  """
  @spec explain(map, binary()) :: binary()
  def explain(ctx, explain) do
    case tokenize_exp(explain) do
      {:error, _, _, _, _, _} ->
        ""

      {:ok, [{:exp_str, _tokens, _range} = exp_str], _, _, _, _} ->
        expand(ctx, exp_str)
    end
  end

  @doc """
  Given a context, return it after parsing its `ctx.spf` and populating its `ctx.ast`.

  Returns the context with its `ctx.ast` populated based on the `ctx.spf_tokens`
  found by the tokenizer.

  Any syntax error seen will cause the `ctx.error` to be set, as well as `ctx.reason`.
  Since the entire SPF string is parsed, `ctx.reason` will point to the last syntax
  error seen and the SPF evaluation will result in a permanent error.

  Otherwise, the `ctx.ast` can be evaluated to arrive at a result.

  """
  @spec parse(map) :: map
  def parse(context)

  def parse(%{error: error} = ctx) when error != nil,
    do: ctx

  def parse(%{spf: spf} = ctx) do
    {:ok, tokens, rest, _, _, _} = tokenize_spf(spf)

    Map.put(ctx, :spf_tokens, tokens)
    |> Map.put(:spf_rest, rest)
    |> Map.put(:ast, [])
    |> check(:spf_length)
    |> check(:spf_residue)
    |> then(fn ctx -> Enum.reduce(tokens, ctx, &parse/2) end)
    |> check(:explain_reachable)
    |> check(:no_implicit)
    |> check(:max_redirect)
    |> check(:all_no_redirect)
    |> check(:all_last)
  end

  # PARSER

  defp parse({atom, [qual, args], range}, ctx) when atom in [:a, :mx] do
    # A, MX
    {spec, _} = taketok(args, :domspec)
    {dual, _} = taketok(args, :dual_cidr)

    domain = expand(ctx, spec)
    cidr = cidr(dual)
    term = spf_term(ctx, range)

    if domain == :einvalid or cidr == :einvalid do
      error(ctx, :syntax_error, "invalid term #{term}", :permerror)
    else
      ast(ctx, {atom, [qual, domain, cidr], range})
      |> tick(:num_dnsm)
      |> log(:parse, :debug, "DNS MECH (#{ctx.num_dnsm}): #{term}")
      |> test(:parse, :debug, not String.contains?(term, domain), "MACRO expansion - #{domain}")
    end
  end

  defp parse({:all, [qual], range}, ctx),
    # All
    do: ast(ctx, {:all, [qual], range})

  defp parse({atom, [qual, domspec], range}, ctx) when atom in [:include, :exists] do
    # Exists, Include
    term = spf_term(ctx, range)

    case(expand(ctx, domspec)) do
      :einvalid ->
        error(ctx, :syntax_error, "syntax error #{term}", :permerror)

      domain ->
        ast(ctx, {atom, [qual, domain], range})
        |> tick(:num_dnsm)
        |> log(:parse, :debug, "DNS MECH (#{ctx.num_dnsm}): #{term}")
        |> test(:parse, :debug, not String.contains?(term, domain), "MACRO expansion - #{domain}")
    end
  end

  defp parse({:exp, [domspec], range}, ctx) do
    # Exp
    term = spf_term(ctx, range)

    case expand(ctx, domspec) do
      :einvalid ->
        error(ctx, :syntax_error, "syntax error for #{term}", :permerror)

      domain ->
        ast(ctx, {:exp, [domain], range})
        |> test(:parse, :debug, not String.contains?(term, domain), "MACRO expansion - #{domain}")
    end
  end

  defp parse({atom, [qual, ip], range}, ctx) when atom in [:ip4, :ip6] do
    # IP4, IP6
    case pfxparse(ip, atom) do
      {:ok, pfx} ->
        ast(ctx, {atom, [qual, pfx], range})

      {:error, _} ->
        error(ctx, :syntax_error, "syntax error for #{spf_term(ctx, range)}", :permerror)
    end
  end

  defp parse({:ptr, [qual, args], range}, ctx) do
    # Ptr
    {spec, _} = taketok(args, :domspec)
    term = spf_term(ctx, range)

    case expand(ctx, spec) do
      :einvalid ->
        error(ctx, :syntax_error, "syntax error #{term}", :permerror)

      domain ->
        ast(ctx, {:ptr, [qual, domain], range})
        |> tick(:num_dnsm)
        |> log(:parse, :debug, "DNS MECH (#{ctx.num_dnsm}): #{term}")
        |> log(:parse, :warn, "#{term} ** usage is not recommended")
        |> test(:parse, :debug, not String.contains?(term, domain), "MACRO expansion - #{domain}")
    end
  end

  defp parse({:redirect, [domspec], range}, ctx) do
    # Redirect
    term = spf_term(ctx, range)

    case expand(ctx, domspec) do
      :einvalid ->
        error(ctx, :syntax_error, "syntax error for #{term}", :permerror)

      domain ->
        ast(ctx, {:redirect, [domain], range})
        |> tick(:num_dnsm)
        |> log(:parse, :debug, "DNS MECH (#{ctx.num_dnsm}): #{term}")
        |> test(:parse, :debug, not String.contains?(term, domain), "MACRO expansion - #{domain}")
    end
  end

  defp parse({:version, [n], range} = _token, ctx) do
    # Version
    case n do
      1 ->
        ctx

      _ ->
        error(ctx, :syntax_error, "Unknown SPF version #{spf_term(ctx, range)}", :permerror)
    end
  end

  defp parse({:whitespace, [wspace], range}, ctx) do
    # Whitespace
    ctx =
      if String.length(wspace) > 1,
        do: log(ctx, :parse, :warn, "repeated whitespace: #{inspect(range)}"),
        else: ctx

    if String.contains?(wspace, "\t"),
      do: log(ctx, :parse, :warn, "tab as whitespace: #{inspect(range)}"),
      else: ctx
  end

  defp parse({:unknown, _tokvalue, range} = _token, ctx) do
    # Unknown
    error(ctx, :syntax_error, "syntax error for '#{spf_term(ctx, range)}'", :permerror)
  end

  defp parse({:unknown_mod, _tokvalue, range} = _token, ctx) do
    # Unknown_mod
    log(ctx, :parse, :warn, "ignored unknown modifier '#{spf_term(ctx, range)}'")
  end

  defp parse(token, ctx),
    # CatchAll
    do: log(ctx, :parse, :error, "Spf.parser.check: no handler available for #{inspect(token)}")

  # CHECKS

  defp check(ctx, :spf_length) do
    case String.length(ctx.spf) do
      len when len > 512 -> log(ctx, :parse, :warn, "SPF string length #{len} > 512 characters")
      _ -> ctx
    end
  end

  defp check(ctx, :spf_residue) do
    case String.length(ctx.spf_rest) do
      len when len > 0 -> log(ctx, :parse, :warn, "SPF string residue #{inspect(ctx.spf_rest)}")
      _ -> ctx
    end
  end

  defp check(ctx, :explain_reachable) do
    # if none of the terms have a fail qualifier, an explain is superfluous
    if ctx.explain != nil do
      mechs =
        Enum.filter(ctx.ast, fn {type, _tokval, _range} -> type != :redirect end)
        |> Enum.map(fn {_type, tokval, _range} -> tokval end)
        |> Enum.filter(fn l -> List.first(l, ?+) == ?- end)

      case mechs do
        [] -> log(ctx, :parse, :warn, "SPF record cannot fail, so explain is never used")
        _ -> ctx
      end
    else
      ctx
    end
  end

  defp check(ctx, :no_implicit) do
    # warn if there's no redirect and no all present
    explicit = Enum.filter(ctx.ast, fn {type, _tokval, _range} -> type in [:all, :redirect] end)

    case explicit do
      [] -> log(ctx, :parse, :warn, "SPF record has implicit end (?all)")
      _ -> ctx
    end
  end

  defp check(ctx, :max_redirect) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-5
    # redirect modifier is allowed only once
    redirs = Enum.filter(ctx.ast, fn {type, _tokal, _range} -> type == :redirect end)

    if length(redirs) > 1 do
      [_, {_, _, range} | _] = redirs

      error(
        ctx,
        :repeated_modifier,
        "#{spf_term(ctx, range)} - redirect is allowed only once",
        :permerror
      )
    else
      ctx
    end
  end

  defp check(ctx, :all_no_redirect) do
    # warn on ignoring a superfluous `redirect`
    all = Enum.filter(ctx.ast, fn {type, _tokval, _range} -> type == :all end)

    if length(all) > 0 do
      case List.keytake(ctx[:ast], :redirect, 0) do
        nil ->
          ctx

        {redir, ast} ->
          log(ctx, :parse, :warn, "redirect #{inspect(redir)} ignored: `all` is present")
          |> Map.put(:ast, ast)
      end
    else
      ctx
    end
  end

  defp check(ctx, :all_last) do
    # warns on terms being ignored
    # - exp is actually part of the context and does not appear in the ast
    # - redirect is (already) removed from ast if all is present
    rest = Enum.drop_while(ctx.ast, fn {t, _, _} -> t != :all end)

    case rest do
      [{_, _, r0} | tail] when tail != [] ->
        Enum.reduce(tail, ctx, fn {_, _, r1}, ctx ->
          log(ctx, :parse, :warn, "term after #{spf_term(ctx, r0)} ignored: #{spf_term(ctx, r1)}")
        end)

      _ ->
        ctx
    end
  end
end
