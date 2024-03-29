library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library util;
  use util.huffman_pkg.all;
  use util.math_pkg.all;
  use util.png_pkg.all;

entity huffman is
  generic (
    C_BTYPE             : integer range 0 to 3 := 1;
    C_INPUT_BITWIDTH    : integer              := 17;
    C_MATCH_LENGTH_BITS : integer
  );
  port (
    isl_clk    : in    std_logic;
    isl_flush  : in    std_logic;
    isl_valid  : in    std_logic;
    islv_data  : in    std_logic_vector(C_INPUT_BITWIDTH - 1 downto 0);
    oslv_data  : out   std_logic_vector(7 downto 0);
    osl_valid  : out   std_logic;
    osl_finish : out   std_logic
  );
end entity huffman;

architecture behavioral of huffman is

  signal isl_valid_d1 : std_logic                         := '0';
  signal islv_data_d1 : std_logic_vector(islv_data'range) := (others => '0');
  signal sl_valid_out : std_logic                         := '0';
  signal slv_data_out : std_logic_vector(oslv_data'range) := (others => '0');

  signal sl_finish               : std_logic := '0';
  signal sl_flush                : std_logic := '0';
  signal sl_aggregation_finished : std_logic := '0';

  signal slv_current_value : std_logic_vector(islv_data'range) := (others => '0');

  type t_states is (IDLE, WAIT_FOR_INPUT, LITERAL_CODE, LENGTH_CODE, EXTRA_LENGTH_CODE, DISTANCE_CODE, EXTRA_DISTANCE_CODE, EOB, PAD, SEND_BYTES_FINAL);

  signal state : t_states := IDLE;

  type t_aggregator is record
    sl_valid_in   : std_logic;
    slv_data_in   : std_logic_vector(12 downto 0);
    int_bits      : integer range 1 to 13;
    sl_descending : std_logic;
  end record t_aggregator;

  signal aggregator : t_aggregator := ('0', (others => '0'), 1, '0');

  -- Maximum buffer size should be max. distance_bits + max. distance_extra_bits = 5 + 13.
  -- However, synthesis only works properly with power-of-two sizes.

  type t_buffer32 is record
    int_current_index : integer range 0 to 31;
    slv_data          : std_logic_vector(31 downto 0);
  end record t_buffer32;

  signal buffer32 : t_buffer32 := (0, (others => '0'));

begin

  -- TODO: BTYPE & BFINAL don't belong to huffman, but rather to deflate.
  -- Problem:
  -- BTYPE & BFINAL are prepended to all data blocks (compressed and uncompressed)
  -- LEN and NLEN are specific to C_BTYPE = 0

  -- RFC 1951, 3.2.6. Compression with fixed Huffman codes (BTYPE=01)
  proc_fixed_huffman : process (isl_clk) is

    variable v_huffman_code : t_huffman_code;

    variable v_int_match_length,
            v_int_match_distance : integer;

    variable v_int_buffer_index_tmp : integer range 0 to 7;

  begin

    if (rising_edge(isl_clk)) then
      -- defaults
      sl_finish                <= '0';
      aggregator.sl_valid_in   <= '0';
      aggregator.sl_descending <= '1';

      -- assert not (state /= WAIT_FOR_INPUT and isl_valid = '1') report "Data can't be received in state " & to_string(state);
      isl_valid_d1 <= isl_valid;
      islv_data_d1 <= islv_data;

      -- Preserve the flush impulse, since it might be not processed directly.
      if (isl_flush = '1') then
        sl_flush <= '1';
      end if;

      case state is

        when IDLE =>

          -- send everything in one block
          -- TODO: revisit all the reverting
          aggregator.sl_valid_in <= '1';
          aggregator.slv_data_in <= revert_vector(std_logic_vector(to_unsigned(C_BTYPE, 2)) & '1') & "0000000000";
          aggregator.int_bits    <= 3;
          -- 0 if revert_vector() is used
          aggregator.sl_descending <= '0';

          state <= WAIT_FOR_INPUT;

        when WAIT_FOR_INPUT =>

          if (isl_valid = '1') then
            if (islv_data(islv_data'high) = '0') then
              -- no match = literal/raw data
              state                   <= LITERAL_CODE;
              v_huffman_code.sl_match := '0';
            else
              -- match, following states:
              -- LENGTH_CODE -> EXTRA_LENGTH_CODE -> DISTANCE_CODE -> EXTRA_DISTANCE_CODE
              state                   <= LENGTH_CODE;
              v_huffman_code.sl_match := '1';
            end if;
            slv_current_value <= islv_data;
          elsif (isl_valid_d1 = '1') then
            if (islv_data_d1(islv_data_d1'high) = '0') then
              -- no match = literal/raw data
              state                   <= LITERAL_CODE;
              v_huffman_code.sl_match := '0';
            else
              -- match, following states:
              -- LENGTH_CODE -> EXTRA_LENGTH_CODE -> DISTANCE_CODE -> EXTRA_DISTANCE_CODE
              state                   <= LENGTH_CODE;
              v_huffman_code.sl_match := '1';
            end if;
            slv_current_value <= islv_data_d1;
          elsif (sl_flush = '1') then
            sl_flush <= '0';
            state    <= EOB;
          end if;

        when LITERAL_CODE =>

          v_huffman_code.lit := get_literal_code(to_integer(unsigned(slv_current_value(islv_data'high - 1 downto islv_data'high - 8))));

          report "input_value, buffer index, literal, literal huffman, huffman bits";
          report "LITERAL_CODE " &
                 to_string(slv_current_value) & " " &
                 to_string(buffer32.int_current_index) & " " &
                 to_string(to_integer(unsigned(slv_current_value(islv_data'high - 1 downto islv_data'high - 8)))) & " " &
                 to_string(v_huffman_code.lit.value) & " " &
                 to_string(v_huffman_code.lit.bits);

          aggregator.sl_valid_in <= '1';
          aggregator.slv_data_in <= std_logic_vector(to_unsigned(v_huffman_code.lit.value, 13));
          aggregator.int_bits    <= v_huffman_code.lit.bits;

          state <= WAIT_FOR_INPUT;

        when LENGTH_CODE =>

          v_int_match_length    := to_integer(unsigned(slv_current_value(C_MATCH_LENGTH_BITS - 1 downto 0)));
          v_huffman_code.length := get_length_code(v_int_match_length);

          report "input_value, buffer index, match length, match length huffman, huffman bits";
          report "LENGTH_CODE " &
                 to_string(slv_current_value) & " " &
                 to_string(buffer32.int_current_index) & " " &
                 to_string(v_int_match_length) & " " &
                 to_string(v_huffman_code.length.value) & " " &
                 to_string(v_huffman_code.length.bits);

          aggregator.sl_valid_in <= '1';
          aggregator.slv_data_in <= std_logic_vector(to_unsigned(v_huffman_code.length.value, 13));
          aggregator.int_bits    <= v_huffman_code.length.bits;

          state <= EXTRA_LENGTH_CODE;

        when EXTRA_LENGTH_CODE =>

          v_huffman_code.length_extra := get_length_extra_code(v_int_match_length);

          report "input_value, buffer index, match length, match length extra huffman, huffman bits";
          report "EXTRA_LENGTH_CODE " &
                 to_string(slv_current_value) & " " &
                 to_string(buffer32.int_current_index) & " " &
                 to_string(v_int_match_length) & " " &
                 to_string(v_huffman_code.length_extra.value) & " " &
                 to_string(v_huffman_code.length_extra.bits);

          if (v_huffman_code.length_extra.bits /= 0) then
            aggregator.sl_valid_in   <= '1';
            aggregator.slv_data_in   <= revert_vector(std_logic_vector(to_unsigned(v_huffman_code.length_extra.value, 13)));
            aggregator.int_bits      <= v_huffman_code.length_extra.bits;
            aggregator.sl_descending <= '0';
          end if;

          state <= DISTANCE_CODE;

        when DISTANCE_CODE =>

          v_int_match_distance    := to_integer(unsigned(slv_current_value(islv_data'high - 1 downto C_MATCH_LENGTH_BITS)));
          v_huffman_code.distance := get_distance_code(v_int_match_distance);

          report "input_value, buffer index, match distance, match distance huffman, huffman bits";
          report "DISTANCE_CODE " &
                 to_string(slv_current_value) & " " &
                 to_string(buffer32.int_current_index) & " " &
                 to_string(v_int_match_distance) & " " &
                 to_string(v_huffman_code.distance.value) & " " &
                 to_string(v_huffman_code.distance.bits);

          aggregator.sl_valid_in <= '1';
          aggregator.slv_data_in <= std_logic_vector(to_unsigned(v_huffman_code.distance.value, 13));
          aggregator.int_bits    <= v_huffman_code.distance.bits;

          state <= EXTRA_DISTANCE_CODE;

        when EXTRA_DISTANCE_CODE =>

          v_huffman_code.distance_extra := get_distance_extra_code(v_int_match_distance);

          report "input_value, buffer index, match distance, match distance extra huffman, huffman bits";
          report "EXTRA_DISTANCE_CODE " &
                 to_string(buffer32.int_current_index) & " " &
                 to_string(v_int_match_distance) & " " &
                 to_string(v_huffman_code.distance_extra.value) & " " &
                 to_string(v_huffman_code.distance_extra.bits);

          if (v_huffman_code.distance_extra.bits /= 0) then
            aggregator.sl_valid_in   <= '1';
            aggregator.slv_data_in   <= revert_vector(std_logic_vector(to_unsigned(v_huffman_code.distance_extra.value, 13)));
            aggregator.int_bits      <= v_huffman_code.distance_extra.bits;
            aggregator.sl_descending <= '0';
          end if;

          state <= WAIT_FOR_INPUT;

        when EOB =>

          -- append end of block -> eob is 7 bit zeros (256) -> zeros get appended anyway
          aggregator.sl_valid_in <= '1';
          aggregator.slv_data_in <= std_logic_vector(to_unsigned(0, 13));
          aggregator.int_bits    <= 7;

          state <= PAD;

        when PAD =>

          -- Current index of the buffer needs to be updated manually, since it
          -- gets the desired value only at the next cycle.
          v_int_buffer_index_tmp := (buffer32.int_current_index + 7) mod 8;
          if (v_int_buffer_index_tmp /= 0) then
            -- pad zeros (for full byte) at the end
            aggregator.sl_valid_in <= '1';
            aggregator.slv_data_in <= std_logic_vector(to_unsigned(0, 13));
            aggregator.int_bits    <= 8 - v_int_buffer_index_tmp;
          end if;

          state <= SEND_BYTES_FINAL;

        when SEND_BYTES_FINAL =>

          if (sl_aggregation_finished = '1') then
            sl_finish <= '1';
            state     <= IDLE;
          end if;

      end case;

    end if;

  end process proc_fixed_huffman;

  proc_aggregator : process (isl_clk) is

    -- only used to suppress a ghdl synthesis error
    -- TODO: extract a MWE and report the bug
    variable v_slv_data_out : std_logic_vector(oslv_data'range);

    variable v_int_current_index : integer range 0 to buffer32.slv_data'length - 1;

  begin

    if (rising_edge(isl_clk)) then
      sl_valid_out            <= '0';
      sl_aggregation_finished <= '0';

      -- Output of aggregator.
      v_int_current_index := buffer32.int_current_index;
      if (v_int_current_index >= 8) then
        sl_valid_out        <= '1';
        v_slv_data_out      := buffer32.slv_data(v_int_current_index - 1 downto v_int_current_index - 8);
        slv_data_out        <= revert_vector(v_slv_data_out);
        v_int_current_index := v_int_current_index - 8;
      elsif (state = SEND_BYTES_FINAL) then
        sl_aggregation_finished <= '1';
      end if;

      -- Input to aggregator.
      if (aggregator.sl_valid_in = '1') then
        v_int_current_index := v_int_current_index + aggregator.int_bits;

        -- shift the whole buffer
        for pos in buffer32.slv_data'range loop

          buffer32.slv_data(pos) <= buffer32.slv_data((pos - aggregator.int_bits) mod buffer32.slv_data'length);

        end loop;

        -- insert new values, maximum 13 (aggregator.int_bits)
        for pos in 0 to 12 loop

          exit when pos = aggregator.int_bits;

          if (aggregator.sl_descending = '1') then
            buffer32.slv_data(pos) <= aggregator.slv_data_in(pos);
          else
            -- After reverting the bits, the important bits are at the other end of the slv.
            -- I. e. starting at aggregator.slv_data_in'high, not 0.
            buffer32.slv_data(pos) <= aggregator.slv_data_in(aggregator.slv_data_in'high - aggregator.int_bits + pos + 1);
          end if;

        end loop;

      end if;

      buffer32.int_current_index <= v_int_current_index;
    end if;

  end process proc_aggregator;

  oslv_data  <= slv_data_out;
  osl_valid  <= sl_valid_out;
  osl_finish <= sl_finish;

end architecture behavioral;
