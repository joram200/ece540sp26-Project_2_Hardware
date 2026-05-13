typedef logic [11:0] pixel_t;
                     // row,    col
typedef pixel_t frame_t [0:239][0:319];

module vgaRegisterFile #(parameter numRegs = 16)
(
    input logic clk,
    input logic rst,
    input logic[31:0] addrIn,
    input logic[31:0] dataIn,
    output logic[31:0] dataOut,
    input logic readEn,
    input logic writeEn,

    // REG 0: VGA_CTL_REG
    output logic vgaEnReg,
    output logic pixelWriteEn,

    // REG 1: VGA_OUTPUT_ENABLE_REG, RO
    input logic[11:0] vgaOutputReg,

    // REG 2: VGA_PIXEL_ADDR
    output logic[31:0] vgaPixelAddr,
    // REG 3: VGA_PIXEL_DATA
    output logic[31:0] vgaPixelData
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
                // REG 1->3 is read only. Updated by the hardware
                if((addr != 32'd1))
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
       registerFile[1] <= {20'b0, vgaOutputReg};
    end

    always_comb
    begin: peripheral_output_logic
        vgaEnReg = registerFile[0][0];
        pixelWriteEn = registerFile[0][1];
        vgaPixelAddr = registerFile[2];
        vgaPixelData = registerFile[3];
    end
endmodule

module vga_wb_slave_agent
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

module frameBuffer
(
    input logic clk,
    input logic rst,
    input logic writeEn,
    output pixel_t outputPixel,
    input pixel_t inputPixel,
    input logic[31:0] pixelWriteAddr,
    input logic[23:0] pixelReadAddr
);
    // at min 0.004608s to write a full buffer
    // at 75Hz, 0.01333333s per frame
    localparam int FB_ROW  = 240;
    localparam int FB_COL  = 320; // width
    localparam int FB_PIXELS = FB_COL * FB_ROW;
    (* ram_style = "block" *) pixel_t frameBuffer [0:FB_PIXELS-1];

    logic[18:0] writeAddr;
    logic[18:0] readAddr;
    pixel_t readData;

    logic writeCounter;
    logic readCounter;

    assign writeAddr = pixelWriteAddr[23:12] * FB_COL + pixelWriteAddr[11:0];
    assign readAddr = pixelReadAddr[23:13] * FB_COL + pixelReadAddr[11:1];

    always_ff@(posedge clk)
    begin: frame_write
        if(writeEn)
        begin
            // row, column
            frameBuffer[writeAddr] <= inputPixel;
        end
        readData <=  frameBuffer[readAddr];
    end

    always_comb
    begin: frame_read
        outputPixel = readData;
    end
endmodule

module scanoutEngine
(
    input logic clk,
    input logic rst,
    input pixel_t inputPixel,
    input logic video_on,
    output logic[3:0] vgaRed,
    output logic[3:0] vgaGreen,
    output logic[3:0] vgaBlue
);
    always_ff@(posedge clk)
    begin
        if(rst)
        begin
            vgaRed <= 'b0;
            vgaGreen <= 'b0;
            vgaBlue <= 'b0;
        end
        else
        begin
            if(video_on)
            begin
                vgaRed <= inputPixel[11:8];
                vgaGreen <= inputPixel[7:4];
                vgaBlue <= inputPixel[3:0];
            end
            else
            begin
                vgaRed <= 'b0;
                vgaGreen <= 'b0;
                vgaBlue <= 'b0;
            end
        end
    end
endmodule

module vgaTop #(parameter DATA_WIDTH = 32, ADDR_WIDTH = 32)
(
    input logic wb_clk_i,
    input logic wb_rst_i,
    input logic wb_cyc_i,
    input logic[ADDR_WIDTH-1:0] wb_adr_i,
    input logic[DATA_WIDTH-1:0] wb_dat_i,
    input logic wb_we_i,
    input logic wb_stb_i,
    output logic[DATA_WIDTH-1:0] wb_dat_o,
    output logic wb_ack_o,
    output logic wb_err_o,

    output logic[3:0] vgaRed,
    output logic[3:0] vgaGreen,
    output logic[3:0] vgaBlue,
    output logic vgaHsync,
    output logic vgaVsync
);
    logic videoOn;
    logic[11:0] pixelRowAddr;
    logic[11:0] pixelColAddr;
    pixel_t displayPixel;
    logic[31:0] pixelAddr;
    logic[31:0] pixelData;
    logic regWriteEn;
    logic regReadEn;
    logic vgaEn;
    logic pixelWriteEn;

    logic[3:0] vgaRed_m;
    logic[3:0] vgaGreen_m;
    logic[3:0] vgaBlue_m;

    always_ff@(posedge wb_clk_i)
    begin
        if(vgaEn)
        begin
            vgaRed <= vgaRed_m;
            vgaGreen <= vgaGreen_m;
            vgaBlue <= vgaBlue_m;
        end
        else
        begin
            vgaRed <= 'b0;
            vgaGreen <= 'b0;
            vgaBlue <= 'b0;
        end
    end

    // pixel addr from software generates done
    vgaRegisterFile vgaRegFile
    (
        .clk(wb_clk_i),
        .rst(wb_rst_i),
        .addrIn(wb_adr_i),
        .dataIn(wb_dat_i),
        .dataOut(wb_dat_o),
        .readEn(regReadEn),
        .writeEn(regWriteEn),

        .vgaEnReg(vgaEn),
        .pixelWriteEn(pixelWriteEn),
        .vgaOutputReg({vgaBlue, vgaGreen, vgaRed}),
        .vgaPixelAddr(pixelAddr),
        .vgaPixelData(pixelData)
    );
    
    vga_wb_slave_agent vgaAgent
    (
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),
        .wb_cyc_i(wb_cyc_i),
        .wb_we_i(wb_we_i),
        .wb_stb_i(wb_stb_i),
        .wb_ack_o(wb_ack_o),
        .wb_err_o(wb_err_o),
        .readEn(regReadEn),
        .writeEn(regWriteEn)
    );

    scanoutEngine myEngine
    (
        .clk(wb_clk_i),
        .rst(wb_rst_i),
        .video_on(videoOn),
        .inputPixel(displayPixel),
        .vgaRed(vgaRed_m),
        .vgaGreen(vgaGreen_m),
        .vgaBlue(vgaBlue_m)
    );

    frameBuffer myBuff
    (
        .clk(wb_clk_i),
        .rst(wb_rst_i),
        .writeEn(pixelWriteEn),
        .outputPixel(displayPixel),
        .inputPixel(pixelData[11:0]),
        .pixelReadAddr({pixelRowAddr, pixelColAddr}), // this comes from the dtg
        .pixelWriteAddr(pixelAddr)
    );
    dtg myDtg
    (
        .clock(wb_clk_i),
        .rst(wb_rst_i),
        .horiz_sync(vgaHsync), 
        .vert_sync(vgaVsync), 
        .video_on(videoOn), 
        .pixel_row(pixelRowAddr), 
        .pixel_column(pixelColAddr)
    );
endmodule

