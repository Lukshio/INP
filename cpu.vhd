-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Lukas Jezek <xjezek19 AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

--PC
signal pc_reg		    :std_logic_vector(12 downto 0);
signal pc_inc	        :std_logic;
signal pc_dec		    :std_logic;
signal pc_ptr           :std_logic;
--PTR
signal ptr_reg		    :std_logic_vector(12 downto 0) := "1000000000000";
signal ptr_inc		    :std_logic;
signal ptr_dec		    :std_logic;
--CNT
signal cnt_reg		    :std_logic_vector(7 downto 0);
signal cnt_inc	        :std_logic;
signal cnt_dec	        :std_logic;
--TMP pro ukladani cyklu
signal tmp_ptr          :std_logic_vector(12 downto 0);

--MX1
signal sel_MX1_Addr     :std_logic;
signal MX1_output       :std_logic_vector(12 downto 0 ) := (others => '0');

--MX2
signal sel_MX2_WData    :std_logic_vector (1 downto 0) := (others => '0');
signal MX2_output       :std_logic_vector(7 downto 0) := (others => '0');


-- FSM
type fsm_state is (
    init_state,
    fetch_state,
    decode_state,
    ptr_inc_state,
    ptr_dec_state,
    value_inc_state,
    dec_val_state,
    value_inc_help_state,
    dec_val_help_state,
    while_start_state,
    while_start_help1_state,
    while_start_help2_state,
    while_start_help_null_state,
    while_end_state,
    while_end_help_state,
    while_end_move_ptr_state,
    while_end_move_ptr_help_state,
    prepare_print_state,
    print_state,
    input_state,
    input_help_state,
    prepare_do_while_end_state,
    do_while_end_state,
    do_while_start_state,
    null_input_state
);

signal state: fsm_state := init_state;
signal next_state: fsm_state := init_state;

begin
-- CNT nakonec nepouzito
    cnt: process (CLK, RESET, cnt_inc, cnt_dec) is
		begin 
            if(RESET = '1') then
                cnt_reg <= (others => '0');
            elsif rising_edge(CLK) then
                if (cnt_inc = '1') then
                    cnt_reg <= cnt_reg + 1;
                elsif (cnt_dec = '1') then
                    cnt_reg <= cnt_reg - 1;
                end if;     
            end if;
		end process;

-- PC
    pc: process (CLK, RESET, pc_inc, pc_dec, pc_ptr) is
		begin 
            if(RESET = '1') then
                pc_reg <= "0000000000000";
            elsif rising_edge(CLK) then
                if(pc_inc = '1') then
                    pc_reg <= pc_reg + 1;
                elsif (pc_dec = '1') then
                    pc_reg <= pc_reg - 1;
                elsif (pc_ptr = '1') then
                    pc_reg <= tmp_ptr;
                end if;
            end if;        
		end process;

-- PTR
    ptr: process (CLK, RESET, ptr_inc, ptr_dec) is
    begin 
        if(RESET = '1') then
            ptr_reg <= "1000000000000";
        elsif rising_edge(CLK) then
            if(ptr_inc = '1') then
                if ptr_reg = "1111111111111" then
                    ptr_reg <= "1000000000000";
                else
                    ptr_reg <= ptr_reg + 1;
                end if;
            elsif (ptr_dec = '1') then
                if ptr_reg = "1000000000000" then
                    ptr_reg <= "1111111111111";
                else
                    ptr_reg <= ptr_reg - 1;
                end if;
            end if;
        end if;        
    end process;

