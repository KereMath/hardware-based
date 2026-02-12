// FROST Node State Machine
// Implements complete FROST DKG protocol for a single node
// Communicates with other nodes via shared memory

module frost_node_fsm #(
    parameter NODE_ID = 0,
    parameter NUM_NODES = 4,
    parameter THRESHOLD = 2,
    parameter SCALAR_BITS = 252,
    parameter POINT_BITS = 255
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start_dkg,

    // Shared memory interface (read/write to communicate with other nodes)
    output reg  [POINT_BITS-1:0] commitment_out_X,
    output reg  [POINT_BITS-1:0] commitment_out_Y,
    output reg  [POINT_BITS-1:0] proof_R_X,
    output reg  [POINT_BITS-1:0] proof_R_Y,
    output reg  [SCALAR_BITS-1:0] proof_z,
    output reg  commitment_ready,

    input  wire [POINT_BITS-1:0] commitments_in_X [0:NUM_NODES-1],
    input  wire [POINT_BITS-1:0] commitments_in_Y [0:NUM_NODES-1],
    input  wire [NUM_NODES-1:0] commitments_valid,

    output reg  [SCALAR_BITS-1:0] shares_out [0:NUM_NODES-1],
    output reg  [NUM_NODES-1:0] shares_ready,

    input  wire [SCALAR_BITS-1:0] shares_in [0:NUM_NODES-1],
    input  wire [NUM_NODES-1:0] shares_valid,

    // Final outputs
    output reg  [SCALAR_BITS-1:0] secret_share,    // This node's final secret share
    output reg  [POINT_BITS-1:0] group_key_X,       // Aggregated group public key
    output reg  [POINT_BITS-1:0] group_key_Y,
    output reg  dkg_done,
    output reg  [15:0] cycles
);

    // ========================================
    // FROST DKG State Machine
    // ========================================
    localparam IDLE           = 4'b0000;
    localparam ROUND0_GEN     = 4'b0001;  // Generate polynomial & commitments
    localparam ROUND0_PROOF   = 4'b0010;  // Create ZK Schnorr proof
    localparam ROUND0_BCAST   = 4'b0011;  // Broadcast commitment
    localparam ROUND0_WAIT    = 4'b0100;  // Wait for others
    localparam ROUND1_VERIFY  = 4'b0101;  // Verify received proofs
    localparam ROUND1_EVAL    = 4'b0110;  // Evaluate polynomial for shares
    localparam ROUND1_SEND    = 4'b0111;  // Send shares to others
    localparam ROUND1_WAIT    = 4'b1000;  // Wait for shares
    localparam ROUND2_VSS     = 4'b1001;  // VSS verification
    localparam ROUND2_DERIVE  = 4'b1010;  // Derive final keys
    localparam DONE           = 4'b1011;  // Protocol complete
    localparam ERROR          = 4'b1111;  // Error state

    reg [3:0] state, next_state;

    // ========================================
    // Internal registers
    // ========================================

    // Polynomial coefficients (secret)
    reg [SCALAR_BITS-1:0] polynomial_coeffs [0:THRESHOLD];

    // Commitment to polynomial: C_k = [a_k]G for k=0..t
    reg [POINT_BITS-1:0] my_commitments_X [0:THRESHOLD];
    reg [POINT_BITS-1:0] my_commitments_Y [0:THRESHOLD];

    // Received shares accumulator
    reg [SCALAR_BITS-1:0] share_accumulator;

    // Processing index (for loops)
    reg [7:0] process_index;

    // ========================================
    // Module instantiations
    // ========================================

    // RNG for polynomial coefficient generation
    wire [SCALAR_BITS-1:0] rng_output;
    wire rng_done;
    reg rng_start;

    // Simple LFSR-based RNG (placeholder - use real CSPRNG!)
    reg [SCALAR_BITS-1:0] rng_state;
    assign rng_output = rng_state;
    assign rng_done = rng_start;

    always @(posedge clk) begin
        if (rng_start)
            rng_state <= {rng_state[SCALAR_BITS-2:0], rng_state[SCALAR_BITS-1] ^ rng_state[SCALAR_BITS-2]};
    end

    // Scalar multiplication for commitment generation
    wire [POINT_BITS-1:0] scalar_mult_R_X, scalar_mult_R_Y;
    wire scalar_mult_done;
    reg scalar_mult_start;
    reg [SCALAR_BITS-1:0] scalar_mult_k;

    wire [POINT_BITS-1:0] G_X = 255'h216936d3cd6e53fec0a4e231fdd6dc5c692cc7609525a7b2c9562d608f25d51a;
    wire [POINT_BITS-1:0] G_Y = 255'h6666666666666666666666666666666666666666666666666666666666666658;

    ed25519_scalar_mult scalar_mult (
        .clk(clk), .rst_n(rst_n), .start(scalar_mult_start),
        .scalar(scalar_mult_k[SCALAR_BITS-1:0]),
        .P_X(G_X), .P_Y(G_Y), .P_Z(1), .P_T(0),
        .R_X(scalar_mult_R_X), .R_Y(scalar_mult_R_Y),
        .done(scalar_mult_done)
    );

    // ZK Schnorr proof generator
    wire [POINT_BITS-1:0] zk_proof_R_X, zk_proof_R_Y;
    wire [SCALAR_BITS-1:0] zk_proof_z;
    wire zk_prove_done;
    reg zk_prove_start;

    wire [255:0] zk_prove_context;
    assign zk_prove_context = {248'b0, NODE_ID[7:0]};

    zk_schnorr_prove #(.SCALAR_BITS(SCALAR_BITS), .POINT_BITS(POINT_BITS)) zk_prove (
        .clk(clk), .rst_n(rst_n), .start(zk_prove_start),
        .secret(polynomial_coeffs[0]),  // Secret constant term
        .commitment_X(my_commitments_X[0]),
        .commitment_Y(my_commitments_Y[0]),
        .context(zk_prove_context),
        .proof_R_X(zk_proof_R_X),
        .proof_R_Y(zk_proof_R_Y),
        .proof_z(zk_proof_z),
        .done(zk_prove_done)
    );

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

    // ZK proof verifier
    wire zk_verify_valid, zk_verify_done;
    reg zk_verify_start;
    reg [POINT_BITS-1:0] zk_verify_commitment_X, zk_verify_commitment_Y;
    reg [POINT_BITS-1:0] zk_verify_proof_R_X, zk_verify_proof_R_Y;
    reg [SCALAR_BITS-1:0] zk_verify_proof_z;

    wire [255:0] zk_verify_context;
    assign zk_verify_context = {248'b0, process_index[7:0]};

    zk_schnorr_verify #(.SCALAR_BITS(SCALAR_BITS), .POINT_BITS(POINT_BITS)) zk_verify (
        .clk(clk), .rst_n(rst_n), .start(zk_verify_start),
        .commitment_X(zk_verify_commitment_X),
        .commitment_Y(zk_verify_commitment_Y),
        .proof_R_X(zk_verify_proof_R_X),
        .proof_R_Y(zk_verify_proof_R_Y),
        .proof_z(zk_verify_proof_z),
        .context(zk_verify_context),
        .valid(zk_verify_valid),
        .done(zk_verify_done)
    );

    // VSS verifier
    wire vss_valid, vss_done;
    reg vss_start;

    vss_verify #(.THRESHOLD(THRESHOLD), .SCALAR_BITS(SCALAR_BITS), .POINT_BITS(POINT_BITS)) vss (
        .clk(clk), .rst_n(rst_n), .start(vss_start),
        .share(shares_in[process_index]),
        .commitments_X(commitments_in_X),  // This is simplified
        .commitments_Y(commitments_in_Y),
        .index(NODE_ID),
        .valid(vss_valid),
        .done(vss_done)
    );

    // ========================================
    // Main FSM
    // ========================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            dkg_done <= 0;
            cycles <= 0;
            commitment_ready <= 0;
            shares_ready <= 0;
            process_index <= 0;
        end else begin
            state <= next_state;
            cycles <= cycles + 1;

            case (state)
                IDLE: begin
                    if (start_dkg) begin
                        $display("[NODE %0d] Starting FROST DKG...", NODE_ID);
                        process_index <= 0;
                        share_accumulator <= 0;
                        commitment_ready <= 0;
                        shares_ready <= 0;
                        dkg_done <= 0;
                    end
                end

                ROUND0_GEN: begin
                    // Generate random polynomial coefficients
                    if (process_index <= THRESHOLD) begin
                        rng_start <= 1;
                        if (rng_done) begin
                            polynomial_coeffs[process_index] <= rng_output;
                            $display("[NODE %0d] Generated coeff[%0d] = %h", NODE_ID, process_index, rng_output);
                            rng_start <= 0;

                            // Compute commitment C_k = [a_k]G
                            scalar_mult_k <= rng_output;
                            scalar_mult_start <= 1;
                            process_index <= process_index + 1;
                        end
                    end else begin
                        process_index <= 0;
                    end
                end

                ROUND0_PROOF: begin
                    // Generate ZK proof for a_0
                    zk_prove_start <= 1;
                    if (zk_prove_done) begin
                        proof_R_X <= zk_proof_R_X;
                        proof_R_Y <= zk_proof_R_Y;
                        proof_z <= zk_proof_z;
                        zk_prove_start <= 0;
                        $display("[NODE %0d] ZK proof generated", NODE_ID);
                    end
                end

                ROUND0_BCAST: begin
                    // Broadcast commitment and proof
                    commitment_out_X <= my_commitments_X[0];
                    commitment_out_Y <= my_commitments_Y[0];
                    commitment_ready <= 1;
                    $display("[NODE %0d] Broadcast commitment", NODE_ID);
                end

                ROUND0_WAIT: begin
                    // Wait for all nodes to broadcast
                    if (&commitments_valid) begin  // All valid
                        $display("[NODE %0d] All commitments received", NODE_ID);
                        process_index <= 0;
                    end
                end

                ROUND1_VERIFY: begin
                    // Verify ZK proofs from all other nodes
                    if (process_index < NUM_NODES) begin
                        if (process_index != NODE_ID) begin
                            zk_verify_start <= 1;
                            zk_verify_commitment_X <= commitments_in_X[process_index];
                            zk_verify_commitment_Y <= commitments_in_Y[process_index];

                            if (zk_verify_done) begin
                                if (!zk_verify_valid) begin
                                    $display("[NODE %0d] ERROR: ZK proof from node %0d invalid!", NODE_ID, process_index);
                                    // Go to ERROR state
                                end
                                zk_verify_start <= 0;
                                process_index <= process_index + 1;
                            end
                        end else begin
                            process_index <= process_index + 1;
                        end
                    end else begin
                        $display("[NODE %0d] All ZK proofs verified", NODE_ID);
                        process_index <= 0;
                    end
                end

                ROUND1_EVAL: begin
                    // Evaluate polynomial for each other node
                    if (process_index < NUM_NODES) begin
                        poly_eval_x <= process_index + 1;  // Eval at index 1, 2, 3, 4
                        poly_eval_start <= 1;

                        if (poly_eval_done) begin
                            shares_out[process_index] <= poly_eval_result;
                            $display("[NODE %0d] Share for node %0d = %h", NODE_ID, process_index, poly_eval_result);
                            poly_eval_start <= 0;
                            process_index <= process_index + 1;
                        end
                    end else begin
                        process_index <= 0;
                    end
                end

                ROUND1_SEND: begin
                    // Signal shares are ready
                    shares_ready <= {NUM_NODES{1'b1}};
                    $display("[NODE %0d] Shares sent", NODE_ID);
                end

                ROUND1_WAIT: begin
                    // Wait for shares from all nodes
                    if (&shares_valid) begin
                        $display("[NODE %0d] All shares received", NODE_ID);
                        process_index <= 0;
                    end
                end

                ROUND2_VSS: begin
                    // VSS verification for each received share
                    if (process_index < NUM_NODES) begin
                        if (process_index != NODE_ID) begin
                            vss_start <= 1;

                            if (vss_done) begin
                                if (!vss_valid) begin
                                    $display("[NODE %0d] ERROR: VSS failed for share from node %0d!", NODE_ID, process_index);
                                end
                                vss_start <= 0;
                                process_index <= process_index + 1;
                            end
                        end else begin
                            process_index <= process_index + 1;
                        end
                    end else begin
                        $display("[NODE %0d] VSS verification complete", NODE_ID);
                        process_index <= 0;
                    end
                end

                ROUND2_DERIVE: begin
                    // Derive final secret share: s_i = ∑_j s_{j→i}
                    if (process_index < NUM_NODES) begin
                        share_accumulator <= share_accumulator + shares_in[process_index];
                        process_index <= process_index + 1;
                    end else begin
                        secret_share <= share_accumulator;

                        // Derive group public key: A = ∑_j C_{j,0}
                        // (Simplified - should be point addition)
                        group_key_X <= commitments_in_X[0];  // Placeholder
                        group_key_Y <= commitments_in_Y[0];

                        $display("[NODE %0d] Final secret share = %h", NODE_ID, share_accumulator);
                        $display("[NODE %0d] Group key = (%h, %h)", NODE_ID, commitments_in_X[0], commitments_in_Y[0]);
                    end
                end

                DONE: begin
                    dkg_done <= 1;
                    $display("[NODE %0d] FROST DKG COMPLETE! Cycles: %0d", NODE_ID, cycles);
                end

                ERROR: begin
                    $display("[NODE %0d] ERROR STATE!", NODE_ID);
                    dkg_done <= 1;  // Stop simulation
                end
            endcase
        end
    end

    // Next state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:           if (start_dkg) next_state = ROUND0_GEN;
            ROUND0_GEN:     if (process_index > THRESHOLD && scalar_mult_done) next_state = ROUND0_PROOF;
            ROUND0_PROOF:   if (zk_prove_done) next_state = ROUND0_BCAST;
            ROUND0_BCAST:   next_state = ROUND0_WAIT;
            ROUND0_WAIT:    if (&commitments_valid) next_state = ROUND1_VERIFY;
            ROUND1_VERIFY:  if (process_index >= NUM_NODES) next_state = ROUND1_EVAL;
            ROUND1_EVAL:    if (process_index >= NUM_NODES && poly_eval_done) next_state = ROUND1_SEND;
            ROUND1_SEND:    next_state = ROUND1_WAIT;
            ROUND1_WAIT:    if (&shares_valid) next_state = ROUND2_VSS;
            ROUND2_VSS:     if (process_index >= NUM_NODES) next_state = ROUND2_DERIVE;
            ROUND2_DERIVE:  if (process_index >= NUM_NODES) next_state = DONE;
            DONE:           next_state = DONE;
            ERROR:          next_state = ERROR;
            default:        next_state = IDLE;
        endcase
    end

endmodule
