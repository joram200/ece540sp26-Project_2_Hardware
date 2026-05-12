/**
 * @file	dtg.sv
 * @brief	Horizontal/Vertical display timing and sync generator for VESA timing
 *
 * @author	Original:  Srivatsa Yogendra, John Lynch, and Roy Kravitz	
 * @author	Modifications: Roy Kravitz (roy.kravitz@pdx.edu) and Gemini
 * @date	31-Jan-2026
 * @version	3.0
 *
 * @detail
 *	 Revision History
 *	 ----------------
 *	1.0	John Lynch	10-Oct-2012	Added video_on output; simplified counter logic
 *	1.5	Roy Kravitz	25-Oct-2012	Modified for kcpsm6 and Nexys3
 * 	2.0	Srivatsa Y.	20-Sep-2017	Modified the design, to produce signals for 1024*768 resolution
 *	3.0	Roy Kravitz	31-Jan-2026	Converted to SystemVerilog, made default 640 x 480 @ 60Hz
 *
 *	Description:
 *	------------
 *	 This circuit provides pixel location and horizontal and vertical sync for a 1024 x 768 video image. 
 */
module dtg(
	input logic			clock,			// pixel clock: 25 MHz (default 640x480@60) or 31.5 MHz (DTG_640x480_75HZ)
	input logic			rst,			// reset - asserted high for reset
	output logic		horiz_sync,		// Horizontal sync signal to display
	output logic		vert_sync,		// Vertical sync signal to display
	output logic		video_on,		// video is enabled - 1-active video area 0-blanking		
	output logic [11:0]	pixel_row,		// current pixel row address
	output logic [11:0]	pixel_column	// curren pixel column address
);

// -----------------------------------------------------------------------------
// Timing presets
//
// This module keeps the SAME constant names (HORIZ_PIXELS, H_FRONT_PORCH, ...),
// but allows selecting between two 640x480 modes using a compile-time define.
//
// Default (recommended for HDMI TX bridge): 640x480 @ 60 Hz
//   pixel clock ≈ 25.175 MHz (often OK at 25.000 MHz in FPGA labs)
// Optional (often OK on VGA DAC, less reliable via HDMI): 640x480 @ 75 Hz
//   pixel clock = 31.500 MHz
//
// Select 75 Hz mode by adding: +define+DTG_640x480_75HZ  (or `define in a header)
// -----------------------------------------------------------------------------

`ifdef DTG_640x480_75HZ
    // --- 640x480 @ 75 Hz (VGA-friendly) ---
    // Horizontal: 640 active, 16 FP, 64 sync, 120 BP => total 840
    // Vertical:   480 active,  1 FP,  3 sync,  16 BP => total 500
    localparam HORIZ_PIXELS  = 12'd640;
    localparam H_FRONT_PORCH = 12'd16;
    localparam H_SYNC_WIDTH  = 12'd64;
    localparam H_BACK_PORCH  = 12'd120;

    localparam VERT_PIXELS   = 12'd480;
    localparam V_FRONT_PORCH = 12'd1;
    localparam V_SYNC_WIDTH  = 12'd3;
    localparam V_BACK_PORCH  = 12'd16;
`else
    // --- 640x480 @ 60 Hz (HDMI/CEA-friendly) ---
    // Horizontal: 640 active, 16 FP, 96 sync, 48 BP => total 800
    // Vertical:   480 active, 10 FP,  2 sync, 33 BP => total 525
    localparam HORIZ_PIXELS  = 12'd640;
    localparam H_FRONT_PORCH = 12'd16;
    localparam H_SYNC_WIDTH  = 12'd96;
    localparam H_BACK_PORCH  = 12'd48;

    localparam VERT_PIXELS   = 12'd480;
    localparam V_FRONT_PORCH = 12'd10;
    localparam V_SYNC_WIDTH  = 12'd2;
    localparam V_BACK_PORCH  = 12'd33;
`endif

// --- Derived Timing (do not edit) ---
localparam HSYNC_START   = HORIZ_PIXELS + H_FRONT_PORCH;
localparam HSYNC_END     = HORIZ_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH;
localparam HCNT_MAX      = HORIZ_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH + H_BACK_PORCH - 1;

localparam VSYNC_START   = VERT_PIXELS + V_FRONT_PORCH;
localparam VSYNC_END     = VERT_PIXELS + V_FRONT_PORCH + V_SYNC_WIDTH;
localparam VCNT_MAX      = VERT_PIXELS + V_FRONT_PORCH + V_SYNC_WIDTH + V_BACK_PORCH - 1;

always_ff @(posedge clock) 
	begin: generate_video_signals
		if(rst)
		begin
			pixel_column <= 1'b0;
			pixel_row    <= 1'b0;
			horiz_sync   <= 1'b1;
			vert_sync    <= 1'b1;
			video_on     <= 1'b0;
		end
		else 
		begin: handle_sync_counters
			// increment horizontal sync counter.  Wrap if at end of row
			if(pixel_column == HCNT_MAX) 
			begin
				pixel_column <= 12'd0;
				if (pixel_row == VCNT_MAX)
					pixel_row <= 12'd0;
				else
					pixel_row <= pixel_row + 12'd1;
			end
			else 
			begin
				pixel_column <= pixel_column + 12'd1;
			end
										
			//generate active-low horizontal and vertical sync pulses
			horiz_sync <=  ~((pixel_column >= HSYNC_START) && (pixel_column < HSYNC_END));
			vert_sync <= ~((pixel_row >= VSYNC_START) && (pixel_row < VSYNC_END));
				
			// generate the video_on signals and the pixel counts
			video_on <= ((pixel_column < HORIZ_PIXELS) && (pixel_row < VERT_PIXELS));
		end: handle_sync_counters	
end: generate_video_signals
	
endmodule: dtg