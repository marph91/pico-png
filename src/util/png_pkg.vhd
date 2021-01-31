library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library util;
  use util.math_pkg.all;

package png_pkg is

  function get_img_depth (color_type : integer) return integer;

  function xor_vector (a, b : std_logic_vector) return std_logic_vector;

  function revert_vector (slv_in : std_logic_vector) return std_logic_vector;

  function calculate_crc32 (
    data : std_logic_vector;
    revert : std_logic) return std_logic_vector;

  function calculate_crc32 (
    data : std_logic_vector;
    crc_init : std_logic_vector(31 downto 0);
    revert : std_logic) return std_logic_vector;

  function generate_chunk (
    chunk_type : std_logic_vector(4 * 8 - 1 downto 0);
    chunk_data : std_logic_vector) return std_logic_vector;

  function calculate_adler32 (
    data : std_logic_vector;
    start_value : std_logic_vector(31 downto 0)) return std_logic_vector;

  function calc_huffman_bitwidth (
    constant btype : integer range 0 to 3;
    constant input_buffer_size : integer range 3 to 258;
    constant search_buffer_size : integer range 1 to 32768;
    constant max_match_length_user : integer) return integer;

  function get_max_match_length (
    constant input_buffer_size : integer range 3 to 258;
    constant search_buffer_size : integer range 1 to 32768;
    constant max_match_length_user : integer) return integer;

end package png_pkg;

