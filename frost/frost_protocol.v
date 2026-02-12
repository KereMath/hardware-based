// FROST Protocol Specific Modules
// - Polynomial Evaluation (for secret sharing)
// - ZK Schnorr Proof Generation/Verification
// - VSS Verification

// Polynomial Evaluation Module
// Evaluates polynomial f(x) = a_0 + a_1*x + a_2*x^2 (fixed degree=2 for threshold 2-of-4)
// Uses Horner's method for efficiency
module polynomial_eval #(
    parameter FIELD_BITS = 255
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [FIELD_BITS-1:0] coeff_0,  // Constant term
    input  wire [FIELD_BITS-1:0] coeff_1,  // x coefficient
    input  wire [FIELD_BITS-1:0] coeff_2,  // x^2 coefficient
    input  wire [FIELD_BITS-1:0] x,        // Evaluation point
    output reg  [FIELD_BITS-1:0] result,
    output reg  done
);

    // Horner's method: f(x) = a_0 + x(a_1 + x*a_2)
    // For degree 2: compute a_2, then a_2*x + a_1, then (a_2*x + a_1)*x + a_0

    localparam IDLE = 3'b000;
    localparam MULT1 = 3'b001;  // Compute a_2 * x
    localparam ADD1 = 3'b010;   // Add a_1
    localparam MULT2 = 3'b011;  // Multiply by x again
    localparam ADD2 = 3'b100;   // Add a_0
    localparam FINISH = 3'b101;

    reg [2:0] state;
    reg [FIELD_BITS-1:0] accumulator;
    reg [FIELD_BITS-1:0] temp;

    // Field multiplication - simplified (just regular mult for now)
    wire [FIELD_BITS*2-1:0] mult_result_wide;
    reg [FIELD_BITS-1:0] mult_a, mult_b;
    assign mult_result_wide = mult_a * mult_b;
    wire [FIELD_BITS-1:0] mult_result = mult_result_wide[FIELD_BITS-1:0];  // Simplified reduction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;  // Clear done when in IDLE
                    if (start) begin
                        mult_a <= coeff_2;
                        mult_b <= x;
                        state <= MULT1;
                    end
                end

                MULT1: begin
                    // a_2 * x completed
                    temp <= mult_result;
                    state <= ADD1;
                end

                ADD1: begin
                    // temp + a_1
                    accumulator <= temp + coeff_1;
                    mult_a <= temp + coeff_1;
                    mult_b <= x;
                    state <= MULT2;
                end

                MULT2: begin
                    // (a_2*x + a_1) * x completed
                    temp <= mult_result;
                    state <= ADD2;
                end

                ADD2: begin
                    // Final: temp + a_0
                    accumulator <= temp + coeff_0;
                    state <= FINISH;
                end

                FINISH: begin
                    result <= accumulator;
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule


