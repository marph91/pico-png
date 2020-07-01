library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package png_pkg is
  function get_img_depth(color_type : integer) return integer;
  function xor_vector(a, b : std_logic_vector) return std_logic_vector;
  function revert_vector(slv_in : std_logic_vector) return std_logic_vector;
  function calculate_crc32(data : std_logic_vector;
                           revert : std_logic) return std_logic_vector;
  function calculate_crc32(data : std_logic_vector;
                           crc_init : std_logic_vector(31 downto 0);
                           revert : std_logic) return std_logic_vector;
  function generate_chunk(chunk_type : std_logic_vector(4*8-1 downto 0);
                          chunk_data : std_logic_vector) return std_logic_vector;
  function calculate_adler32(data : std_logic_vector;
                             start_value : std_logic_vector(31 downto 0)) return std_logic_vector;
end png_pkg;

package body png_pkg is
  -- get the image depth, based on the color type
  function get_img_depth(color_type : integer) return integer is
  begin
    if color_type = 0 then
      return 1; -- gray
    elsif color_type = 2 then
      return 3; -- RGB
    elsif color_type = 3 then
      return 1; -- palette (TODO: is this correct?)
    elsif color_type = 4 then
      return 2; -- gray with alpha
    elsif color_type = 6 then
      return 4; -- RGB with alpha
    else
      assert false report "invalid color type " & to_string(color_type);
    end if;
  end;

  -- xor two vectors
  function xor_vector(a, b : std_logic_vector) return std_logic_vector is
    variable c : std_logic_vector(a'RANGE);
  begin
    assert a'LENGTH = b'LENGTH;
    for index in 0 to a'LENGTH-1 loop
      c(c'HIGH - index) := a(a'HIGH - index) xor b(b'HIGH - index);
    end loop;
    return c;
  end xor_vector;

  -- revert the bitorder of a vector
  function revert_vector(slv_in : std_logic_vector) return std_logic_vector is
    variable v_slv_reverted: std_logic_vector(slv_in'REVERSE_RANGE);
  begin
    for i in slv_in'RANGE loop
      v_slv_reverted(i) := slv_in(i);
    end loop;
    return v_slv_reverted;
  end;

  function calculate_crc32(data : std_logic_vector;
                           revert : std_logic) return std_logic_vector is
  begin
    return calculate_crc32(data, x"00000000", revert);
  end function;

  -- TODO: CRC lut (https://www.w3.org/TR/PNG-CRCAppendix.html)
  function calculate_crc32(data : std_logic_vector;
                           crc_init : std_logic_vector(31 downto 0);
                           revert : std_logic) return std_logic_vector is
    variable v_crc : std_logic_vector(4*8 downto 0) := (others => '0');
    variable v_crc_new : std_logic_vector(4*8-1 downto 0) := (others => '0');
    variable v_crc_init : std_logic_vector(4*8-1 downto 0) := (others => '0');
    variable data_in_preprocessed : std_logic_vector(data'LENGTH+4*8-1 downto 0) := (others => '0');
    -- extra constant to prevent wrong bitorder
    variable polynomial : std_logic_vector(4*8 downto 0) := '1' & x"04C11DB7";
  begin
    assert data'LENGTH mod 8 = 0;

    -- insert the data (and pad 32 bits)
    data_in_preprocessed(data_in_preprocessed'HIGH downto 4*8) := data;

    -- xor the first 32 bits with the init crc (at start = x"FFFFFFFF" -> negation)
    v_crc_init := not crc_init;
    data_in_preprocessed(data_in_preprocessed'HIGH downto data_in_preprocessed'HIGH - 31) :=
      xor_vector(v_crc_init, data_in_preprocessed(data_in_preprocessed'HIGH downto data_in_preprocessed'HIGH - 31));

    -- invert the bitorder of each byte
    for i in 0 to data_in_preprocessed'LENGTH / 8 - 1 loop
      data_in_preprocessed((i+1)*8-1 downto i*8) := revert_vector(data_in_preprocessed((i+1)*8-1 downto i*8));
    end loop;

    -- assign start value for crc calculation
    v_crc_new := data_in_preprocessed(data_in_preprocessed'HIGH downto data_in_preprocessed'HIGH - 31);

    -- process all input data
    for i in data'LENGTH-1 downto 0 loop
      v_crc := v_crc_new & data_in_preprocessed(i);
      if v_crc(v_crc'HIGH) = '1' then
        v_crc := xor_vector(v_crc, polynomial);
      end if;
      v_crc_new := v_crc(v_crc'HIGH-1 downto 0);
    end loop;

    -- TODO: why the bytes have to be inverted?
    if revert = '1' then
      v_crc_new := v_crc_new(7 downto 0) & v_crc_new(15 downto 8) &
                   v_crc_new(23 downto 16) & v_crc_new(31 downto 24);
    end if;

    -- invert the bitorder of each byte
    for i in 0 to v_crc_new'LENGTH / 8 - 1 loop
      v_crc_new((i+1)*8-1 downto i*8) := revert_vector(v_crc_new((i+1)*8-1 downto i*8));
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
  function generate_chunk(chunk_type : std_logic_vector(4*8-1 downto 0);
                          chunk_data : std_logic_vector) return std_logic_vector is
    variable v_chunk_length : std_logic_vector(4*8-1 downto 0) := (others => '0');
    variable v_current_length : integer := 0;
    variable v_chunk_crc : std_logic_vector(4*8-1 downto 0) := (others => '0');
  begin
    if chunk_type = x"49484452" then
      assert chunk_data'LENGTH = 13*8 report integer'IMAGE(chunk_data'LENGTH);
    end if;

    v_current_length := chunk_data'LENGTH/8;
    v_chunk_length := std_logic_vector(to_unsigned(v_current_length, 4*8));

    v_chunk_crc := calculate_crc32(chunk_type & chunk_data, '1');

    -- TODO: not supported (ignored) by ghdl synthesis yet
    -- synthesis translate_off
    if chunk_type = x"49454e44" then
      assert v_chunk_crc = x"ae426082" report to_hstring(v_chunk_crc);
    end if;
    -- synthesis translate_on
    return v_chunk_length & chunk_type & chunk_data & v_chunk_crc;
  end generate_chunk;

  -- TODO: LUT
  -- Start value for first iteration must be 1!
  function calculate_adler32(data : std_logic_vector;
                             start_value : std_logic_vector(31 downto 0)) return std_logic_vector is
    variable v_s1 : integer range 0 to 2**16-1 := 0;
    variable v_s2 : integer range 0 to 2**16-1 := 0;
    variable v_current_byte : integer range 0 to 2**8-1 := 0;
  begin
    assert data'LENGTH mod 8 = 0;

    v_s1 := to_integer(unsigned(start_value(15 downto 0)));
    v_s2 := to_integer(unsigned(start_value(31 downto 16)));

    for byte in data'LENGTH / 8 - 1 downto 0 loop
      -- TODO: Check for alternative modulo function, since the implementation differs between vendors.
      -- All tried approaches had worse ressource usage. For alternatives, see:
      -- https://stackoverflow.com/questions/2773628/better-ways-to-implement-a-modulo-operation-algorithm-question
      v_current_byte := to_integer(unsigned(data((byte+1) * 8 - 1 downto byte * 8)));
      v_s1 := (v_s1 + v_current_byte) mod 65521;
      v_s2 := (v_s2 + v_s1) mod 65521;
    end loop;
    return std_logic_vector(to_unsigned(v_s2, 16)) & std_logic_vector(to_unsigned(v_s1, 16));
  end calculate_adler32;
end png_pkg;