library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wolfcore is
        port(
                dataOutput      : out std_logic_vector(31 downto 0);
                dataInput       : in std_logic_vector(31 downto 0);
                dataAddr        : out std_logic_vector(31 downto 0);
                dataWrEn        : out std_logic;
                instrInput      : in std_logic_vector(31 downto 0);
                pc                      : buffer std_logic_Vector(31 downto 0);
                CPU_Status      : buffer std_logic_vector(31 downto 0);
                rst                     : in std_logic;
                clk                     : in std_logic;
                forceRoot       : in std_logic;
                flushing        : out std_logic
        );
end entity;

architecture default of wolfcore is
        type regFileType is array(12 downto 0) of std_logic_vector(31 downto 0);
        signal inputA   : std_logic_vector(31 downto 0);
        signal inputB   : std_logic_vector(31 downto 0);
        signal regFile : regFileType;

        type cpuStateType is ( Nominal, Flush );
        signal cpuState :   cpuStateType;
        --signal pc             : std_logic_vector(31 downto 0);
        signal ALU_Overflow : std_logic_vector(31 downto 0);
        signal ALU_Out  : std_logic_vector(31 downto 0);
        signal ALU_Status       : std_logic_vector(7 downto 0);
        signal ALU_reg: std_logic_vector(31 downto 0);
        signal ALU_Overflow_reg: std_logic_vector(31 downto 0);
        signal ALU_Status_reg : std_logic_vector(7 downto 0);
        -- The instruction as it travels down the pipeline
        signal instrDecode      : std_logic_vector(31 downto 0);
        signal instrExecute     : std_logic_vector(31 downto 0);
        signal instrWB          : std_logic_vector(31 downto 0);
        -- Used during decode
        signal immEn    : std_logic;
        signal regA             : std_logic_vector(3 downto 0);
        signal regB             : std_logic_vector(3 downto 0);
        signal inputImm : std_logic_vector(13 downto 0);
        signal shadowPC : std_logic_vector(31 downto 0);

        -- Used during execute
        signal opcExecute: std_logic_vector(4 downto 0);
        signal wbReg    : std_logic_vector(3 downto 0);
        signal wbCond   : std_logic_vector(2 downto 0);
        signal wbEn             : std_logic;
        signal updateStatus : std_logic;

        signal instrWriteBack : std_logic_vector(31 downto 0);
        signal opcWriteBack : std_logic_vector(4 downto 0);

        -- The magnificent combinatorial ALU! All hail the ALU!
        component ALU 
                port(
                instr                   : in std_logic_vector(4 downto 0);              -- instruction (decoded)
                inputA                  : in std_logic_vector(31 downto 0);             -- input data A
                inputB                  : in std_logic_vector(31 downto 0);             -- input data B
                ALU_Out                 : buffer std_logic_vector(31 downto 0);    -- ALU results 
                ALU_Overflow    : buffer std_logic_vector(31 downto 0);    -- ALU overflow results 
                ALU_Status              : buffer std_logic_vector(7 downto 0)           -- Status of the ALU
                );
        end component;  


begin

        mainALU: ALU port map( 
                instr => opcExecute,
                inputA => inputA,
                inputB => inputB,
                ALU_Out => ALU_Out,
                ALU_Overflow => ALU_Overflow,
                ALU_Status => ALU_Status
                );

process(opcWriteBack, CPU_Status, wbCond) begin
        if(opcWriteBack = "00001") then
                wbEn <= '1';
        else    
                case wbCond is
                        -- Always
                        when "001" =>
                                wbEn <= '1';
                        -- Never
                        when "000" =>
                                wbEn <= '0';
                        -- When 0
                        when "010" =>
                                wbEn <= CPU_Status(7);
                        -- When not 0
                        when "011" =>
                                wbEn <= not CPU_Status(7);
                        -- When "positive" -> MSB = 0
                        when "100" =>
                                wbEn <= not CPU_Status(6);
                        -- When "negative" -> MSB = 1
                        when "101" =>
                                wbEn <= CPU_Status(6);
                        when "110" =>
                                wbEn <= CPU_Status(5);
                        when "111" =>
                                wbEn <= not CPU_Status(5);
                        when others =>
                                wbEn <= '0';
                end case;
        end if;
end process;

process(cpuState) begin
    if(cpuState = Nominal) then
        flushing <= '0';
    else
        flushing <= '1';
    end if;
end process;

