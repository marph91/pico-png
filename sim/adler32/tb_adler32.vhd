library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library png_lib;

library util;
use util.math_pkg.all;

library sim;
use sim.vunit_common_pkg.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_adler32 is
  generic (
    runner_cfg       : string;
    id               : string;
    C_INPUT_BITWIDTH : integer
  );
end entity;

architecture tb of tb_adler32 is
  signal sl_clk : std_logic := '0';
  signal sl_start : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_INPUT_BITWIDTH-1 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(31 downto 0) := (others => '0');

  shared variable data_src : integer_array_t;
  shared variable data_ref : integer_array_t;

  signal data_check_done, stimuli_done : boolean := false;

begin
  dut : entity png_lib.adler32
  generic map (
    C_INPUT_BITWIDTH => C_INPUT_BITWIDTH
  )
  port map (
    isl_clk     => sl_clk,
    isl_start   => sl_start,
    isl_valid   => sl_valid_in,
    islv_data   => slv_data_in,
    oslv_data   => slv_data_out
  );
  
  clk_gen(sl_clk, 10 ns);

  main: process
  begin
    test_runner_setup(runner, runner_cfg);
    set_stop_level(failure);
    data_src := load_csv(tb_path(runner_cfg) & "gen/input_" & id & ".csv");
    data_ref := load_csv(tb_path(runner_cfg) & "gen/output_" & id & ".csv");

    wait until (stimuli_done and
                data_check_done and
                rising_edge(sl_clk));
    test_runner_cleanup(runner);
    wait;
  end process;

  proc_stimuli: process
  begin
    wait until rising_edge(sl_clk);
    sl_start <= '1';
    wait until rising_edge(sl_clk);
    sl_start <= '0';
    wait until rising_edge(sl_clk);

    for i in 0 to width(data_src)-1 loop
      wait until rising_edge(sl_clk);
      sl_valid_in <= '1';
      slv_data_in <= std_logic_vector(to_signed(get(data_src, i, 0), slv_data_in'length));
      wait until rising_edge(sl_clk);
      sl_valid_in <= '0';
    end loop;

    stimuli_done <= true;
    wait;
  end process;

  proc_data_check: process
  begin
    wait until rising_edge(sl_clk);
    data_check_done <= false;

    wait until rising_edge(sl_clk) and stimuli_done;
    check_equal(slv_data_out, std_logic_vector(to_signed(get(data_ref, 0, 0), slv_data_out'length)));
    
    report ("Done checking");
    data_check_done <= true;
    wait;
  end process;
end;