// ZK Schnorr Proof Generator
// Proves knowledge of secret s such that C = [s]G
// Proof π = (R, z) where:
//   k = random nonce
//   R = [k]G
//   c = H(C || R || context)
//   z = k + c*s
module zk_schnorr_prove #(
    parameter SCALAR_BITS = 252,
    parameter POINT_BITS = 255
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,

    // Secret scalar s
    input  wire [SCALAR_BITS-1:0] secret,

    // Public commitment C = [s]G (X, Y coordinates)
    input  wire [POINT_BITS-1:0] commitment_X,
    input  wire [POINT_BITS-1:0] commitment_Y,

    // Context (e.g., party ID)
    input  wire [255:0] context,

    // Proof output: (R_X, R_Y, z)
    output reg  [POINT_BITS-1:0] proof_R_X,
    output reg  [POINT_BITS-1:0] proof_R_Y,
    output reg  [SCALAR_BITS-1:0] proof_z,
    output reg  done
);

    localparam IDLE = 3'b000;
    localparam GEN_NONCE = 3'b001;
    localparam COMPUTE_R = 3'b010;
    localparam HASH = 3'b011;
    localparam COMPUTE_Z = 3'b100;
    localparam FINISH = 3'b101;

    reg [2:0] state;
    reg [SCALAR_BITS-1:0] k;  // Random nonce
    reg [255:0] challenge;    // c = H(...)

    // RNG for nonce generation
    reg rng_start;
    wire [SCALAR_BITS-1:0] rng_output;
    wire rng_done;

    // Pseudo-RNG (placeholder - use real CSPRNG in production!)
    reg [SCALAR_BITS-1:0] rng_state;
    assign rng_output = rng_state;
    assign rng_done = rng_start;

    always @(posedge clk) begin
        if (rng_start)
            rng_state <= rng_state * 1664525 + 1013904223;  // LCG
    end

    // Scalar multiplication: R = [k]G
    wire [POINT_BITS-1:0] scalar_mult_R_X, scalar_mult_R_Y;
    wire scalar_mult_done;
    reg scalar_mult_start;

    // Base point G
    wire [POINT_BITS-1:0] G_X = 255'h216936d3cd6e53fec0a4e231fdd6dc5c692cc7609525a7b2c9562d608f25d51a;
    wire [POINT_BITS-1:0] G_Y = 255'h6666666666666666666666666666666666666666666666666666666666666658;

    ed25519_scalar_mult scalar_mult_inst (
        .clk(clk), .rst_n(rst_n), .start(scalar_mult_start),
        .scalar(k[SCALAR_BITS-1:0]),
        .P_X(G_X), .P_Y(G_Y), .P_Z(1), .P_T(0),
        .R_X(scalar_mult_R_X), .R_Y(scalar_mult_R_Y),
        .R_Z(), .R_T(),
        .done(scalar_mult_done)
    );

    // SHA-256 for challenge
    wire [255:0] hash_out;
    wire hash_done;
    reg hash_start;
    reg [511:0] hash_input;

    sha256_core hash_inst (
        .clk(clk), .rst_n(rst_n), .start(hash_start),
        .message_block(hash_input),
        .hash_in(256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19),  // SHA256 IV
        .hash_out(hash_out),
        .done(hash_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= GEN_NONCE;
                        done <= 0;
                    end
                end

                GEN_NONCE: begin
                    rng_start <= 1;
                    if (rng_done) begin
                        k <= rng_output;
                        rng_start <= 0;
                        state <= COMPUTE_R;
                    end
                end

                COMPUTE_R: begin
                    scalar_mult_start <= 1;
                    if (scalar_mult_done) begin
                        proof_R_X <= scalar_mult_R_X;
                        proof_R_Y <= scalar_mult_R_Y;
                        scalar_mult_start <= 0;
                        state <= HASH;
                    end
                end

                HASH: begin
                    // Challenge c = H(C || R || context)
                    // Mix all inputs into 512-bit hash block
                    hash_input <= {
                        commitment_X[127:0] ^ proof_R_X[127:0] ^ context[127:0],    // 128 bits
                        commitment_Y[127:0] ^ proof_R_Y[127:0] ^ context[255:128],  // 128 bits
                        commitment_X[254:128] ^ proof_R_X[254:128],                 // 127 bits
                        commitment_Y[254:128] ^ proof_R_Y[254:128],                 // 127 bits
                        2'b00                                                       // 2 bits padding
                    };
                    hash_start <= 1;

                    if (hash_done) begin
                        challenge <= hash_out;
                        hash_start <= 0;
                        state <= COMPUTE_Z;
                    end
                end

                COMPUTE_Z: begin
                    // z = k + c*s (mod L, where L is the order)
                    proof_z <= k + (challenge[SCALAR_BITS-1:0] * secret);  // Simplified (needs proper mod L)
                    state <= FINISH;
                end

                FINISH: begin
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule


// ZK Schnorr Proof Verifier
// Verifies proof π = (R, z) for commitment C
// Check: [z]G == R + [c]C where c = H(C || R || context)
module zk_schnorr_verify #(
    parameter SCALAR_BITS = 252,
    parameter POINT_BITS = 255
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,

    // Public commitment C
    input  wire [POINT_BITS-1:0] commitment_X,
    input  wire [POINT_BITS-1:0] commitment_Y,

    // Proof (R, z)
    input  wire [POINT_BITS-1:0] proof_R_X,
    input  wire [POINT_BITS-1:0] proof_R_Y,
    input  wire [SCALAR_BITS-1:0] proof_z,

    // Context
    input  wire [255:0] context,

    // Verification result
    output reg  valid,
    output reg  done
);

    localparam IDLE = 4'b0000;
    localparam HASH = 4'b0001;
    localparam WAIT_HASH = 4'b0010;
    localparam COMPUTE_LHS = 4'b0011;      // [z]G
    localparam WAIT_LHS = 4'b0100;
    localparam COMPUTE_RHS_MULT = 4'b0101; // [c]C
    localparam WAIT_RHS_MULT = 4'b0110;
    localparam COMPUTE_RHS_ADD = 4'b0111;  // R + [c]C
    localparam WAIT_RHS_ADD = 4'b1000;
    localparam COMPARE = 4'b1001;
    localparam FINISH = 4'b1010;

    reg [3:0] state;
    reg [255:0] challenge;

    // Point for LHS and RHS
    reg [POINT_BITS-1:0] LHS_X, LHS_Y;
    reg [POINT_BITS-1:0] RHS_X, RHS_Y;
    reg [POINT_BITS-1:0] cC_X, cC_Y;  // [c]C intermediate

    // SHA-256 for challenge
    wire [255:0] hash_out;
    wire hash_done;
    reg hash_start;
    reg [511:0] hash_input;

    sha256_core hash_inst (
        .clk(clk), .rst_n(rst_n), .start(hash_start),
        .message_block(hash_input),
        .hash_in(256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19),
        .hash_out(hash_out),
        .done(hash_done)
    );

    // Base point G for Ed25519
    wire [POINT_BITS-1:0] G_X = 255'h216936d3cd6e53fec0a4e231fdd6dc5c692cc7609525a7b2c9562d608f25d51a;
    wire [POINT_BITS-1:0] G_Y = 255'h6666666666666666666666666666666666666666666666666666666666666658;

    // Scalar multiplication for [z]G
    wire [POINT_BITS-1:0] lhs_mult_X, lhs_mult_Y;
    wire lhs_mult_done;
    reg lhs_mult_start;

    ed25519_scalar_mult lhs_mult (
        .clk(clk), .rst_n(rst_n), .start(lhs_mult_start),
        .scalar(proof_z),
        .P_X(G_X), .P_Y(G_Y), .P_Z(255'd1), .P_T(255'd0),
        .R_X(lhs_mult_X), .R_Y(lhs_mult_Y),
        .R_Z(), .R_T(),
        .done(lhs_mult_done),
        .cycles()
    );

    // Scalar multiplication for [c]C
    wire [POINT_BITS-1:0] rhs_mult_X, rhs_mult_Y;
    wire rhs_mult_done;
    reg rhs_mult_start;

    ed25519_scalar_mult rhs_mult (
        .clk(clk), .rst_n(rst_n), .start(rhs_mult_start),
        .scalar(challenge[SCALAR_BITS-1:0]),
        .P_X(commitment_X), .P_Y(commitment_Y), .P_Z(255'd1), .P_T(255'd0),
        .R_X(rhs_mult_X), .R_Y(rhs_mult_Y),
        .R_Z(), .R_T(),
        .done(rhs_mult_done),
        .cycles()
    );

    // Point addition for R + [c]C
    wire [POINT_BITS-1:0] add_X, add_Y;
    wire add_done;
    reg add_start;

    ed25519_point_add point_add (
        .clk(clk), .rst_n(rst_n), .start(add_start),
        .P1_X(proof_R_X), .P1_Y(proof_R_Y), .P1_Z(255'd1), .P1_T(255'd0),
        .P2_X(cC_X), .P2_Y(cC_Y), .P2_Z(255'd1), .P2_T(255'd0),
        .P3_X(add_X), .P3_Y(add_Y),
        .P3_Z(), .P3_T(),
        .done(add_done),
        .cycles()
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
            valid <= 0;
            hash_start <= 0;
            lhs_mult_start <= 0;
            rhs_mult_start <= 0;
            add_start <= 0;
        end else begin
            // Clear start signals after done
            if (hash_done) hash_start <= 0;
            if (lhs_mult_done) lhs_mult_start <= 0;
            if (rhs_mult_done) rhs_mult_start <= 0;
            if (add_done) add_start <= 0;

            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        state <= HASH;
                    end
                end

                HASH: begin
                    // Compute challenge c = H(C || R || context)
                    hash_input <= {
                        commitment_X[127:0] ^ proof_R_X[127:0] ^ context[127:0],
                        commitment_Y[127:0] ^ proof_R_Y[127:0] ^ context[255:128],
                        commitment_X[254:128] ^ proof_R_X[254:128],
                        commitment_Y[254:128] ^ proof_R_Y[254:128],
                        2'b00
                    };
                    hash_start <= 1;
                    state <= WAIT_HASH;
                end

                WAIT_HASH: begin
                    if (hash_done) begin
                        challenge <= hash_out;
                        state <= COMPUTE_LHS;
                    end
                end

                COMPUTE_LHS: begin
                    // Compute [z]G
                    lhs_mult_start <= 1;
                    state <= WAIT_LHS;
                end

                WAIT_LHS: begin
                    if (lhs_mult_done) begin
                        LHS_X <= lhs_mult_X;
                        LHS_Y <= lhs_mult_Y;
                        state <= COMPUTE_RHS_MULT;
                    end
                end

                COMPUTE_RHS_MULT: begin
                    // Compute [c]C
                    rhs_mult_start <= 1;
                    state <= WAIT_RHS_MULT;
                end

                WAIT_RHS_MULT: begin
                    if (rhs_mult_done) begin
                        cC_X <= rhs_mult_X;
                        cC_Y <= rhs_mult_Y;
                        state <= COMPUTE_RHS_ADD;
                    end
                end

                COMPUTE_RHS_ADD: begin
                    // Compute R + [c]C
                    add_start <= 1;
                    state <= WAIT_RHS_ADD;
                end

                WAIT_RHS_ADD: begin
                    if (add_done) begin
                        RHS_X <= add_X;
                        RHS_Y <= add_Y;
                        state <= COMPARE;
                    end
                end

                COMPARE: begin
                    // Check if LHS == RHS
                    valid <= (LHS_X == RHS_X) && (LHS_Y == RHS_Y);
                    state <= FINISH;
                end

                FINISH: begin
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule


// VSS (Verifiable Secret Sharing) Verification
// Verify that received share s_{j→i} matches commitment C_j
// Check: [s_{j→i}]G == ∑_{k=0}^t C_{j,k}·i^k
module vss_verify #(
    parameter SCALAR_BITS = 252,
    parameter POINT_BITS = 255
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,

    // Received share
    input  wire [SCALAR_BITS-1:0] share,

    // Commitments C_0, C_1, C_2 (individual ports for THRESHOLD=2)
    input  wire [POINT_BITS-1:0] C0_X,
    input  wire [POINT_BITS-1:0] C0_Y,
    input  wire [POINT_BITS-1:0] C1_X,
    input  wire [POINT_BITS-1:0] C1_Y,
    input  wire [POINT_BITS-1:0] C2_X,
    input  wire [POINT_BITS-1:0] C2_Y,

    // Evaluation point (party index i)
    input  wire [SCALAR_BITS-1:0] index,

    // Verification result
    output reg  valid,
    output reg  done
);

    // VSS Verification: Check if [share]G == C_0 + [i]C_1 + [i^2]C_2
    // For threshold 2, we have polynomial f(x) = a_0 + a_1*x + a_2*x^2
    // Commitments: C_0 = [a_0]G, C_1 = [a_1]G, C_2 = [a_2]G
    // Share: s_i = f(i) = a_0 + a_1*i + a_2*i^2
    // Verify: [s_i]G == C_0 + [i]C_1 + [i^2]C_2

    localparam IDLE = 4'b0000;
    localparam COMPUTE_LHS = 4'b0001;     // [share]G
    localparam WAIT_LHS = 4'b0010;
    localparam COMPUTE_I_C1 = 4'b0011;    // [i]C_1
    localparam WAIT_I_C1 = 4'b0100;
    localparam COMPUTE_I2_C2 = 4'b0101;   // [i^2]C_2
    localparam WAIT_I2_C2 = 4'b0110;
    localparam ADD_C0_IC1 = 4'b0111;      // C_0 + [i]C_1
    localparam WAIT_ADD1 = 4'b1000;
    localparam ADD_RESULT_I2C2 = 4'b1001; // (C_0 + [i]C_1) + [i^2]C_2
    localparam WAIT_ADD2 = 4'b1010;
    localparam COMPARE = 4'b1011;
    localparam FINISH = 4'b1100;

    reg [3:0] state;

    // LHS and RHS points
    reg [POINT_BITS-1:0] LHS_X, LHS_Y;
    reg [POINT_BITS-1:0] RHS_X, RHS_Y;

    // Intermediate results
    reg [POINT_BITS-1:0] i_C1_X, i_C1_Y;      // [i]C_1
    reg [POINT_BITS-1:0] i2_C2_X, i2_C2_Y;    // [i^2]C_2
    reg [POINT_BITS-1:0] temp_sum_X, temp_sum_Y;  // Temporary sum

    // Scalar multiplication: [scalar]Point
    reg scalar_mult_start;
    reg [SCALAR_BITS-1:0] scalar_mult_k;
    reg [POINT_BITS-1:0] scalar_mult_P_X, scalar_mult_P_Y;
    wire [POINT_BITS-1:0] scalar_mult_Q_X, scalar_mult_Q_Y;
    wire scalar_mult_done;

    ed25519_scalar_mult scalar_mult (
        .clk(clk), .rst_n(rst_n), .start(scalar_mult_start),
        .scalar({1'b0, scalar_mult_k}),
        .P_X(scalar_mult_P_X), .P_Y(scalar_mult_P_Y),
        .P_Z(255'd1), .P_T(255'd1),
        .R_X(scalar_mult_Q_X), .R_Y(scalar_mult_Q_Y),
        .R_Z(), .R_T(),
        .done(scalar_mult_done),
        .cycles()  // Not used
    );

    // Point addition: P + Q
    reg point_add_start;
    reg [POINT_BITS-1:0] point_add_P_X, point_add_P_Y;
    reg [POINT_BITS-1:0] point_add_Q_X, point_add_Q_Y;
    wire [POINT_BITS-1:0] point_add_R_X, point_add_R_Y;
    wire point_add_done;

    ed25519_point_add point_add (
        .clk(clk), .rst_n(rst_n), .start(point_add_start),
        .P1_X(point_add_P_X), .P1_Y(point_add_P_Y), .P1_Z(255'd1), .P1_T(255'd1),
        .P2_X(point_add_Q_X), .P2_Y(point_add_Q_Y), .P2_Z(255'd1), .P2_T(255'd1),
        .P3_X(point_add_R_X), .P3_Y(point_add_R_Y),
        .P3_Z(), .P3_T(),
        .done(point_add_done)
    );

    // Compute i^2
    wire [SCALAR_BITS*2-1:0] index_squared_wide;
    assign index_squared_wide = index * index;
    wire [SCALAR_BITS-1:0] index_squared = index_squared_wide[SCALAR_BITS-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
            valid <= 0;
            scalar_mult_start <= 0;
            point_add_start <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        done <= 0;
                        valid <= 0;
                        state <= COMPUTE_LHS;
                    end
                end

                COMPUTE_LHS: begin
                    // Compute [share]G
                    scalar_mult_k <= share;
                    scalar_mult_P_X <= 255'd15112221891218833716476647996989161020559857364886120180555412087366036343862;  // Base point Gx
                    scalar_mult_P_Y <= 255'd46316835694926478169428394003475163141307993866256225615783033603165251855960;  // Gy
                    scalar_mult_start <= 1;
                    state <= WAIT_LHS;
                end

                WAIT_LHS: begin
                    if (scalar_mult_done) begin
                        LHS_X <= scalar_mult_Q_X;
                        LHS_Y <= scalar_mult_Q_Y;
                        scalar_mult_start <= 0;
                        state <= COMPUTE_I_C1;
                    end
                end

                COMPUTE_I_C1: begin
                    // Compute [i]C_1
                    scalar_mult_k <= index;
                    scalar_mult_P_X <= C1_X;
                    scalar_mult_P_Y <= C1_Y;
                    scalar_mult_start <= 1;
                    state <= WAIT_I_C1;
                end

                WAIT_I_C1: begin
                    if (scalar_mult_done) begin
                        i_C1_X <= scalar_mult_Q_X;
                        i_C1_Y <= scalar_mult_Q_Y;
                        scalar_mult_start <= 0;
                        state <= COMPUTE_I2_C2;
                    end
                end

                COMPUTE_I2_C2: begin
                    // Compute [i^2]C_2
                    scalar_mult_k <= index_squared;
                    scalar_mult_P_X <= C2_X;
                    scalar_mult_P_Y <= C2_Y;
                    scalar_mult_start <= 1;
                    state <= WAIT_I2_C2;
                end

                WAIT_I2_C2: begin
                    if (scalar_mult_done) begin
                        i2_C2_X <= scalar_mult_Q_X;
                        i2_C2_Y <= scalar_mult_Q_Y;
                        scalar_mult_start <= 0;
                        state <= ADD_C0_IC1;
                    end
                end

                ADD_C0_IC1: begin
                    // Add C_0 + [i]C_1
                    point_add_P_X <= C0_X;
                    point_add_P_Y <= C0_Y;
                    point_add_Q_X <= i_C1_X;
                    point_add_Q_Y <= i_C1_Y;
                    point_add_start <= 1;
                    state <= WAIT_ADD1;
                end

                WAIT_ADD1: begin
                    if (point_add_done) begin
                        temp_sum_X <= point_add_R_X;
                        temp_sum_Y <= point_add_R_Y;
                        point_add_start <= 0;
                        state <= ADD_RESULT_I2C2;
                    end
                end

                ADD_RESULT_I2C2: begin
                    // Add (C_0 + [i]C_1) + [i^2]C_2
                    point_add_P_X <= temp_sum_X;
                    point_add_P_Y <= temp_sum_Y;
                    point_add_Q_X <= i2_C2_X;
                    point_add_Q_Y <= i2_C2_Y;
                    point_add_start <= 1;
                    state <= WAIT_ADD2;
                end

                WAIT_ADD2: begin
                    if (point_add_done) begin
                        RHS_X <= point_add_R_X;
                        RHS_Y <= point_add_R_Y;
                        point_add_start <= 0;
                        state <= COMPARE;
                    end
                end

                COMPARE: begin
                    // Check if LHS == RHS
                    valid <= (LHS_X == RHS_X) && (LHS_Y == RHS_Y);
                    state <= FINISH;
                end

                FINISH: begin
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