-- MX1
    MUX1: process(CLK, RESET, sel_MX1_Addr, pc_reg, ptr_reg) is
        begin
            if RESET = '1' then
                MX1_output <= (others => '0');
            elsif (CLK'event) then
                case sel_MX1_Addr is
                    when '0' =>
                        MX1_output <= pc_reg;
					when '1' =>
						MX1_output <= ptr_reg;
                    when others => 
                end case;
            end if;
        end process;
    DATA_ADDR <= MX1_output;

-- MX2
    MUX2: process(CLK, RESET, sel_MX2_WData, IN_DATA, DATA_RDATA) is
        begin
            if RESET = '1' then
                MX2_output <= (others => '0');
            elsif (CLK'event) then
                case sel_MX2_WData is
                    when "00" =>
                        MX2_output <= IN_DATA;
					when "01" =>
						MX2_output <= DATA_RDATA+1;
                    when "10" => 
                        MX2_output <= DATA_RDATA - 1;
                    when others => 
                end case;
            end if;
        end process;
        DATA_WDATA <= MX2_output;

-- FSM
    state_logic: process (CLK, RESET, EN)
        begin
            if RESET = '1' then
                state <= init_state;
            elsif CLK'event and CLK = '1' then
                if EN = '1' then
                    state <= next_state;
                end if;
            end if;
    end process;

        fsm: process (state, OUT_BUSY, IN_VLD, DATA_RDATA)
        begin
        --set init vals
                pc_inc <= '0';
                pc_dec <= '0';
                pc_ptr <= '0';
                ptr_inc <= '0';
                ptr_dec <= '0';

                DATA_EN <= '0';
                DATA_RDWR <= '0';
                IN_REQ  <= '0';
                OUT_WE <= '0';

                sel_MX2_WData <= "00";
                --sel_MX1_Addr <= '0';
                --pc_ptr <= '0';
                case state is
                    when init_state =>
                        sel_MX1_Addr <= '0';
                        next_state <= fetch_state;
                    when fetch_state =>
                        sel_MX1_Addr <= '0';
                        DATA_EN <= '1';
                        next_state <= decode_state;
                    when decode_state =>
                    sel_MX1_Addr <= '0';
                        case DATA_RDATA is
                            when X"3E" =>  --   >
                                next_state <= ptr_inc_state;
                            when X"3C" =>   --  <
                                next_state <= ptr_dec_state;
                            when X"2B" =>   --  +
                                --sel_MX1_Addr <= '1';
                                next_state <= value_inc_state;
                            when X"2D" =>   --  -
                                next_state <= dec_val_state;
                            when X"5B" =>   --  [
                                next_state <= while_start_state;
                            when X"5D" =>   --  ]
                                next_state <= while_end_state;
                            when X"28" =>  --  (
                                next_state <= do_while_start_state;
                            when X"29" =>  --  )
                                next_state <= prepare_do_while_end_state;
                            when X"2E" =>   --  .
                                next_state <= prepare_print_state;
                            when X"2C" =>   --  ,
                                next_state <= input_state;
                            when X"00" =>   -- stop
                                next_state <= null_input_state;
                            when others =>
                                next_state <= null_input_state;
                        end case;
                when ptr_inc_state =>
                        pc_inc <= '1';
                        ptr_inc <= '1';
                        next_state <= fetch_state;
                when ptr_dec_state =>
                        pc_inc <= '1';
                        ptr_dec <= '1';
                        next_state <= fetch_state;
                when value_inc_state =>
                        --sel_MX1_Addr <= '1';
                        DATA_EN <= '1';
                        DATA_RDWR <= '0';
                        sel_MX1_Addr <= '1';
                        next_state <= value_inc_help_state;
                when value_inc_help_state =>
                        --sel_MX1_Addr <= '1';
                        DATA_EN <= '1';
                        DATA_RDWR <= '1';
                        sel_MX1_Addr <= '1';
                        sel_MX2_WData <= "01";
                        pc_inc <= '1';
                        next_state <= fetch_state;
                when dec_val_state =>
                        --sel_MX1_Addr <= '1';
                        DATA_EN <= '1';
                        DATA_RDWR <= '0';
                        sel_MX1_Addr <= '1';
                        next_state <= dec_val_help_state;
                when dec_val_help_state =>
                        --sel_MX1_Addr <= '1';
                        DATA_EN <= '1';
                        DATA_RDWR <= '1';
                        sel_MX1_Addr <= '1';
                        sel_MX2_WData <= "10";
                        pc_inc <= '1';
                        next_state <= fetch_state;
                when while_start_state =>
                    sel_MX1_Addr <= '1';
                    pc_inc <= '1';
                    DATA_EN <= '1';
                    DATA_RDWR <= '0';
                    next_state <= while_start_help1_state;
                when while_start_help1_state =>
                    if DATA_RDATA = 0 then
                        sel_MX1_Addr <= '0';
                        DATA_EN <= '1';
                        DATA_RDWR <= '0';
                        next_state <= while_start_help2_state;
                    else
                        next_state <= fetch_state;
                    end if;
                when while_start_help2_state =>
                    DATA_EN <= '1';
                    if DATA_RDATA = X"5D" then
                        pc_inc <= '1';
                        next_state <= fetch_state;
                    else
                        pc_inc <= '1';
                        next_state <= while_start_help_null_state;
                    end if;
                when while_start_help_null_state =>
                        sel_MX1_Addr <= '0';
                        DATA_EN <= '1';
                        DATA_RDWR <= '0';
                        next_state <= while_start_help2_state;
                when while_end_state =>
                        sel_MX1_Addr <= '1';
                        DATA_RDWR <= '0';
                        DATA_EN <= '1';
                        next_state <= while_end_help_state;
                when while_end_help_state =>
                        if DATA_RDATA = "00000000" then
                            pc_inc <= '1';
                            next_state <= fetch_state;
                        else
                            sel_MX1_Addr <= '0';
                            pc_dec <= '1';
                            next_state <= while_end_move_ptr_state;
                        end if;
                when while_end_move_ptr_state =>
                        sel_MX1_Addr <= '0';
                        DATA_RDWR <= '0';
                        DATA_EN <= '1';
                        next_state <= while_end_move_ptr_help_state;
                when while_end_move_ptr_help_state =>
                        if DATA_RDATA = X"5B" then
                            pc_inc <= '1';
                            next_state <= fetch_state;
                        else
                            pc_dec <= '1';
                            next_state <= while_end_move_ptr_state;
                        end if;
                when do_while_start_state =>
                    tmp_ptr <= pc_reg + 1;
                    pc_inc <= '1';
                    next_state <= fetch_state;
                when prepare_do_while_end_state =>
                        sel_MX1_Addr <= '1';
                        DATA_EN <= '1';
                        DATA_RDWR <= '0';
                        pc_inc <= '1';
                        next_state <= do_while_end_state;
                when do_while_end_state =>
                    if DATA_RDATA = "00000000" then
                        next_state <= fetch_state;
                    else
                        pc_ptr <= '1';
                        next_state <= fetch_state;
                    end if;
                when input_state =>
                    next_state <= input_help_state;
                    IN_REQ <= '1';
                    sel_MX1_Addr <= '1';
                    sel_MX2_WData <= "00";
                when input_help_state =>
                    if(IN_VLD = '1') then
                        DATA_EN <= '1';
                        DATA_RDWR <= '1';
                        IN_REQ <= '0';
                        pc_inc <= '1';
                        next_state <= fetch_state;
                    else
                        IN_REQ <= '1';
                        sel_MX1_Addr <= '1';
                        sel_MX2_WData <= "00";
                        next_state <= input_state;
                    end if;
                when prepare_print_state =>
                    if(OUT_BUSY = '0') then
                        DATA_EN <= '1';
                        DATA_RDWR <= '0';
                        sel_MX1_Addr <= '1';
                        next_state <= print_state;
                    else
                        next_state <= prepare_print_state;
                    end if;
                when print_state =>
                    sel_MX1_Addr <= '1';
                    DATA_EN <= '1';
                    DATA_RDWR <= '0';
                    OUT_WE <= '1';
                    OUT_DATA <= DATA_RDATA;
                    pc_inc <= '1';
                    next_state <= fetch_state;
                when null_input_state =>
                when others =>
                    pc_inc <= '1';
                    end case;
            end process;
end behavioral;