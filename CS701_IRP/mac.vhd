-- Simple MAC Unit
-- Written by Cecil Symes

-- Synchronous MAC unit
-- Always outputs result
-- Will add and accumulate inputs on every rising clock edge

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.Numeric_Std.all;
use work.TdmaMinTypes.all;

entity mac is
  port (
	en		: in  std_logic;
	reset	: in  std_logic;
    data1	: in  std_logic_vector(15 downto 0);
    data2	: in  std_logic_vector(15 downto 0);
    dataout	: out std_logic_vector(31 downto 0) := X"00000000"
  );
end entity mac;

architecture behaviour of mac is	
begin

	accumulate : process(en)
		variable dataout_int_V : signed(31 downto 0) := X"00000000";
	begin
		if rising_edge(en) then
			if reset = '1' then
				dataout_int_V := X"00000000";
				dataout <= X"00000000";
			elsif en = '1' then
				dataout_int_V := signed(data1) * signed(data2) + dataout_int_V;
				dataout <= std_logic_vector(dataout_int_V);
			end if;
		end if;
	end process accumulate;

end architecture behaviour;