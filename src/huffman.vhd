library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;
use util.math_pkg.all;

entity huffman is
  generic (
    C_BTYPE : integer range 0 to 3 := 0;
    C_BITWIDTH : integer := 17
  );
  port (
    isl_clk   : in std_logic;
    isl_flush : in std_logic;
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(C_BITWIDTH-1 downto 0);
    oslv_data : out std_logic_vector(7 downto 0);
    osl_valid : out std_logic;
    osl_finish: out std_logic;
    oint_valid_bits : out integer range 1 to 72;
    osl_rdy   : out std_logic
  );
end;

architecture behavioral of huffman is
  -- constant C_MAX_DATA_LENGTH : integer := 16; -- TODO: up to 2^16
  signal int_current_index : integer range 0 to 63 := 0;
  signal slv_64_bit_buffer : std_logic_vector(63 downto 0) := (others => '0');

  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(7 downto 0) := (others => '0');

  signal slv_block_data : std_logic_vector(71 downto 0) := (others => '0');
  signal int_block_bytes_to_send : integer range 0 to 16 := 0; -- TODO: range can be bigger

  signal sl_finish : std_logic := '0';
  signal sl_bfinal : std_logic := '0';

begin
  proc_assemble_32_bit: process(isl_clk)
    variable v_int_valid_bits : integer range 8 to 17 := 9;
  begin
    if rising_edge(isl_clk) then
      if isl_valid = '1' then
        if C_BTYPE /= 0 then
          -- distinguish between match or non match
          if islv_data(islv_data'LEFT) = '1' then
            v_int_valid_bits := 17;
          else
            v_int_valid_bits := 9;
          end if;
        else
          v_int_valid_bits := 8;
        end if;
        slv_64_bit_buffer(63 - int_current_index downto 63 - int_current_index - v_int_valid_bits + 1) <=
          islv_data(islv_data'HIGH downto islv_data'HIGH - v_int_valid_bits + 1);
        int_current_index <= int_current_index + v_int_valid_bits;
      elsif int_current_index >= 32 then
        slv_64_bit_buffer <= slv_64_bit_buffer(31 downto 0) & x"00000000";
        int_current_index <= int_current_index - 32;
      end if;
    end if;
  end process;

  gen_huffman: if C_BTYPE = 0 generate
    -- no huffman encoding
    -- 2 byte LEN, 2 byte NLEN, X bits DATA

    -- TODO: this doesn't belong to huffman, but rather to deflate
    -- problem:
    -- BTYPE & BFINAL are prepended to all data blocks (compressed and uncompressed)
    -- LEN and NLEN are specific to C_BTYPE = 0
    proc_no_encoding: process(isl_clk)
      variable v_bfinal : std_logic := '0';
      variable v_len : std_logic_vector(15 downto 0) := (others => '0');
    begin
      if rising_edge(isl_clk) then
        sl_finish <= '0';

        if isl_valid = '0' and (int_current_index >= 32 or (isl_flush = '1' and int_current_index > 0)) then
          if int_current_index <= 32 and isl_flush = '1' then
            v_bfinal := '1';
            sl_bfinal <= '1';
          end if;

          if int_current_index >= 32 then
            v_len := std_logic_vector(to_unsigned(32/8, 16));
          else
            v_len := std_logic_vector(to_unsigned(int_current_index/8, 16));
          end if;

          slv_block_data <=
            "00000" & -- Any bits of input up to the next byte boundary are ignored.
            std_logic_vector(to_unsigned(C_BTYPE, 2)) & v_bfinal & -- BTYPE & BFINAL
            v_len(7 downto 0) & v_len(15 downto 8) & -- LEN (MSByte second)
            not v_len(7 downto 0) & not v_len(15 downto 8) & -- NLEN (MSByte second)
            slv_64_bit_buffer(63 downto 32); -- DATA
          int_block_bytes_to_send <= 5 + to_integer(unsigned(v_len));
          v_bfinal := '0';
        end if;

        if int_block_bytes_to_send > 0 then
          sl_valid_out <= '1';
          int_block_bytes_to_send <= int_block_bytes_to_send - 1;
          slv_data_out <= slv_block_data(slv_block_data'HIGH downto slv_block_data'HIGH-7);
          slv_block_data <= slv_block_data(slv_block_data'HIGH-8 downto 0) & "00000000";
        else
          sl_valid_out <= '0';
          if sl_bfinal = '1' then
            sl_finish <= '1';
            sl_bfinal <= '0';
          end if;
        end if;
      end if;
    end process;
  end generate;

  oslv_data <= slv_data_out;
  osl_valid <= sl_valid_out;
  oint_valid_bits <= 8;
  osl_finish <= sl_finish;
  osl_rdy <= '1' when int_current_index < 32 and int_block_bytes_to_send = 0 else '0';
end behavioral;