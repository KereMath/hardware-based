// Optimized Ed25519 Scalar Multiplication
// Fixed FSM with proper start pulse handling
// Montgomery ladder with 252 iterations

module ed25519_scalar_mult (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [252:0] scalar,
    input  wire [254:0] P_X,
    input  wire [254:0] P_Y,
    input  wire [254:0] P_Z,
    input  wire [254:0] P_T,
    output reg  [254:0] R_X,
    output reg  [254:0] R_Y,
    output reg  [254:0] R_Z,
    output reg  [254:0] R_T,
    output reg  done,
    output reg  [15:0] cycles
);

    // State machine - FIXED
    localparam IDLE   = 3'b000;
    localparam INIT   = 3'b001;
    localparam DOUBLE = 3'b010;
    localparam WAIT_DOUBLE = 3'b011;
    localparam ADD    = 3'b100;
    localparam WAIT_ADD = 3'b101;
    localparam FINISH = 3'b110;

    reg [2:0] state;
    reg [8:0] bit_index;

    // Montgomery ladder registers
    reg [254:0] R0_X, R0_Y, R0_Z, R0_T;
    reg [254:0] R1_X, R1_Y, R1_Z, R1_T;

    // Point operations
    wire [254:0] double_X, double_Y, double_Z, double_T;
    wire [254:0] add_X, add_Y, add_Z, add_T;
    wire double_done, add_done;
    reg double_start, add_start;

    ed25519_point_double double_inst (
        .clk(clk), .rst_n(rst_n), .start(double_start),
        .P_X(R0_X), .P_Y(R0_Y), .P_Z(R0_Z), .P_T(R0_T),
        .R_X(double_X), .R_Y(double_Y), .R_Z(double_Z), .R_T(double_T),
        .done(double_done)
    );

    ed25519_point_add add_inst (
        .clk(clk), .rst_n(rst_n), .start(add_start),
        .P1_X(R0_X), .P1_Y(R0_Y), .P1_Z(R0_Z), .P1_T(R0_T),
        .P2_X(R1_X), .P2_Y(R1_Y), .P2_Z(R1_Z), .P2_T(R1_T),
        .P3_X(add_X), .P3_Y(add_Y), .P3_Z(add_Z), .P3_T(add_T),
        .done(add_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
            cycles <= 0;
            double_start <= 0;
            add_start <= 0;
        end else begin
            // Default: clear start signals
            if (double_done) double_start <= 0;
            if (add_done) add_start <= 0;

            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        // Initialize
                        bit_index <= 251;  // Start from bit 251 down to 0
                        R0_X <= 0; R0_Y <= 1; R0_Z <= 1; R0_T <= 0;  // Identity point
                        R1_X <= P_X; R1_Y <= P_Y; R1_Z <= P_Z; R1_T <= P_T;  // Input point
                        cycles <= 0;
                        state <= DOUBLE;
                    end
                end

                DOUBLE: begin
                    // Start point doubling
                    double_start <= 1;
                    state <= WAIT_DOUBLE;
                end

                WAIT_DOUBLE: begin
                    if (double_done) begin
                        // Save doubled point
                        R0_X <= double_X;
                        R0_Y <= double_Y;
                        R0_Z <= double_Z;
                        R0_T <= double_T;
                        cycles <= cycles + 1;
                        state <= ADD;
                    end
                end

                ADD: begin
                    if (scalar[bit_index]) begin
                        // Bit is 1: do addition
                        add_start <= 1;
                        state <= WAIT_ADD;
                    end else begin
                        // Bit is 0: skip addition
                        if (bit_index == 0) begin
                            state <= FINISH;
                        end else begin
                            bit_index <= bit_index - 1;
                            state <= DOUBLE;
                        end
                    end
                end

                WAIT_ADD: begin
                    if (add_done) begin
                        // Save added point
                        R0_X <= add_X;
                        R0_Y <= add_Y;
                        R0_Z <= add_Z;
                        R0_T <= add_T;
                        cycles <= cycles + 1;

                        if (bit_index == 0) begin
                            state <= FINISH;
                        end else begin
                            bit_index <= bit_index - 1;
                            state <= DOUBLE;
                        end
                    end
                end

                FINISH: begin
                    R_X <= R0_X;
                    R_Y <= R0_Y;
                    R_Z <= R0_Z;
                    R_T <= R0_T;
                    done <= 1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
