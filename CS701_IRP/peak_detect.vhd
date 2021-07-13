-- Simple Peak Detect Unit
-- Written by Cecil Symes

-- Synchronous Peak Detection unit
-- Stores previous input
-- If current input is lower, then the previous was a peak, so output the peak detected flag

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.Numeric_Std.all;

entity peak_detect is
  port (
    clk					: in  std_logic;
    data				: in  std_logic_vector(15 downto 0);
    peak_detected		: out  std_logic := '0'
  );
end entity peak_detect;

architecture behaviour of peak_detect is
	
	signal prev_data : unsigned(15 downto 0) := X"0000";
	signal in_valley : std_logic := '0';
	
begin

	detect : process(clk)
	begin
		if rising_edge(clk) then
			-- in_valley indicates that a peak has been detected and we are currently in a "valley"
			if in_valley = '0' then
				if signed(prev_data) > signed(data) then
					in_valley <= '1';
					peak_detected <= '1';
				end if;
			else
				-- We are leaving the valley, so clear the flag
				if signed(prev_data) < signed(data) then
					in_valley <= '0';
				end if;
				peak_detected <= '0';
			end if;
		prev_data <= unsigned(data);
		end if;
	end process detect;

end architecture behaviour;