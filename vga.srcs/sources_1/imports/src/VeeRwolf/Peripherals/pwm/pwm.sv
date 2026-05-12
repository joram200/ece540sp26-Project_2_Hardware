/**
 * @file pwm.c
 * @author Matthew Hardenburgh
 * @brief hdl code for pwm peripheral. 
 * @copyright copyright (c) 2026 Matthew Hardenburgh, all rights reserved
 * @date 4/29/26
 * 
*/

package util;
    typedef enum logic[1:0]
    {  
        IDLE,
        WRITE,
        READ
    } wb_states_t;
endpackage

module pwm
(
    input logic clk,
    input logic reset,

    input logic en,
    input logic[31:0] freq,
    input logic[31:0] dutyCycle,

    output logic pwm_out
);
    logic[31:0] freqCounter;

    
    always_ff @(posedge clk, posedge reset) 
    begin: counter
        if(reset)
        begin
            freqCounter <= 32'b0;
        end
        else
        begin
            if(freqCounter == freq)
            begin
                freqCounter <= 32'b0;
            end
            else
            begin
                freqCounter <= freqCounter + 1;
            end
        end
    end

    always@(posedge clk, posedge reset)
    begin : pwm_out_logic
        if(reset)
        begin
            pwm_out <= 1'b0;
        end
        else
        begin
            if(freqCounter < dutyCycle)
            begin
                pwm_out <= 1'b1 & en;
            end
            else
                pwm_out <= 1'b0 & en;
        end
    end

endmodule