process(clk, rst) begin
        if(rst = '1') then
                inputA  <= X"0000_0000";        
                inputB  <= X"0000_0000";        
                pc              <= X"0000_0000";        
                CPU_Status <= X"0000_0000";
                for i in regFile'range loop
                        regFile(i)      <= X"0000_0000";
                end loop;
                instrDecode     <= X"0000_0000";
                instrExecute <= X"0000_0000";
                instrWB         <= X"0000_0000";

                immEn   <= '0';
                regA    <= X"0";
                regB    <= X"0";
                inputImm <= std_logic_vector(to_unsigned(0, 14));
                opcExecute      <= "00000";
                wbReg   <= X"0";
                wbCond  <= "000";

                cpuState    <= Nominal;
                
                instrWriteBack  <= X"0000_0000";
                opcWriteBack    <= "00000";
        elsif (clk'event and clk='1') then
                -- FETCH
                --if( cpuState = Nominal ) then
                    immEn       <= instrInput(31);
                    regA        <= instrInput(30 downto 27);
                    regB        <= instrInput(26 downto 23);
                    inputImm    <= instrInput(26 downto 13);
                    shadowPC    <= pc;

                    instrDecode <= instrInput;
                --else
                --    immEn       <= '0';
                --    regA        <= "0000";
                --    regB        <= "0000";
                --    inputImm    <= std_logic_vector(to_unsigned(0, 14));
                --    shadowPC    <= X"0000_0000";

                --    instrDecode <= X"0000_0000";
                --end if;

                -- DECODE
                if(immEn = '1') then
                        inputB  <= std_logic_vector(to_unsigned(0, 18)) & inputImm;
                else
                        case to_integer(unsigned(regB)) is
                                when 13 =>
                                        inputB  <= shadowPC;
                                when 14 =>
                                        inputB  <= ALU_Overflow;
                                when 15 =>
                                        inputB  <= CPU_Status;
                                when others =>
                                        inputB  <= regFile(to_integer(unsigned(regB)));
                        end case;
                end if;

                case to_integer(unsigned(regA)) is
                        when 13 =>
                                inputA  <= shadowPC;
                        when 14 =>
                                inputA  <= ALU_Overflow;
                        when 15 =>
                                inputA  <= CPU_Status;
                        when others =>
                                inputA  <= regFile(to_integer(unsigned(regA)));
                end case;
    
                if( cpuState = Nominal ) then
                    opcExecute      <= instrDecode(12 downto 8);
                    instrExecute    <= instrDecode;
                else
                    opcExecute      <= "00000";
                    instrExecute    <= X"0000_0000"; 
                end if;
        
                -- EXECUTE
                -- Stuff that ripples through the ALU gets copied into a flipflop
                if( cpuState = Nominal ) then
                    ALU_reg                 <= ALU_Out;
                    ALU_Overflow_reg <= ALU_Overflow;
                    ALU_Status_reg  <= ALU_Status;

                    -- If it's a load/store operation, we need to do something besides the ALU operation
                    -- If STORE operation
                    if( opcExecute = "00010" ) then
                            dataWrEn        <= '1'; 
                            dataOutput      <= inputA;
                            dataAddr        <= inputB;
                    -- Perhaps LOAD then?
                    elsif ( opcExecute = "00001" ) then
                            dataWrEn        <= '0';
                            dataAddr        <= inputB;
                    else
                            dataWrEn        <= '0';
                            dataOutput      <= X"0000_0000";
                            dataAddr        <= X"0000_0000";
                    end if;

                    -- We take along important information for the writeback
                    instrWriteBack  <= instrExecute;
                    opcWriteBack    <= instrExecute(12 downto 8);
                    wbReg           <= instrExecute(7 downto 4);
                    wbCond          <= instrExecute(3 downto 1);
                    updateStatus    <= instrExecute(0);
                else
                    instrWriteBack  <= X"0000_0000";
                    opcWriteBack    <= "00000";
                    wbReg           <= "0000";
                    wbCond          <= "000";
                    updateStatus    <= '0';

                    ALU_reg         <= X"0000_0000";
                    ALU_Overflow_reg <= X"0000_0000";
                    ALU_Status_reg  <= X"00";
                end if;

                -- WRITEBACK
                if(wbEn='1' and opcWriteBack="00001" and cpuState = Nominal) then
                        case to_integer(unsigned(wbReg)) is
                                when 0 to 12 =>
                                        regFile(to_integer(unsigned(wbReg))) <= dataInput;
                                        pc <= std_logic_vector(unsigned(pc) + to_unsigned(1, pc'length));
                                        cpuState <= Nominal;
                                when 13 =>
                                        pc <= dataInput;
                                        cpuState <= Flush;
                                when others =>
                                        pc <= std_logic_vector(unsigned(pc) + to_unsigned(1, pc'length));
                                        cpuState <= Nominal;
                        end case;
                elsif(wbEn = '1' and cpuState = Nominal) then
                        case to_integer(unsigned(wbReg)) is
                                when 0 to 12 =>
                                regFile(to_integer(unsigned(wbReg))) <= ALU_reg;
                                    pc <= std_logic_vector(unsigned(pc) + to_unsigned(1, pc'length));
                                    cpuState <= Nominal;
                                when 13 =>
                                    pc <= ALU_reg;
                                    cpuState <= Flush;
                                when others =>
                                    pc <= std_logic_vector(unsigned(pc) + to_unsigned(1, pc'length));
                                    cpuState <= Nominal;
                        end case;                       
                else
                        pc <= std_logic_vector(unsigned(pc) + to_unsigned(1, pc'length));
                        cpuState <= Nominal;
                end if;

                if( (forceRoot = '1' or CPU_Status(31 downto 30) = "00") 
                        and wbReg = X"F" 
                        and wbEn = '1'
                        ) then
                        CPU_Status <= ALU_reg;
                elsif(updateStatus = '1') then
                        CPU_Status(7 downto 0)  <= ALU_Status_reg;
                end if;
        end if;
end process;
end architecture;
