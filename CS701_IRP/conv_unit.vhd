library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.Numeric_Std.all;
use work.TdmaMinTypes.all;

entity conv_unit is
	generic(
		num_samples			: in integer := 4
	);
	port(
		clk					: in  std_logic
	);
end entity conv_unit;

architecture behaviour of conv_unit is
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
	
	-- FSM declarations
	type mac_state_type is (reset, idle, fetch, calc, store);
	signal mac_state		: mac_state_type := reset;
	
	-- Internal signals
	signal mac_clk : std_logic := '0';
	signal en : std_logic := '0';
	signal reset_sig : std_logic := '0';
	signal data1 : std_logic_vector(15 downto 0);
	signal data2 : std_logic_vector(15 downto 0);
	signal dataout	: std_logic_vector(31 downto 0);
	signal complete : std_logic := '0';
	
	type mac_data_input is array (natural range <>) of std_logic_vector(15 downto 0);
	type mac_data_output is array (natural range <>) of std_logic_vector(31 downto 0);
	signal inputA : mac_data_input(num_samples-1 downto 0);
	signal inputB : mac_data_input(num_samples-1 downto 0);
	signal output : mac_data_output((2*num_samples-2) downto 0);
	
	signal i_int : std_logic_vector(2*num_samples-1 downto 0);
	signal j_int : std_logic_vector(2*num_samples-1 downto 0);
	signal m_int : std_logic_vector(2*num_samples-1 downto 0);
	
begin

	-- AND so that we can disable MAC fully and reduce power usage
	mac_clk <= clk and en;
	
	mac1 : mac
	port map(
		clk => mac_clk,
		en => en,
		reset => reset_sig,
		data1 => data1,
		data2 => data2,	
		dataout => dataout
	);
	
	data_init : process
	begin
		inputA(0) <= "1111111111111101"; -- -3
		inputA(1) <= "0000000000000010"; -- 2
		inputA(2) <= "1111111111111111"; -- -1
		inputA(3) <= "0000000000000001"; -- 1
		
		inputB(0) <= "1111111111111111"; -- -1
		inputB(1) <= "0000000000000000"; -- 0
		inputB(2) <= "1111111111111101"; -- -3
		inputB(3) <= "0000000000000010"; -- 2
		wait;
	end process data_init;

	fsm : process(clk)
		-- y[m] = Sum(i = 0 to i = num_samples-1)(x[i] * h[i - m])
		variable i : integer := 0;
		variable j : integer := 0;
		variable m : integer := 0;
		variable invalid_count : integer := 0;
	begin
		if rising_edge(clk) then
			if mac_state = idle then
				mac_state <= fetch;
			end if;
		
			case mac_state is
			when reset =>
				-- Reset internal accumulate
				en <= '1';
				reset_sig <= '1';
				data1 <= x"0000";
				data2 <= x"0000";
				
				if m = (2*num_samples - 1) then
					-- If m is out of range then operation complete, go to idle
					mac_state <= idle;
					m := 0;
					i := 0;
					j := 0;
					complete <= '1';
				else
					-- If m is still valid, go back to fetch
					mac_state <= fetch;
					i := 0;
					j := 0;
				end if;
				
			when idle =>
				-- Do nothing
				en <= '0';
				reset_sig <= '0';
				data1 <= x"0000";
				data2 <= x"0000";
				complete <= '0';
				
			when fetch =>
				-- Wait for data to come from memory, takes 1 cycle
				en <= '0';
				reset_sig <= '0';
				
				-- Calculate address to fetch from depending on current mode
				j := num_samples - 1 + i - m; -- For Correlation
				-- j := m - i; -- For Convolution
				
				-- Increment invalid_count if address is valid for i and j values
				if i < 0 or i > num_samples-1 then
					invalid_count := invalid_count + 1;
					data1 <= x"0000";
				else
					data1 <= inputA(i); -- address_array(MEM_LOCATION_ARRAY_A) <= start_addr + i;
				end if;
				if j < 0 or j > num_samples-1 then
					invalid_count := invalid_count + 1;
					data2 <= x"0000";
				else
					data2 <= inputB(j); -- address_array(MEM_LOCATION_ARRAY_B) <= start_addr + i;
				end if;
				
				-- If both indexes are invalid go to store to save results
				if invalid_count = 2 then
					mac_state <= store;
					invalid_count := 0;
				elsif invalid_count = 1 then
					-- If one is invalid then fetch next data
					mac_state <= fetch;
					invalid_count := 0;
					
					-- Increment i counter
					i := i + 1;
				else
					-- If none are invalid then calculate result as normal
					mac_state <= calc;
					invalid_count := 0;
				end if;
				
			when calc =>
				-- Input data to MAC and store result
				-- data1 <= dataout_array(MEM_LOCATION_ARRAY_A);
				-- data2 <= dataout_array(MEM_LOCATION_ARRAY_B);
				
				en <= '1';
				reset_sig <= '0';
				
				-- Increment i counter
				i := i + 1;
				
				mac_state <= fetch;
				
			when store =>
				en <= '0';
				reset_sig <= '0';
			
				-- Save convolution output
				output(m) <= dataout;
				
				-- Increment m
				m := m + 1;
				
				-- Go to reset to reset the MAC output
				mac_state <= reset;
				
			when others =>
				-- Go to reset
				mac_state <= reset;
			end case;
			
			i_int <= std_logic_vector(to_signed(i, i_int'length));
			j_int <= std_logic_vector(to_signed(j, j_int'length));
			m_int <= std_logic_vector(to_signed(m, m_int'length));
		end if;
	end process fsm;
	
end architecture behaviour;