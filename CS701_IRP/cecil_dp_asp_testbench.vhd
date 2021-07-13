-- Data Processing Application Specific Processor Testbench
-- Written by Cecil Symes

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.Numeric_Std.all;
use work.TdmaMinTypes.all;

entity cecil_dp_asp_testbench is
end entity cecil_dp_asp_testbench;

architecture behaviour of cecil_dp_asp_testbench is

	-- Component declarations	
	component cecil_dp_asp is
		generic (
			mem_banks		: positive
		);
		port (
			clk				: in  std_logic;
			ledr			: out std_logic_vector(9 downto 0);
			send			: out tdma_min_port;
			recv			: in tdma_min_port
		);
	end component cecil_dp_asp;
	
	-- Internal signal declarations
	signal clk : std_logic;
	signal send : tdma_min_port;
	signal ledr : std_logic_vector(9 downto 0);
	signal recv : tdma_min_port;
	
	signal test : std_logic := '0';
	
begin
	
	dp_asp1 : cecil_dp_asp
	generic map (
		mem_banks => 2
	)
	port map(
		clk => clk,
		ledr => ledr,
		send => send,
		recv => recv
	);
	
	clk_gen : process
	begin
		clk <= '1';
		wait for 5 ns;
		clk <= '0';
		wait for 5 ns;
	end process clk_gen;
	
	init : process
		variable count : unsigned(31 downto 0) := x"80000000";
		variable init_count : integer := 0;
	begin
		if init_count < 4 then
			recv.data <= x"00001000"; -- NULL
			
		elsif init_count < 5 then
			recv.data <= x"921200D1"; -- StoreMem state, MemA, 4 samples, 128 start addr
		elsif init_count < 6 then
			recv.data <= x"8000FFFD"; -- Data packet, -3
		elsif init_count < 7 then
			recv.data <= x"80000002"; -- Data packet, 2
		elsif init_count < 8 then
			recv.data <= x"8000FFFF"; -- Data packet, -1
		elsif init_count < 11 then
			recv.data <= x"80000001"; -- Data packet, 1
			
		elsif init_count < 13 then
			recv.data <= x"921280D1"; -- StoreMem state, MemB, 4 samples, 128 start addr
		elsif init_count < 14 then
			recv.data <= x"8000FFFF"; -- Data packet, -1
		elsif init_count < 15 then
			recv.data <= x"80000000"; -- Data packet, 0
		elsif init_count < 16 then
			recv.data <= x"8000FFFD"; -- Data packet, -3
		elsif init_count < 19 then
			recv.data <= x"80000002"; -- Data packet, 2
			
		elsif init_count < 22 then
			recv.data <= x"92268888"; -- MAC state, Correlation mode, Dest MemA, 4 samples, 128 start addr

		else
			-- Wait for confirmation packet that the MAC has finished correlation
			if send.data(31 downto 28) = x"C" then
				recv.data <= x"92264888"; -- MAC state, Convolution mode, Dest NoC, 4 samples, 128 start addr
				--recv.data <= x"9212823F"; -- StoreMem state, MemB, 9 samples, 510 start addr
			else
				recv.data <= x"80000002";
			end if;
			
		end if;
		
		init_count := init_count + 1;
		
		wait for 10 ns;
	end process init;
	
end architecture behaviour;