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

entity tb_deflate is
  generic (
    runner_cfg           : string;
    filename             : string;
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
  signal sl_finish_out : std_logic := '0';
  signal sl_rdy : std_logic := '0';

  shared variable data_src : integer_array_t;

  signal data_check_done, stimuli_done : boolean := false;

  signal int_output_count : integer := 0;

begin
  dut : entity png_lib.deflate
  generic map (
    C_INPUT_BUFFER_SIZE  => C_INPUT_BUFFER_SIZE,
    C_SEARCH_BUFFER_SIZE => C_SEARCH_BUFFER_SIZE,
    C_BTYPE              => C_BTYPE
  )
  port map (
    isl_clk     => sl_clk,
    isl_flush   => sl_flush,
    isl_valid   => sl_valid_in,
    islv_data   => slv_data_in,
    oslv_data   => slv_data_out,
    osl_valid   => sl_valid_out,
    osl_finish  => sl_finish_out
  );
  
  clk_gen(sl_clk, 10 ns);

  main: process
  begin
    test_runner_setup(runner, runner_cfg);
    set_stop_level(failure);
    data_src := load_csv(tb_path(runner_cfg) & "gen/" & filename & ".csv");

    wait until (stimuli_done and
                data_check_done and
                rising_edge(sl_clk));
    test_runner_cleanup(runner);
    wait;
  end process;

  proc_stimuli : process
  begin
    wait until rising_edge(sl_clk);
    for i in 0 to width(data_src) - 1 loop
      while sl_rdy = '0' loop
        sl_valid_in <= '0';
        wait until rising_edge(sl_clk);
      end loop;
      report "### input: " & integer'image(i);
      sl_valid_in <= '1';
      slv_data_in <= std_logic_vector(to_unsigned(get(data_src, i, 0), slv_data_in'length));
      wait until rising_edge(sl_clk);
    end loop;
    sl_valid_in <= '0';
    wait until rising_edge(sl_clk);

    -- flush the buffer at the end
    sl_flush <= '1';
    wait until rising_edge(sl_clk);
    sl_flush <= '0';

    stimuli_done <= true;
    wait;
  end process;

  proc_output_data : process
  begin
    wait until rising_edge(sl_clk);
    data_check_done <= false;

    while sl_finish_out = '0' loop
      wait until rising_edge(sl_clk);
      if sl_valid_out = '1' then
        int_output_count <= int_output_count + 1;
      end if;
    end loop;
    
    report "input bytes: " & integer'image(width(data_src));
    report "output bytes: " & integer'image(int_output_count);
    report "compression ratio: " & real'image(real(width(data_src)) / real(int_output_count));
    
    report ("Done checking");
    data_check_done <= true;
    wait;
  end process;
end;
