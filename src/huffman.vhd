library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library util;
  use util.math_pkg.all;
  use util.png_pkg.all;

entity huffman is
  generic (
    C_BTYPE    : integer range 0 to 3 := 1;
    C_BITWIDTH : integer              := 17
  );
  port (
    isl_clk    : in    std_logic;
    isl_flush  : in    std_logic;
    isl_valid  : in    std_logic;
    islv_data  : in    std_logic_vector(C_BITWIDTH - 1 downto 0);
    oslv_data  : out   std_logic_vector(7 downto 0);
    osl_valid  : out   std_logic;
    osl_finish : out   std_logic;
    osl_rdy    : out   std_logic
  );
end entity huffman;

architecture behavioral of huffman is

  -- constant C_MAX_DATA_LENGTH : integer := 16; -- TODO: up to 2^16

  type t_buffer64 is record
    int_current_index    : integer range 0 to 63;
    int_current_index_d1 : integer range 0 to 63;
    slv_data             : std_logic_vector(63 downto 0);
  end record;

  signal buffer64 : t_buffer64 := (0, 0, (others => '0'));

  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(7 downto 0) := (others => '0');

  signal slv_block_data          : std_logic_vector(71 downto 0) := (others => '0');
  signal int_block_bytes_to_send : integer range 0 to 16 := 0; -- TODO: range can be bigger

  signal sl_finish                          : std_logic := '0';
  signal sl_bfinal                          : std_logic := '0';
  signal sl_flush, sl_flush_increment_index : std_logic := '0';

  signal slv_current_value : std_logic_vector(C_BITWIDTH - 1 downto 0) := (others => '0');

  type t_states is (IDLE, WAIT_FOR_INPUT, LITERAL_CODE, LENGTH_CODE, EXTRA_LENGTH_BITS, DISTANCE_CODE, EXTRA_DISTANCE_BITS, SEND_BYTES);

  signal state : t_states := IDLE;

  type t_barrel_shifter is record
    sl_valid_in   : std_logic;
    slv_data_in   : std_logic_vector(12 downto 0);
    int_bits      : integer range 1 to 13;
    sl_descending : std_logic;
  end record;

  signal barrel_shifter : t_barrel_shifter := ('0', (others => '0'), 1, '0');

