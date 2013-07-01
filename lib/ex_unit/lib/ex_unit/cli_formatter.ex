defmodule ExUnit.CLIFormatter do
  @moduledoc """
  Formatter responsible for printing raw text
  on the CLI
  """

  @behaviour ExUnit.Formatter
  @timeout 30_000
  use GenServer.Behaviour


  import ExUnit.Formatter, only: [format_time: 2, format_test_failure: 4, format_test_case_failure: 4]

  defrecord Config, tests_counter: 0, invalid_counter: 0, test_failures: [], case_failures: []

  ## Behaviour

  def suite_started(_opts) do
    { :ok, pid } = :gen_server.start_link(__MODULE__, [], [])
    pid
  end

  def suite_finished(id, run_us, load_us) do
    :gen_server.call(id, { :suite_finished, run_us, load_us }, @timeout)
  end

  def case_started(id, test_case) do
    :gen_server.cast(id, { :case_started, test_case })
  end

  def case_finished(id, test_case) do
    :gen_server.cast(id, { :case_finished, test_case })
  end

  def test_started(id, test) do
    :gen_server.cast(id, { :test_started, test })
  end

  def test_finished(id, test) do
    :gen_server.cast(id, { :test_finished, test })
  end

  ## Callbacks

  def init(_args) do
    { :ok, Config.new }
  end

  def handle_call({ :suite_finished, run_us, load_us }, _from, config) do
    print_suite(config.tests_counter, config.invalid_counter, config.test_failures, config.case_failures, run_us, load_us)
    { :stop, :normal, length(config.test_failures), config }
  end

  def handle_call(reqest, from, config) do
    super(reqest, from, config)
  end

  def handle_cast({ :test_started, ExUnit.Test[name: name] }, config) do
    IO.write "    * #{name} "
    { :noreply, config }
  end

  def handle_cast({ :test_finished, ExUnit.Test[failure: nil] = test }, config) do
    IO.write success "\r    * #{test.name} \n"
    { :noreply, config.update_tests_counter(&1 + 1) }
  end

  def handle_cast({ :test_finished, ExUnit.Test[failure: { :invalid, _ }] = test }, config) do
    IO.write invalid "\r    * #{test.name} \n"
    { :noreply, config.update_tests_counter(&1 + 1).
        update_invalid_counter(&1 + 1) }
  end

  def handle_cast({ :test_finished, test }, config) do
    IO.write failure "\r    * #{test.name} \n"
    { :noreply, config.update_tests_counter(&1 + 1).
        update_test_failures([test|&1]) }
  end

  def handle_cast({ :case_started, ExUnit.TestCase[name: name] }, config) do
    IO.write "  #{name}\n"
    { :noreply, config }
  end

  def handle_cast({ :case_finished, test_case }, config) do
    IO.write "\n"
    if test_case.failure do
      { :noreply, config.update_case_failures([test_case|&1]) }
    else
      { :noreply, config }
    end
  end

  def handle_cast(request, config) do
    super(request, config)
  end

  defp print_suite(counter, 0, [], [], run_us, load_us) do
    IO.write "\n\n"
    IO.puts format_time(run_us, load_us)
    IO.puts success("#{counter} tests, 0 failures")
  end

  defp print_suite(counter, num_invalids, test_failures, case_failures, run_us, load_us) do
    IO.write "\n\nFailures:\n\n"

    num_fails = Enum.reduce Enum.reverse(test_failures), 0, print_test_failure(&1, &2, File.cwd!)
    Enum.reduce Enum.reverse(case_failures), num_fails, print_test_case_failure(&1, &2, File.cwd!)

    IO.puts format_time(run_us, load_us)
    message = "#{counter} tests, #{num_fails} failures"

    if num_invalids > 0 do
      message = message <>  ", #{num_invalids} invalid"
    end

    cond do
      num_fails > 0    -> IO.puts failure(message)
      num_invalids > 0 -> IO.puts invalid(message)
      true             -> IO.puts success(message)
    end
  end

  defp print_test_failure(test, acc, cwd) do
    IO.puts format_test_failure(test, acc + 1, cwd, function(formatter/2))
    acc + 1
  end

  defp print_test_case_failure(test_case, acc, cwd) do
    IO.puts format_test_case_failure(test_case, acc + 1, cwd, function(formatter/2))
    acc + 1
  end

  # Color styles

  defp colorize(escape, string) do
    IO.ANSI.escape_fragment("%{#{escape}}") <> string <> IO.ANSI.escape_fragment("%{reset}")
  end

  defp success(msg) do
    colorize("green", msg)
  end

  defp invalid(msg) do
    colorize("yellow", msg)
  end

  defp failure(msg) do
    colorize("red", msg)
  end

  defp formatter(:error_info, msg),    do: colorize("red", msg)
  defp formatter(:location_info, msg), do: colorize("cyan", msg)
  defp formatter(_,  msg),             do: msg
end
