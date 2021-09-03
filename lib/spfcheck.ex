defmodule Spfcheck do
  @external_resource "README.md"
  @moduledoc File.read!("README.md")
             |> String.split("<!-- @MODULEDOC -->")
             |> Enum.fetch!(1)
  alias Spf
  alias IO.ANSI

  @options [
    # <ip> which defaults to 127.0.0.1
    ip: :string,
    # <sender> which defaults to me@host.local
    sender: :string,
    # 0 error, 1 warn, 2 note, 3 info, 4 debug
    verbosity: :integer,
    # local dns RRs -> <name> SP <type> SP <value>
    dns: :string,
    # read args from input file, 1 invocation per line
    batch: :string,
    # use csv output -> uses predefined columns:
    # domain, ip, sender, verdict, reason, explanantion, term, spf
    # csv: :boolean,
    help: :boolean,
    # use color, defaults to true
    nocolor: :boolean,
    # 0 short, 1 medium or 2 long
    report: :integer
  ]

  @aliases [
    i: :ip,
    s: :sender,
    v: :verbosity,
    h: :help,
    d: :dns,
    n: :nocolor,
    r: :report,
    b: :batch
  ]

  @verbosity %{
    :error => 0,
    :warn => 1,
    :note => 2,
    :info => 3,
    :debug => 4
  }

  @report %{
    0 => :short,
    1 => :medium,
    2 => :long
  }

  # Helpers

  defp color(type, width) do
    padded = String.pad_leading("#{type}", width)

    iodata =
      case type do
        :error -> ANSI.format([:red_background, :white, padded])
        :warn -> ANSI.format([:yellow, padded])
        :note -> ANSI.format([:green, padded])
        :debug -> ANSI.format([:white_background, :red, padded])
        _ -> padded
      end

    IO.iodata_to_binary(iodata)
  end

  defp loglead(nth, type, depth) do
    nth = String.pad_leading("#{nth}", 2)
    type = color(type, 5)
    depth = String.duplicate("| ", depth)
    "[spf #{nth}][#{type}] #{depth}"
  end

  def usage() do
    """

    Usage: spfcheck [options] domain

    Options:
     -b, --batch=string   file with list of domains to check
     -d, --dns            file with DNS records to preload the DNS cache
     -h, --help           prints this message and exits
     -i, --ip=string      specify sender's <ip> to check (default 127.0.0.1)
     -n, --nocolor        suppress colors in terminal output
     -r, --report=int     reporting level 0..2 (default 1)
     -s, --sender=string  specify sender from address (default me@host.local)
     -v, --verbosity=int  noise level 0..4 (default 2)

    Batch processing

      spfcheck can take the domains to test from a text file that contains
      one domain test per line.  Options can be specified as well.  E.g.

      Example domains.txt:
        example.com -i 1.1.1.1
        example.com -i 2.2.2.2 -s me@example.com
        ...

    DNS preload

      DNS queries are cached and the cache can be preloaded to override the
      live DNS with specific records.  Useful to try out SPF records before
      publishing them in DNS.  The -d options should point to a text file
      that contains 1 record per line specifying the key, type and value
      all on 1 line.

      Example dns.txt
        example.com  txt  v=spf1 a mx ~all


    Examples:

      spfcheck example.com
      spfcheck -i 1.1.1.1 -s someone@example.com example.com
      spfcheck --ip=1.1.1.1 --sender=someone@example.com example.com
      spfcheck -b ./domains.txt

    """
  end

  # Log callback

  def log(ctx, {type, msg}) do
    if @verbosity[type] <= ctx.verbosity do
      lead = loglead(ctx.nth, type, ctx.depth)
      IO.puts(:stderr, "#{lead} #{msg}")
    end
  end

  def log(ctx, {type, {_token, _tokval, range}, msg}) do
    if @verbosity[type] <= ctx.verbosity do
      tokstr = String.slice(ctx[:spf], range)
      lead = loglead(ctx.nth, type, ctx.depth)
      IO.puts(:stderr, "#{lead}> #{tokstr} - #{msg}")
    end
  end

  # MAIN

  @doc """
  Check spf for given ip, sender and domain.
  """
  def main(argv) do
    {parsed, domains, _invalid} = OptionParser.parse(argv, aliases: @aliases, strict: @options)

    unless Keyword.get(parsed, :nocolor, false),
      do: Application.put_env(:elixir, :ansi_enabled, true)

    IO.inspect({parsed, domains}, label: :cli)

    if Keyword.get(parsed, :help, false) do
      IO.puts(usage())
      exit({:shutdown, 1})
    end

    for domain <- domains do
      IO.puts("\nspfcheck on #{domain}, opts #{inspect(parsed)}")
      parsed = [log: &log/2] ++ parsed
      {verdict, explain, term} = Spf.check(domain, parsed)

      exp = if explain != "", do: " (#{explain})", else: ""
      term = if term, do: ", match by #{inspect(term)}", else: ", nothing matched"
      IO.puts("#{verdict}#{exp}#{term}")
    end
  end
end
