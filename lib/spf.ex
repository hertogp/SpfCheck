defmodule Spf do
  @moduledoc """
  Check SPF for a specific `sender` and possible options.

  The `Spf.check/2` function takes a sender and possible options and returns an
  evaluation [`context`](`t:Spf.Context.t/0`) that contains the verdict and
  some statistics of the evaluation.

  ## Example

      iex> unless File.dir?("tmp"), do: File.mkdir("tmp")
      iex> File.write("tmp/zone.txt", \"""
      ...> example.com TXT v=spf1 -all exp=why.%{d}
      ...> why.example.com TXT %{d}: %{i} is not one of our MTA's
      ...> \""")
      :ok
      iex> ctx = Spf.check("example.com", dns: "tmp/zone.txt")
      iex> {ctx.verdict, ctx.reason, ctx.explanation}
      {:fail, "spf[0] -all", "example.com: 127.0.0.1 is not one of our MTA's"}

  """
  @doc """
  Check SPF for given `sender` and possible options.

  Options include:
  - `:dns` filepath or zonedata to pre-populate the context's DNS cache
  - `:helo` the helo presented by sending MTA, defaults to `sender`
  - `:ip` ipv4 or ipv6 address, in binary, of sending MTA, defaults to `127.0.0.1`
  - `:log` a user log/4 function to relay notifications, defaults to `nil`
  - `:verbosity` how verbose the notifications should be (0..5), defaults to `3`
  - `:nameserver` an IPv4 or IPv6 address to use as recursive nameserver

  The keyword list may contain multiple entries of the `:nameserver` option, in
  which case they will be tried in the order listed.

  The user supplied callback `log/4` is called with:
  - `context`, the current evaluation context
  - `facility`, an atom denoting which part of Spf logged the message
  - `severity`, one of: `:error`, `:warn`, `:info`, `:debug`
  - `message`, the log message as a binary

  This is what `Spfcheck` uses to log information to stderr during an SPF
  evaluation.

  This function returns the evaluation context.

  ## Examples

      iex> zone = \"""
      ...> example.com TXT v=spf1 +all
      ...> \"""
      iex> Spf.check("example.com", dns: zone) |> Map.get(:verdict)
      :pass

  """
  @spec check(binary, Keyword.t()) :: Spf.Context.t()
  def check(sender, opts \\ []) do
    Spf.Context.new(sender, opts)
    |> Spf.Eval.evaluate()
    |> add_owner()
  end

  @spec add_owner(Spf.Context.t()) :: Spf.Context.t()
  defp add_owner(ctx) do
    {owner, email} =
      case Spf.DNS.authority(ctx, ctx.domain) do
        {:ok, _, owner, email} -> {owner, email}
        {:error, reason} -> {"DNS error", "#{reason}"}
      end

    Map.put(ctx, :owner, owner)
    |> Map.put(:contact, email)
  end
end
