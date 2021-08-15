defmodule Spf.Tokens do
  @moduledoc """
  Functions to turn an SPF string into tokens.
  """

  import NimbleParsec

  # Helpers
  def anycase(string) do
    string
    |> String.to_charlist()
    |> Enum.map(&bothcases/1)
    |> Enum.reduce(empty(), fn elm, acc -> concat(acc, elm) end)
  end

  def anycase(combinator, string),
    do: concat(combinator, anycase(string))

  def bothcases(c) when ?a <= c and c <= ?z,
    do: ascii_char([c, c - 32])

  def bothcases(c) when ?A <= c and c <= ?Z,
    do: ascii_char([c, c + 32])

  def bothcases(c),
    do: ascii_char([c])

  def digit(),
    do: ascii_char([?0..?9])

  def digit(combinator),
    do: concat(combinator, digit())

  # -> TODO, remove once Pfx.parse becomes available
  defp pfxparse(pfx) do
    Pfx.new(pfx)
  rescue
    _ -> {:error, pfx}
  end

  @doc """
  Matches 1 or more whitespaces (space or tab).

  """

  def eoterm() do
    choice([
      whitespace(),
      eos()
    ])
    |> lookahead()
  end

  def eoterm(combinator),
    do: concat(combinator, eoterm())

  def eoterm2(),
    do: lookahead(choice([whitespace(), eos()]))

  def eoterm2(c),
    do: concat(c, eoterm2())

  def mark_start(_rest, _args, context, _line, offset, args \\ []),
    do: {args, Map.put(context, :start, offset)}

  defp range(context, offset),
    do: Range.new(Map.get(context, :start, 0), offset - 1)

  # TOKENS

  # token = {atom, args, range}
  # - atom is type of token
  # - args is args for Parser.token handler function
  # - range is {start, end} of token in spf string
  def token(rest, args, context, line, offset, atom)
  # line = {linenr, start_line (0-based offset from start of entire binary)
  # offset = token_end (0-based offset from start of entire binary)

  # Whitespace
  def token(_rest, args, context, _line, offset, :whitespace),
    do: {[{:whitespace, args, range(context, offset)}], context}

  def token(_rest, args, context, _line, offset, :dual_cidr2),
    do: {[{:dual_cidr, args, range(context, offset)}], context}

  def token(_rest, args, context, _line, offset, :dual_cidr4),
    do: {[{:dual_cidr, args ++ [128], range(context, offset)}], context}

  def token(_rest, args, context, _line, offset, :dual_cidr6),
    do: {[{:dual_cidr, [32] ++ args, range(context, offset)}], context}

  # Version
  def token(_rest, args, context, _line, offset, :version) do
    {[{:version, args, range(context, offset)}], context}
  end

  # Qualifier
  def token(_rest, args, context, _line, offset, :qualifier) do
    tokval = if args == [], do: [?+], else: args
    {[{:qualifier, tokval, range(context, offset)}], context}
  end

  # Include, Exists
  def token(_rest, args, context, _line, offset, atom) when atom in [:include, :exists] do
    IO.inspect(args, label: :tokens_include)
    [{:qualifier, q, _offset}, macro] = Enum.reverse(args)
    {[{atom, [q, macro], range(context, offset)}], context}
  end

  # All
  def token(_rest, args, context, _line, offset, :all) do
    [{:qualifier, q, _offset}] = args
    {[{:all, [q], range(context, offset)}], context}
  end

  # IP4, IP6
  def token(_rest, args, context, _line, offset, atom) when atom in [:ip4, :ip6] do
    [{:unknown, addr, _}, {:qualifier, q, _}] = args
    addr = List.to_string(addr) |> pfxparse()
    {[{atom, [q, addr], range(context, offset)}], context}
  end

  # A, MX, PTR
  def token(_rest, args, context, _line, offset, atom) when atom in [:a, :mx, :ptr] do
    tokval =
      case Enum.reverse(args) do
        [{:qualifier, q, _range}] -> [q]
        [{:qualifier, q, _rang} | domain_spec] -> [q, domain_spec]
      end

    {[{atom, tokval, range(context, offset)}], context}
  end

  # Literal
  def token(_rest, args, context, _line, offset, :literal) do
    [tokval] = args
    {[{:literal, tokval, range(context, offset)}], context}
  end

  # Transform
  def token(_rest, args, context, _line, _offset, :transform) do
    tokval =
      case args do
        [] -> [0, false]
        [?r] -> [0, true]
        [?r | tail] -> [Enum.reverse(tail) |> List.to_integer(), true]
        num -> [Enum.reverse(num) |> List.to_integer(), false]
      end

    {tokval, context}
  end

  # Expand -> {:expand, [letter, keepN, reverse?, delimiters], range}
  def token(_rest, args, context, _line, offset, :expand1) do
    IO.inspect(args, label: :expand1)
    [ltr, reverse, keep | delims] = Enum.reverse(args)
    delims = if delims == [], do: ["."], else: Enum.map(delims, fn x -> List.to_string([x]) end)
    IO.inspect(delims, label: :expand1_delims)
    tokval = [ltr, keep, reverse, delims]

    {[{:expand, tokval, range(context, offset)}], context}
  end

  def token(_rest, args, context, _line, offset, :expand2),
    do: {[{:expand, args, range(context, offset)}], context}

  # Domain_spec
  def token(_rest, args, context, _line, offset, :domain_spec),
    do: {[{:domain_spec, Enum.reverse(args), range(context, offset)}], context}

  # CatchAll
  def token(_rest, args, context, _line, offset, atom),
    do: {[{atom, Enum.reverse(args), range(context, offset)}], context}

  # order matters: all before a
  def term() do
    choice([
      whitespace(),
      version(),
      all(),
      a(),
      mx(),
      ip4(),
      ip6(),
      include(),
      exists(),
      ptr(),
      redirect(),
      explanation(),
      nonspaces()
    ])
  end

  def term(combinator),
    do: concat(combinator, term())

  def terms(),
    do: term() |> repeat()

  # Helper Tokens
  def whitespace() do
    start()
    |> ascii_char([?\ , ?\t])
    |> times(min: 1)
    |> reduce({List, :to_string, []})
    |> post_traverse({:token, [:whitespace]})
  end

  @doc """
  Matches one or more non-space characters as a catch all for unknown blobs

  """
  def nonspaces() do
    start()
    |> ascii_char(not: ?\ , not: ?\t)
    |> times(min: 1)
    |> post_traverse({:token, [:unknown]})
  end

  def nonspaces(combinator),
    do: concat(combinator, nonspaces())

  def dual_cidr() do
    choice([
      start()
      |> ignore(string("/"))
      |> integer(min: 1)
      |> ignore(string("//"))
      |> integer(min: 1)
      |> eoterm2()
      |> post_traverse({:token, [:dual_cidr2]}),
      start()
      |> ignore(string("/"))
      |> integer(min: 1)
      |> eoterm2()
      |> post_traverse({:token, [:dual_cidr4]}),
      start()
      |> ignore(string("//"))
      |> integer(min: 1)
      |> eoterm2()
      |> post_traverse({:token, [:dual_cidr6]})
    ])
  end

  # when used, this always produces a qualifier token; defaults to '+'
  def qualifier() do
    start()
    |> ascii_char([?+, ?-, ?~, ??])
    |> optional()
    |> post_traverse({:token, [:qualifier]})
  end

  def qualifier(combinator),
    do: concat(combinator, qualifier())

  # DIRECTIVES

  # def version() do
  #   anycase("v=spf")
  #   |> ignore()
  #   |> integer(min: 1)
  #   |> post_traverse({:token, [:version]})
  # end

  def start() do
    empty()
    |> post_traverse({:mark_start, []})
  end

  def start(combinator),
    do: concat(combinator, start())

  def version() do
    start()
    |> ignore(anycase("v=spf"))
    |> integer(min: 1)
    |> post_traverse({:token, [:version]})
  end

  def all() do
    qualifier()
    |> ignore(anycase("all"))
    |> post_traverse({:token, [:all]})
  end

  def include() do
    start()
    |> qualifier()
    |> ignore(anycase("include:"))
    |> macro()
    |> pre_traverse({:token, [:include]})
  end

  def ip4() do
    start()
    |> qualifier()
    |> ignore(anycase("ip4:"))
    |> nonspaces()
    |> post_traverse({:token, [:ip4]})
  end

  def ip6() do
    start()
    |> qualifier()
    |> ignore(anycase("ip6:"))
    |> nonspaces()
    |> post_traverse({:token, [:ip6]})
  end

  def a() do
    start()
    |> qualifier()
    |> ignore(anycase("a"))
    |> optional(ignore(ascii_char([?:])) |> macro())
    |> optional(dual_cidr())
    |> post_traverse({:token, [:a]})
  end

  def mx() do
    start()
    |> qualifier()
    |> ignore(anycase("mx"))
    |> optional(ignore(ascii_char([?:])) |> macro())
    |> optional(dual_cidr())
    |> post_traverse({:token, [:mx]})
  end

  def exists() do
    start()
    |> qualifier()
    |> ignore(anycase("exists:"))
    |> macro()
    |> post_traverse({:token, [:exists]})
  end

  def ptr() do
    start()
    |> qualifier()
    |> ignore(anycase("ptr"))
    |> optional(ignore(ascii_char([?:])) |> macro())
    |> post_traverse({:token, [:ptr]})
  end

  # MODIFIERS
  def redirect() do
    start()
    |> ignore(anycase("redirect="))
    |> macro()
    |> post_traverse({:token, [:redirect]})
  end

  def explanation() do
    start()
    |> ignore(anycase("exp="))
    |> macro()
    |> post_traverse({:token, [:exp]})
  end

  # MACROS

  def m_delimiter(),
    do: ascii_char([?., ?-, ?+, ?,, ?/, ?_, ?=])

  def m_letter(),
    do:
      ascii_char(
        [?s, ?l, ?o, ?d, ?i, ?p, ?h, ?c, ?r, ?t, ?v] ++
          [?S, ?L, ?O, ?D, ?I, ?P, ?H, ?C, ?R, ?T, ?V]
      )

  def m_letter(combinator),
    do: concat(combinator, m_letter())

  def m_literal(),
    do: ascii_char([0x21..0x24, 0x26..0x7E])

  def m_literal(combinator),
    do: concat(combinator, m_literal())

  # a macro-expand without a transform will have a :transform token with
  # an empty list as token value; otherwise
  def m_transform() do
    times(digit(), min: 0)
    |> optional(ascii_char([?r]))
    |> post_traverse({:token, [:transform]})
  end

  def m_transform(combinator),
    do: concat(combinator, m_transform())

  def m_expand() do
    choice([
      m_expand1(),
      m_expand2()
    ])
  end

  def m_expand1 do
    ignore(string("%{"))
    |> m_letter()
    |> m_transform()
    |> repeat(m_delimiter())
    |> ignore(string("}"))
    |> post_traverse({:token, [:expand1]})
  end

  def m_expand2() do
    ignore(ascii_char([?%]))
    |> ascii_char([?%, ?-, ?_])
    |> reduce({List, :first, []})
    |> post_traverse({:token, [:expand2]})
  end

  def m_literals() do
    lookahead_not(dual_cidr())
    |> m_literal()
    |> times(min: 1)
    |> reduce({List, :to_string, []})
    |> post_traverse({:token, [:literal]})
  end

  def m_literals(combinator),
    do: concat(combinator, m_literals())

  def macro() do
    choice([
      m_expand(),
      m_literals()
    ])
    |> times(min: 1)
    |> post_traverse({:token, [:domain_spec]})
  end

  def macro(combinator) do
    concat(combinator, macro())
  end
end
