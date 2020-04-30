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
use vunit_lib.array_pkg.all;

entity tb_deflate is
  generic (
    runner_cfg           : string;
    id                   : string;
    data_ref             : string;

    C_INPUT_BUFFER_SIZE  : integer;
    C_SEARCH_BUFFER_SIZE : integer;

    C_BTYPE              : integer
  );
end entity;

architecture tb of tb_deflate is
  signal sl_clk : std_logic := '0';
  signal sl_flush : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(7 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(7 downto 0) := (others => '0');
  signal int_valid_bits_out : integer;
  signal sl_rdy : std_logic := '0';

  shared variable data_src : array_t;

  signal data_check_done, stimuli_done : boolean := false;

begin
  dut : entity png_lib.deflate
  generic map (
    C_INPUT_BUFFER_SIZE => C_INPUT_BUFFER_SIZE,
    C_SEARCH_BUFFER_SIZE => C_SEARCH_BUFFER_SIZE,

    C_BTYPE => C_BTYPE
  )
  port map (
    isl_clk     => sl_clk,
    isl_flush   => sl_flush,
    isl_valid   => sl_valid_in,
    islv_data   => slv_data_in,
    oslv_data   => slv_data_out,
    osl_valid   => sl_valid_out,
    oint_valid_bits => int_valid_bits_out,
    osl_rdy     => sl_rdy
  );
  
  clk_gen(sl_clk, 10 ns);

  main: process
  begin
    test_runner_setup(runner, runner_cfg);
    set_stop_level(failure);
    data_src.load_csv(tb_path(runner_cfg) & "gen/input_" & id & ".csv");

    wait until (stimuli_done and
                data_check_done and
                rising_edge(sl_clk));
    test_runner_cleanup(runner);
    wait;
  end process;

  proc_stimuli: process
  begin
    wait until rising_edge(sl_clk);
    for i in 0 to data_src.width-1 loop
      wait until rising_edge(sl_clk) and sl_rdy = '1';
      sl_valid_in <= '1';
      slv_data_in <= std_logic_vector(to_unsigned(data_src.get(i, 0), slv_data_in'length));
      wait until rising_edge(sl_clk);
      sl_valid_in <= '0';
    end loop;

    -- flush the buffer at the end
    sl_flush <= '1';
    wait until rising_edge(sl_clk);
    sl_flush <= '0';

    stimuli_done <= true;
    wait;
  end process;

  proc_data_check: process
  begin
    wait until rising_edge(sl_clk);
    data_check_done <= false;

    -- TODO
    
    report ("Done checking");
    data_check_done <= true;
    wait;
  end process;
end;