module registerFile #(parameter numRegs = 14, numPwm = 6)
(
    input logic clk,
    input logic rst,
    input logic[31:0] addrIn,
    input logic[31:0] dataIn,
    output logic[31:0] dataOut,
    input logic readEn,
    input logic writeEn,

    // REG 0: PWM_ENABLE_REG
    output logic[numPwm-1:0] pwmEnReg,

    // REG 1: PWM_OUTPUT_REG
    input logic[numPwm-1:0] pwmOutputReg,

    // REG 2-7: PWM_FREQ_REG
    output logic[31:0] pwmFreq[6],
    // REG 8-13: PWM_DUTY_CYCLE_REG
    output logic[31:0] pwmDutyCycleReg[6]
);
    logic[31:0] registerFile[numRegs];
    logic[31:0] addr;
    
    always_comb
    begin: addr_decode_logic
        addr = (addrIn & 32'h0000003F) >> 2;
    end

    always_ff@(posedge clk, posedge rst)
    begin: write_logic
        if(rst)
        begin
            for(int i = 0; i < numRegs; i++)
            begin
                registerFile[i] <= 32'b0;
            end
        end
        else
        begin
            if(writeEn && !(addr > numRegs))
            begin
                // REG 1 is read only. Updated by the hardware
                if(addr != 32'b1)
                    registerFile[addr] <= dataIn;
            end
        end
    end

    always_comb
    begin: read_logic
        if(readEn && !(addr > numRegs))
            dataOut = registerFile[addr];
        else
            dataOut = 'b0;
    end

    always_ff@(posedge clk)
    begin: peripheral_input_logic
       registerFile[1] <= pwmOutputReg;
    end

    always_comb
    begin: peripheral_output_logic
        pwmEnReg = registerFile[0];
        for(int i = 0; i < 6; i++)
        begin
            pwmFreq[i] = registerFile[i+2];
            pwmDutyCycleReg[i] = registerFile[i+8];
        end
    end
endmodule

module wb_slave_agent
(
    input logic wb_clk_i,
    input logic wb_rst_i,
    input logic wb_cyc_i,
    //input logic[3:0] wb_sel_i,
    input logic wb_we_i, 
    input logic wb_stb_i,

    output logic wb_ack_o, 
    output logic wb_err_o,
    output logic wb_inta_o, // interrupt output

    output logic readEn,
    output logic writeEn
);

    util::wb_states_t stateCounter = util::IDLE;
    util::wb_states_t nextState = util::IDLE;

    always_ff @(posedge wb_clk_i, posedge wb_rst_i)
    begin: state_counter
        if(wb_rst_i)
            stateCounter <= util::IDLE;
        else
            stateCounter <= nextState;
    end

    always_comb
    begin: next_state_logic
        unique case(stateCounter)
            util::IDLE:
            begin
                if(wb_rst_i)
                    nextState = util::IDLE;
                else
                begin
                    if(wb_cyc_i && wb_stb_i)
                    begin
                        if(wb_we_i)
                            nextState = util::WRITE;
                        else
                            nextState = util::READ;
                    end
                    else
                        nextState <= util::IDLE;
                end
            end
            util::READ, util::WRITE:
                nextState = util::IDLE;
        endcase
    end

    always_comb
    begin: output_logic
        unique case(stateCounter)
            util::IDLE:
            begin
                wb_ack_o = 1'b0;
                readEn = 1'b0;
                writeEn = 1'b0;
            end
            util::WRITE:
            begin
                wb_ack_o = 1'b1;
                readEn = 1'b0;
                writeEn = 1'b1;
            end
            util::READ:
            begin
                wb_ack_o = 1'b1;
                readEn = 1'b1;
                writeEn = 1'b0;
            end
        endcase
    end

    assign wb_err_o = 1'b0;
    assign wb_inta_o = 1'b0;
endmodule

module pwmTop #(parameter dw = 32, aw = 32, NUM_PWM = 6)
(
    	// WISHBONE Interface
	wb_clk_i, wb_rst_i, wb_cyc_i, wb_adr_i, wb_dat_i, wb_we_i, wb_stb_i,
	wb_dat_o, wb_ack_o, wb_err_o,

    pwmOutput
);
    //
    // WISHBONE Interface
    //
    input             wb_clk_i;	// Clock
    input             wb_rst_i;	// Reset
    input             wb_cyc_i;	// cycle valid input
    input   [aw-1:0]	wb_adr_i;	// address bus inputs
    input   [dw-1:0]	wb_dat_i;	// input data bus
    input             wb_we_i;	// indicates write transfer
    input             wb_stb_i;	// strobe input
    output  [dw-1:0]  wb_dat_o;	// output data bus
    output            wb_ack_o;	// normal termination
    output            wb_err_o;	// termination w/ error
    output logic[NUM_PWM-1:0] pwmOutput;

    logic readEn;
    logic writeEn;
    logic[NUM_PWM-1:0] pwmEn;
    logic[31:0] pwmFrq[NUM_PWM];
    logic[31:0] pwmDutyCycle[NUM_PWM];

    wb_slave_agent wishbone_agent
    (
        .wb_clk_i(wb_clk_i), .wb_rst_i(wb_rst_i), 
        .wb_cyc_i(wb_cyc_i),
        .wb_we_i(wb_we_i),
        .wb_stb_i(wb_stb_i),
        .wb_ack_o(wb_ack_o),
        .wb_err_o(wb_err_o),
        .readEn(readEn),
        .writeEn(writeEn)
    );

    registerFile myRegFile
    (
        .clk(wb_clk_i), .rst(wb_rst_i), .addrIn(wb_adr_i), .dataIn(wb_dat_i), .dataOut(wb_dat_o), .readEn(readEn), .writeEn(writeEn), 
        .pwmEnReg(pwmEn), .pwmOutputReg(pwmOutput), .pwmFreq(pwmFrq), .pwmDutyCycleReg(pwmDutyCycle)
    );

    genvar iIter;

    generate
        for(iIter = 0; iIter < NUM_PWM; iIter++)
        begin
            pwm myPwm(.clk(wb_clk_i), .reset(wb_rst_i), .en(pwmEn[iIter]), .freq(pwmFrq[iIter]), .dutyCycle(pwmDutyCycle[iIter]), .pwm_out(pwmOutput[iIter]));
        end
    endgenerate

endmodule