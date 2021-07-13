library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.Numeric_Std.all;
use work.TdmaMinTypes.all;

entity conv_unit_testbench is
end entity conv_unit_testbench;

architecture behaviour of conv_unit_testbench is
	-- Component instantation
	component conv_unit is
		generic(
			num_samples			: in integer := 4
		);
		port(
			clk					: in  std_logic
		);
	end component conv_unit;
	
	-- Internal signals
	signal clk : std_logic;
	
begin

	conv1 : conv_unit
	port map(
		clk => clk
	);

	clk_gen : process
	begin
		clk <= '1';
		wait for 5 ns;
		clk <= '0';
		wait for 5 ns;
	end process clk_gen;
	
end architecture behaviour;