begin

  -- TODO: BTYPE & BFINAL don't belong to huffman, but rather to deflate.
  -- Problem:
  -- BTYPE & BFINAL are prepended to all data blocks (compressed and uncompressed)
  -- LEN and NLEN are specific to C_BTYPE = 0

  gen_huffman : if C_BTYPE = 0 generate
    -- 3.2.4. Non-compressed blocks (BTYPE=00)
    -- no huffman encoding
    -- 2 byte LEN, 2 byte NLEN, X bits DATA

    proc_assemble_32_bit : process (isl_clk) is
    begin

      if (rising_edge(isl_clk)) then
        if (isl_valid = '1') then
          buffer64.slv_data(63 - buffer64.int_current_index downto 63 - buffer64.int_current_index - C_BITWIDTH + 1) <=
                                                                                                                        islv_data(islv_data'HIGH downto islv_data'HIGH - C_BITWIDTH + 1);
          buffer64.int_current_index                                                                                 <= buffer64.int_current_index + C_BITWIDTH;
        elsif (buffer64.int_current_index >= 32) then
          buffer64.slv_data          <= buffer64.slv_data(31 downto 0) & x"00000000";
          buffer64.int_current_index <= buffer64.int_current_index - 32;
        end if;
      end if;

    end process proc_assemble_32_bit;

    proc_no_encoding : process (isl_clk) is

      variable v_bfinal : std_logic;
      variable v_len    : std_logic_vector(15 downto 0);

    begin

      if (rising_edge(isl_clk)) then
        sl_finish <= '0';

        if (isl_valid = '0' and (buffer64.int_current_index >= 32 or (isl_flush = '1' and buffer64.int_current_index /= 0))) then
          if (buffer64.int_current_index <= 32 and isl_flush = '1') then
            v_bfinal := '1';
            sl_bfinal <= '1';
          else
            v_bfinal := '0';
          end if;

          if (buffer64.int_current_index >= 32) then
            v_len := std_logic_vector(to_unsigned(32 / 8, 16));
          else
            v_len := std_logic_vector(to_unsigned(buffer64.int_current_index / 8, 16));
          end if;

          -- block data composition:
          -- 5 bit: Any bits of input up to the next byte boundary are ignored.
          -- 3 bit: BTYPE & BFINAL
          -- 16 bit: LEN (MSByte second)
          -- 16 bit: NLEN (MSByte second)
          -- 32 bit: DATA
          slv_block_data          <= "00000" &
                                     std_logic_vector(to_unsigned(C_BTYPE, 2)) & v_bfinal &
                                     v_len(7 downto 0) & v_len(15 downto 8) &
                                     not v_len(7 downto 0) & not v_len(15 downto 8) &
                                     buffer64.slv_data(63 downto 32);
          int_block_bytes_to_send <= 5 + to_integer(unsigned(v_len));
          v_bfinal := '0';
        end if;

        if (int_block_bytes_to_send /= 0) then
          sl_valid_out            <= '1';
          int_block_bytes_to_send <= int_block_bytes_to_send - 1;
          slv_data_out            <= slv_block_data(slv_block_data'HIGH downto slv_block_data'HIGH - 7);
          slv_block_data          <= slv_block_data(slv_block_data'HIGH - 8 downto 0) & "00000000";
        else
          sl_valid_out <= '0';
          if (sl_bfinal = '1') then
            sl_finish <= '1';
            sl_bfinal <= '0';
          end if;
        end if;
      end if;

    end process proc_no_encoding;

    osl_rdy <= '1' when buffer64.int_current_index < 32 and int_block_bytes_to_send = 0 else
               '0';

  else generate
    -- https://www.ietf.org/rfc/rfc1951.txt
    -- 3.2.6. Compression with fixed Huffman codes (BTYPE=01)
    proc_fixed_huffman : process (isl_clk) is

      variable v_int_literal_value,
               v_int_match_length,
               v_int_bitwidth,
               v_int_code,
               v_int_start_value,
               v_int_match_distance : integer;
      -- only used to suppress a ghdl synthesis error
      -- TODO: extract a MWE and report the bug
      variable v_slv_data_out : std_logic_vector(7 downto 0);

    begin

      if (rising_edge(isl_clk)) then
        if (isl_flush = '1') then
          sl_bfinal                <= '1';
          sl_flush                 <= '1';
          sl_flush_increment_index <= '1';
        end if;

        barrel_shifter.sl_valid_in    <= '0';
        buffer64.int_current_index_d1 <= buffer64.int_current_index;                                                                    -- delay for barrel shifter

        case state is

          when IDLE =>
            sl_finish <= '0';

            -- send everything in one block
            -- TODO: revisit all the reverting
            barrel_shifter.sl_valid_in   <= '1';
            barrel_shifter.slv_data_in   <= revert_vector(std_logic_vector(to_unsigned(C_BTYPE, 2)) & '1') & "0000000000";
            barrel_shifter.int_bits      <= 3;
            barrel_shifter.sl_descending <= '0';                                                                                        -- 0 if revert_vector() is used
            buffer64.int_current_index   <= buffer64.int_current_index + 3;

            state <= WAIT_FOR_INPUT;

          when WAIT_FOR_INPUT =>
            if (isl_valid = '1') then
              if (islv_data(islv_data'HIGH) = '0') then
                -- no match = literal/raw data
                state <= LITERAL_CODE;
              else
                -- match, following states:
                -- LENGTH_CODE -> EXTRA_LENGTH_BITS -> DISTANCE_CODE -> EXTRA_DISTANCE_BITS
                state <= LENGTH_CODE;
              end if;
              slv_current_value <= islv_data;
            end if;

            if (sl_flush = '1') then
              state <= SEND_BYTES;
            end if;

          when LITERAL_CODE =>
            v_int_literal_value := to_integer(unsigned(
                                                       slv_current_value(islv_data'HIGH - 1 downto islv_data'HIGH - 8)));
            if (v_int_literal_value <= 143) then
              v_int_bitwidth := 8;
              v_int_code     := 48 + v_int_literal_value;
            else
              v_int_bitwidth := 9;
              v_int_code     := 256 + v_int_literal_value;
            end if;

            barrel_shifter.sl_valid_in   <= '1';
            barrel_shifter.slv_data_in   <= std_logic_vector(to_unsigned(v_int_code, 13));
            barrel_shifter.int_bits      <= v_int_bitwidth;
            barrel_shifter.sl_descending <= '1';
            buffer64.int_current_index   <= buffer64.int_current_index + v_int_bitwidth;

            state <= SEND_BYTES;

          when LENGTH_CODE =>
            v_int_match_length := to_integer(unsigned(
                                                      slv_current_value(3 downto 0)));
            if (v_int_match_length <= 10) then
              v_int_code := 254 + v_int_match_length;
            elsif (v_int_match_length <= 12) then
              v_int_code := 265;
            elsif (v_int_match_length <= 14) then
              v_int_code := 266;
            elsif (v_int_match_length <= 16) then
              v_int_code := 267;
            elsif (v_int_match_length <= 18) then
              v_int_code := 268;
            elsif (v_int_match_length <= 22) then
              v_int_code := 269;
            elsif (v_int_match_length <= 26) then
              v_int_code := 270;
            elsif (v_int_match_length <= 30) then
              v_int_code := 271;
            elsif (v_int_match_length <= 34) then
              v_int_code := 272;
            elsif (v_int_match_length <= 42) then
              v_int_code := 273;
            elsif (v_int_match_length <= 50) then
              v_int_code := 274;
            elsif (v_int_match_length <= 58) then
              v_int_code := 275;
            elsif (v_int_match_length <= 66) then
              v_int_code := 276;
            elsif (v_int_match_length <= 82) then
              v_int_code := 277;
            elsif (v_int_match_length <= 98) then
              v_int_code := 278;
            elsif (v_int_match_length <= 114) then
              v_int_code := 279;
            elsif (v_int_match_length <= 130) then
              v_int_code := 280;
            elsif (v_int_match_length <= 162) then
              v_int_code := 281;
            elsif (v_int_match_length <= 194) then
              v_int_code := 282;
            elsif (v_int_match_length <= 226) then
              v_int_code := 283;
            elsif (v_int_match_length <= 257) then
              v_int_code := 284;
            elsif (v_int_match_length = 258) then
              v_int_code := 285;
            else
              assert false report "invalid length" & to_string(v_int_match_length);
            end if;

            if (v_int_match_length <= 114) then
              v_int_bitwidth := 7;
            else
              v_int_bitwidth := 8;
            end if;

            report "LENGTH_CODE " & to_string(buffer64.int_current_index) & " " & to_string(v_int_code);

            barrel_shifter.sl_valid_in   <= '1';
            barrel_shifter.slv_data_in   <= std_logic_vector(to_unsigned(v_int_code, 13));
            barrel_shifter.int_bits      <= v_int_bitwidth;
            barrel_shifter.sl_descending <= '1';
            buffer64.int_current_index   <= buffer64.int_current_index + v_int_bitwidth;

            -- no extra bits for lengths <= 10
            -- will save one cycle in EXTRA_LENGTH_BITS
            if (v_int_match_length <= 10 or v_int_match_length = 285) then
              state <= DISTANCE_CODE;
            else
              state <= EXTRA_LENGTH_BITS;
            end if;

          when EXTRA_LENGTH_BITS =>
            if (v_int_match_length <= 18) then
              v_int_bitwidth    := 1;
              v_int_start_value := 11;
            elsif (v_int_match_length <= 34) then
              v_int_bitwidth    := 2;
              v_int_start_value := 19;
            elsif (v_int_match_length <= 66) then
              v_int_bitwidth    := 3;
              v_int_start_value := 35;
            elsif (v_int_match_length <= 130) then
              v_int_bitwidth    := 4;
              v_int_start_value := 67;
            elsif (v_int_match_length <= 257) then
              v_int_bitwidth    := 5;
              v_int_start_value := 131;
            else
              assert false report "invalid length" & to_string(v_int_match_length);
            end if;

            report "EXTRA_LENGTH_BITS " &
              to_string(buffer64.int_current_index) & " " &
              to_string(v_int_match_length) & " " &
              to_string(v_int_start_value);

            barrel_shifter.sl_valid_in   <= '1';
            barrel_shifter.slv_data_in   <= revert_vector(std_logic_vector(to_unsigned(v_int_match_length - v_int_start_value, 13)));
            barrel_shifter.int_bits      <= v_int_bitwidth;
            barrel_shifter.sl_descending <= '0';
            buffer64.int_current_index   <= buffer64.int_current_index + v_int_bitwidth;

            state <= DISTANCE_CODE;

          when DISTANCE_CODE =>
            -- 5 bit distance code
            v_int_match_distance := to_integer(unsigned(
                                                        slv_current_value(islv_data'HIGH - 1 downto 4)));

            if (v_int_match_distance <= 4) then
              v_int_code := v_int_match_distance - 1;
            elsif (v_int_match_distance <= 6) then
              v_int_code := 4;
            elsif (v_int_match_distance <= 8) then
              v_int_code := 5;
            elsif (v_int_match_distance <= 12) then
              v_int_code := 6;
            elsif (v_int_match_distance <= 16) then
              v_int_code := 7;
            elsif (v_int_match_distance <= 24) then
              v_int_code := 8;
            elsif (v_int_match_distance <= 32) then
              v_int_code := 9;
            elsif (v_int_match_distance <= 48) then
              v_int_code := 10;
            elsif (v_int_match_distance <= 64) then
              v_int_code := 11;
            elsif (v_int_match_distance <= 96) then
              v_int_code := 12;
            elsif (v_int_match_distance <= 128) then
              v_int_code := 13;
            elsif (v_int_match_distance <= 192) then
              v_int_code := 14;
            elsif (v_int_match_distance <= 256) then
              v_int_code := 15;
            elsif (v_int_match_distance <= 384) then
              v_int_code := 16;
            elsif (v_int_match_distance <= 512) then
              v_int_code := 17;
            elsif (v_int_match_distance <= 768) then
              v_int_code := 18;
            elsif (v_int_match_distance <= 1024) then
              v_int_code := 19;
            elsif (v_int_match_distance <= 1536) then
              v_int_code := 20;
            elsif (v_int_match_distance <= 2048) then
              v_int_code := 21;
            elsif (v_int_match_distance <= 3072) then
              v_int_code := 22;
            elsif (v_int_match_distance <= 4096) then
              v_int_code := 23;
            elsif (v_int_match_distance <= 6144) then
              v_int_code := 24;
            elsif (v_int_match_distance <= 8192) then
              v_int_code := 25;
            elsif (v_int_match_distance <= 12288) then
              v_int_code := 26;
            elsif (v_int_match_distance <= 16384) then
              v_int_code := 27;
            elsif (v_int_match_distance <= 24576) then
              v_int_code := 28;
            elsif (v_int_match_distance <= 32768) then
              v_int_code := 29;
            else
              assert false report "invalid distance" & to_string(v_int_match_distance);
            end if;

            report "DISTANCE_CODE " & to_string(buffer64.int_current_index) & " " & to_string(v_int_code);

            barrel_shifter.sl_valid_in   <= '1';
            barrel_shifter.slv_data_in   <= std_logic_vector(to_unsigned(v_int_code, 13));
            barrel_shifter.int_bits      <= 5;
            barrel_shifter.sl_descending <= '1';
            buffer64.int_current_index   <= buffer64.int_current_index + 5;

            -- no extra bits for distance <= 4
            -- will save one cycle in EXTRA_DISTANCE_BITS
            if (v_int_match_distance <= 4) then
              state <= SEND_BYTES;
            else
              state <= EXTRA_DISTANCE_BITS;
            end if;

          when EXTRA_DISTANCE_BITS =>
            if (v_int_match_distance <= 8) then
              v_int_bitwidth    := 1;
              v_int_start_value := 5;
            elsif (v_int_match_distance <= 16) then
              v_int_bitwidth    := 2;
              v_int_start_value := 9;
            elsif (v_int_match_distance <= 32) then
              v_int_bitwidth    := 3;
              v_int_start_value := 17;
            elsif (v_int_match_distance <= 64) then
              v_int_bitwidth    := 4;
              v_int_start_value := 33;
            elsif (v_int_match_distance <= 128) then
              v_int_bitwidth    := 5;
              v_int_start_value := 65;
            elsif (v_int_match_distance <= 256) then
              v_int_bitwidth    := 6;
              v_int_start_value := 129;
            elsif (v_int_match_distance <= 512) then
              v_int_bitwidth    := 7;
              v_int_start_value := 257;
            elsif (v_int_match_distance <= 1024) then
              v_int_bitwidth    := 8;
              v_int_start_value := 513;
            elsif (v_int_match_distance <= 2048) then
              v_int_bitwidth    := 9;
              v_int_start_value := 1025;
            elsif (v_int_match_distance <= 4096) then
              v_int_bitwidth    := 10;
              v_int_start_value := 2049;
            elsif (v_int_match_distance <= 8192) then
              v_int_bitwidth    := 11;
              v_int_start_value := 4097;
            elsif (v_int_match_distance <= 16384) then
              v_int_bitwidth    := 12;
              v_int_start_value := 8193;
            elsif (v_int_match_distance <= 32768) then
              v_int_bitwidth    := 13;
              v_int_start_value := 16384;
            else
              assert false report "invalid distance" & to_string(v_int_match_distance);
            end if;

            report "EXTRA_DISTANCE_BITS " &
              to_string(buffer64.int_current_index) & " " &
              to_string(v_int_bitwidth) & " " &
              to_string(v_int_match_length) & " " &
              to_string(v_int_start_value);

            barrel_shifter.sl_valid_in   <= '1';
            barrel_shifter.slv_data_in   <= revert_vector(std_logic_vector(to_unsigned(v_int_match_distance - v_int_start_value, 13)));
            barrel_shifter.int_bits      <= v_int_bitwidth;
            barrel_shifter.sl_descending <= '0';
            buffer64.int_current_index   <= buffer64.int_current_index + v_int_bitwidth;

            state <= SEND_BYTES;

          when SEND_BYTES =>
            if (sl_flush_increment_index = '1') then
              -- append end of block -> eob is 7 bit zeros (256) -> zeros get appended anyway
              barrel_shifter.sl_valid_in   <= '1';
              barrel_shifter.slv_data_in   <= std_logic_vector(to_unsigned(0, 13));
              barrel_shifter.int_bits      <= 7;
              barrel_shifter.sl_descending <= '1';
              buffer64.int_current_index   <= buffer64.int_current_index + 7;

              sl_flush_increment_index <= '0';
              sl_valid_out             <= '0';
            elsif (buffer64.int_current_index >= 8) then
              if (buffer64.int_current_index_d1 >= buffer64.int_current_index) then                                                     -- wait until the counts are synched
                sl_valid_out               <= '1';
                buffer64.int_current_index <= buffer64.int_current_index - 8;
                v_slv_data_out := buffer64.slv_data(buffer64.int_current_index - 1 downto buffer64.int_current_index - 8);
                slv_data_out               <= revert_vector(v_slv_data_out);
              else
                sl_valid_out <= '0';
              end if;
            elsif (buffer64.int_current_index /= 0 and sl_flush = '1') then
              sl_valid_out <= '0';
              sl_flush     <= '0';
              -- pad zeros (for full byte) at the end
              barrel_shifter.sl_valid_in   <= '1';
              barrel_shifter.slv_data_in   <= std_logic_vector(to_unsigned(0, 13));
              barrel_shifter.int_bits      <= 8 - buffer64.int_current_index;
              barrel_shifter.sl_descending <= '1';
              buffer64.int_current_index   <= buffer64.int_current_index + 8 - buffer64.int_current_index;
            else
              if (sl_bfinal = '1') then
                sl_bfinal <= '0';
                sl_flush  <= '0';
                sl_finish <= '1';
                state     <= IDLE;
              else
                state <= WAIT_FOR_INPUT;
              end if;
              sl_valid_out <= '0';
            end if;

        end case;

      end if;

    end process proc_fixed_huffman;

    proc_barrel_shifter : process (isl_clk) is
    begin

      if (rising_edge(isl_clk)) then
        if (barrel_shifter.sl_valid_in = '1') then
          -- shift the whole buffer
          for pos in buffer64.slv_data'RANGE loop
            buffer64.slv_data(pos) <= buffer64.slv_data((pos - barrel_shifter.int_bits) mod buffer64.slv_data'LENGTH);
          end loop;

          -- insert new values, maximum 13 (barrel_shifter.int_bits)
          for pos in 0 to 12 loop
            exit when pos = barrel_shifter.int_bits;

            if (barrel_shifter.sl_descending = '1') then
              buffer64.slv_data(pos) <= barrel_shifter.slv_data_in(pos);
            else
              -- After reverting the bits, the important bits are at the other end of the slv.
              -- I. e. starting at barrel_shifter.slv_data_in'HIGH, not 0.
              buffer64.slv_data(pos) <=
                                        barrel_shifter.slv_data_in(barrel_shifter.slv_data_in'HIGH - barrel_shifter.int_bits + pos + 1);
            end if;
          end loop;
        end if;
      end if;

    end process proc_barrel_shifter;

    osl_rdy <= '1' when state = WAIT_FOR_INPUT else
               '0';
  end generate gen_huffman;

  oslv_data  <= slv_data_out;
  osl_valid  <= sl_valid_out;
  osl_finish <= sl_finish;

end architecture behavioral;
