defmodule Spf.Context do
  @moduledoc """
  Functions to create, access and update an SPF evaluation context.
  """

  # Helpers

  defp ipt_update({k, v}, ctx) do
    ctx =
      case Iptrie.lookup(ctx.ipt, k) do
        {k2, v2} ->
          log(
            ctx,
            :ipt,
            :warn,
            "#{k} covered by #{k2} from #{inspect(v2)}"
          )

        nil ->
          ctx
      end

    ipt = Iptrie.update(ctx.ipt, k, [v], fn list -> [v | list] end)

    Map.put(ctx, :ipt, ipt)
    |> log(:ipt, :debug, "UPDATE: #{k} -> #{inspect(v)}")
  end

  defp prefix(ip, [len4, len6]) do
    pfx = Pfx.new(ip)

    case pfx.maxlen do
      32 -> Pfx.keep(pfx, len4)
      _ -> Pfx.keep(pfx, len6)
    end
  rescue
    _ -> :error
  end

  # CONTEXT

  @doc """
  Update `ctx.ipt` with one or more ip,value-pairs.

  When given a list op ip's, they all will be be updated with given `value`
  which should consist of a tuple `{q, nth, term}` which records the SPF record
  and term (including the qualifier) that attributed the ip or ip's.

  """
  def addip(ctx, ips, dual, value) when is_list(ips) do
    kvs =
      Enum.map(ips, fn ip -> {prefix(ip, dual), value} end)
      |> Enum.filter(fn {k, _v} -> k != :error end)

    Enum.reduce(kvs, ctx, &ipt_update/2)
  end

  def addip(ctx, ip, dual, value) when is_binary(ip) do
    ipt_update({prefix(ip, dual), value}, ctx)
  end

  @doc """
  Returns the SPF string for `nth` domain if available, nil otherwise.

  """
  @spec get_spf(map, integer | binary) :: binary
  def get_spf(ctx, nth) when is_integer(nth) do
    with domain when is_binary(domain) <- ctx.map[nth] do
      get_spf(ctx, domain)
    else
      # TODO: better error handling here!
      _ -> "ERROR SPF [#{nth}] NOT FOUND"
    end
  end

  def get_spf(ctx, domain) when is_binary(domain) do
    case Spf.DNS.from_cache(ctx, domain, :txt) do
      {:ok, []} -> "ERROR SPF NOT FOUND"
      {:ok, rrs} -> Enum.find(rrs, "ERROR SPF NOT FOUND", &Spf.spf?/1)
      {:error, _} -> "ERROR SPF NOT FOUND"
    end
  end

  @spec log(map, atom, atom, binary) :: map
  def log(ctx, facility, severity, msg) do
    if ctx[:log],
      do: ctx.log.(ctx, facility, severity, msg)

    ctx =
      Map.update(ctx, :msg, [{ctx.nth, facility, severity, msg}], fn msgs ->
        [{ctx.nth, facility, severity, msg} | msgs]
      end)

    case severity do
      :warn -> tick(ctx, :num_warn)
      :error -> tick(ctx, :num_error)
      _ -> ctx
    end
  end

  @doc """
  Returns a map with macroletters expansions for given `domain`, `ip` and `sender`.

  Uppercase macro letters expand as their lowercase variants, but are URL escaped.

  """
  @spec macros(binary, binary, binary) :: map
  def macros(domain, ip, sender) do
    pfx = Pfx.new(ip)
    tstamp = DateTime.utc_now() |> DateTime.to_unix()

    m = %{
      # d = <domain>
      ?d => domain,
      # c = SMTP client IP (easily readable format)
      ?c => "#{pfx}",
      # i = <ip>, for ip6 this expands to dotted format
      ?i => if(pfx.maxlen == 32, do: "#{pfx}", else: Pfx.format(pfx, width: 4, base: 16)),
      # s = <sender>
      ?s => sender,
      # o = domain of <sender> (after last @ in sender)
      ?o => String.replace(sender, ~r(^.*@), ""),
      # l = local-part of <sender> (before last @ in sender)
      ?l => String.replace(sender, ~r(@[^@]*$), ""),
      # p = the validated domain name of <ip> (do not use)
      ?p => Pfx.dns_ptr(ip),
      # v = the string "in-addr" if <ip> is ipv4, or "ip6" if <ip> is ipv6
      ?v => (pfx.maxlen == 32 && "in-addr") || "ip6",
      # h = HELO/EHLO domain (fake it with domain part of sender)
      ?h => String.replace(sender, ~r(^.*@), ""),
      # r = domain name of host performing the check
      ?r => "localhost"
    }

    # add uppercase variants: they are URL escaped (except for ?t and ?T)
    Enum.reduce(m, m, fn {k, v}, m -> Map.put(m, k - 32, URI.encode(v)) end)
    |> Map.put(?t, tstamp)
    |> Map.put(?T, tstamp)
  end

  @doc """
  Returns a context map for SPF parsing and evaluation.
  """
  def new(domain, opts \\ []) do
    # TODO: check validity of user supplied IP address
    ip = Keyword.get(opts, :ip, "127.0.0.1")

    sender = Keyword.get(opts, :sender, "postmaster@host.local")
    atype = if Pfx.new(ip).maxlen == 32, do: :a, else: :aaaa

    %{
      # the nth spf record is now current
      nth: 0,
      # linear increasing count of spf records
      cnt: 1,
      # current recursion depth (for pretty logging)
      depth: 0,
      # current <domain> whose authorisation is evaluated
      domain: domain,
      # tracks what was seen before: nth=>domain, domain=>nth; for reporting
      map: %{0 => domain, domain => 0},
      # push state (part of ctx) when recursing on include'd domains
      stack: [],
      # <ip> for which authorization is sought
      ip: ip,
      # type of A RR lookup (A or AAAA), depends on <ip>
      atype: atype,
      # <sender> that is using <ip> to send mail
      sender: sender,
      # user log function, or local one.
      log: Keyword.get(opts, :log, nil),
      # default verdict is ?all, ie neutral
      verdict: :neutral,
      # what actually caused a match
      reason: "",
      # default :inet_res timeout in msec
      dns_timeout: 2000,
      # dns cache {key, type} => [value]
      dns: %{},
      # no dns error seen (yet)
      error: nil,
      # how macro letters expand for current domain
      macro: macros(domain, ip, sender),
      # output errors (1), warnings (2), notes (3), info (4) or debug (5) messages (quiet=0)
      verbosity: Keyword.get(opts, :verbosity, 4),
      # log of messages, whether outputted or not
      msg: [],
      # parser state flags
      f_include: false,
      f_all: false,
      f_redirect: false,
      # explain term (if any)
      explain: nil,
      explanation: "",
      # track some stats: dns queries, void lookups, dns mech's, checks done
      num_dnsq: 0,
      num_dnsv: 0,
      num_dnsm: 0,
      max_dnsq: 10,
      max_dnsv: 2,
      max_dnsm: 10,
      num_checks: 0,
      num_warn: 0,
      num_error: 0,
      # list of terms to be evaluated to arrive at a verdict
      ast: [],
      # how long the evaluation took
      duration: 0,
      # ip -> [{q, nth}, ..], if len(list) > 1 -> duplicate ip's seen
      ipt: Iptrie.new(),
      # report back
      report: Keyword.get(opts, :report, :short)
    }
    |> Spf.DNS.load_file(Keyword.get(opts, :rrs, nil))
    |> log(:ctx, :debug, "created context for #{domain}")
  end

  @doc """
  Pop the previous state of given `ctx` from its stack.

  This function restores the details of a previous SPF record, whose evaluation
  encountered an `include` mechanism.

  """
  @spec pop(map) :: map
  def pop(ctx) do
    case ctx.stack do
      [] ->
        log(ctx, :ctx, :error, "attempted to pop from empty stack")

      [state | tail] ->
        Map.put(ctx, :stack, tail)
        |> Map.merge(state)
        |> log(:ctx, :debug, "popped state, back to #{state.domain}")
    end
  end

  @doc """
  Push the current state of given `ctx` onto its stack and re-init the context.

  The details of the current SPF record are pushed onto a stack and the context
  is re-initialized for retrieving, parsing and evaluate a new `include`d
  record.

  """
  @spec push(map, binary) :: map
  def push(ctx, domain) do
    state = %{
      depth: ctx.depth,
      domain: ctx.domain,
      f_include: ctx.f_include,
      f_redirect: ctx.f_redirect,
      f_all: ctx.f_all,
      nth: ctx.nth,
      macro: ctx.macro,
      ast: ctx.ast,
      spf: ctx.spf,
      explain: ctx.explain
    }

    nth = ctx.cnt

    tick(ctx, :cnt)
    |> tick(:depth)
    |> Map.put(:stack, [state | ctx.stack])
    |> Map.put(:map, Map.merge(ctx.map, %{nth => domain, domain => nth}))
    |> Map.put(:domain, domain)
    |> Map.put(:f_include, true)
    |> Map.put(:f_redirect, false)
    |> Map.put(:f_all, false)
    |> Map.put(:nth, nth)
    |> Map.put(:macro, macros(domain, ctx.ip, ctx.sender))
    |> Map.put(:ast, [])
    |> Map.put(:spf, "")
    |> Map.put(:explain, nil)
  end

  @doc """
  Reinitializes current `ctx` for given `domain` of a redirect modifier.

  This permanently clears the details of the current SPF record under
  evaluation, including its stack.

  """
  @spec redirect(map, binary) :: map
  def redirect(ctx, domain) do
    nth = ctx.cnt

    tick(ctx, :cnt)
    |> Map.put(:depth, 0)
    |> Map.put(:stack, [])
    |> Map.put(:map, Map.merge(ctx.map, %{nth => domain, domain => nth}))
    |> Map.put(:domain, domain)
    |> Map.put(:error, nil)
    |> Map.put(:f_include, false)
    |> Map.put(:f_redirect, false)
    |> Map.put(:f_all, false)
    |> Map.put(:nth, nth)
    |> Map.put(:macro, macros(domain, ctx.ip, ctx.sender))
    |> Map.put(:ast, [])
    |> Map.put(:spf, "")
    |> Map.put(:explain, nil)
  end

  @doc """
  Adds `label`ed log `msg` to given `ctx`, if `test` is true
  """
  def test(ctx, facility, severity, test, msg)

  def test(ctx, facility, severity, true, msg),
    do: log(ctx, facility, severity, msg)

  def test(ctx, _, _, false, _),
    do: ctx

  @doc """
  Add `delta` to `counter`, returns updated `context`.

  If `counter` is not present in `context`, it will be created.

  """
  @spec tick(map, atom, integer) :: map
  def tick(ctx, counter, delta \\ 1) when is_atom(counter),
    do: Map.update(ctx, counter, delta, fn n -> n + delta end)
end
