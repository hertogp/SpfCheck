defmodule Spfcheck do
  @external_resource "README.md"
  @moduledoc File.read!("README.md")
             |> String.split("<!-- @MODULEDOC -->")
             |> Enum.fetch!(1)
  alias Spf
  alias Spf.Context
  alias IO.ANSI

  @options [
    color: :boolean,
    dns: :string,
    helo: :string,
    help: :boolean,
    ip: :string,
    verbosity: :integer
  ]

  @aliases [
    H: :help,
    c: :color,
    d: :dns,
    h: :helo,
    i: :ip,
    v: :verbosity
  ]

  @verbosity %{
    :quiet => 0,
    :error => 1,
    :warn => 2,
    :note => 3,
    :info => 4,
    :debug => 5
  }

  @csv_fields [
    :domain,
    :ip,
    :sender,
    :verdict,
    :reason,
    :explanation,
    :num_spf,
    :num_dnsm,
    :num_dnsq,
    :num_dnsv,
    :num_checks,
    :num_warn,
    :num_error,
    :duration
  ]

  # Helpers

  defp color(type, width) do
    padded = String.pad_leading("#{type}", width)

    iodata =
      case type do
        :error -> ANSI.format([:red_background, :white, padded])
        :warn -> ANSI.format([:light_yellow, padded])
        :note -> ANSI.format([:green, padded])
        :debug -> ANSI.format([:light_blue, padded])
        _ -> padded
      end

    IO.iodata_to_binary(iodata)
  end

  # Log callback

  def log(ctx, facility, severity, msg) do
    if @verbosity[severity] <= ctx.verbosity do
      nth = String.pad_leading("#{ctx.nth}", 2)
      facility = String.pad_trailing("#{facility}", 5)
      severity = color(severity, 5)
      depth = String.duplicate("| ", ctx.depth)
      lead = "[spf #{nth}][#{facility}][#{severity}] #{depth}"
      IO.puts(:stderr, "#{lead}> #{msg}")
    end
  end

  # MAIN

  @doc """
  Check spf for given ip, sender and domain.
  """
  def main(argv) do
    {parsed, senders, _invalid} = OptionParser.parse(argv, aliases: @aliases, strict: @options)

    if Keyword.get(parsed, :help, false), do: usage()

    if Keyword.get(parsed, :color, true),
      do: Application.put_env(:elixir, :ansi_enabled, true),
      else: Application.put_env(:elixir, :ansi_enabled, false)

    parsed = Keyword.put(parsed, :log, &log/4)

    if [] == senders,
      do: do_stdin(parsed)

    for sender <- senders do
      Spf.check(sender, parsed)
      |> report(0)
      |> report(1)
      |> report(2)
      |> report(3)
      |> report(4)
      |> report(5)
      |> report(6)
      |> report(7)
    end
  end

  defp do_stdin(parsed) do
    IO.puts(Enum.join(@csv_fields, ","))

    IO.stream()
    |> Enum.each(&do_stdin(parsed, String.trim(&1)))
  end

  # skip comments and empty lines
  defp do_stdin(_parsed, "#" <> _comment), do: nil
  defp do_stdin(_parsed, ""), do: nil

  defp do_stdin(opts, line) do
    argv = String.split(line, ~r/\s+/, trim: true)
    {parsed, domains, _invalid} = OptionParser.parse(argv, aliases: @aliases, strict: @options)
    opts = Keyword.merge(opts, parsed)

    for domain <- domains do
      Spf.check(domain, opts)
      |> csv_result()
    end
  end

  defp csv_result(ctx) do
    Enum.map(@csv_fields, fn field -> "#{inspect(ctx[field])}" end)
    |> Enum.join(",")
    |> IO.puts()
  end

  # Report result
  defp report(ctx, 0) do
    meta = """
    ---
    title: SPF report on #{ctx.domain}.
    author: spfcheck
    date: #{DateTime.utc_now() |> Calendar.strftime("%c")}
    ...
    """

    IO.puts(meta)

    IO.puts("\n# Verdict\n")

    IO.puts("```")

    Enum.map(@csv_fields, fn field -> {"#{field}", "#{ctx[field]}"} end)
    |> Enum.map(fn {k, v} -> {String.pad_trailing(k, 11, " "), v} end)
    |> Enum.map(fn {k, v} -> IO.puts("#{k}: #{v}") end)

    IO.puts("```")
    ctx
  end

  # Report Spf's
  defp report(ctx, 1) do
    IO.puts("\n## SPF records seen\n")
    nths = Map.keys(ctx.map) |> Enum.filter(fn x -> is_integer(x) end) |> Enum.sort()

    IO.puts("```")

    for nth <- nths do
      domain = ctx.map[nth]

      spf = Context.get_spf(ctx, domain)
      IO.puts("[#{nth}] #{domain}")
      IO.puts("    #{spf}")
    end

    IO.puts("```")

    ctx
  end

  # Report warnings
  defp report(ctx, 2) do
    warnings =
      ctx.msg
      |> Enum.filter(fn t -> elem(t, 2) == :warn end)
      |> Enum.reverse()

    IO.puts("\n## Warnings\n")

    case warnings do
      [] ->
        IO.puts("None.")

      msgs ->
        IO.puts("```")

        Enum.map(msgs, fn {nth, facility, severity, msg} ->
          IO.puts("spf [#{nth}] %#{facility}-#{severity}: #{msg}")
        end)

        IO.puts("```")
    end

    ctx
  end

  # Report errors
  defp report(ctx, 3) do
    errors =
      ctx.msg
      |> Enum.filter(fn t -> elem(t, 2) == :error end)
      |> Enum.reverse()

    IO.puts("\n## Errors\n")

    case errors do
      [] ->
        IO.puts("None.")

      msgs ->
        IO.puts("```")

        Enum.map(msgs, fn {nth, facility, severity, msg} ->
          IO.puts("spf [#{nth}] %#{facility}-#{severity}: #{msg}")
        end)

        IO.puts("```")
    end

    ctx
  end

  # Report Prefixes
  defp report(ctx, 4) do
    IO.puts("\n## Prefixes\n")
    wseen = 5
    wpfx = 35
    indent = "    "

    spfs =
      for n <- 0..ctx.num_spf do
        {n, Context.get_spf(ctx, n)}
      end
      |> Enum.into(%{})

    IO.puts("#{indent} #Seen #{String.pad_trailing("Prefixes", wpfx)} Source(s)")

    for {ip, v} <- Iptrie.to_list(ctx.ipt) do
      seen = String.pad_trailing("#{length(v)}", wseen)
      pfx = "#{ip}" |> String.pad_trailing(wpfx)

      terms =
        for {_q, nth, {_, _, slice}} <- v do
          "spf[#{nth}] " <> String.slice(Map.get(spfs, nth, ""), slice)
        end
        |> Enum.sort()
        |> Enum.join(", ")

      IO.puts("#{indent} #{seen} #{pfx} #{terms}")
    end

    ctx
  end

  # Report DNS
  defp report(ctx, 5) do
    IO.puts("\n## DNS\n")

    IO.puts("```")

    Spf.DNS.to_list(ctx)
    |> Enum.join("\n")
    |> IO.puts()

    IO.puts("```")

    errors = Spf.DNS.to_list(ctx, valid: false)

    if length(errors) > 0 do
      IO.puts("\n## DNS issues\n")
      IO.puts("```")

      Enum.join(errors, "\n")
      |> IO.puts()

      IO.puts("```")
    end

    ctx
  end

  # Report AST
  defp report(ctx, 6) do
    IO.puts("\n## AST\n")

    IO.puts("```")

    ctx.ast
    |> Enum.map(fn x -> inspect(x) end)
    |> Enum.join("\n")
    |> IO.puts()

    IO.puts("```")
    IO.puts("\nexplain: #{inspect(ctx.explain)}")
    ctx
  end

  defp report(ctx, 7) do
    IO.puts("\n## TOKENS\n")

    IO.puts("```")

    ctx.spf_tokens
    |> Enum.map(fn x -> inspect(x) end)
    |> Enum.join("\n")
    |> IO.puts()

    IO.puts("```")
    ctx
  end

  def usage() do
    """

    Usage: spfcheck [options] sender

    where sender = [localpart@]domain and localpart defaults to 'postmaster'

    Options:
     -H, --help           print this message and exit
     -c, --color          use colored output (--no-color to set this to false)
     -d, --dns=filepath   file with DNS RR records to override live DNS
     -h, --helo=string    sending MTA's helo/ehlo identity (defaults to nil)
     -i, --ip=string      sending MTA's IPv4/IPv6 address (defaults to 127.0.0.1)
     -v, --verbosity      set logging noise level (0..5)

    Examples:

      spfcheck example.com
      spfcheck  -i 1.1.1.1   --helo example.net xyz@example.com
      spfcheck --ip=1.1.1.1 --sender=someone@example.com example.com -r ./dns.txt

    DNS RR override

      DNS queries are cached and the cache can be preloaded to override the
      live DNS with specific records.  Useful to try out SPF records before
      publishing them in DNS.  The `-r` option should point to a text file
      that contains 1 RR record per line specifying the name type and rdata
      all on 1 line.  Note that the file is not in BIND format and all RR's
      must be written in full and keys are taken relative to root (.)

      Example dns.txt
        example.com  TXT  v=spf1 a mx exists:%{i}.example.net ~all
        example.com  TXT  verification=asdfi234098sf
        127.0.0.1.example.net A  127.0.0.1

      Note that each line contains a single `name type rdata` combination, so
      for multiple TXT records (e.g.) specify each on its own line, like in
      the example above.  Lines that begin with '#' or *SP'#' are ignored


    Batch mode reads from stdin

      If no domains were listen on the commandline, the domains to check are
      read from stdin, including possible flags that will override the ones
      given on the cli itself.  Note that in this case, csv output is produced
      on stdout (other logging still goes to stderr, use -v 0 to silence that)

      Examples

       % cat domains.txt | spfcheck -v 0 -i 1.1.1.1
       % cat domains.tst
         example.com -s postmaster@example.com -i 127.0.0.1
         example.net -v 5

    """
    |> IO.puts()

    exit({:shutdown, 1})
  end
end
