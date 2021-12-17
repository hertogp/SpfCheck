defmodule Spf.Parser do
  @moduledoc """
  Functions to parse an SPF string or explain string for a given SPF [`context`](`t:Spf.Context.t/0`).

  The parser also performs expansion during the semantic checks, so both
  functions take an SPF [`context`](`t:Spf.Context.t/0`) as their only argument.

  """
  import Spf.Context
  import Spf.Lexer
  alias Spf.DNS
  alias Spf.Eval

  @type token :: Spf.Lexer.token()

  @null_slice 1..0//-1
  @reserved_names ["all", "a", "mx", "ptr", "ip4", "ip6", "include", "exists", "exp", "redirect"]

  # API

  @doc """
  Parse [`context`](`t:Spf.Context.t/0`)'s explain string and store the result under
  the `:explanation` key.

  In case of any syntax errors, sets the explanation string to an empty string.
  """
  @spec explain(Spf.Context.t()) :: Spf.Context.t()
  def explain(%{explain_string: explain} = context) do
    case tokenize_exp(explain) do
      {:error, _, _, _} ->
        Map.put(context, :explanation, "")

      {:ok, [{:exp_str, tokens, _range}], _, _} ->
        # TODO: log errors as encountered by expand
        Map.put(context, :explanation, expand(context, tokens, :explain))
    end
  end

  @doc """
  Parse [`context`](`t:Spf.Context.t/0`)'s SPF string and store the result under the
  `:ast` key.

  The parser will parse the entire record so as to find as many problems as
  possible.

  The parser will log notifications for:
  - ignoring an include'd explain modifier
  - for each DNS mechanism encountered (at :debug level)

  The parser will log warnings for:
  - an SPF string length longer than 512 characters
  - any residue text in the SPF string after parsing
  - when an exp modifier is present, but the SPF record cannot fail
  - SPF records with implicit endings
  - ignoring a redirect modifier because the all mechanism is present
  - each ignored term occurring after an all mechanism
  - the use of the ptr mechanism (which is not recommended)
  - the use of the p-macro (also not recommended)
  - repeated whitespace to separate terms
  - use of tab character(s) to sepearate terms
  - ignoring an unknown modifier
  - a redirect modifer, when no all is present, that is not the last term

  The parser will log an error for:
  - repeated modifier terms
  - syntax errors in domain specifications
  - syntax errors in dual-cidr notations
  - invalid IP addresses
  - unknown terms that are not unknown modifiers

  The logging simply adds messages to the `context.msg` list but, when logging
  an error, the `context.error` and `context.reason` are also set.

  Since the parser does not stop at the first error, the `context.error` and
  `context.reason` show the details of the last error seen.  If given `context`
  also has a function reference stored in `context.log`, it is called with
  4 arguments:
  - [`context`](`t:Spf.Context.t/0`)
  - `facility`, an atom denoting which part sent the message
  - `severity`, an atom like :info, :warn, :error, :debug
  - `msg`, the message string

  In the absence of an error, `context.ast` is fit for evaluation.

  """
  @spec parse(Spf.Context.t()) :: Spf.Context.t()
  def parse(context)

  def parse(%{error: error} = ctx) when error != nil,
    do: ctx

  def parse(%{spf: spf} = ctx) do
    {:ok, tokens, rest, _} = tokenize_spf(spf)

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
    |> check(:redirect_last)
    |> check(:all_last)
    |> then(&Map.update(&1, :map, %{}, fn m -> Map.put(m, &1.domain, spf) end))
  end

  # HELPERS

  @spec ast(Spf.Context.t(), token) :: Spf.Context.t()
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
          log(ctx, :parse, :info, "#{term} - ignoring included explain")
        else
          if ctx.explain do
            error(ctx, :parse, :repeated_modifier, "#{term} - repeated modifier", :permerror)
          else
            Map.put(ctx, :explain, token)
          end
        end

      token ->
        Map.update(ctx, :ast, [token], fn tokens -> tokens ++ [token] end)
    end
  end

  @spec cidr(Spf.Context.t(), [] | token) :: {atom, list} | {:error, :einvalid}
  defp cidr(_ctx, []),
    do: {:ok, [32, 128]}

  defp cidr(ctx, {:cidr, [len4, len6], range}) do
    term = spf_term(ctx, range)

    if len4 in 0..32 and len6 in 0..128 do
      cond do
        len4 == 0 -> {:wzero_mask, [len4, len6]}
        len4 == 32 and String.match?(term, ~r/^\/32/) -> {:wmax_mask, [len4, len6]}
        len6 == 0 -> {:wzero_mask, [len4, len6]}
        len6 == 128 and String.match?(term, ~r/128$/) -> {:wmax_mask, [len4, len6]}
        # TODO: add leading zero check here -> {:error, :epfxlen}
        String.match?(term, ~r/\/0\d/) -> {:error, :invalid}
        true -> {:ok, [len4, len6]}
      end
    else
      {:error, :einvalid}
    end
  end

  @spec drop_labels(binary) :: binary
  defp drop_labels(domain) do
    # drop leftmost labels if name exceeds 253 characters
    # - assumes name is a dotted domain name
    case String.split_at(domain, -253) do
      {"", name} -> name
      {_, name} -> String.replace(name, ~r/^[^.]*./, "")
    end
  end

  defp check_toplabel([]), do: []

  defp check_toplabel(tokens) do
    with {:literal, [label], range} <- List.last(tokens) do
      domain = String.replace(label, ~r/\.$/, "")
      labels = String.split(domain, ".")
      label = List.last(labels)
      emptylabel = String.length(label) == 0
      noldhlabel = String.replace(label, ~r/[[:alnum:]]|-/, "") != ""
      allnumeric = String.replace(label, ~r/\d+/, "") == ""
      hyphenated = String.starts_with?(label, "-") or String.ends_with?(label, "-")
      singlelabel = length(labels) == 1

      cond do
        noldhlabel -> [{:error, :noldhlabel, @null_slice}]
        emptylabel -> [{:error, :emptylabel, @null_slice}]
        allnumeric -> [{:error, :allnumeric, @null_slice}]
        hyphenated -> [{:error, :hyphenated, @null_slice}]
        emptylabel -> [{:error, :emptylabel, @null_slice}]
        singlelabel -> [{:error, :singlelabel, @null_slice}]
        true -> List.replace_at(tokens, -1, {:literal, [domain], range})
      end
    else
      _ -> tokens
    end
  end

  # expand a list of (:literal, :expand, :error) into:
  # - string (either a domain-name or an explanation string), or
  # - :einvalid (in case of any errors)
  # TODO: expand should return {ctx, expanded} and log errors it encountered
  # notes:
  # - the consequence of an :einvalid for a domain spec is determined at eval-time
  # - any errors in expanding an explain string, yields empty string
  # - macro letters c,r,t only valid when expanding an explain-string
  # - empty domain specification is (for :domspec) an error
  #
  @spec expand(Spf.Context.t(), list | token) :: binary | :einvalid
  defp expand(ctx, tokens, type \\ :domspec)

  defp expand(ctx, [], :domspec), do: ctx.domain
  defp expand(_ctx, [], :explain), do: ""

  defp expand(ctx, tokens, type) when is_list(tokens) do
    tokens = if type == :domspec, do: check_toplabel(tokens), else: tokens

    expanded =
      for {token, args, _range} <- tokens do
        expand(ctx, token, args, type)
      end

    case Enum.member?(expanded, :einvalid) do
      true -> if type == :domspec, do: :einvalid, else: ""
      false -> Enum.join(expanded) |> drop_labels()
    end
  end

  @spec expand(Spf.Context.t(), atom, list, atom) :: binary
  defp expand(ctx, :expand, [ltr, keep, reverse, delimiters], type) do
    if type == :domspec and ltr in [?c, ?r, ?t] do
      error(ctx, :parse, :syntax_error, "Cannot use #{[ltr]}-macro in a domain specification")
      :einvalid
    else
      macro(ctx, ltr)
      |> String.split(delimiters)
      |> (fn x -> if reverse, do: Enum.reverse(x), else: x end).()
      |> (fn x -> if keep in 0..length(x), do: Enum.slice(x, -keep, keep), else: x end).()
      |> Enum.join(".")
    end
  end

  defp expand(_ctx, :expand, ["%"], _type), do: "%"
  defp expand(_ctx, :expand, ["-"], _type), do: "%20"
  defp expand(_ctx, :expand, ["_"], _type), do: " "
  defp expand(_ctx, :literal, [str], _type), do: str
  defp expand(_ctx, :whitespace, [str], _type), do: str
  defp expand(_ctx, :error, _reason, _type), do: :einvalid

  @spec macro(Spf.Context.t(), non_neg_integer) :: binary
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
      ?t -> ctx.t0
    end
  end

  @spec macro_c(binary) :: binary
  defp macro_c(ip) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-7.3
    # - use inet.ntoa to get shorthand ip6 (appease v-macro-ip6 test)
    Pfx.new(ip)
    |> Pfx.marshall({0, 0, 0, 0})
    |> :inet.ntoa()
    |> List.to_string()
  end

  @spec macro_i(binary) :: binary
  defp macro_i(ip) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-7.3
    # - upcase reversed ip address (appease v-macro-ip6 test)
    pfx = Pfx.new(ip)

    case pfx.maxlen do
      32 -> "#{pfx}"
      _ -> Pfx.format(pfx, width: 4, base: 16) |> String.upcase()
    end
  end

  @spec macro_p(Spf.Context.t()) :: binary
  defp macro_p(ctx) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-7.3
    # "p" macro expands to a validated domain name of <ip>
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

    case dns do
      {:error, _reason} ->
        "unknown"

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
        |> case do
          nil -> "unknown"
          {_, str} -> inspect(str) |> String.trim("\"")
        end
    end
  end

  @spec pfxparse(binary, atom) :: {atom, Pfx.t()} | {:error, binary}
  defp pfxparse(pfx, :ip4) do
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-5.6
    leadzero = String.match?(pfx, ~r/(^|[\.\/])0[0-9]/)
    fournums = String.match?(pfx, ~r/^\d+\.\d+\.\d+\.\d+/)

    warn =
      cond do
        String.match?(pfx, ~r/\/0$/) -> :wzero_mask
        String.match?(pfx, ~r/\/32$/) -> :wmax_mask
        true -> :ok
      end

    if fournums and not leadzero,
      do: {warn, Pfx.new(pfx)},
      else: {:error, pfx}
  rescue
    _ -> {:error, pfx}
  end

  defp pfxparse(pfx, :ip6) do
    warn =
      cond do
        String.match?(pfx, ~r/\/0$/) -> :wzero_mask
        String.match?(pfx, ~r/\/128$/) -> :wmax_mask
        true -> :ok
      end

    {warn, Pfx.new(pfx)}
  rescue
    _ -> {:error, pfx}
  end

  defp spf_plus(ctx, range),
    do: String.slice(ctx.spf, range) |> String.starts_with?("+")

  # CHECKS
  # - checks performed by Spf.Parser at various stages
  @spec check(Spf.Context.t(), atom) :: Spf.Context.t()
  defp check(ctx, :spf_length) do
    # SPF_LENGTH
    term = "spf[#{ctx.nth}] #{ctx.domain}"

    case String.length(ctx.spf) do
      len when len > 512 ->
        log(ctx, :parse, :warn, "#{term} - TXT length #{len} > 512 characters")

      _ ->
        ctx
    end
  end

  defp check(ctx, :spf_residue) do
    # Spf_residue
    term = "spf[#{ctx.nth}] #{ctx.domain}"

    case String.length(ctx.spf_rest) do
      len when len > 0 ->
        log(ctx, :parse, :warn, "#{term} - SPF residue #{inspect(ctx.spf_rest)}")

      _ ->
        ctx
    end
  end

  defp check(ctx, :explain_reachable) do
    # Explain_reachable
    # if none of the terms have a fail qualifier, an explain is superfluous
    if ctx.explain != nil do
      Enum.filter(ctx.ast, fn {type, _tokval, _range} -> type != :redirect end)
      |> Enum.map(fn {_type, tokval, _range} -> tokval end)
      |> Enum.filter(fn l -> List.first(l, ?+) == ?- end)
      |> case do
        [] ->
          term = "spf[#{ctx.nth}] #{ctx.domain}"
          log(ctx, :parse, :warn, "#{term} - SPF cannot fail, explain never used")

        _ ->
          ctx
      end
    else
      ctx
    end
  end

  defp check(ctx, :no_implicit) do
    # No_implicit
    # warn if there's no redirect and no all present
    explicit = Enum.filter(ctx.ast, fn {type, _tokval, _range} -> type in [:all, :redirect] end)

    case explicit do
      [] -> log(ctx, :parse, :warn, "spf[#{ctx.nth}] #{ctx.domain} - has implicit end (?all)")
      _ -> ctx
    end
  end

  defp check(ctx, :max_redirect) do
    # Max_redirect
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-5
    # redirect modifier is allowed only once
    redirs = Enum.filter(ctx.ast, fn {type, _tokal, _range} -> type == :redirect end)

    if length(redirs) > 1 do
      [_, {_, _, range} | _] = redirs
      term = spf_term(ctx, range)
      error(ctx, :parse, :repeated_modifier, "#{term} - redirect allowed only once", :permerror)
    else
      ctx
    end
  end

  defp check(ctx, :redirect_last) do
    # Redirect_last
    # https://www.rfc-editor.org/rfc/rfc7208.html#section-4.6.3
    # redirect modifier takes effect after all mechanisms have been evaluated
    # - note this check must come after check :all_no_redirect
    {redir, ast} = List.keytake(ctx.ast, :redirect, 0) || {nil, nil}
    last = List.last(ctx.ast)

    case redir do
      nil ->
        ctx

      ^last ->
        ctx

      {_, _, range} ->
        log(ctx, :parse, :warn, "#{spf_term(ctx, range)} - not last term")
        |> Map.put(:ast, ast ++ [redir])
    end
  end

  defp check(ctx, :all_no_redirect) do
    # All_no_redirect
    # warn on ignoring a superfluous `redirect`
    # - note that this check must come before :redirect_last
    all = Enum.filter(ctx.ast, fn {type, _tokval, _range} -> type == :all end)

    if length(all) > 0 do
      case List.keytake(ctx[:ast], :redirect, 0) do
        nil ->
          ctx

        {{:redirect, _, range}, ast} ->
          term = spf_term(ctx, range)

          log(ctx, :parse, :warn, "#{term} - ignored in the presence of `all`")
          |> Map.put(:ast, ast)
      end
    else
      ctx
    end
  end

  defp check(ctx, :all_last) do
    # All_last
    # warns on terms being ignored
    # - exp is actually part of the context and does not appear in the ast
    # - redirect is (already) removed from ast if all is present
    rest = Enum.drop_while(ctx.ast, fn {t, _, _} -> t != :all end)

    case rest do
      [{_, _, r0} | tail] when tail != [] ->
        Enum.reduce(tail, ctx, fn {_, _, r1}, ctx ->
          log(ctx, :parse, :warn, "#{spf_term(ctx, r1)} - ignored, is after #{spf_term(ctx, r0)}")
        end)

      _ ->
        ctx
    end
  end

  # PARSER

  @spec parse(token, Spf.Context.t()) :: Spf.Context.t()
  defp parse({atom, [qual | args], range}, ctx) when atom in [:a, :mx] do
    # A, MX
    {dual, spec} = List.pop_at(args, -1)
    domain = expand(ctx, spec)
    {warn, cidr} = cidr(ctx, dual)

    term = spf_term(ctx, range)
    plus = spf_plus(ctx, range)

    if domain == :einvalid or warn == :error do
      error(ctx, :parse, :syntax_error, "#{term} - syntax error", :permerror)
    else
      ast(ctx, {atom, [qual, domain, cidr], range})
      |> tick(:num_dnsm)
      |> then(&log(&1, :parse, :info, "#{term} - DNS MECH (#{&1.num_dnsm})"))
      |> test(:parse, :debug, not String.contains?(term, domain), "#{term} -x-> #{domain}")
      |> test(:parse, :warn, warn == :wzero_mask, "#{term} - ZERO prefix length not advisable")
      |> test(:parse, :warn, warn == :wmax_mask, "#{term} - default mask can be omitted")
      |> test(:parse, :warn, plus, "#{term} - use of default '+'")
    end
  end

  defp parse({:all, [qual], range}, ctx) do
    # All
    term = spf_term(ctx, range)
    plus = spf_plus(ctx, range)

    ast(ctx, {:all, [qual], range})
    |> test(:parse, :warn, qual in [??, ?+], "#{term} - usage not advisable")
    |> test(:parse, :warn, plus, "#{term} - use of default '+'")
  end

  defp parse({atom, [qual | domspec], range}, ctx) when atom in [:include, :exists] do
    # Exists, Include
    term = spf_term(ctx, range)
    plus = spf_plus(ctx, range)

    case(expand(ctx, domspec)) do
      :einvalid ->
        error(ctx, :parse, :syntax_error, "#{term} - syntax error", :permerror)

      domain ->
        ast(ctx, {atom, [qual, domain], range})
        |> tick(:num_dnsm)
        |> then(&log(&1, :parse, :info, "#{term} - DNS MECH (#{&1.num_dnsm})"))
        |> test(:parse, :debug, not String.contains?(term, domain), "#{term} -x-> #{domain}")
        |> test(:parse, :warn, plus, "#{term} - use of default '+'")
    end
  end

  defp parse({:exp, domspec, range}, ctx) do
    # Exp
    term = spf_term(ctx, range)

    case expand(ctx, domspec) do
      :einvalid ->
        error(ctx, :parse, :syntax_error, "#{term} - syntax error", :permerror)

      domain ->
        ast(ctx, {:exp, [domain], range})
        |> test(:parse, :debug, not String.contains?(term, domain), "#{term} -x-> #{domain}")
    end
  end

  defp parse({atom, [qual, {:literal, [ip], _}], range}, ctx) when atom in [:ip4, :ip6] do
    # IP4, IP6
    # TODO: have only cidr() check/warn for prefix lengths, eliminate that
    # check in pfxparse() (DRY principle)
    term = spf_term(ctx, range)
    plus = spf_plus(ctx, range)

    case pfxparse(ip, atom) do
      {:error, _} ->
        error(ctx, :parse, :syntax_error, "#{term} - syntax error", :permerror)

      {warn, pfx} ->
        lenh = String.split(ip, "/") |> hd() |> Pfx.trim() |> Pfx.pfxlen()
        lenp = Pfx.pfxlen(pfx)
        masked = lenh - lenp

        ast(ctx, {atom, [qual, pfx], range})
        |> test(:parse, :warn, warn == :wmax_mask, "#{term} - default mask can be omitted")
        |> test(:parse, :warn, warn == :wzero_mask, "#{term} - ZERO prefix length not advisable!")
        |> test(:parse, :warn, plus, "#{term} - default '+' can be omitted")
        |> test(:parse, :warn, masked > 0, "#{term} - #{masked} host bits masked, #{pfx}")
    end
  end

  defp parse({:ptr, [qual | spec], range}, ctx) do
    # Ptr
    term = spf_term(ctx, range)
    plus = spf_plus(ctx, range)

    case expand(ctx, spec) do
      :einvalid ->
        error(ctx, :parse, :syntax_error, "#{term} - syntax error", :permerror)

      domain ->
        ast(ctx, {:ptr, [qual, domain], range})
        |> tick(:num_dnsm)
        |> then(&log(&1, :parse, :info, "#{term} - DNS MECH (#{&1.num_dnsm})"))
        |> log(:parse, :warn, "#{term} - usage not recommended")
        |> test(:parse, :debug, not String.contains?(term, domain), "#{term} -x-> #{domain}")
        |> test(:parse, :warn, plus, "#{term} - use of default '+'")
    end
  end

  defp parse({:redirect, domspec, range}, ctx) do
    # Redirect
    term = spf_term(ctx, range)

    case expand(ctx, domspec) do
      :einvalid ->
        error(ctx, :parse, :syntax_error, "#{term} - syntax error", :permerror)

      domain ->
        ast(ctx, {:redirect, [domain], range})
        |> tick(:num_dnsm)
        |> then(&log(&1, :parse, :info, "#{term} - DNS MECH (#{&1.num_dnsm})"))
        |> test(:parse, :debug, not String.contains?(term, domain), "#{term} -x-> #{domain}")
    end
  end

  defp parse({:version, [n], range} = _token, ctx) do
    # Version
    term = spf_term(ctx, range)

    case n do
      1 -> ctx
      _ -> error(ctx, :parse, :syntax_error, "#{term} - unknown spf version", :permerror)
    end
  end

  defp parse({:whitespace, [wspace], range}, ctx) do
    # Whitespace
    record = "spf[#{ctx.nth}] #{ctx.domain}"

    ctx =
      if String.length(wspace) > 1,
        do: log(ctx, :parse, :warn, "#{record} #{inspect(range)} - repeated whitespace"),
        else: ctx

    if String.contains?(wspace, "\t"),
      do: log(ctx, :parse, :warn, "#{record} #{inspect(range)} - has tab"),
      else: ctx
  end

  defp parse({:unknown, [name | args], range} = _token, ctx) do
    # Unknown modifier, cannot have a known name
    term = spf_term(ctx, range)
    spec_error = Enum.filter(args, fn x -> elem(x, 0) == :error end)

    cond do
      length(spec_error) > 0 ->
        error(ctx, :parse, :syntax_error, "#{term} - syntax error", :permerror)

      String.downcase(name) in @reserved_names ->
        error(ctx, :parse, :syntax_error, "#{name} cannot be used as a modifier", :permerror)

      true ->
        log(ctx, :parse, :warn, "#{term} - unknown modifier ignored")
    end
  end

  defp parse({:error, _tokvalue, range} = _token, ctx) do
    # Unknown
    error(ctx, :parse, :syntax_error, "#{spf_term(ctx, range)} - syntax error", :permerror)
  end

  defp parse({_, _, range}, ctx),
    # CatchAll
    do: log(ctx, :parse, :error, "#{spf_term(ctx, range)} - Spf.parser.check has no handler!!")
end
