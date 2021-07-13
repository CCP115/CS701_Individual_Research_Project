-- Cecil Symes

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity mac_testbench is
end entity mac_testbench;

architecture behaviour of mac_testbench is
	-- Component instantation
	component mac is
		port (
		clk					: in  std_logic;
		en					: in  std_logic;
		reset				: in  std_logic;
		data1				: in  std_logic_vector(15 downto 0);
		data2				: in  std_logic_vector(15 downto 0);
		dataout				: out std_logic_vector(31 downto 0)
		);
	end component mac;
	
	-- Internal signals
	signal clk : std_logic;
	signal en : std_logic;
	signal reset : std_logic;
	signal data1 : std_logic_vector(15 downto 0);
	signal data2 : std_logic_vector(15 downto 0);
	signal dataout	: std_logic_vector(31 downto 0);
begin
	mac1 : mac port map(clk => clk,
							en => en,
							reset => reset,
							data1 => data1,
							data2 => data2,
							dataout => dataout);
	
	clk_gen : process
	begin
		clk <= '1';
		wait for 5 ns;
		clk <= '0';
		wait for 5 ns;
	end process clk_gen;
	
	init : process
	begin
	-- Code that runs once
		reset <= '0';
		en <= '0', '1' after 20 ns, '0' after 40 ns;
		data1 <= "0000000000000000",
				"0000000000000010" after 20 ns,
				"0000000000000011" after 30 ns;
		data2 <= "0000000000000000",
				"0000000000000001" after 20 ns,
				"0000000000000010" after 30 ns;
		wait;
	end process init;
	
end architecture behaviour;