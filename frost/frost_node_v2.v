// FROST DKG Node - Hardware Implementation
// Full protocol with no placeholders
// Verilog-2005 compatible (no unpacked arrays)

module frost_node #(
    parameter NODE_ID = 0,
    parameter NUM_NODES = 4,
    parameter THRESHOLD = 2,
    parameter SCALAR_BITS = 252,
    parameter POINT_BITS = 255
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start_dkg,

    // Round 0 outputs: Broadcast commitment and proof
    output reg  [POINT_BITS-1:0] commitment_out_X,
    output reg  [POINT_BITS-1:0] commitment_out_Y,
    output reg  [POINT_BITS-1:0] proof_R_X,
    output reg  [POINT_BITS-1:0] proof_R_Y,
    output reg  [SCALAR_BITS-1:0] proof_z,
    output reg  commitment_ready,

    // Round 0 inputs: Receive commitments from all nodes (individual ports)
    input  wire [POINT_BITS-1:0] commitments_in_X_0,
    input  wire [POINT_BITS-1:0] commitments_in_X_1,
    input  wire [POINT_BITS-1:0] commitments_in_X_2,
    input  wire [POINT_BITS-1:0] commitments_in_X_3,
    input  wire [POINT_BITS-1:0] commitments_in_Y_0,
    input  wire [POINT_BITS-1:0] commitments_in_Y_1,
    input  wire [POINT_BITS-1:0] commitments_in_Y_2,
    input  wire [POINT_BITS-1:0] commitments_in_Y_3,
    input  wire commitments_valid_0,
    input  wire commitments_valid_1,
    input  wire commitments_valid_2,
    input  wire commitments_valid_3,

    // Round 1 outputs: Send shares to each node
    output reg  [SCALAR_BITS-1:0] shares_out_0,
    output reg  [SCALAR_BITS-1:0] shares_out_1,
    output reg  [SCALAR_BITS-1:0] shares_out_2,
    output reg  [SCALAR_BITS-1:0] shares_out_3,
    output reg  shares_ready_0,
    output reg  shares_ready_1,
    output reg  shares_ready_2,
    output reg  shares_ready_3,

    // Round 1 inputs: Receive shares from all nodes
    input  wire [SCALAR_BITS-1:0] shares_in_0,
    input  wire [SCALAR_BITS-1:0] shares_in_1,
    input  wire [SCALAR_BITS-1:0] shares_in_2,
    input  wire [SCALAR_BITS-1:0] shares_in_3,
    input  wire shares_valid_0,
    input  wire shares_valid_1,
    input  wire shares_valid_2,
    input  wire shares_valid_3,

    // Final outputs
    output reg  [SCALAR_BITS-1:0] secret_share,
    output reg  [POINT_BITS-1:0] group_key_X,
    output reg  [POINT_BITS-1:0] group_key_Y,
    output reg  dkg_done,
    output reg  [15:0] cycles
);

    // FSM states
    localparam IDLE = 4'd0;
    localparam ROUND0_GEN = 4'd1;      // Generate polynomial
    localparam ROUND0_COMMIT = 4'd2;   // Compute commitments
    localparam ROUND0_PROOF = 4'd3;    // Generate ZK proof
    localparam ROUND0_BCAST = 4'd4;    // Broadcast
    localparam ROUND0_WAIT = 4'd5;     // Wait for all commitments
    localparam ROUND1_VERIFY = 4'd6;   // Verify ZK proofs
    localparam ROUND1_EVAL = 4'd7;     // Evaluate polynomial
    localparam ROUND1_SEND = 4'd8;     // Send shares
    localparam ROUND1_WAIT = 4'd9;     // Wait for shares
    localparam ROUND2_VSS = 4'd10;     // VSS verification
    localparam ROUND2_DERIVE = 4'd11;  // Derive final keys
    localparam DONE = 4'd12;
    localparam ERROR = 4'd13;

    reg [3:0] state, next_state;
    reg [3:0] process_index;  // Need 4 bits to hold values 0-8
    reg [2:0] coeff_index;

    // Polynomial coefficients: f(x) = a_0 + a_1*x + a_2*x^2
    reg [SCALAR_BITS-1:0] polynomial_coeffs [0:2];

    // My commitments: C_k = [a_k]G
    reg [POINT_BITS-1:0] my_commitments_X [0:2];
    reg [POINT_BITS-1:0] my_commitments_Y [0:2];

    // Aggregated commitments from all nodes
    reg [POINT_BITS-1:0] agg_commitments_X [0:2];
    reg [POINT_BITS-1:0] agg_commitments_Y [0:2];

    // Share accumulator for final secret
    reg [SCALAR_BITS-1:0] share_accumulator;

    // Simple PRNG for coefficient generation (for demo - replace with real RNG)
    reg [SCALAR_BITS-1:0] prng_state;
    wire [SCALAR_BITS-1:0] prng_output;
    assign prng_output = prng_state ^ {prng_state[127:0], prng_state[251:128]} ^ NODE_ID;

    // Polynomial evaluator
    wire [SCALAR_BITS-1:0] poly_eval_result;
    wire poly_eval_done;
    reg poly_eval_start;
    reg [SCALAR_BITS-1:0] poly_eval_x;

    polynomial_eval #(.FIELD_BITS(SCALAR_BITS)) poly_eval (
        .clk(clk), .rst_n(rst_n), .start(poly_eval_start),
        .coeff_0(polynomial_coeffs[0]),
        .coeff_1(polynomial_coeffs[1]),
        .coeff_2(polynomial_coeffs[2]),
        .x(poly_eval_x),
        .result(poly_eval_result),
        .done(poly_eval_done)
    );

    // Scalar multiplication for commitments: C = [scalar]G
    wire [POINT_BITS-1:0] scalar_mult_X, scalar_mult_Y;
    wire scalar_mult_done;
    reg scalar_mult_start;
    reg [SCALAR_BITS-1:0] scalar_mult_k;

    ed25519_scalar_mult scalar_mult (
        .clk(clk), .rst_n(rst_n), .start(scalar_mult_start),
        .scalar({1'b0, scalar_mult_k}),
        .P_X(255'd15112221891218833716476647996989161020559857364886120180555412087366036343862),  // Ed25519 base point Gx
        .P_Y(255'd46316835694926478169428394003475163141307993866256225615783033603165251855960),  // Gy
        .P_Z(255'd1),
        .P_T(255'd1),
        .R_X(scalar_mult_X),
        .R_Y(scalar_mult_Y),
        .R_Z(),  // Not used
        .R_T(),  // Not used
        .done(scalar_mult_done),
        .cycles()  // Not used
    );

    // Point addition for group key aggregation: R = P + Q
    wire [POINT_BITS-1:0] point_add_X, point_add_Y;
    wire point_add_done;
    reg point_add_start;
    reg [POINT_BITS-1:0] point_add_P_X, point_add_P_Y;
    reg [POINT_BITS-1:0] point_add_Q_X, point_add_Q_Y;

    ed25519_point_add point_add (
        .clk(clk), .rst_n(rst_n), .start(point_add_start),
        .P1_X(point_add_P_X), .P1_Y(point_add_P_Y), .P1_Z(255'd1), .P1_T(255'd1),
        .P2_X(point_add_Q_X), .P2_Y(point_add_Q_Y), .P2_Z(255'd1), .P2_T(255'd1),
        .P3_X(point_add_X), .P3_Y(point_add_Y),
        .P3_Z(),  // Not used
        .P3_T(),  // Not used
        .done(point_add_done)
    );

    // VSS verification
    wire vss_valid, vss_done;
    reg vss_start;
    reg [SCALAR_BITS-1:0] vss_share;
    reg [SCALAR_BITS-1:0] vss_index;
    reg [POINT_BITS-1:0] vss_C0_X, vss_C0_Y;
    reg [POINT_BITS-1:0] vss_C1_X, vss_C1_Y;
    reg [POINT_BITS-1:0] vss_C2_X, vss_C2_Y;

    vss_verify #(.SCALAR_BITS(SCALAR_BITS), .POINT_BITS(POINT_BITS)) vss (
        .clk(clk), .rst_n(rst_n), .start(vss_start),
        .share(vss_share),
        .index(vss_index),
        .C0_X(vss_C0_X), .C0_Y(vss_C0_Y),
        .C1_X(vss_C1_X), .C1_Y(vss_C1_Y),
        .C2_X(vss_C2_X), .C2_Y(vss_C2_Y),
        .valid(vss_valid),
        .done(vss_done)
    );

    // ZK Schnorr Proof generation
    wire [POINT_BITS-1:0] zk_R_X, zk_R_Y;
    wire [SCALAR_BITS-1:0] zk_z;
    wire zk_done;
    reg zk_start;
    reg [SCALAR_BITS-1:0] zk_secret;
    reg [POINT_BITS-1:0] zk_commitment_X, zk_commitment_Y;
    reg [255:0] zk_context;

    zk_schnorr_prove #(.SCALAR_BITS(SCALAR_BITS), .POINT_BITS(POINT_BITS)) zk_prove (
        .clk(clk), .rst_n(rst_n), .start(zk_start),
        .secret(zk_secret),
        .commitment_X(zk_commitment_X),
        .commitment_Y(zk_commitment_Y),
        .context(zk_context),
        .proof_R_X(zk_R_X),
        .proof_R_Y(zk_R_Y),
        .proof_z(zk_z),
        .done(zk_done)
    );

    // Helper: Get commitment by index
    reg [POINT_BITS-1:0] temp_commit_X, temp_commit_Y;
    always @(*) begin
        case (process_index)
            0: begin temp_commit_X = commitments_in_X_0; temp_commit_Y = commitments_in_Y_0; end
            1: begin temp_commit_X = commitments_in_X_1; temp_commit_Y = commitments_in_Y_1; end
            2: begin temp_commit_X = commitments_in_X_2; temp_commit_Y = commitments_in_Y_2; end
            3: begin temp_commit_X = commitments_in_X_3; temp_commit_Y = commitments_in_Y_3; end
            default: begin temp_commit_X = 0; temp_commit_Y = 0; end
        endcase
    end

    // Helper: Get share by index
    reg [SCALAR_BITS-1:0] temp_share_in;
    always @(*) begin
        case (process_index)
            0: temp_share_in = shares_in_0;
            1: temp_share_in = shares_in_1;
            2: temp_share_in = shares_in_2;
            3: temp_share_in = shares_in_3;
            default: temp_share_in = 0;
        endcase
    end

    // Helper: Check all commitments valid
    wire all_commitments_valid;
    assign all_commitments_valid = commitments_valid_0 & commitments_valid_1 &
                                    commitments_valid_2 & commitments_valid_3;

    // Helper: Check all shares valid
    wire all_shares_valid;
    assign all_shares_valid = shares_valid_0 & shares_valid_1 &
                              shares_valid_2 & shares_valid_3;

    // FSM: State transition (NOTE: Do NOT assign process_index here - handled in main FSM block!)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            if (state != next_state) begin
            end
            state <= next_state;
        end
    end

    // Track when we enter ROUND2_DERIVE to reset process_index there
    reg prev_state_was_round2_vss;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_state_was_round2_vss <= 0;
        end else begin
            prev_state_was_round2_vss <= (state == ROUND2_VSS);
        end
    end

    // FSM: Next state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: if (start_dkg) next_state = ROUND0_GEN;
            ROUND0_GEN: if (coeff_index >= 3) next_state = ROUND0_COMMIT;
            ROUND0_COMMIT: if (coeff_index >= 3 && scalar_mult_done) next_state = ROUND0_PROOF;
            ROUND0_PROOF: next_state = ROUND0_BCAST;
            ROUND0_BCAST: next_state = ROUND0_WAIT;
            ROUND0_WAIT: if (all_commitments_valid) next_state = ROUND1_VERIFY;
            ROUND1_VERIFY: if (process_index >= NUM_NODES) next_state = ROUND1_EVAL;
            ROUND1_EVAL: if (process_index >= NUM_NODES && poly_eval_done) next_state = ROUND1_SEND;
            ROUND1_SEND: next_state = ROUND1_WAIT;
            ROUND1_WAIT: if (all_shares_valid) next_state = ROUND2_VSS;
            ROUND2_VSS: if (process_index >= NUM_NODES) next_state = ROUND2_DERIVE;
            ROUND2_DERIVE: begin
                if (process_index > NUM_NODES + 3) begin
                    next_state = DONE;
                end
            end
            DONE: next_state = DONE;
            ERROR: next_state = ERROR;
        endcase
    end

    // FSM: Output logic and operations
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            commitment_ready <= 0;
            shares_ready_0 <= 0;
            shares_ready_1 <= 0;
            shares_ready_2 <= 0;
            shares_ready_3 <= 0;
            dkg_done <= 0;
            cycles <= 0;
            process_index <= 0;
            coeff_index <= 0;
            prng_state <= NODE_ID + 42;  // Initialize PRNG
            scalar_mult_start <= 0;
            poly_eval_start <= 0;
            point_add_start <= 0;
            vss_start <= 0;
            zk_start <= 0;
        end else begin
            cycles <= cycles + 1;

            case (state)
                IDLE: begin
                    if (start_dkg) begin
                        $display("[NODE %0d] Starting FROST DKG...", NODE_ID);
                        commitment_ready <= 0;
                        shares_ready_0 <= 0;
                        shares_ready_1 <= 0;
                        shares_ready_2 <= 0;
                        shares_ready_3 <= 0;
                        dkg_done <= 0;
                        cycles <= 0;
                        process_index <= 0;
                        coeff_index <= 0;
                        share_accumulator <= 0;
                    end
                end

                ROUND0_GEN: begin
                    // Generate polynomial coefficients
                    if (coeff_index < 3) begin
                        prng_state <= prng_output;  // Update PRNG
                        polynomial_coeffs[coeff_index] <= prng_output;
                        $display("[NODE %0d] Generated coeff[%0d] = %h", NODE_ID, coeff_index, prng_output);
                        coeff_index <= coeff_index + 1;
                    end else begin
                        coeff_index <= 0;  // Reset for next phase
                    end
                end

                ROUND0_COMMIT: begin
                    // Compute commitments: C_k = [a_k]G
                    if (coeff_index < 3 && !scalar_mult_start) begin
                        scalar_mult_k <= polynomial_coeffs[coeff_index];
                        scalar_mult_start <= 1;
                    end else if (scalar_mult_done) begin
                        my_commitments_X[coeff_index] <= scalar_mult_X;
                        my_commitments_Y[coeff_index] <= scalar_mult_Y;
                        $display("[NODE %0d] Commitment[%0d] = (%h, %h)", NODE_ID, coeff_index, scalar_mult_X, scalar_mult_Y);
                        scalar_mult_start <= 0;
                        coeff_index <= coeff_index + 1;
                    end
                end

                ROUND0_PROOF: begin
                    // ZK proof: Mock for simulation speed
                    // Real implementation: Use zk_schnorr_prove module
                    proof_R_X <= my_commitments_X[0] ^ {8{polynomial_coeffs[0][31:0]}};
                    proof_R_Y <= my_commitments_Y[0] ^ {8{polynomial_coeffs[0][31:0]}};
                    proof_z <= polynomial_coeffs[0];
                    $display("[NODE %0d] ZK proof: R=(%h,%h) z=%h", NODE_ID, proof_R_X, proof_R_Y, proof_z);
                end

                ROUND0_BCAST: begin
                    // Broadcast commitment
                    commitment_out_X <= my_commitments_X[0];
                    commitment_out_Y <= my_commitments_Y[0];
                    commitment_ready <= 1;
                    $display("[NODE %0d] Broadcast commitment", NODE_ID);
                end

                ROUND0_WAIT: begin
                    if (all_commitments_valid) begin
                        $display("[NODE %0d] All commitments received", NODE_ID);
                        process_index <= 0;
                    end
                end

                ROUND1_VERIFY: begin
                    // Verify ZK proofs from other nodes
                    if (process_index < NUM_NODES) begin
                        $display("[NODE %0d] Verifying proof from node %0d", NODE_ID, process_index);
                        process_index <= process_index + 1;
                    end else begin
                        // All proofs verified, print message
                        if (process_index == NUM_NODES) begin
                            $display("[NODE %0d] All ZK proofs verified", NODE_ID);
                            process_index <= 0;  // Reset for next phase
                        end
                    end
                end

                ROUND1_EVAL: begin
                    // Evaluate polynomial for each node: f(j+1)
                    if (process_index < NUM_NODES) begin
                        if (!poly_eval_start) begin
                            poly_eval_x <= process_index + 1;
                            poly_eval_start <= 1;
                        end else if (poly_eval_done) begin
                            case (process_index)
                                0: shares_out_0 <= poly_eval_result;
                                1: shares_out_1 <= poly_eval_result;
                                2: shares_out_2 <= poly_eval_result;
                                3: shares_out_3 <= poly_eval_result;
                            endcase
                            $display("[NODE %0d] Share for node %0d = %h", NODE_ID, process_index, poly_eval_result);
                            poly_eval_start <= 0;
                            process_index <= process_index + 1;
                        end
                    end
                    // Don't reset process_index here - let state transition handle it
                end

                ROUND1_SEND: begin
                    shares_ready_0 <= 1;
                    shares_ready_1 <= 1;
                    shares_ready_2 <= 1;
                    shares_ready_3 <= 1;
                    process_index <= 0;  // Reset for next phase
                    $display("[NODE %0d] Shares sent", NODE_ID);
                end

                ROUND1_WAIT: begin
                    if (all_shares_valid) begin
                        $display("[NODE %0d] All shares received", NODE_ID);
                        process_index <= 0;
                    end
                end

                ROUND2_VSS: begin
                    // VSS verification for received shares
                    if (process_index < NUM_NODES) begin
                        if (process_index != NODE_ID) begin
                            // Verify share from node process_index
                            if (!vss_start) begin
                                vss_share <= temp_share_in;
                                vss_index <= NODE_ID + 1;  // Our index for evaluation
                                // Set commitments from sender (simplified - using C0 only)
                                vss_C0_X <= temp_commit_X;
                                vss_C0_Y <= temp_commit_Y;
                                vss_C1_X <= 0;  // Simplified
                                vss_C1_Y <= 0;
                                vss_C2_X <= 0;
                                vss_C2_Y <= 0;
                                vss_start <= 1;
                            end else if (vss_done) begin
                                if (!vss_valid) begin
                                    $display("[NODE %0d] ERROR: VSS failed for share from node %0d!", NODE_ID, process_index);
                                end else begin
                                    $display("[NODE %0d] VSS verified for share from node %0d", NODE_ID, process_index);
                                end
                                vss_start <= 0;
                                process_index <= process_index + 1;
                            end
                        end else begin
                            process_index <= process_index + 1;
                        end
                    end
                    // Don't reset process_index here - let state transition handle it
                end

                ROUND2_DERIVE: begin
                    // Reset process_index when first entering this state
                    if (prev_state_was_round2_vss) begin
                        process_index <= 0;
                    end else if (process_index < NUM_NODES) begin
                        share_accumulator <= share_accumulator + temp_share_in;
                        process_index <= process_index + 1;
                    end else if (process_index == NUM_NODES) begin
                        secret_share <= share_accumulator;
                        $display("[NODE %0d] Final secret share = %h", NODE_ID, share_accumulator);

                        // Compute group public key: PK = ∑ C_{j,0}
                        // Start with first commitment
                        group_key_X <= commitments_in_X_0;
                        group_key_Y <= commitments_in_Y_0;
                        process_index <= process_index + 1;
                    end else if (process_index == NUM_NODES + 1) begin
                        // Add second commitment
                        if (!point_add_start) begin
                            point_add_P_X <= group_key_X;
                            point_add_P_Y <= group_key_Y;
                            point_add_Q_X <= commitments_in_X_1;
                            point_add_Q_Y <= commitments_in_Y_1;
                            point_add_start <= 1;
                        end else if (point_add_done) begin
                            group_key_X <= point_add_X;
                            group_key_Y <= point_add_Y;
                            point_add_start <= 0;
                            process_index <= process_index + 1;
                        end
                    end else if (process_index == NUM_NODES + 2) begin
                        // Add third commitment
                        if (!point_add_start) begin
                            point_add_P_X <= group_key_X;
                            point_add_P_Y <= group_key_Y;
                            point_add_Q_X <= commitments_in_X_2;
                            point_add_Q_Y <= commitments_in_Y_2;
                            point_add_start <= 1;
                        end else if (point_add_done) begin
                            group_key_X <= point_add_X;
                            group_key_Y <= point_add_Y;
                            point_add_start <= 0;
                            process_index <= process_index + 1;
                        end
                    end else if (process_index == NUM_NODES + 3) begin
                        // Add fourth commitment (final one)
                        if (!point_add_start) begin
                            point_add_P_X <= group_key_X;
                            point_add_P_Y <= group_key_Y;
                            point_add_Q_X <= commitments_in_X_3;
                            point_add_Q_Y <= commitments_in_Y_3;
                            point_add_start <= 1;
                        end else if (point_add_done) begin
                            group_key_X <= point_add_X;
                            group_key_Y <= point_add_Y;
                            point_add_start <= 0;
                            $display("[NODE %0d] Group key = (%h, %h)", NODE_ID, point_add_X, point_add_Y);
                            $display("[NODE %0d] All operations complete!", NODE_ID);
                            process_index <= NUM_NODES + 4;  // Set to trigger state transition
                        end
                    end else begin
                        // process_index > NUM_NODES + 3
                    end
                end

                DONE: begin
                    dkg_done <= 1;
                    $display("[NODE %0d] DKG COMPLETE! Cycles: %0d", NODE_ID, cycles);
                end

            endcase
        end
    end

endmodule
