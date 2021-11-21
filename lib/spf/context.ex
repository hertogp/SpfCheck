defmodule Spf.Context do
  @moduledoc """
  Functions to create, access and update an SPF evaluation context.

  Many functions take and return an evaluation context whose purpose
  is to store information gathered during the evaluation.  This includes
  a dns cache, an ip lookup table that maps prefixes to SPF terms that
  named them, a stack for recursive evaluations, as well as some statistics
  around DNS mechanisms seen and void DNS responses seen.

  """

  @typedoc """
  An SPF evaluation result.
  """
  @type verdict :: :fail | :neutral | :none | :pass | :permerror | :softfail | :temperror

  @typedoc """
  An SPF evaluation context.
  """
  @type t :: %{
          :ast => list(),
          :atype => :a | :aaaa,
          :contact => binary(),
          :depth => non_neg_integer(),
          :dns => map(),
          :dns_timeout => non_neg_integer(),
          :domain => binary(),
          :duration => non_neg_integer(),
          :error => nil | atom(),
          :explain => nil | tuple(),
          :explain_string => binary(),
          :explanation => binary(),
          :helo => binary(),
          :ip => binary(),
          :ipt => Iptrie.t(),
          :local => binary(),
          :log => function(),
          :map => map(),
          :max_dnsm => non_neg_integer(),
          :max_dnsv => non_neg_integer(),
          :msg => list(),
          :nth => non_neg_integer(),
          :num_checks => non_neg_integer(),
          :num_dnsm => non_neg_integer(),
          :num_dnsq => non_neg_integer(),
          :num_dnsv => non_neg_integer(),
          :num_error => non_neg_integer(),
          :num_spf => non_neg_integer(),
          :num_warn => non_neg_integer(),
          :owner => binary(),
          :reason => binary(),
          :sender => binary(),
          :spf => binary(),
          :spf_rest => binary(),
          :spf_tokens => list(),
          :stack => list(),
          :t0 => non_neg_integer(),
          :traces => map(),
          :verbosity => non_neg_integer(),
          :verdict => verdict()
        }

  @typedoc """
  A `t:Spf.Tokens.token/0`.
  """
  @type token :: Spf.Tokens.token()

  @typedoc """
  A `t:Pfx.prefix/0`.
  """
  @type prefix :: Pfx.prefix()

  @typedoc """
  A `{qualifier, nth, term}` tuple, where `nth` is the nth SPF record where `term` was
  found.

  The context's ip lookup table stores these tuples thus tracking which term in
  which SPF record provided a qualifier for a prefix.  Since an evaluation may
  involve multiple SPF records, each prefix actually stores a list of these
  tuples.

  Once the sender's ip has a longest prefix match, the qualifier will tell how
  the mechanism at hand matches.

  """
  @type iptval :: {Spf.Tokens.q(), non_neg_integer, binary}

  # Helpers

  @spec ipt_update({prefix, iptval}, t) :: t
  defp ipt_update({k, v}, ctx) do
    data = Iptrie.lookup(ctx.ipt, k)
    ipt = Iptrie.update(ctx.ipt, k, [v], fn list -> [v | list] end)

    seen_before =
      case data do
        nil -> false
        {k2, _v} -> not Pfx.member?(ctx.ip, k2)
      end

    Map.put(ctx, :ipt, ipt)
    |> log(:ipt, :debug, "UPDATE: #{k} -> #{inspect(v)}")
    |> test(:ipt, :warn, seen_before, "#{k} seen before: #{inspect(data)}")
  end

  @spec prefix(binary, [non_neg_integer]) :: :error | prefix
  defp prefix(ip, [len4, len6]) do
    pfx = Pfx.new(ip)

    case pfx.maxlen do
      32 -> Pfx.keep(pfx, len4)
      _ -> Pfx.keep(pfx, len6)
    end
  rescue
    _ -> :error
  end

  @spec trace(t, binary) :: t
  defp trace(ctx, new_domain) do
    new_domain = String.downcase(new_domain)
    cur_domain = String.downcase(ctx.domain)

    Map.update(ctx.traces, cur_domain, [], fn v -> v end)
    |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, k, [new_domain | v]) end)
    |> then(fn traces -> Map.put(ctx, :traces, traces) end)
  end

  # API CONTEXT

  @doc """
  Updates `context.ipt` with one or more {`t:prefix/0`, `t:iptval/0`}-pairs.

  When given a list op ip's, they all will be be updated with given 
  `t:iptval/0` which records the SPF record and term (including the qualifier)
  that attributed the ip or ip's.

  The `dual` parameter contains the dual-cidr lengths to apply to the given
  ip addresses.

  """
  @spec addip(t, list(), list(), iptval) :: t
  def addip(context, ips, dual, value) when is_list(ips) do
    kvs =
      Enum.map(ips, fn ip -> {prefix(ip, dual), value} end)
      |> Enum.filter(fn {k, _v} -> k != :error end)

    Enum.reduce(kvs, context, &ipt_update/2)
  end

  @spec addip(t, binary, list(), iptval) :: t
  def addip(context, ip, dual, value) when is_binary(ip) do
    case prefix(ip, dual) do
      :error -> log(context, :ctx, :error, "ignored malformed IP #{ip}")
      pfx -> ipt_update({pfx, value}, context)
    end
  end

  @doc """
  Updates `context` with given `error`, `reason` and `verdict`.

  When `verdict` is nil, `context.verdict` is not updated.  This
  allows for setting error conditions whose impact is to be evaluated
  at a later stage.

  """
  @spec error(t, atom, binary, nil | atom) :: t
  def error(context, error, reason, verdict \\ nil) do
    Map.put(context, :error, error)
    |> Map.put(:reason, reason)
    |> Map.put(:verdict, verdict || context.verdict)
    |> log(:eval, :error, reason)
  end

  @doc """
  Returns a previous SPF string given either its `domain` of `nth`-tracking number.

  Used for reporting rather than evalutation an SPF record.

  """
  @spec get_spf(t, integer | binary) :: binary
  def get_spf(context, nth) when is_integer(nth) do
    with domain when is_binary(domain) <- context.map[nth] do
      get_spf(context, domain)
    else
      _ -> "ERROR SPF[#{nth}] NOT FOUND"
    end
  end

  def get_spf(context, domain) when is_binary(domain) do
    case Spf.DNS.from_cache(context, domain, :txt) do
      # {:ok, []} -> "ERROR SPF NOT FOUND"
      {:error, _} -> "ERROR SPF NOT FOUND"
      {:ok, rrs} -> Enum.find(rrs, "ERROR SPF NOT FOUND", &Spf.Eval.spf?/1)
    end
  end

  @doc """
  Given a current `context` and a `range`, return the SPF term in that range.

  Retrieves a slice of the `context.spf` current record being evaluated.
  Used for logging events.

  """
  @spec spf_term(t, Range.t()) :: binary
  def spf_term(context, range),
    do: "spf[#{context.nth}] #{String.slice(context.spf, range)}"

  @doc """
  Updates `context`'s message queue and, if available, calls the user supplied log
  function.

  The `log/4` is called with:
  - `context` the current context/state of the evalution
  - `facility` an atom denoting which part of the program emitted the event
  - `severity` an atom describing the severity
  - `msg` a binary with event details

  """
  @spec log(t, atom, atom, binary) :: t
  def log(context, facility, severity, msg) do
    if context[:log],
      do: context.log.(context, facility, severity, msg)

    nth = Map.get(context, :nth, 0)

    context =
      Map.update(context, :msg, [{nth, facility, severity, msg}], fn msgs ->
        [{nth, facility, severity, msg} | msgs]
      end)

    case severity do
      :warn -> tick(context, :num_warn)
      :error -> tick(context, :num_error)
      _ -> context
    end
  end

  @doc """
  Returns true if `new_domain` constitues a loop for given `context`, false
  otherwise.

  Loops may occur when two SPF records (eventually) include or redirect to
  each other and is considered a permanent error.

  """
  @spec loop?(t, binary) :: boolean
  def loop?(context, new_domain) do
    new_domain = String.downcase(new_domain)
    cur_domain = String.downcase(context.domain)
    cur_domain in Map.get(context.traces, new_domain, [])
  end

  @doc """
  Split an email address into a local and a domain part.

  The local part is left to the left-most `@`, if there is no local
  part it defaults to "postmaster".  Note that splitting an empty
  string yields `{"postmaster", ""}`.

  """
  @spec split(binary) :: {binary, binary}
  def split(mbox) do
    words = String.split(mbox, "@", parts: 2, trim: true)

    case words do
      [] -> {"postmaster", ""}
      [local, domain] -> {local, domain}
      [domain] -> {"postmaster", domain}
    end
  end

  @doc """
  Returns a new `t:Spf.Context.t/0` for given `sender`.

  Options include:
  - `dns:`, filepath or binary with zonedata (defaults to nil)
  - `helo:`, sender's helo string to use (defaults to `sender`)
  - `ip:`, sender ip to use (defaults to `127.0.0.1`)
  - `log:`, user supplied log function (defaults to nil)
  - `verbosity:`, log level `0..5` to use (defaults to `4`)

  The initial `domain` is derived from given `sender`.  The default for
  `ip` is likely to traverse all SPF mechanisms during evaluation, gathering
  as much information as possible.  Set `ip:` to a real IPv4 or IPv6 address
  to check a policy for that specific address.

  The context is used for the entire SPF evaluation, including during any
  recursive calls.  When evaluating an `include` mechanism, the current state (a
  few selected context properties) is pushed onto an internal stack and a new
  `domain` is set.  After evaluating the `include` mechanism, the state if
  popped and the results are processed according to the `include`-mechanism's
  qualifier.

  When evaluating a `redirect` modifier, the current state is altered for the
  new domain specified by the modifier.

  """
  @spec new(binary, Keyword.t()) :: t
  def new(sender, opts \\ []) do
    helo = Keyword.get(opts, :helo, sender)
    {local, domain} = split(sender)

    {local, domain} =
      if String.length(domain) < 1,
        do: split(helo),
        else: {local, domain}

    # IPV4-mapped IPv6 addresses are converted to the mapped IPv4 address
    # note: check validity of user supplied IP address, default to 127.0.0.1
    ip = Keyword.get(opts, :ip, "127.0.0.1")

    pfx =
      try do
        Pfx.new(ip)
      rescue
        ArgumentError -> Pfx.new("127.0.0.1")
      end

    # extract IPv4 address from an IPv4-mapped IPv6 address
    pfx =
      if Pfx.member?(pfx, "::FFFF:0:0/96"),
        do: Pfx.cut(pfx, -1, -32),
        else: pfx

    atype = if pfx.maxlen == 32 or Pfx.member?(pfx, "::FFFF:0/96"), do: :a, else: :aaaa

    %{
      ast: [],
      atype: atype,
      contact: "",
      depth: 0,
      dns: %{},
      dns_timeout: 2000,
      domain: domain,
      duration: 0,
      error: nil,
      explain: nil,
      explain_string: "",
      explanation: "",
      helo: helo,
      ip: "#{pfx}",
      ipt: Iptrie.new(),
      local: local,
      log: Keyword.get(opts, :log, nil),
      map: %{0 => domain, domain => 0},
      max_dnsm: 10,
      max_dnsv: 2,
      msg: [],
      nth: 0,
      num_checks: 0,
      num_dnsm: 0,
      num_dnsq: 0,
      num_dnsv: 0,
      num_error: 0,
      num_spf: 1,
      num_warn: 0,
      owner: "",
      reason: "",
      sender: sender,
      spf: "",
      spf_rest: "",
      spf_tokens: [],
      stack: [],
      t0: DateTime.utc_now() |> DateTime.to_unix(),
      traces: %{},
      verbosity: Keyword.get(opts, :verbosity, 4),
      verdict: :neutral
    }
    |> Spf.DNS.load(Keyword.get(opts, :dns, nil))
    |> log(:ctx, :debug, "created context for #{domain}")
    |> log(:spf, :note, "spfcheck(#{domain}, #{pfx}, #{sender})")
  end

  @doc """
  Pop the previous state of given `context` from its stack.

  Before evaluating an include mechanism, the current SPF's record state
  is pushed onto the stack.  This function restores that state from the
  stack.

  """
  @spec pop(t) :: t
  def pop(context) do
    case context.stack do
      [] ->
        log(context, :ctx, :error, "attempted to pop from empty stack")

      [state | tail] ->
        Map.put(context, :stack, tail)
        |> Map.merge(state)
        |> log(:ctx, :debug, "popped state, back to #{state.domain}")
    end
  end

  @doc """
  Push the current state of given `context` onto its stack and re-init the context.

  The details of the current SPF record are pushed onto a stack and the context
  is re-initialized for retrieving, parsing and evaluate a new `include`d
  record.

  """
  @spec push(t, binary) :: t
  def push(context, domain) do
    state = %{
      depth: context.depth,
      domain: context.domain,
      nth: context.nth,
      ast: context.ast,
      spf: context.spf,
      explain: context.explain
    }

    nth = context.num_spf

    tick(context, :num_spf)
    |> tick(:depth)
    |> trace(domain)
    |> Map.put(:stack, [state | context.stack])
    |> Map.put(:map, Map.merge(context.map, %{nth => domain, domain => nth}))
    |> Map.put(:domain, domain)
    |> Map.put(:nth, nth)
    |> Map.put(:ast, [])
    |> Map.put(:spf, "")
    |> Map.put(:explain, nil)
    |> log(:ctx, :debug, "pushed state for #{state.domain}")
  end

  @doc """
  Reinitializes current `context` for given `domain` of a redirect modifier.

  When a redirect modifier is encountered it basically replaces the current SPF
  record and the context is modified accordingly..

  """
  @spec redirect(t, binary) :: t
  def redirect(context, domain) do
    # do NOT empty the stack: a redirect modifier may be in an included record
    tick(context, :num_spf)
    |> trace(domain)
    |> Map.put(:depth, 0)
    |> Map.put(:nth, context.num_spf)
    |> Map.put(
      :map,
      Map.merge(context.map, %{context.num_spf => domain, domain => context.num_spf})
    )
    |> Map.put(:domain, domain)
    |> Map.put(:error, nil)
    |> Map.put(:ast, [])
    |> Map.put(:spf, "")
    |> Map.put(:explain, nil)
  end

  @doc """
  If `test` is true, logs the given `msg` with its `facility` and `severity`.

  A convencience function to quickly perform some test (in the call) and, if
  true, log it as well.

  """
  @spec test(t, atom, atom, boolean, binary) :: t
  def test(context, facility, severity, test, msg)

  def test(context, facility, severity, true, msg),
    do: log(context, facility, severity, msg)

  def test(context, _, _, _, _),
    # nil is also false
    do: context

  @doc """
  Adds `delta` to `counter` and returns updated `context`.

  Valid counters include:
  - `:num_spf`, the number of SPF records seen
  - `:num_dnsm` the number of DNS mechanisms seen
  - `:num_dnsq` the number of DNS queries performed
  - `:num_dnsv` the number of void DNS queries seen
  - `:num_checks` the number of checks performed
  - `:num_warn` the number of warnings seen
  - `:num_error` the number of errors see (may not be fatal)
  - `:depth` the current recursion depth

  """
  @spec tick(t, atom, integer) :: t
  def tick(context, counter, delta \\ 1) do
    count = Map.get(context, counter, nil)

    if count do
      Map.put(context, counter, count + delta)
    else
      log(context, :ctx, :error, "unknown counter #{inspect(counter)} - ignored")
    end
  end
end
