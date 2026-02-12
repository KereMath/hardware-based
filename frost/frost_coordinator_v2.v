// FROST DKG Coordinator - Hardware Implementation
// Coordinates 4 nodes with individual wire connections (no arrays)
// Full protocol implementation

module frost_coordinator #(
    parameter NUM_NODES = 4,
    parameter THRESHOLD = 2,
    parameter SCALAR_BITS = 252,
    parameter POINT_BITS = 255
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start_protocol,

    output wire protocol_done,
    output reg  [15:0] total_cycles,
    output wire [SCALAR_BITS-1:0] final_keys_0,
    output wire [SCALAR_BITS-1:0] final_keys_1,
    output wire [SCALAR_BITS-1:0] final_keys_2,
    output wire [SCALAR_BITS-1:0] final_keys_3
);

    // Node 0 signals
    wire [POINT_BITS-1:0] n0_commit_X, n0_commit_Y;
    wire [POINT_BITS-1:0] n0_proof_R_X, n0_proof_R_Y;
    wire [SCALAR_BITS-1:0] n0_proof_z;
    wire n0_commit_ready;
    wire [SCALAR_BITS-1:0] n0_share_out_0, n0_share_out_1, n0_share_out_2, n0_share_out_3;
    wire n0_share_ready_0, n0_share_ready_1, n0_share_ready_2, n0_share_ready_3;
    wire [SCALAR_BITS-1:0] n0_secret;
    wire [POINT_BITS-1:0] n0_group_X, n0_group_Y;
    wire n0_done;
    wire [15:0] n0_cycles;

    // Node 1 signals
    wire [POINT_BITS-1:0] n1_commit_X, n1_commit_Y;
    wire [POINT_BITS-1:0] n1_proof_R_X, n1_proof_R_Y;
    wire [SCALAR_BITS-1:0] n1_proof_z;
    wire n1_commit_ready;
    wire [SCALAR_BITS-1:0] n1_share_out_0, n1_share_out_1, n1_share_out_2, n1_share_out_3;
    wire n1_share_ready_0, n1_share_ready_1, n1_share_ready_2, n1_share_ready_3;
    wire [SCALAR_BITS-1:0] n1_secret;
    wire [POINT_BITS-1:0] n1_group_X, n1_group_Y;
    wire n1_done;
    wire [15:0] n1_cycles;

    // Node 2 signals
    wire [POINT_BITS-1:0] n2_commit_X, n2_commit_Y;
    wire [POINT_BITS-1:0] n2_proof_R_X, n2_proof_R_Y;
    wire [SCALAR_BITS-1:0] n2_proof_z;
    wire n2_commit_ready;
    wire [SCALAR_BITS-1:0] n2_share_out_0, n2_share_out_1, n2_share_out_2, n2_share_out_3;
    wire n2_share_ready_0, n2_share_ready_1, n2_share_ready_2, n2_share_ready_3;
    wire [SCALAR_BITS-1:0] n2_secret;
    wire [POINT_BITS-1:0] n2_group_X, n2_group_Y;
    wire n2_done;
    wire [15:0] n2_cycles;

    // Node 3 signals
    wire [POINT_BITS-1:0] n3_commit_X, n3_commit_Y;
    wire [POINT_BITS-1:0] n3_proof_R_X, n3_proof_R_Y;
    wire [SCALAR_BITS-1:0] n3_proof_z;
    wire n3_commit_ready;
    wire [SCALAR_BITS-1:0] n3_share_out_0, n3_share_out_1, n3_share_out_2, n3_share_out_3;
    wire n3_share_ready_0, n3_share_ready_1, n3_share_ready_2, n3_share_ready_3;
    wire [SCALAR_BITS-1:0] n3_secret;
    wire [POINT_BITS-1:0] n3_group_X, n3_group_Y;
    wire n3_done;
    wire [15:0] n3_cycles;

    // Instantiate Node 0
    frost_node #(
        .NODE_ID(0), .NUM_NODES(NUM_NODES), .THRESHOLD(THRESHOLD),
        .SCALAR_BITS(SCALAR_BITS), .POINT_BITS(POINT_BITS)
    ) node0 (
        .clk(clk), .rst_n(rst_n), .start_dkg(start_protocol),
        // Outputs
        .commitment_out_X(n0_commit_X), .commitment_out_Y(n0_commit_Y),
        .proof_R_X(n0_proof_R_X), .proof_R_Y(n0_proof_R_Y), .proof_z(n0_proof_z),
        .commitment_ready(n0_commit_ready),
        // Commitment inputs from all nodes
        .commitments_in_X_0(n0_commit_X), .commitments_in_Y_0(n0_commit_Y),
        .commitments_in_X_1(n1_commit_X), .commitments_in_Y_1(n1_commit_Y),
        .commitments_in_X_2(n2_commit_X), .commitments_in_Y_2(n2_commit_Y),
        .commitments_in_X_3(n3_commit_X), .commitments_in_Y_3(n3_commit_Y),
        .commitments_valid_0(n0_commit_ready),
        .commitments_valid_1(n1_commit_ready),
        .commitments_valid_2(n2_commit_ready),
        .commitments_valid_3(n3_commit_ready),
        // Share outputs
        .shares_out_0(n0_share_out_0), .shares_out_1(n0_share_out_1),
        .shares_out_2(n0_share_out_2), .shares_out_3(n0_share_out_3),
        .shares_ready_0(n0_share_ready_0), .shares_ready_1(n0_share_ready_1),
        .shares_ready_2(n0_share_ready_2), .shares_ready_3(n0_share_ready_3),
        // Share inputs from all nodes (each node gets shares from all)
        .shares_in_0(n0_share_out_0), .shares_in_1(n1_share_out_0),
        .shares_in_2(n2_share_out_0), .shares_in_3(n3_share_out_0),
        .shares_valid_0(n0_share_ready_0), .shares_valid_1(n1_share_ready_0),
        .shares_valid_2(n2_share_ready_0), .shares_valid_3(n3_share_ready_0),
        // Final outputs
        .secret_share(n0_secret), .group_key_X(n0_group_X), .group_key_Y(n0_group_Y),
        .dkg_done(n0_done), .cycles(n0_cycles)
    );

    // Instantiate Node 1
    frost_node #(
        .NODE_ID(1), .NUM_NODES(NUM_NODES), .THRESHOLD(THRESHOLD),
        .SCALAR_BITS(SCALAR_BITS), .POINT_BITS(POINT_BITS)
    ) node1 (
        .clk(clk), .rst_n(rst_n), .start_dkg(start_protocol),
        .commitment_out_X(n1_commit_X), .commitment_out_Y(n1_commit_Y),
        .proof_R_X(n1_proof_R_X), .proof_R_Y(n1_proof_R_Y), .proof_z(n1_proof_z),
        .commitment_ready(n1_commit_ready),
        .commitments_in_X_0(n0_commit_X), .commitments_in_Y_0(n0_commit_Y),
        .commitments_in_X_1(n1_commit_X), .commitments_in_Y_1(n1_commit_Y),
        .commitments_in_X_2(n2_commit_X), .commitments_in_Y_2(n2_commit_Y),
        .commitments_in_X_3(n3_commit_X), .commitments_in_Y_3(n3_commit_Y),
        .commitments_valid_0(n0_commit_ready), .commitments_valid_1(n1_commit_ready),
        .commitments_valid_2(n2_commit_ready), .commitments_valid_3(n3_commit_ready),
        .shares_out_0(n1_share_out_0), .shares_out_1(n1_share_out_1),
        .shares_out_2(n1_share_out_2), .shares_out_3(n1_share_out_3),
        .shares_ready_0(n1_share_ready_0), .shares_ready_1(n1_share_ready_1),
        .shares_ready_2(n1_share_ready_2), .shares_ready_3(n1_share_ready_3),
        .shares_in_0(n0_share_out_1), .shares_in_1(n1_share_out_1),
        .shares_in_2(n2_share_out_1), .shares_in_3(n3_share_out_1),
        .shares_valid_0(n0_share_ready_1), .shares_valid_1(n1_share_ready_1),
        .shares_valid_2(n2_share_ready_1), .shares_valid_3(n3_share_ready_1),
        .secret_share(n1_secret), .group_key_X(n1_group_X), .group_key_Y(n1_group_Y),
        .dkg_done(n1_done), .cycles(n1_cycles)
    );

    // Instantiate Node 2
    frost_node #(
        .NODE_ID(2), .NUM_NODES(NUM_NODES), .THRESHOLD(THRESHOLD),
        .SCALAR_BITS(SCALAR_BITS), .POINT_BITS(POINT_BITS)
    ) node2 (
        .clk(clk), .rst_n(rst_n), .start_dkg(start_protocol),
        .commitment_out_X(n2_commit_X), .commitment_out_Y(n2_commit_Y),
        .proof_R_X(n2_proof_R_X), .proof_R_Y(n2_proof_R_Y), .proof_z(n2_proof_z),
        .commitment_ready(n2_commit_ready),
        .commitments_in_X_0(n0_commit_X), .commitments_in_Y_0(n0_commit_Y),
        .commitments_in_X_1(n1_commit_X), .commitments_in_Y_1(n1_commit_Y),
        .commitments_in_X_2(n2_commit_X), .commitments_in_Y_2(n2_commit_Y),
        .commitments_in_X_3(n3_commit_X), .commitments_in_Y_3(n3_commit_Y),
        .commitments_valid_0(n0_commit_ready), .commitments_valid_1(n1_commit_ready),
        .commitments_valid_2(n2_commit_ready), .commitments_valid_3(n3_commit_ready),
        .shares_out_0(n2_share_out_0), .shares_out_1(n2_share_out_1),
        .shares_out_2(n2_share_out_2), .shares_out_3(n2_share_out_3),
        .shares_ready_0(n2_share_ready_0), .shares_ready_1(n2_share_ready_1),
        .shares_ready_2(n2_share_ready_2), .shares_ready_3(n2_share_ready_3),
        .shares_in_0(n0_share_out_2), .shares_in_1(n1_share_out_2),
        .shares_in_2(n2_share_out_2), .shares_in_3(n3_share_out_2),
        .shares_valid_0(n0_share_ready_2), .shares_valid_1(n1_share_ready_2),
        .shares_valid_2(n2_share_ready_2), .shares_valid_3(n3_share_ready_2),
        .secret_share(n2_secret), .group_key_X(n2_group_X), .group_key_Y(n2_group_Y),
        .dkg_done(n2_done), .cycles(n2_cycles)
    );

    // Instantiate Node 3
    frost_node #(
        .NODE_ID(3), .NUM_NODES(NUM_NODES), .THRESHOLD(THRESHOLD),
        .SCALAR_BITS(SCALAR_BITS), .POINT_BITS(POINT_BITS)
    ) node3 (
        .clk(clk), .rst_n(rst_n), .start_dkg(start_protocol),
        .commitment_out_X(n3_commit_X), .commitment_out_Y(n3_commit_Y),
        .proof_R_X(n3_proof_R_X), .proof_R_Y(n3_proof_R_Y), .proof_z(n3_proof_z),
        .commitment_ready(n3_commit_ready),
        .commitments_in_X_0(n0_commit_X), .commitments_in_Y_0(n0_commit_Y),
        .commitments_in_X_1(n1_commit_X), .commitments_in_Y_1(n1_commit_Y),
        .commitments_in_X_2(n2_commit_X), .commitments_in_Y_2(n2_commit_Y),
        .commitments_in_X_3(n3_commit_X), .commitments_in_Y_3(n3_commit_Y),
        .commitments_valid_0(n0_commit_ready), .commitments_valid_1(n1_commit_ready),
        .commitments_valid_2(n2_commit_ready), .commitments_valid_3(n3_commit_ready),
        .shares_out_0(n3_share_out_0), .shares_out_1(n3_share_out_1),
        .shares_out_2(n3_share_out_2), .shares_out_3(n3_share_out_3),
        .shares_ready_0(n3_share_ready_0), .shares_ready_1(n3_share_ready_1),
        .shares_ready_2(n3_share_ready_2), .shares_ready_3(n3_share_ready_3),
        .shares_in_0(n0_share_out_3), .shares_in_1(n1_share_out_3),
        .shares_in_2(n2_share_out_3), .shares_in_3(n3_share_out_3),
        .shares_valid_0(n0_share_ready_3), .shares_valid_1(n1_share_ready_3),
        .shares_valid_2(n2_share_ready_3), .shares_valid_3(n3_share_ready_3),
        .secret_share(n3_secret), .group_key_X(n3_group_X), .group_key_Y(n3_group_Y),
        .dkg_done(n3_done), .cycles(n3_cycles)
    );

    // Protocol completion
    assign protocol_done = n0_done & n1_done & n2_done & n3_done;

    // Output final keys
    assign final_keys_0 = n0_secret;
    assign final_keys_1 = n1_secret;
    assign final_keys_2 = n2_secret;
    assign final_keys_3 = n3_secret;

    // Cycle counter (use max of all nodes)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_cycles <= 0;
        end else begin
            if (n0_cycles > total_cycles) total_cycles <= n0_cycles;
            if (n1_cycles > total_cycles) total_cycles <= n1_cycles;
            if (n2_cycles > total_cycles) total_cycles <= n2_cycles;
            if (n3_cycles > total_cycles) total_cycles <= n3_cycles;
        end
    end

endmodule
