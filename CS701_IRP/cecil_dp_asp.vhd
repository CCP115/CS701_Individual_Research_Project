-- Data Processing Application Specific Processor
-- Written by Cecil Symes

-- Able to do the following functions:
-- Direct Passthrough, Moving Average Filter, FIR Filter, Convolution/Correlation

-- Modes correspond to:
-- 0000 (0) => Reset/Idle (DPASP always moves from Reset to Idle, Idle cannot be accessed directly)
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
	type dpasp_state_type is (Reset, Idle, Direct, StoreMem, MovingAvg, FIR, PeakDetect, Convolution, Correlation);
	signal dpasp_state : dpasp_state_type := Reset;
	
	type mac_state_type is (mac_ready, mac_reset, mac_fetch, mac_wait, mac_calc, mac_store);
	signal mac_state : mac_state_type := mac_ready;
	
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
	signal mac_num_samples	: integer range 0 to 256 := 0;
	signal mac_start_addr	: std_logic_vector(8 downto 0) := "000000000";
	signal mac_en 			: std_logic := '0';
	signal mac_reset_sig	: std_logic := '0';
	signal mac_data1		: std_logic_vector(15 downto 0);
	signal mac_data2		: std_logic_vector(15 downto 0);
	signal mac_dataout		: std_logic_vector(31 downto 0);
	signal to_shift			: unsigned(8 downto 0) := "000000001";
	
	-- Output is just used to check numerical values of output for functional correctness
	type mac_data_output is array (natural range <>) of std_logic_vector(31 downto 0);
	signal output 			: mac_data_output(15 downto 0);
	
	-- Outputs for Debugging Purposes
	signal test_mac_i : integer := 0;
	signal test_mac_j : integer := 0;
	signal test_mac_m : integer := 0;
	
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
	
	-- Instantiate MAC unit for Convolution & Correlation
	mac1 : mac
	port map(
		en => mac_en,
		reset => mac_reset_sig,
		data1 => mac_data1,
		data2 => mac_data2,	
		dataout => mac_dataout
	);	
	
	--Process audio packets based on current dpasp_state
	fsm : process(clk)
		-- FSM variable declarations
		variable dpasp_next_state : dpasp_state_type := Reset;
		
		-- StoreMem variable declarations
		variable sm_start_addr_V : std_logic_vector(8 downto 0) := "000000000";
		variable sm_addr_offset : unsigned(8 downto 0) := "000000000";
		variable sm_count : integer := 0;
		variable sm_max : integer := 0;
		
		-- MAC variable declarations
		variable mac_shift_amt : integer := 0;
		
		-- Convolution & Correlation variable declarations
		-- y[m] = Sum(i = 0 to i = num_samples-1)(x[i] * h[j]), j = num_samples - 1 + i - m
		variable mac_i : integer := 0;
		variable mac_j : integer := 0;
		variable mac_m : integer := 0;
		variable mac_invalid_count : integer := 0;
		variable mac_store_addr : integer range 0 to 511:= 0;
		
		
	begin
		if rising_edge(clk) then
			
			-- Read configuration packet, dpasp_next_state is only used in Reset, Idle, and Direct
			if recv.data(31 downto 28) = "1001" then
				-- Choose next mode
				case recv.data(19 downto 16) is
				when "0000" =>
					dpasp_next_state := Reset;
					--ledr <= "0000000000";
				
				when "0001" =>
					dpasp_next_state := Direct;
					next_dest <= recv.data(23 downto 20);
					--ledr <= "0000000001";
				
				when "0010" =>
					dpasp_next_state := StoreMem;
					
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
					dpasp_next_state := MovingAvg;
					--ledr <= "0000000011";
					
				when "0100" =>
					dpasp_next_state := FIR;
					--ledr <= "0000000100";
					
				when "0101" =>
					dpasp_next_state := PeakDetect;
					--ledr <= "0000000101";
					
				when "0110" =>
					--ledr <= "0000000110";
					
					-- Update the configuration packets only if first time entering the state
					if dpasp_state /= Correlation and dpasp_state /= Convolution then
						-- Save the selected operation, '0' - Convolution, '1' - Correlation
						mac_op_sel <= recv.data(15);
						
						if recv.data(15) = '1' then
							dpasp_next_state := Correlation;
						else
							dpasp_next_state := Convolution;
						end if;
						
						-- Save the destination for the output data
						if recv.data(14) = '1' then
							-- '1' - NoC
							mac_dest <= 1;
							next_dest <= recv.data(23 downto 20);
						else
							-- '0' - Memory Bank A (0)
							mac_dest <= 0;
						end if;
						
						-- Save number of samples to use
						mac_shift_amt := to_integer(unsigned(recv.data(13 downto 10)));
						mac_num_samples <= to_integer(shift_left(to_shift, mac_shift_amt));
						
						-- Save starting address
						mac_start_addr <= recv.data(8 downto 0);
					end if;
					
				when others =>
					-- Do Nothing
					--ledr <= "1111111111";
				end case;
			else
				-- If in Direct then stay Direct, otherwise return to default state Idle
				if dpasp_state = Direct then
					dpasp_next_state := Direct;
				else
					dpasp_next_state := Idle;
				end if;
			end if;
			
			
			-- Change behaviour based on current state
			case dpasp_state is
				when Reset =>
					-- Reset all completion signals
					ledr <= "0000000000";
					
					-- Reset StoreMem counters and signals
					sm_finished <= '0';
					sm_addr_offset := "000000000";
					sm_count := 0;
					sm_max := 0;
					
					-- Reset MAC unit counters and signals
					mac_en <= '0';
					mac_reset_sig <= '0';
					mac_data1 <= x"0000";
					mac_data2 <= x"0000";
					
					-- Reset TDMA Port
					send.data <= x"00000000";
					send.addr <= x"00";
					
					-- Wait for new command packet to provide next state
					dpasp_state <= dpasp_next_state;
				when Idle =>
					-- Wait for new command packet to provide next state
					dpasp_state <= dpasp_next_state;
				
				-- Direct Passthrough
				when Direct =>
					-- Wait for new command packet to provide next state
					send.data <= recv.data;
					send.addr <= x"0" & next_dest;
					dpasp_state <= dpasp_next_state;
					
				when StoreMem =>
					-- Store given samples if pending
					sm_max := to_integer(sm_samples);
					if sm_finished = '0' then
						if recv.data(31 downto 28) = "1000" then
							if sm_count <= sm_max then
								-- Loop for number of samples
								we_array(sm_ind) <= '1';
								address_array(sm_ind) <= std_logic_vector(unsigned(sm_start_addr) + sm_addr_offset);
								datain_array(sm_ind) <= recv.data(15 downto 0);
								sm_addr_offset := sm_addr_offset + to_unsigned(1, sm_addr_offset'length);
								sm_count := sm_count + 1;
								
								-- Check to see if outside bound of memory, send invalid completion packet
								-- If sm_count is 0 then we have overflowed from 511, therefore stop before invalid write occurs
								if (unsigned(sm_start_addr) + sm_addr_offset) = "000000000" then
									send.data <= x"D" & next_dest & x"0" & x"1" & x"0000";
									send.addr <= x"0" & next_dest;
									sm_finished <= '1';
								end if;
								
							else
								-- Reached number of samples, finish
								sm_finished <= '1';
								--we_array(sm_ind) <= '0';
								
								-- Send completion acknowledgement packet, finished successfully
								send.data <= x"D" & next_dest & x"000000";
								send.addr <= x"0" & next_dest;
							end if;
						end if;
					else
						dpasp_state <= Reset;
						we_array(sm_ind) <= '0';
					end if;
					
				when MovingAvg =>
				
					-- Only change state when finished
					dpasp_state <= dpasp_next_state;
					
				When FIR =>
					-- Only change state when finished
					dpasp_state <= dpasp_next_state;
					
				when PeakDetect =>
					-- Only change state when finished
					dpasp_state <= dpasp_next_state;
					
				when Convolution | Correlation =>
				
					case mac_state is
					when mac_reset =>
						-- Reset internal accumulate
						mac_en <= '1';
						mac_reset_sig <= '1';
						mac_data1 <= x"0000";
						mac_data2 <= x"0000";
						
						-- Reset destination signals
						we_array(0) <= '0';
						send.data <= x"00000000";
						send.addr <= x"00";
						
						if mac_m = (2*mac_num_samples - 1) then
							-- If mac_m is out of range then operation complete, go to mac_ready
							mac_state <= mac_ready;
							mac_m := 0;
							mac_i := 0;
							mac_j := 0;
							dpasp_state <= Reset;
							
							-- Send completion acknowledgement packet, operation ended normally
							send.data <= x"C" & next_dest & x"0" & x"0" & x"0000";
							send.addr <= x"0" & next_dest;
							
						elsif (to_integer(unsigned(mac_start_addr)) + mac_m) > 512 then
							-- If start_addr + m is larger than 512 then end operation early
							mac_state <= mac_ready;
							mac_m := 0;
							mac_i := 0;
							mac_j := 0;
							dpasp_state <= Reset;
							
							-- Send completion acknowledgement packet, state ended early
							send.data <= x"C" & next_dest & x"0" &  x"1" & x"0000";
							send.addr <= x"0" & next_dest;
							
						else
							-- If mac_m is still valid, go back to mac_fetch
							mac_state <= mac_fetch;
							mac_i := 0;
							mac_j := 0;
						end if;
						
					when mac_ready =>
						-- MAC unit returns to this state every time convolution completes, waits for next time it is called
						mac_state <= mac_reset;
						
					when mac_fetch =>
						-- Wait for data to come from memory, takes 1 cycle
						mac_en <= '0';
						mac_reset_sig <= '0';
						
						-- Calculate a j index for h[j] according to the current mode
						if mac_op_sel = '1' then
							mac_j := mac_num_samples - 1 + mac_i - mac_m; -- For Correlation
						else
							mac_j := mac_m - mac_i; -- For Convolution
						end if;
						
						-- Check if either index need to be adjusted
						if mac_op_sel = '1' then
							-- If in Correlation, if mac_j < 0 then adjust mac_j up and mac_i down
							if mac_j < 0 then
								mac_i := mac_i + (0 - mac_j);
								mac_j := 0;
							end if;
						else
							-- If in Convolution, if mac_j > mac_num_samples - 1 then adjust mac_j down and mac_i up
							if mac_j > (mac_num_samples - 1) then
								mac_i := mac_i + (mac_j - (mac_num_samples - 1));
								mac_j := mac_num_samples - 1;
							end if;
						end if;						
						
						-- Check if these indexes are out of valid bounds and the result should be stored
						if mac_op_sel = '1' then
							-- If in Correlation and either mac_i or mac_j is above num_samples - 1, move to store result
							if mac_i > (mac_num_samples - 1) or mac_j > (mac_num_samples - 1) then
								mac_data1 <= x"0000";
								mac_data2 <= x"0000";
								mac_state <= mac_store;
								address_array(0) <= std_logic_vector(to_unsigned(mac_store_addr + mac_m, 9));
								datain_array(0) <= mac_dataout(15 downto 0);
							
							else
								-- If both indexes valid then move to calculation stage
								address_array(0) <= std_logic_vector(unsigned(mac_start_addr) + to_unsigned(mac_i, mac_start_addr'length));
								address_array(1) <= std_logic_vector(unsigned(mac_start_addr) + to_unsigned(mac_j, mac_start_addr'length));
								mac_state <= mac_wait;
							end if;
							
						else
							-- If in Convolution and either mac_i is above num_samples - 1, or mac_j is below 0, move to store result
							if mac_i > (mac_num_samples - 1) or mac_j < 0 then
								mac_data1 <= x"0000";
								mac_data2 <= x"0000";
								mac_state <= mac_store;
								address_array(0) <= std_logic_vector(to_unsigned(mac_store_addr + mac_m, 9));
								datain_array(0) <= mac_dataout(15 downto 0);
							
							else
								-- If both indexes valid then move to calculation stage
								address_array(0) <= std_logic_vector(unsigned(mac_start_addr) + to_unsigned(mac_i, mac_start_addr'length));
								address_array(1) <= std_logic_vector(unsigned(mac_start_addr) + to_unsigned(mac_j, mac_start_addr'length));
								mac_state <= mac_wait;
							end if;
							
						end if;
						
						-- Outputs for Debugging Purposes						
						test_mac_i <= mac_i;
						test_mac_j <= mac_j;
						
					when mac_wait =>
						-- Wait for memory
						mac_state <= mac_calc;
						
					when mac_calc =>
						-- Start to get data for MAC
						mac_data1 <= dataout_array(0);
						mac_data2 <= dataout_array(1);
						
						mac_en <= '1';
						mac_reset_sig <= '0';
						
						-- Increment mac_i counter
						mac_i := mac_i + 1;
						
						mac_state <= mac_fetch;
						
						-- Outputs for Debugging Purposes
						test_mac_i <= mac_i;
						test_mac_j <= mac_j;
						
					when mac_store =>
						mac_en <= '0';
						mac_reset_sig <= '0';
					
						-- Save convolution output depending on mac_dest
						output(mac_m) <= mac_dataout; -- OUTPUT is purely used for debugging purposes
						if mac_dest = 0 then
							-- Memory Bank A
							we_array(0) <= '1';
						else
							-- Output to NoC
							send.data <= x"7" & next_dest & x"0" & "000" & mac_op_sel & mac_dataout(15 downto 0);
							send.addr <= x"0" & next_dest;
						end if;
						
						-- Increment mac_m
						mac_m := mac_m + 1;
						
						-- Go to mac_reset to mac_reset the MAC output
						mac_state <= mac_reset;
						
						-- Output for Debugging Purposes
						test_mac_m <= mac_m;
						
					when others =>
						-- Go to mac_reset
						mac_state <= mac_reset;
					end case;
					
				when others =>
					-- Go back to Reset state
					dpasp_state <= dpasp_next_state;
				end case;
			
			
		end if;
	end process fsm;
	
end architecture behaviour;