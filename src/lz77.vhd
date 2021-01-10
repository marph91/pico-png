library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;
use util.math_pkg.all;

entity lz77 is
  generic (
    C_INPUT_BUFFER_SIZE  : integer range 3 to 258 := 10;
    C_SEARCH_BUFFER_SIZE : integer range 1 to 32768 := 12
  );
  port (
    isl_clk   : in std_logic;
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(7 downto 0);
    oslv_data : out std_logic_vector(16 + 7 downto 0);
    osl_valid : out std_logic;
    osl_rdy   : out std_logic
  );
end;

architecture behavioral of lz77 is
  constant C_MAX_MATCH_LENGTH : integer := min_int(C_INPUT_BUFFER_SIZE-1, 2**4-1);

  type t_slv_buffer is array(C_SEARCH_BUFFER_SIZE downto -C_INPUT_BUFFER_SIZE+1) of std_logic_vector(7 downto 0);
  signal a_buffer : t_slv_buffer := (others => (others => 'U'));

  type t_match is record
    int_offset     : integer range 0 to 2**12-1;
    int_length     : integer range 0 to 2**4-1;
    slv_next_datum : std_logic_vector(7 downto 0);
  end record t_match;
  signal rec_best_match : t_match := (0, 0, (others => '0'));

  type t_states is (IDLE, FILL, MATCH, OUTPUT_MATCH);
  signal state : t_states := IDLE;

  signal int_datums_to_fill : integer range 0 to C_INPUT_BUFFER_SIZE := 0;
  signal int_start_index : integer range 1 to C_SEARCH_BUFFER_SIZE := 0;
  signal sl_valid_out : std_logic := '0';

begin
  proc_lz77: process(isl_clk)
    variable v_int_match_length : integer range 1 to C_MAX_MATCH_LENGTH := 1;
    variable v_int_search_index : integer range 0 to C_SEARCH_BUFFER_SIZE := 0;
    variable v_sl_max_length : std_logic := '0';
  begin
    if rising_edge(isl_clk) then
      sl_valid_out <= '0';

      case state is
        when IDLE =>
          int_datums_to_fill <= C_INPUT_BUFFER_SIZE;
          state <= FILL;

        when FILL =>
          if isl_valid = '1' then
            int_datums_to_fill <= int_datums_to_fill - 1;
            a_buffer <= a_buffer(a_buffer'LEFT-1 downto a_buffer'RIGHT) & islv_data;
          end if;

          if int_datums_to_fill = 0 then
            state <= MATCH;
            rec_best_match <= (0, 0, a_buffer(0));
          end if;

        when MATCH =>
          -- find the index of the next matching element
          v_int_search_index := 0;
          for current_index in a_buffer'HIGH downto 1 loop
            if a_buffer(current_index) = a_buffer(0) and current_index >= int_start_index then
              v_int_search_index := current_index;
            end if;
          end loop;

          -- get the length of the match if a matching element was found
          if v_int_search_index /= 0 then
            v_int_match_length := 1;
            v_sl_max_length := '0';
            for current_index in 1 to C_MAX_MATCH_LENGTH-1 loop
              if a_buffer(v_int_search_index - current_index) = a_buffer(-current_index) and
                 v_sl_max_length = '0' then
                v_int_match_length := v_int_match_length+1;
              else
                v_sl_max_length := '1';
              end if;
            end loop;

            -- check whether this match is better (=longer) than the current best match
            if v_int_match_length > rec_best_match.int_length then
              rec_best_match <= (v_int_search_index, v_int_match_length, a_buffer(-v_int_match_length));
            end if;
          end if;

          -- increment or change state if the whole buffer was inspected
          if v_int_search_index /= C_SEARCH_BUFFER_SIZE and v_int_search_index /= 0 and v_int_match_length < C_MAX_MATCH_LENGTH then
            int_start_index <= v_int_search_index+1;
          else
            state <= OUTPUT_MATCH;
          end if;

        when OUTPUT_MATCH =>
          int_start_index <= 1;
          int_datums_to_fill <= rec_best_match.int_length + 1;
          state <= FILL;
          sl_valid_out <= '1';

      end case;
    end if;
  end process;

  oslv_data <= std_logic_vector(to_unsigned(rec_best_match.int_length, 4)) &
               std_logic_vector(to_unsigned(rec_best_match.int_offset, 12)) &
               rec_best_match.slv_next_datum;
  osl_valid <= sl_valid_out;
  osl_rdy <= '1' when int_datums_to_fill /= 0 else '0';
end behavioral;