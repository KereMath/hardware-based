// FROST DKG Coordinator
// Top-level module that instantiates 4 nodes and coordinates execution
// Manages shared memory for inter-node communication

module frost_coordinator #(
    parameter NUM_NODES = 4,
    parameter THRESHOLD = 2,
    parameter SCALAR_BITS = 252,
    parameter POINT_BITS = 255
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start_protocol,
    output reg  protocol_done,
    output reg  [15:0] total_cycles,
    output reg  [SCALAR_BITS-1:0] final_keys [0:NUM_NODES-1]
);

    // ========================================
    // Shared Memory Arrays
    // ========================================

    // Commitment storage (Round 0 broadcast)
    reg [POINT_BITS-1:0] shared_commitments_X [0:NUM_NODES-1];
    reg [POINT_BITS-1:0] shared_commitments_Y [0:NUM_NODES-1];
    reg [NUM_NODES-1:0] commitments_valid;

    // Share storage (Round 1 P2P communication)
    reg [SCALAR_BITS-1:0] shared_shares [0:NUM_NODES-1][0:NUM_NODES-1];  // [from][to]
    reg [NUM_NODES-1:0] shares_valid [0:NUM_NODES-1];  // Per-recipient validation

    // ========================================
    // Node instances
    // ========================================

    genvar i;
    generate
        for (i = 0; i < NUM_NODES; i = i + 1) begin : nodes
            wire [POINT_BITS-1:0] node_commitment_X, node_commitment_Y;
            wire [POINT_BITS-1:0] node_proof_R_X, node_proof_R_Y;
            wire [SCALAR_BITS-1:0] node_proof_z;
            wire node_commitment_ready;

            wire [SCALAR_BITS-1:0] node_shares_out [0:NUM_NODES-1];
            wire [NUM_NODES-1:0] node_shares_ready;

            wire [SCALAR_BITS-1:0] node_shares_in [0:NUM_NODES-1];
            wire [NUM_NODES-1:0] node_shares_valid_in;

            wire [SCALAR_BITS-1:0] node_secret_share;
            wire [POINT_BITS-1:0] node_group_key_X, node_group_key_Y;
            wire node_dkg_done;
            wire [15:0] node_cycles;

            // Wire node outputs to shared memory
            always @(posedge clk) begin
                if (node_commitment_ready) begin
                    shared_commitments_X[i] <= node_commitment_X;
                    shared_commitments_Y[i] <= node_commitment_Y;
                    commitments_valid[i] <= 1;
                end

                // Write shares to shared memory
                if (node_shares_ready[0]) begin  // Simplified - check all bits
                    for (integer j = 0; j < NUM_NODES; j = j + 1) begin
                        shared_shares[i][j] <= node_shares_out[j];
                        shares_valid[j][i] <= 1;  // Mark as valid for recipient j
                    end
                end
            end

            // Wire shared memory to node inputs
            assign node_shares_in = shared_shares[i];  // This node receives shares from all
            assign node_shares_valid_in = shares_valid[i];  // Which shares are valid

            frost_node_fsm #(
                .NODE_ID(i),
                .NUM_NODES(NUM_NODES),
                .THRESHOLD(THRESHOLD),
                .SCALAR_BITS(SCALAR_BITS),
                .POINT_BITS(POINT_BITS)
            ) node (
                .clk(clk),
                .rst_n(rst_n),
                .start_dkg(start_protocol),

                // Commitment outputs
                .commitment_out_X(node_commitment_X),
                .commitment_out_Y(node_commitment_Y),
                .proof_R_X(node_proof_R_X),
                .proof_R_Y(node_proof_R_Y),
                .proof_z(node_proof_z),
                .commitment_ready(node_commitment_ready),

                // Commitment inputs (from shared memory)
                .commitments_in_X(shared_commitments_X),
                .commitments_in_Y(shared_commitments_Y),
                .commitments_valid(commitments_valid),

                // Share outputs
                .shares_out(node_shares_out),
                .shares_ready(node_shares_ready),

                // Share inputs (from shared memory)
                .shares_in(node_shares_in),
                .shares_valid(node_shares_valid_in),

                // Final outputs
                .secret_share(node_secret_share),
                .group_key_X(node_group_key_X),
                .group_key_Y(node_group_key_Y),
                .dkg_done(node_dkg_done),
                .cycles(node_cycles)
            );

            // Store final keys
            always @(posedge clk) begin
                if (node_dkg_done) begin
                    final_keys[i] <= node_secret_share;
                end
            end
        end
    endgenerate

    // ========================================
    // Protocol completion detection
    // ========================================

    wire all_nodes_done;
    assign all_nodes_done = &{nodes[0].node_dkg_done, nodes[1].node_dkg_done,
                              nodes[2].node_dkg_done, nodes[3].node_dkg_done};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            protocol_done <= 0;
            total_cycles <= 0;
        end else begin
            total_cycles <= total_cycles + 1;

            if (all_nodes_done && !protocol_done) begin
                protocol_done <= 1;
                $display("========================================");
                $display("FROST DKG PROTOCOL COMPLETE!");
                $display("Total Cycles: %0d", total_cycles);
                $display("========================================");

                for (integer k = 0; k < NUM_NODES; k = k + 1) begin
                    $display("Node %0d: Secret Share = %h", k, final_keys[k]);
                end
            end
        end
    end

    // ========================================
    // Shared memory initialization
    // ========================================

    initial begin
        commitments_valid = 0;
        for (integer m = 0; m < NUM_NODES; m = m + 1) begin
            shares_valid[m] = 0;
        end
    end

endmodule


// Shared Memory Module (standalone version)
module frost_shared_memory #(
    parameter NUM_NODES = 4,
    parameter DATA_WIDTH = 256
)(
    input  wire clk,
    input  wire rst_n,

    // Write ports (one per node)
    input  wire [NUM_NODES-1:0] wr_en,
    input  wire [7:0] wr_addr [NUM_NODES-1:0],
    input  wire [DATA_WIDTH-1:0] wr_data [NUM_NODES-1:0],

    // Read ports (one per node)
    input  wire [7:0] rd_addr [NUM_NODES-1:0],
    output wire [DATA_WIDTH-1:0] rd_data [NUM_NODES-1:0]
);

    // Memory array: [node_id][address]
    reg [DATA_WIDTH-1:0] mem [0:NUM_NODES-1][0:255];

    // Write logic
    genvar i;
    generate
        for (i = 0; i < NUM_NODES; i = i + 1) begin : write_ports
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    // Reset memory
                    for (integer j = 0; j < 256; j = j + 1) begin
                        mem[i][j] <= 0;
                    end
                end else if (wr_en[i]) begin
                    mem[i][wr_addr[i]] <= wr_data[i];
                end
            end
        end
    endgenerate

    // Read logic (combinational)
    generate
        for (i = 0; i < NUM_NODES; i = i + 1) begin : read_ports
            assign rd_data[i] = mem[i][rd_addr[i]];
        end
    endgenerate

endmodule


// Round Synchronization Barrier
module round_sync_barrier #(
    parameter NUM_NODES = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [NUM_NODES-1:0] node_ready,  // Each node signals ready
    output reg  all_ready,
    output reg  [15:0] wait_cycles
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            all_ready <= 0;
            wait_cycles <= 0;
        end else begin
            if (&node_ready) begin  // AND reduction - all ready
                all_ready <= 1;
                wait_cycles <= 0;
            end else begin
                all_ready <= 0;
                if (|node_ready)  // At least one ready (waiting for others)
                    wait_cycles <= wait_cycles + 1;
            end
        end
    end

endmodule
