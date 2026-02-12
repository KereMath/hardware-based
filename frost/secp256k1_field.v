// Secp256k1 Field Arithmetic Module
// Field: p = 2^256 - 2^32 - 977 (FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFE FFFFFC2F)
//
// Operations:
// - Addition mod p
// - Multiplication mod p
// - Modular reduction (fast, using special form of p)
//
// NO DIVISION! Pure bit-shift and addition

module secp256k1_field_add (
    input  wire [255:0] a,
    input  wire [255:0] b,
    output wire [255:0] result
);

    localparam [255:0] P = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;

    wire [256:0] sum;  // 257 bits to catch overflow
    wire overflow;

    assign sum = {1'b0, a} + {1'b0, b};
    assign overflow = sum[256];

    // If sum >= p, subtract p (single conditional subtraction)
    assign result = (sum >= P) ? (sum[255:0] - P) : sum[255:0];

endmodule


module secp256k1_field_sub (
    input  wire [255:0] a,
    input  wire [255:0] b,
    output wire [255:0] result
);

    localparam [255:0] P = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;

    wire [256:0] diff;
    wire underflow;

    assign diff = {1'b0, a} - {1'b0, b};
    assign underflow = diff[256];  // Sign bit

    // If a < b, add p
    assign result = underflow ? (diff[255:0] + P) : diff[255:0];

endmodule


module secp256k1_mod_reduce (
    input  wire [511:0] x,        // Input (up to 512 bits from multiplication)
    output wire [255:0] result    // x mod p (256 bits)
);

    localparam [255:0] P = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    localparam [255:0] C = 256'h0000000000000000000000000000000000000000000000000000000100000000 + 977;  // 2^32 + 977

    // Fast reduction using p = 2^256 - c
    // x mod p ≈ (x mod 2^256) + (x div 2^256) * c

    wire [255:0] low, high;
    wire [287:0] adjusted;  // May be up to 288 bits after addition
    wire [287:0] adjusted2;

    assign low = x[255:0];
    assign high = x[511:256];

    // First reduction: low + high * c
    assign adjusted = {32'b0, low} + ({32'b0, high} << 32) + ({32'b0, high} * 977);

    // Second reduction if needed (adjusted may still be > 256 bits)
    assign adjusted2 = (adjusted >= {32'b0, P}) ?
                       (adjusted[255:0] + (adjusted[287:256] << 32) + (adjusted[287:256] * 977)) :
                       adjusted;

    // Final conditional subtraction
    assign result = (adjusted2 >= P) ? (adjusted2[255:0] - P) : adjusted2[255:0];

endmodule


// Field multiplication (uses hardware multiplier + mod reduction)
module secp256k1_field_mult (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [255:0] a,
    input  wire [255:0] b,
    output reg  [255:0] result,
    output reg  done
);

    reg [511:0] product;
    wire [255:0] reduced;

    // Instantiate modular reduction
    secp256k1_mod_reduce reducer (
        .x(product),
        .result(reduced)
    );

    // State machine
    localparam IDLE     = 2'b00;
    localparam MULTIPLY = 2'b01;
    localparam REDUCE   = 2'b10;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
            product <= 0;
            result <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        state <= MULTIPLY;
                    end
                end

                MULTIPLY: begin
                    // Hardware multiplier (1-2 cycles depending on synthesis)
                    product <= a * b;
                    state <= REDUCE;
                end

                REDUCE: begin
                    // Reduction is combinational (from reducer module)
                    result <= reduced;
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule


// Field squaring (optimized version of multiplication)
module secp256k1_field_square (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [255:0] a,
    output reg  [255:0] result,
    output reg  done
);

    // Squaring is just multiplication with self
    wire mult_done;
    wire [255:0] mult_result;

    secp256k1_field_mult mult_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .a(a),
        .b(a),
        .result(mult_result),
        .done(mult_done)
    );

    always @(posedge clk) begin
        result <= mult_result;
        done <= mult_done;
    end

endmodule


// Field inversion using Fermat's Little Theorem: a^(-1) = a^(p-2) mod p
// This uses exponentiation by squaring (expensive but works)
module secp256k1_field_inv (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [255:0] a,
    output reg  [255:0] result,
    output reg  done
);

    localparam [255:0] P_MINUS_2 = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D;

    // State machine for exponentiation
    localparam IDLE   = 2'b00;
    localparam EXP    = 2'b01;
    localparam FINISH = 2'b10;

    reg [1:0] state;
    reg [255:0] base, exponent, temp;
    reg [8:0] bit_index;

    wire mult_start, square_start;
    wire mult_done, square_done;
    wire [255:0] mult_result, square_result;

    // Multiplier and squarer instances
    secp256k1_field_mult mult_inst (
        .clk(clk), .rst_n(rst_n), .start(mult_start),
        .a(result), .b(base), .result(mult_result), .done(mult_done)
    );

    secp256k1_field_square square_inst (
        .clk(clk), .rst_n(rst_n), .start(square_start),
        .a(base), .result(square_result), .done(square_done)
    );

    assign mult_start = (state == EXP) && exponent[bit_index];
    assign square_start = (state == EXP);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        base <= a;
                        exponent <= P_MINUS_2;
                        result <= 1;
                        bit_index <= 0;
                        state <= EXP;
                    end
                end

                EXP: begin
                    if (square_done) begin
                        base <= square_result;
                        if (mult_done && exponent[bit_index])
                            result <= mult_result;

                        if (bit_index == 255) begin
                            state <= FINISH;
                        end else begin
                            bit_index <= bit_index + 1;
                        end
                    end
                end

                FINISH: begin
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
