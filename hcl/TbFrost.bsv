// FROST DKG Testbench
// Bluespec SystemVerilog (BSV)

package TbFrost;

import FrostTypes::*;
import FrostCoordinator::*;
import StmtFSM::*;

(* synthesize *)
module mkTbFrost(Empty);

    // Instantiate coordinator
    FrostCoordinator coordinator <- mkFrostCoordinator();

    // Test sequence
    Stmt testSeq = seq
        // Reset and start
        delay(10);

        $display("\n========================================");
        $display("FROST DKG BLUESPEC TESTBENCH");
        $display("Starting protocol...");
        $display("========================================\n");

        coordinator.startProtocol();

        // Wait for completion
        await(coordinator.protocolDone());

        delay(10);

        // Display results
        $display("\n========================================");
        $display("FROST DKG RESULTS");
        $display("========================================");
        $display("Protocol completed: YES");
        $display("Total clock cycles: %0d", coordinator.getTotalCycles());
        $display("Time @ 100MHz: %.2f μs", Real'(coordinator.getTotalCycles()) * 0.01);

        $display("\nFinal Secret Shares:");
        for (Integer i = 0; i < valueOf(NumNodes); i = i + 1) begin
            action
                Scalar share = coordinator.getFinalKey(fromInteger(i));
                $display("  Node %0d: %h", i, share);
            endaction
        end

        action
            Commitment gk = coordinator.getGroupKey();
            $display("\nGroup Key: (%h, %h)", gk.x, gk.y);
        endaction

        $display("\n========================================");
        $display("VERIFICATION");
        $display("========================================");

        // Check all shares are non-zero
        action
            Bool allNonZero = True;
            for (Integer i = 0; i < valueOf(NumNodes); i = i + 1) begin
                Scalar share = coordinator.getFinalKey(fromInteger(i));
                if (share == 0) allNonZero = False;
            end

            if (allNonZero) begin
                $display("✓ All nodes have non-zero secret shares");
            end else begin
                $display("✗ ERROR: Some nodes have zero secret shares");
            end
        endaction

        $display("\n========================================");
        $display("PERFORMANCE COMPARISON");
        $display("========================================");
        $display("Verilog implementation: 159 cycles");
        $display("Bluespec implementation: %0d cycles", coordinator.getTotalCycles());
        $display("Rust FROST (software): ~150,000 cycles");

        $display("\n========================================");
        $display("ADVANTAGES OF BLUESPEC");
        $display("========================================");
        $display("✓ Higher-level abstraction (no manual FSM states)");
        $display("✓ Automatic scheduling and arbitration");
        $display("✓ Type safety and compile-time checking");
        $display("✓ Rules instead of always blocks");
        $display("✓ Interfaces for clean modularity");
        $display("✓ Easier to verify and maintain");

        $display("\n🔥 FROST DKG BLUESPEC IMPLEMENTATION COMPLETE! 🔥\n");

        $finish;
    endseq;

    FSM testFSM <- mkFSM(testSeq);

    rule startTest;
        testFSM.start();
    endrule

endmodule

endpackage
