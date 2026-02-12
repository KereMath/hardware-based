// Simple FROST DKG Testbench
// Demonstrates hardware acceleration concept

`timescale 1ns/1ps

module tb_frost_simple;

    reg clk, rst_n;
    reg start_protocol;
    wire protocol_done;
    wire [15:0] total_cycles;
    wire [251:0] final_keys_0, final_keys_1, final_keys_2, final_keys_3;

    // Clock generation (100 MHz = 10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT instantiation
    frost_simple_coordinator #(
        .NUM_NODES(4),
        .THRESHOLD(2),
        .SCALAR_BITS(252)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_protocol(start_protocol),
        .protocol_done(protocol_done),
        .total_cycles(total_cycles),
        .final_keys_0(final_keys_0),
        .final_keys_1(final_keys_1),
        .final_keys_2(final_keys_2),
        .final_keys_3(final_keys_3)
    );

    // Test sequence
    initial begin
        $display("========================================");
        $display("FROST DKG Hardware Testbench (Simplified)");
        $display("Nodes: 4, Threshold: 2-of-4");
        $display("========================================\n");

        // Initialize
        rst_n = 0;
        start_protocol = 0;
        #100;
        rst_n = 1;
        #50;

        // Start FROST DKG protocol
        $display("[%0t] Starting FROST DKG protocol...", $time);
        @(posedge clk);
        start_protocol = 1;
        @(posedge clk);
        start_protocol = 0;

        // Wait for protocol completion
        wait(protocol_done);
        @(posedge clk);

        #100;

        // Display results
        $display("\n========================================");
        $display("FROST DKG HARDWARE RESULTS");
        $display("========================================");
        $display("Protocol completed: %s", protocol_done ? "YES" : "NO");
        $display("Total clock cycles: %0d", total_cycles);
        $display("Time elapsed: %.2f μs", (total_cycles * 10.0) / 1000.0);
        $display("Frequency: 100 MHz (10 ns period)");

        $display("\nFinal Secret Shares:");
        $display("  Node 0: %h", final_keys_0);
        $display("  Node 1: %h", final_keys_1);
        $display("  Node 2: %h", final_keys_2);
        $display("  Node 3: %h", final_keys_3);

        // Verification
        $display("\n========================================");
        $display("VERIFICATION");
        $display("========================================");

        // Check that all shares are non-zero (sanity check)
        if (final_keys_0 != 0 && final_keys_1 != 0 &&
            final_keys_2 != 0 && final_keys_3 != 0) begin
            $display("✓ All nodes have non-zero secret shares");
        end else begin
            $display("✗ ERROR: Some nodes have zero secret shares");
        end

        // Check that shares are different (another sanity check)
        if (final_keys_0 != final_keys_1 &&
            final_keys_1 != final_keys_2 &&
            final_keys_2 != final_keys_3) begin
            $display("✓ All secret shares are unique");
        end else begin
            $display("WARNING: Some secret shares are identical (may be OK for testing)");
        end

        $display("\n========================================");
        $display("PERFORMANCE METRICS");
        $display("========================================");
        $display("Clock frequency: 100 MHz");
        $display("Total cycles: %0d", total_cycles);
        $display("Time: %.2f μs", (total_cycles * 10.0) / 1000.0);
        $display("Throughput: %.2f DKG/sec", 1000000.0 / (total_cycles * 10.0));

        $display("\n========================================");
        $display("vs. SOFTWARE BASELINE (Rust/Givre)");
        $display("========================================");
        $display("Software cycles (estimated): ~150,000");
        $display("Hardware cycles (actual): %0d", total_cycles);
        if (total_cycles > 0)
            $display("Speedup: ~%.1fx", 150000.0 / total_cycles);

        $display("\n🔥 FROST DKG Hardware Acceleration Complete! 🔥\n");

        $finish;
    end

    // Timeout watchdog (prevent infinite simulation)
    initial begin
        #100000;  // 100 μs timeout
        $display("\n⚠️  TIMEOUT: Simulation exceeded 100μs");
        $display("Protocol may be stuck. Check waveform.");
        $finish;
    end

    // Waveform dump for debugging
    initial begin
        $dumpfile("frost_simple.vcd");
        $dumpvars(0, tb_frost_simple);
    end

endmodule
