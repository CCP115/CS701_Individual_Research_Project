-- Cecil Symes

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity sync_ram_testbench is
end entity sync_ram_testbench;

architecture behaviour of sync_ram_testbench is
	-- Component instantation
	component sync_ram is
	  port (
		clock   : in  std_logic;
		we      : in  std_logic;
		address : in  std_logic_vector;
		datain  : in  std_logic_vector;
		dataout : out std_logic_vector
	  );
	end component sync_ram;
	
	-- Internal signals
	signal clk : std_logic;
	signal we : std_logic;
	signal address : std_logic_vector(8 downto 0);
	signal datain : std_logic_vector(15 downto 0);
	signal dataout : std_logic_vector(15 downto 0);
begin
	memA : sync_ram port map(clock => clk,
							we => we,
							address => address,
							datain => datain,
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
		we <= '0', '1' after 20 ns, '0' after 50 ns;
		address <= "000000000",
					"000000001" after 20 ns,
					"000000010" after 30 ns,
					"000000011" after 40 ns,
					"000000001" after 50 ns,
					"000000010" after 60 ns,
					"000000011" after 70 ns,
					"000000001" after 80 ns,
					"000000100" after 90 ns,
					"000000001" after 100 ns,
					"000000010" after 110 ns,
					"000000011" after 120 ns,
					"000000100" after 130 ns,
					"000000000" after 140 ns;
		datain <= X"0001",
					X"0001" after 20 ns,
					X"0002" after 30 ns,
					X"0003" after 40 ns,
					X"0004" after 50 ns,
					X"0001" after 60 ns,
					X"0001" after 70 ns,
					X"0001" after 80 ns,
					X"0001" after 90 ns,
					X"0001" after 100 ns,
					X"0001" after 110 ns,
					X"0001" after 120 ns,
					X"0001" after 130 ns,
					X"0001" after 140 ns;
		wait;
	end process init;
	
end architecture behaviour;