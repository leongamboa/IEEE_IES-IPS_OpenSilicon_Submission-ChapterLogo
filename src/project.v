`default_nettype none

module tt_um_leongamboa_OpenSilicon_SubmissionChapterLogo (
    input  wire [7:0] ui_in,    
    output wire [7:0] uo_out,   
    input  wire [7:0] uio_in,   
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   
    input  wire       ena,      
    input  wire       clk,      
    input  wire       rst_n     
);

    // ==========================================
    // 1. VGA SYNC GENERATION
    // ==========================================
    wire hsync, vsync, display_on;
    wire [9:0] hpos, vpos;

    hvsync_generator hvsync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(display_on),
        .hpos(hpos),
        .vpos(vpos)
    );

    // ==========================================
    // 2. GAMEPAD INTEGRATION
    // ==========================================
    wire gp_b, gp_y, gp_select, gp_start, gp_up, gp_down, gp_left, gp_right, gp_a, gp_x, gp_l, gp_r, gp_present;

    gamepad_pmod_single snes_pad (
        .rst_n(rst_n),
        .clk(clk),
        .pmod_latch(ui_in[4]), 
        .pmod_clk(ui_in[5]),   
        .pmod_data(ui_in[6]),  
        .b(gp_b), .y(gp_y), .select(gp_select), .start(gp_start),
        .up(gp_up), .down(gp_down), .left(gp_left), .right(gp_right),
        .a(gp_a), .x(gp_x), .l(gp_l), .r(gp_r),
        .is_present(gp_present)
    );

    // Edge detection for the 'A' button to cycle colors
    reg gp_a_prev;
    reg [1:0] color_state;

    always @(posedge clk) begin
        if (~rst_n) begin
            gp_a_prev <= 0;
            color_state <= 0;
        end else begin
            gp_a_prev <= gp_a;
            if (gp_a && !gp_a_prev) begin
                color_state <= color_state + 1;
            end
        end
    end

    // ==========================================
    // 3. BOUNCING LOGIC
    // ==========================================
    reg [9:0] logo_cx;
    reg [9:0] logo_cy;
    reg dir_x, dir_y;

    always @(posedge clk) begin
        if (~rst_n) begin
            logo_cx <= 320;
            logo_cy <= 240;
            dir_x <= 1;
            dir_y <= 1;
        end else if (hpos == 0 && vpos == 0) begin
            // Update position once per frame
            // Radius is 100, so keep center between 100 and (Resolution - 100)
            if (dir_x) begin
                if (logo_cx >= 539) dir_x <= 0;
                logo_cx <= logo_cx + 1;
            end else begin
                if (logo_cx <= 101) dir_x <= 1;
                logo_cx <= logo_cx - 1;
            end

            if (dir_y) begin
                if (logo_cy >= 379) dir_y <= 0;
                logo_cy <= logo_cy + 1;
            end else begin
                if (logo_cy <= 101) dir_y <= 1;
                logo_cy <= logo_cy - 1;
            end
        end
    end

    // ==========================================
    // 4. PROCEDURAL SHAPE MATH (Relative)
    // ==========================================
    // Relative absolute distances for the Circle (avoids signed multiplier overflow)
    wire [10:0] abs_dx = (hpos > logo_cx) ? (hpos - logo_cx) : (logo_cx - hpos);
    wire [10:0] abs_dy = (vpos > logo_cy) ? (vpos - logo_cy) : (logo_cy - vpos);
    wire in_circle = ((abs_dx * abs_dx) + (abs_dy * abs_dy)) < 24'd10000;

    // Signed distances for the Text (allows left/right/up/down logic)
    wire signed [11:0] dx = $signed({2'b00, hpos}) - $signed({2'b00, logo_cx});
    wire signed [11:0] dy = $signed({2'b00, vpos}) - $signed({2'b00, logo_cy});

    // --- Draw the "IEEE" Text Relative to Center ---
    wire in_text_y = (dy >= -12'sd30 && dy <= 12'sd30);

    // Letter 'I'
    wire in_I = in_text_y && (dx >= -12'sd80 && dx <= -12'sd65);

    // First Letter 'E'
    wire in_E1_x = (dx >= -12'sd50 && dx <= -12'sd20);
    wire in_E1_bar = in_E1_x && (
        (dy >= -12'sd30 && dy <= -12'sd18) || // Top bar
        (dy >= -12'sd6  && dy <=  12'sd6)  || // Middle bar
        (dy >=  12'sd18 && dy <=  12'sd30)    // Bottom bar
    );
    wire in_E1_spine = in_text_y && (dx >= -12'sd50 && dx <= -12'sd38);
    wire in_E1 = in_E1_bar | in_E1_spine;

    // Second Letter 'E'
    wire in_E2_x = (dx >= -12'sd5 && dx <= 12'sd25);
    wire in_E2_bar = in_E2_x && (
        (dy >= -12'sd30 && dy <= -12'sd18) || 
        (dy >= -12'sd6  && dy <=  12'sd6)  || 
        (dy >=  12'sd18 && dy <=  12'sd30)    
    );
    wire in_E2_spine = in_text_y && (dx >= -12'sd5 && dx <= 12'sd7);
    wire in_E2 = in_E2_bar | in_E2_spine;

    // Third Letter 'E'
    wire in_E3_x = (dx >= 12'sd40 && dx <= 12'sd70);
    wire in_E3_bar = in_E3_x && (
        (dy >= -12'sd30 && dy <= -12'sd18) || 
        (dy >= -12'sd6  && dy <=  12'sd6)  || 
        (dy >=  12'sd18 && dy <=  12'sd30)    
    );
    wire in_E3_spine = in_text_y && (dx >= 12'sd40 && dx <= 12'sd52);
    wire in_E3 = in_E3_bar | in_E3_spine;

    wire is_text = in_I | in_E1 | in_E2 | in_E3;

    // XOR the text and circle so the text acts as a transparent cut-out!
    wire is_logo_pixel = in_circle ^ is_text;

    // ==========================================
    // 5. COLOR MULTIPLEXER (RGB222)
    // ==========================================
    reg [1:0] R, G, B;

    always @(*) begin
        if (!display_on) begin
            R = 0; G = 0; B = 0;
        end else if (is_logo_pixel) begin
            case (color_state)
                2'd0: begin R = 2'b11; G = 2'b10; B = 2'b00; end // Orange
                2'd1: begin R = 2'b00; G = 2'b01; B = 2'b11; end // Blue
                // 2'd2: begin R = 2'b00; G = 2'b00; B = 2'b00; end  Black
                2'd3: begin R = 2'b11; G = 2'b11; B = 2'b11; end // White
            endcase
        end else begin
            R = 2'b01; G = 2'b01; B = 2'b01; // Grey Background
        end
    end

    // ==========================================
    // 6. OUTPUT ASSIGNMENTS
    // ==========================================
    assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    wire _unused_ok = &{ena, ui_in[7], ui_in[3:0], uio_in, gp_present, gp_b, gp_y, gp_select, gp_start, gp_up, gp_down, gp_left, gp_right, gp_x, gp_l, gp_r};

endmodule

// =========================================================
// GAMEPAD PMOD MODULES 
// =========================================================

module gamepad_pmod_driver #(
    parameter BIT_WIDTH = 24
) (
    input wire rst_n,
    input wire clk,
    input wire pmod_data,
    input wire pmod_clk,
    input wire pmod_latch,
    output reg [BIT_WIDTH-1:0] data_reg
);
  reg pmod_clk_prev;
  reg pmod_latch_prev;
  reg [BIT_WIDTH-1:0] shift_reg;

  reg [1:0] pmod_data_sync;
  reg [1:0] pmod_clk_sync;
  reg [1:0] pmod_latch_sync;

  always @(posedge clk) begin
    if (~rst_n) begin
      pmod_data_sync  <= 2'b0;
      pmod_clk_sync   <= 2'b0;
      pmod_latch_sync <= 2'b0;
    end else begin
      pmod_data_sync  <= {pmod_data_sync[0], pmod_data};
      pmod_clk_sync   <= {pmod_clk_sync[0], pmod_clk};
      pmod_latch_sync <= {pmod_latch_sync[0], pmod_latch};
    end
  end

  always @(posedge clk) begin
    if (~rst_n) begin
      data_reg <= {BIT_WIDTH{1'b1}};
      shift_reg <= {BIT_WIDTH{1'b1}};
      pmod_clk_prev <= 1'b0;
      pmod_latch_prev <= 1'b0;
    end else begin
      pmod_clk_prev   <= pmod_clk_sync[1];
      pmod_latch_prev <= pmod_latch_sync[1];
      if (pmod_latch_sync[1] & ~pmod_latch_prev) begin
        data_reg <= shift_reg;
      end
      if (pmod_clk_sync[1] & ~pmod_clk_prev) begin
        shift_reg <= {shift_reg[BIT_WIDTH-2:0], pmod_data_sync[1]};
      end
    end
  end
endmodule

module gamepad_pmod_decoder (
    input wire [11:0] data_reg,
    output wire b, y, select, start, up, down, left, right, a, x, l, r, is_present
);
  wire reg_empty = (data_reg == 12'hfff);
  assign is_present = reg_empty ? 0 : 1'b1;
  assign {b, y, select, start, up, down, left, right, a, x, l, r} = reg_empty ? 0 : data_reg;
endmodule

module gamepad_pmod_single (
    input wire rst_n, clk, pmod_data, pmod_clk, pmod_latch,
    output wire b, y, select, start, up, down, left, right, a, x, l, r, is_present
);
  wire [11:0] gamepad_pmod_data;

  gamepad_pmod_driver #(.BIT_WIDTH(12)) driver (
      .rst_n(rst_n), .clk(clk), .pmod_data(pmod_data),
      .pmod_clk(pmod_clk), .pmod_latch(pmod_latch),
      .data_reg(gamepad_pmod_data)
  );

  gamepad_pmod_decoder decoder (
      .data_reg(gamepad_pmod_data), .b(b), .y(y), .select(select),
      .start(start), .up(up), .down(down), .left(left), .right(right),
      .a(a), .x(x), .l(l), .r(r), .is_present(is_present)
  );
endmodule
