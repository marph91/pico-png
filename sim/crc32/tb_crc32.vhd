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

entity tb_crc32 is
  generic (
    runner_cfg       : string;
    id               : string;
    C_INPUT_BITWIDTH : integer;
    input_data       : string;
    reference_data   : integer
  );
end entity;

architecture tb of tb_crc32 is
  type t_slv_array is array(natural range <>) of std_logic_vector(C_INPUT_BITWIDTH-1 downto 0);
  
  -- Decode an slv array from a string. Separators are ", ".
  impure function decode_integer_array(encoded_integer_vector : string) return t_slv_array is
    variable parts : lines_t := split(encoded_integer_vector, ", ");
    variable return_value : t_slv_array(0 to parts'LENGTH-1);
  begin
    for i in parts'range loop
      return_value(i) := str_to_slv(parts(i).all);
    end loop;
    return return_value;
  end;
  
  -- Decode a slv from a string. Valid characters are only '0' and '1'.
  function str_to_slv(encoded_slv_string : string) return std_logic_vector is
    variable slv : std_logic_vector(encoded_slv_string'length-1 downto 0);
  begin
    for i in encoded_slv_string'range loop
      case encoded_slv_string(i) is
        when '0' =>
          slv(i-1) := '0';
        when '1' =>
          slv(i-1) := '1';
        when others =>
          slv(i-1) := 'U';
      end case;
    end loop;
    return slv;
  end function str_to_slv;

  signal sl_clk : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_INPUT_BITWIDTH-1 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(31 downto 0) := (others => '0');

  signal data_check_done, stimuli_done : boolean := false;

  constant C_INPUT_DATA : t_slv_array := decode_integer_array(input_data);
  constant C_REFERENCE_DATA : std_logic_vector(31 downto 0) := std_logic_vector(to_signed(reference_data, 32));

begin
  dut : entity png_lib.crc32
  generic map (
    C_INPUT_BITWIDTH => C_INPUT_BITWIDTH
  )
  port map (
    isl_clk     => sl_clk,
    isl_valid   => sl_valid_in,
    islv_data   => slv_data_in,
    oslv_data   => slv_data_out
  );
  
  clk_gen(sl_clk, 10 ns);

  main: process
  begin
    test_runner_setup(runner, runner_cfg);
    set_stop_level(failure);

    wait until (stimuli_done and
                data_check_done and
                rising_edge(sl_clk));
    test_runner_cleanup(runner);
    wait;
  end process;

  proc_stimuli: process
  begin
    wait until rising_edge(sl_clk);
    for i in 0 to C_INPUT_DATA'LENGTH-1 loop
      wait until rising_edge(sl_clk);
      sl_valid_in <= '1';
      slv_data_in <= C_INPUT_DATA(i);
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
    check_equal(slv_data_out, C_REFERENCE_DATA);

    wait until rising_edge(sl_clk);
    -- assert false;
    
    report ("Done checking");
    data_check_done <= true;
    wait;
  end process;
end;