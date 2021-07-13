-- Data Processing Application Specific Processor
-- Written by Cecil Symes

-- Able to do the following functions:
-- Direct Passthrough, Moving Average Filter, FIR Filter, Convolution/Correlation

-- Modes correspond to:
-- 0000 (0) => Reset
-- 0001 (1) => Direct Passthrough
-- 0010 (2) => Store Memory
-- 0011 (3) => Moving Average Filter
-- 0100 (4) => FIR Filter
-- 0101 (5) => Peak Detection
-- 0110 (6) => Multiplication & Accumulation (Convolution & Correlation) (Individual #1)
-- 0111 (7) => Individual #2
-- 1000 onwards (8-F) => Unused

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.Numeric_Std.all;
use work.TdmaMinTypes.all;

entity cecil_dp_asp is
	generic (
		mem_banks		: positive := 2
	);
	port (		
		clk				: in  std_logic;
		ledr			: out std_logic_vector(9 downto 0);
		send			: out tdma_min_port;
		recv			: in tdma_min_port
	);
end entity cecil_dp_asp;

architecture behaviour of cecil_dp_asp is


	-- FSM declarations
	type dpasp_state_type is (Reset, Idle, Direct, StoreMem, MovingAvg, FIR, PeakDetect, Convolution);
	signal dpasp_state : dpasp_state_type := Direct;
	signal dpasp_next_state : dpasp_state_type := Direct;
	
	type mac_state_type is (mac_idle, mac_reset, mac_fetch, mac_calc, mac_store);
	signal mac_state : mac_state_type := mac_idle;
	
	-- Component declarations
	component peak_detect is
		port (
		clk					: in  std_logic;
		data				: in  std_logic_vector(15 downto 0);
		peak_detected		: out  std_logic := '0'
		);
	end component peak_detect;
	
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
	
	component sync_ram is
		port (
			clock   : in  std_logic;
			we      : in  std_logic;
			address : in  std_logic_vector;
			datain  : in  std_logic_vector;
			dataout : out std_logic_vector
		);
	end component sync_ram;
	
	-- Control signal declarations
	signal next_dest		: std_logic_vector(3 downto 0) := x"0";
	
	-- RAM signal declarations
	type WE_ARRAY_TYPE		is array (natural range <>) of std_logic;
	type ADDRESS_ARRAY_TYPE	is array (natural range <>) of std_logic_vector(8 downto 0);
	type DATA_ARRAY_TYPE	is array (natural range <>) of std_logic_vector(15 downto 0);
	signal we_array			: WE_ARRAY_TYPE(0 to mem_banks-1);
	signal address_array	: ADDRESS_ARRAY_TYPE(0 to mem_banks-1);
	signal datain_array		: DATA_ARRAY_TYPE(0 to mem_banks-1);
	signal dataout_array	: DATA_ARRAY_TYPE(0 to mem_banks-1);

	
	-- StoreMem internal signal declarations
	signal sm_ind			: integer range 0 to 1 := 0;
	signal sm_samples		: unsigned(8 downto 0) := "000000000";
	signal sm_start_addr	: std_logic_vector(8 downto 0) := "000000000";
	signal sm_finished		: std_logic := '0';
	
	-- Convolution/Correlation internal signal declarations
	signal mac_op_sel		: std_logic := '0';
	signal mac_dest			: integer range 0 to 1 := 0;
	signal mac_num_samples	: unsigned(8 downto 0) := "000000000";
	signal mac_start_addr	: std_logic_vector(8 downto 0) := "000000000";
	signal mac_clk			: std_logic := '0';
	signal mac_en 			: std_logic := '0';
	signal mac_reset_sig	: std_logic := '0';
	signal mac_data1		: std_logic_vector(15 downto 0);
	signal mac_data2		: std_logic_vector(15 downto 0);
	signal mac_dataout		: std_logic_vector(31 downto 0);
	signal mac_complete		: std_logic := '0';
	signal mac_start		: std_logic := '0';
	
	-- DELETE THESE I THINK
	signal num_samples		: integer := 4;
	
	type mac_data_output is array (natural range <>) of std_logic_vector(31 downto 0);
	signal output 			: mac_data_output(2*num_samples-1 downto 0);
	
begin
	
	
	-- Instantiate local RAM blocks
	mem_gen : for i in 0 to mem_banks-1 generate
		memX : sync_ram
		port map(
			clock => clk,
			we => we_array(i),
			address => address_array(i),
			datain => datain_array(i),
			dataout => dataout_array(i)
		);
	end generate mem_gen;
	
	-- AND so that we can disable MAC fully and reduce power usage
	mac_clk <= clk and mac_en;
	
	-- Instantiate MAC unit for Convolution & Correlation
	mac1 : mac
	port map(
		clk => mac_clk,
		en => mac_en,
		reset => mac_reset_sig,
		data1 => mac_data1,
		data2 => mac_data2,	
		dataout => mac_dataout
	);
	
	-- Check for config packets and change mode accordingly 
	config_packet_reader : process(clk)
	
		-- StoreMem variable declarations
		variable sm_start_addr_V : std_logic_vector(8 downto 0) := "000000000";
		
		-- MAC variable declarations
		variable mac_shift_amt : integer := 0;
		
	begin
		if rising_edge(clk) then
			-- Received data is a configuration packet
			if recv.data(31 downto 28) = "1001" then
			
				-- Choose mode
				case recv.data(19 downto 16) is
				when "0000" =>
					dpasp_next_state <= Reset;
					--ledr <= "0000000000";
					
				when "0001" =>
					dpasp_next_state <= Direct;
					next_dest <= recv.data(23 downto 20);
					--ledr <= "0000000001";
						
				when "0010" =>
					dpasp_next_state <= StoreMem;
					
					-- Get which memory bank to operate on from recv.data(15) (0' = A, '1' = B)
					if recv.data(15) = '1' then
						sm_ind <= 1;
					else
						sm_ind <= 0;
					end if;
					
					-- Get start address specified in recv.data(5 downto 0), and bit shift left 3 to multiply by 8
					sm_start_addr_V := "000" & recv.data(5 downto 0);
					sm_start_addr_V := std_logic_vector(shift_left(unsigned(sm_start_addr_V), 3));
					sm_start_addr <= sm_start_addr_V;
					
					-- Get number of samples to store from recv.data(14 downto 6)
					sm_samples <= unsigned(recv.data(14 downto 6));
					
					--ledr <= "0000000010";
				
				when "0011" =>
					dpasp_next_state <= MovingAvg;
					--ledr <= "0000000011";
					
				when "0100" =>
					dpasp_next_state <= FIR;
					--ledr <= "0000000100";
					
				when "0101" =>
					dpasp_next_state <= PeakDetect;
					--ledr <= "0000000101";
					
				when "0110" =>
					dpasp_next_state <= Convolution;
					--ledr <= "0000000110";
					
					-- Save the selected operation, '0' - Convolution, '1' - Correlation
					mac_op_sel <= recv.data(15);
					
					-- Save the destination for the output data
					if recv.data(14) = '1' then
						-- '1' - NoC
						mac_dest <= 1;
					else
						-- '0' - Memory Bank A (0)
						mac_dest <= 0;
					end if;
					
					-- Save number of samples to use
					mac_shift_amt := to_integer(unsigned(recv.data(13 downto 10)));
					mac_num_samples <= shift_left("000000001", mac_shift_amt);
					
					-- Save starting address
					mac_start_addr <= recv.data(8 downto 0);
					
					-- Enable the MAC
					mac_complete <= '0';
					
				when others =>
					-- Do nothing
					--ledr <= "1111111111";
				end case;
			
			else
				dpasp_next_state <= dpasp_state;
			end if;
			
		end if;
	end process config_packet_reader;
	
	
	--Process audio packets based on current dpasp_state
	fsm : process(clk)
		
		-- StoreMem variable declarations
		variable sm_addr_offset : unsigned(8 downto 0) := "000000000";
		variable sm_count : integer := 0;
		variable sm_max : integer := 0;
		
		-- Convolution & Correlation variable declarations
		-- y[m] = Sum(i = 0 to i = num_samples-1)(x[i] * h[j]), j = num_samples - 1 + i - m
		variable mac_i : integer := 0;
		variable mac_j : integer := 0;
		variable mac_m : integer := 0;
		variable mac_invalid_count : integer := 0;
		
	begin
		if rising_edge(clk) then
			-- Change current state based on config packets and current state
			case dpasp_state is
				when Reset =>
					ledr <= "0000000000";
					
					if recv.data(31 downto 28) = "1001" then
						dpasp_state <= dpasp_next_state;
					end if;

				-- Direct Passthrough
				when Direct =>
					dpasp_state <= dpasp_next_state;
					
				when StoreMem =>
					-- If StoreMem is finished then reset all counters
					if sm_finished = '1' then
						dpasp_state <= Reset;
						sm_finished <= '0';
						
						sm_addr_offset := "000000000";
						sm_count := 0;
						sm_max := 0;
					else
						dpasp_state <= dpasp_next_state;
					end if;	
					
				when MovingAvg =>
					dpasp_state <= dpasp_next_state;
					
				When FIR =>
					dpasp_state <= dpasp_next_state;
					
				when PeakDetect =>
					dpasp_state <= dpasp_next_state;
					
				when Convolution =>
					if mac_complete = '1' then
						dpasp_state <= Reset;
					else
						dpasp_state <= dpasp_next_state;
						mac_start <= '1';
					end if;
					
				when others =>
					-- Do nothing
					
				end case;
			
			-- Change functionality of DPASP based on dpasp_state
			case dpasp_state is
			when Reset =>
				ledr <= "0000000000";
				
				-- Reset all completion signals
				sm_finished <= '0';
				
			-- Direct Passthrough
			when Direct =>
				ledr <= "0000000001";
				send.data <= recv.data;
				send.addr <= x"0" & next_dest;
			
			when StoreMem =>
				ledr <= "0000000010";
				
				sm_max := to_integer(sm_samples);
				-- Store given samples if pending
				if recv.data(31 downto 28) = "1000" then
					if sm_finished = '0' then
						if sm_count <= sm_max then
							-- Loop for number of samples
							we_array(sm_ind) <= '1';
							address_array(sm_ind) <= std_logic_vector(unsigned(sm_start_addr) + sm_addr_offset);
							datain_array(sm_ind) <= recv.data(15 downto 0);
							sm_addr_offset := sm_addr_offset + to_unsigned(1, sm_addr_offset'length);
							sm_count := sm_count + 1;
						else
							-- Reached number of samples, finish
							sm_finished <= '1';
							we_array(sm_ind) <= '0';
							sm_addr_offset := "000000000";
						end if;
					end if;			
				end if;
				
			when MovingAvg =>
				ledr <= "0000000011";
				
			When FIR =>
				ledr <= "0000000100";
				
			when PeakDetect =>
				ledr <= "0000000101";
				
			when Convolution =>
				ledr <= "0000000110";
				
				if mac_complete = '0' then
					case mac_state is
					when mac_reset =>
						-- Reset internal accumulate
						mac_en <= '1';
						mac_reset_sig <= '1';
						mac_data1 <= x"0000";
						mac_data2 <= x"0000";
						
						if mac_m = (2*num_samples - 1) then
							-- If mac_m is out of range then operation complete, go to mac_idle
							mac_state <= mac_idle;
							mac_m := 0;
							mac_i := 0;
							mac_j := 0;
							mac_complete <= '1';
						elsif (to_integer(unsigned(mac_start_addr)) + mac_m) > 512 then
							-- If start_addr + m is larger than 512 then end operation early
							mac_state <= mac_idle;
							mac_m := 0;
							mac_i := 0;
							mac_j := 0;
							mac_complete <= '1';
						else
							-- If mac_m is still valid, go back to mac_fetch
							mac_state <= mac_fetch;
							mac_i := 0;
							mac_j := 0;
						end if;
						
					when mac_idle =>
						-- Do nothing
						mac_en <= '0';
						mac_reset_sig <= '0';
						mac_data1 <= x"0000";
						mac_data2 <= x"0000";
						mac_complete <= '0';
						
						if mac_start = '1' then
							mac_start <= '0';
							mac_state <= mac_reset;
						end if;
						
					when mac_fetch =>
						-- Wait for data to come from memory, takes 1 cycle
						mac_en <= '0';
						mac_reset_sig <= '0';
						
						-- Calculate address to mac_fetch from
						mac_j := num_samples - 1 + mac_i - mac_m;
						
						-- Increment mac_invalid_count if address is valid for mac_i and mac_j values
						if mac_i < 0 or mac_i > num_samples-1 then
							mac_invalid_count := mac_invalid_count + 1;
							mac_data1 <= x"0000";
						else
							address_array(0) <= std_logic_vector(unsigned(mac_start_addr) + to_unsigned(mac_i, mac_start_addr'length));
						end if;
						if mac_j < 0 or mac_j > num_samples-1 then
							mac_invalid_count := mac_invalid_count + 1;
							mac_data2 <= x"0000";
						else
							address_array(1) <= std_logic_vector(unsigned(mac_start_addr) + to_unsigned(mac_j, mac_start_addr'length));
						end if;
						
						-- If both indexes are invalid go to mac_store to save results
						if mac_invalid_count = 2 then
							mac_state <= mac_store;
							mac_invalid_count := 0;
						elsif mac_invalid_count = 1 then
							-- If one is invalid then mac_fetch next data
							mac_state <= mac_fetch;
							mac_invalid_count := 0;
							
							-- Increment mac_i counter
							mac_i := mac_i + 1;
						else
							-- If none are invalid then calculate result as normal
							mac_state <= mac_calc;
							mac_invalid_count := 0;
						end if;
						
					when mac_calc =>
						-- Input data to MAC and mac_store result
						-- mac_data1 <= dataout_array(MEM_LOCATION_ARRAY_A);
						-- mac_data2 <= dataout_array(MEM_LOCATION_ARRAY_B);
						
						mac_en <= '1';
						mac_reset_sig <= '0';
						
						-- Increment mac_i counter
						mac_i := mac_i + 1;
						
						mac_state <= mac_fetch;
						
					when mac_store =>
						mac_en <= '0';
						mac_reset_sig <= '0';
					
						-- Save convolution output
						output(mac_m) <= mac_dataout;
						
						-- Increment mac_m
						mac_m := mac_m + 1;
						
						-- Go to mac_reset to mac_reset the MAC output
						mac_state <= mac_reset;
						
					when others =>
						-- Go to mac_reset
						mac_state <= mac_reset;
					end case;
				end if;
				
			when others =>
				-- Do nothing
				ledr <= "1111111111";
				
			end case;
			
		
			
		end if;
	end process fsm;
	
end architecture behaviour;