package body png_pkg is
  -- get the image depth, based on the color type

  function get_img_depth (color_type : integer) return integer is
  begin

    if (color_type = 0) then
      return 1; -- gray
    elsif (color_type = 2) then
      return 3; -- RGB
    elsif (color_type = 3) then
      return 1; -- palette (TODO: is this correct?)
    elsif (color_type = 4) then
      return 2; -- gray with alpha
    elsif (color_type = 6) then
      return 4; -- RGB with alpha
    else
      assert false report "invalid color type " & to_string(color_type);
    end if;

  end;

  -- xor two vectors

  function xor_vector (a, b : std_logic_vector) return std_logic_vector is
    variable c : std_logic_vector(a'RANGE);
  begin
    assert a'LENGTH = b'LENGTH;
    for index in 0 to a'LENGTH - 1 loop
      c(c'HIGH - index) := a(a'HIGH - index) xor b(b'HIGH - index);
    end loop;
    return c;
  end xor_vector;

  -- revert the bitorder of a vector

  function revert_vector (slv_in : std_logic_vector) return std_logic_vector is
    variable v_slv_reverted : std_logic_vector(slv_in'REVERSE_RANGE);
  begin
    for i in slv_in'RANGE loop
      v_slv_reverted(i) := slv_in(i);
    end loop;
    return v_slv_reverted;
  end;

  function calculate_crc32 (
    data : std_logic_vector;
    revert : std_logic) return std_logic_vector is
  begin
    return calculate_crc32(data, x"00000000", revert);
  end function;

  -- TODO: CRC lut (https://www.w3.org/TR/PNG-CRCAppendix.html)

  function calculate_crc32 (
    data : std_logic_vector;
    crc_init : std_logic_vector(31 downto 0);
    revert : std_logic) return std_logic_vector is
    variable v_crc         : std_logic_vector(4 * 8 downto 0);
    variable v_crc_new     : std_logic_vector(4 * 8 - 1 downto 0);
    variable v_crc_init    : std_logic_vector(4 * 8 - 1 downto 0);
    variable data_prepared : std_logic_vector(data'LENGTH + 4 * 8 - 1 downto 0);
    -- extra constant to prevent wrong bitorder
    variable polynomial : std_logic_vector(4 * 8 downto 0);
  begin
    assert data'LENGTH mod 8 = 0;

    -- Initialize variables.
    data_prepared := (others => '0');
    polynomial := '1' & x"04C11DB7";

    -- insert the data (and pad 32 bits)
    data_prepared(data_prepared'HIGH downto 4*8) := data;

    -- xor the first 32 bits with the init crc (at start = x"FFFFFFFF" -> negation)
    v_crc_init := not crc_init;
    data_prepared(data_prepared'HIGH downto data_prepared'HIGH - 31) := xor_vector(v_crc_init, data_prepared(data_prepared'HIGH downto data_prepared'HIGH - 31));

    -- invert the bitorder of each byte
    for i in 0 to data_prepared'LENGTH / 8 - 1 loop
      data_prepared((i + 1)*8 - 1 downto i*8) := revert_vector(data_prepared((i + 1) * 8 - 1 downto i * 8));
    end loop;

    -- assign start value for crc calculation
    v_crc_new := data_prepared(data_prepared'HIGH downto data_prepared'HIGH - 31);

    -- process all input data
    for i in data'LENGTH - 1 downto 0 loop
      v_crc := v_crc_new & data_prepared(i);

      if (v_crc(v_crc'HIGH) = '1') then
        v_crc := xor_vector(v_crc, polynomial);
      end if;

      v_crc_new := v_crc(v_crc'HIGH - 1 downto 0);
    end loop;

    -- TODO: why the bytes have to be inverted?
    if (revert = '1') then
      v_crc_new := v_crc_new(7 downto 0) & v_crc_new(15 downto 8) &
                   v_crc_new(23 downto 16) & v_crc_new(31 downto 24);
    end if;

    -- invert the bitorder of each byte
    for i in 0 to v_crc_new'LENGTH / 8 - 1 loop
      v_crc_new((i + 1)*8 - 1 downto i*8) := revert_vector(v_crc_new((i + 1) * 8 - 1 downto i * 8));
    end loop;
    -- invert the data bits
    v_crc_new := not v_crc_new;
    return v_crc_new;
  end calculate_crc32;

  -- chunk:
  --   4 byte length of data
  --   4 byte chunk type -> ASCII encoded name
  --   X byte data
  --   4 byte CRC of chunk type and data
  --     -> x^32+x^26+x^23+x^22+x^16+x^12+x^11+x^10+x^8+x^7+x^5+x^4+x^2+x+1 == '1' & x"04C11DB7"

  function generate_chunk (
    chunk_type : std_logic_vector(4 * 8 - 1 downto 0);
    chunk_data : std_logic_vector) return std_logic_vector is
    variable v_chunk_length   : std_logic_vector(4 * 8 - 1 downto 0);
    variable v_current_length : integer;
    variable v_chunk_crc      : std_logic_vector(4 * 8 - 1 downto 0);
  begin

    if (chunk_type = x"49484452") then
      assert chunk_data'LENGTH = 13 * 8 report integer'IMAGE(chunk_data'LENGTH);
    end if;

    v_current_length := chunk_data'LENGTH / 8;
    v_chunk_length := std_logic_vector(to_unsigned(v_current_length, 4 * 8));

    v_chunk_crc := calculate_crc32(chunk_type & chunk_data, '1');

    -- TODO: not supported (ignored) by ghdl synthesis yet
    -- synthesis translate_off
    if (chunk_type = x"49454e44") then
      assert v_chunk_crc = x"ae426082" report to_hstring(v_chunk_crc);
    end if;

    -- synthesis translate_on
    return v_chunk_length & chunk_type & chunk_data & v_chunk_crc;
  end generate_chunk;

  -- Start value for first iteration must be 1!

  function calculate_adler32 (
    data : std_logic_vector;
    start_value : std_logic_vector(31 downto 0)) return std_logic_vector is
    variable v_s1           : integer range 0 to 2 ** 16 - 1;
    variable v_s2           : integer range 0 to 2 ** 16 - 1;
    variable v_current_byte : integer range 0 to 2 ** 8 - 1;
    variable v_sum1         : integer range 0 to 2 ** 17 - 1;
    variable v_sum2         : integer range 0 to 2 ** 17 - 1;
  begin
    assert data'LENGTH mod 8 = 0;

    v_s1 := to_integer(unsigned(start_value(15 downto 0)));
    v_s2 := to_integer(unsigned(start_value(31 downto 16)));

    for byte in data'LENGTH / 8 - 1 downto 0 loop
      v_current_byte := to_integer(unsigned(data((byte + 1) * 8 - 1 downto byte * 8)));
      v_sum1 := v_s1 + v_current_byte;
      -- Calculate the modulo manually, since it uses less resources and has better timing.
      if (v_sum1 < 65521) then
        v_s1 := v_sum1;
      else
        v_s1 := v_sum1 - 65521;
      end if;

      v_sum2 := v_s2 + v_s1;

      if (v_sum2 < 65521) then
        v_s2 := v_sum2;
      elsif (v_sum2 < 65521 * 2) then
        v_s2 := v_sum2 - 65521;
      else
        v_s2 := v_sum2 - 65521 * 2;
      end if;

    end loop;
    return std_logic_vector(to_unsigned(v_s2, 16)) & std_logic_vector(to_unsigned(v_s1, 16));
  end calculate_adler32;

  function calc_huffman_bitwidth (
    constant btype : integer range 0 to 3;
    constant input_buffer_size : integer range 3 to 258;
    constant search_buffer_size : integer range 1 to 32768;
    constant max_match_length_user : integer) return integer is
    variable v_int_match_offset : integer;
    variable v_int_match_length : integer;
  begin

    -- TODO: add btype = 2

    if (btype = 0) then
      return 8;
    end if;

    -- 1 bit match, distance/offset, length
    v_int_match_offset := log2(search_buffer_size);
    v_int_match_length := log2(get_max_match_length(input_buffer_size,
                                                    search_buffer_size,
                                                    max_match_length_user));
    -- At least 8 bit are needed to represent a literal.
    if (v_int_match_offset + v_int_match_length < 8) then
      report "Input and search buffer too small. Output bitwidth will be extended to 8 bit." severity warning;
      report to_string(search_buffer_size) & " " & to_string(v_int_match_offset) & " " &
             to_string(input_buffer_size) & " " & to_string(v_int_match_length);
      return 1 + 8;
    end if;

    return 1 + v_int_match_offset + v_int_match_length;
  end function;

  function get_max_match_length (
    constant input_buffer_size : integer range 3 to 258;
    constant search_buffer_size : integer range 1 to 32768;
    constant max_match_length_user : integer) return integer is
  begin

    -- input_buffer_size - 1, because input buffer starts at 0.
    -- Search buffer starts at 1.
    return min_int(
      min_int(input_buffer_size - 1, search_buffer_size),
      max_match_length_user);

  end function;

end png_pkg;
