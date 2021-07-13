-- Cecil Symes

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity peak_detect_testbench is
end entity peak_detect_testbench;

architecture behaviour of peak_detect_testbench is
	-- Component instantation
	component peak_detect is
	  port (
		clk					: in  std_logic;
		data				: in  std_logic_vector(15 downto 0);
		peak_detected		: out  std_logic := '0'
	  );
	end component peak_detect;
	
	-- Internal signals
	signal clk : std_logic;
	signal data : std_logic_vector(15 downto 0);
	signal peak_detected	: std_logic;
begin
	peak_detect1 : peak_detect port map(clk => clk,
										data => data,
										peak_detected => peak_detected);
	
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
		data <= X"0001",
					X"0002" after 20 ns,
					X"0003" after 30 ns,
					X"0004" after 40 ns,
					X"0005" after 50 ns,
					X"0006" after 60 ns,
					X"0004" after 70 ns,
					X"0003" after 80 ns,
					X"0004" after 90 ns,
					X"0005" after 100 ns,
					X"0006" after 110 ns,
					X"0007" after 120 ns,
					X"0006" after 130 ns,
					X"0009" after 140 ns;
		wait;
	end process init;
	
end architecture behaviour;