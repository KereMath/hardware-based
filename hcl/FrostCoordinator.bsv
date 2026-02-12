// FROST DKG Coordinator - Connects Multiple Nodes
// Bluespec SystemVerilog (BSV)

package FrostCoordinator;

import FrostTypes::*;
import FrostNode::*;
import Vector::*;
import StmtFSM::*;

// ============================================================================
// Coordinator State
// ============================================================================

typedef enum {
    COORD_IDLE,
    COORD_START,
    COORD_EXCHANGE_COMMITMENTS,
    COORD_EXCHANGE_SHARES,
    COORD_DONE
} CoordState deriving (Bits, Eq);

// ============================================================================
// FROST Coordinator Interface
// ============================================================================

interface FrostCoordinator;
    method Action startProtocol();
    method Bool protocolDone();
    method UInt#(32) getTotalCycles();
    method Scalar getFinalKey(NodeId node);
    method Commitment getGroupKey();
endinterface

// ============================================================================
// FROST Coordinator Module
// ============================================================================

(* synthesize *)
module mkFrostCoordinator(FrostCoordinator);

    // Instantiate all nodes
    Vector#(NumNodes, FrostNode) nodes <- genWithM(mkFrostNode);

    // Coordinator state
    Reg#(CoordState) state <- mkReg(COORD_IDLE);
    Reg#(UInt#(32)) totalCycles <- mkReg(0);
    Reg#(Bool) done <- mkReg(False);

    // Cycle counter
    rule countCycles (state != COORD_IDLE && state != COORD_DONE);
        totalCycles <= totalCycles + 1;
    endrule

    // Start all nodes
    rule startNodes (state == COORD_START);
        for (Integer i = 0; i < valueOf(NumNodes); i = i + 1) begin
            nodes[i].startDkg();
        end
        $display("[COORDINATOR] Started all %0d nodes", valueOf(NumNodes));
        state <= COORD_EXCHANGE_COMMITMENTS;
    endrule

    // Exchange commitments between nodes
    Reg#(UInt#(4)) exchangeIndex <- mkReg(0);
    Reg#(Bool) commitmentsExchanged <- mkReg(False);

    rule exchangeCommitments (state == COORD_EXCHANGE_COMMITMENTS && !commitmentsExchanged);
        // Simple broadcast: each node's commitment goes to all other nodes
        for (Integer sender = 0; sender < valueOf(NumNodes); sender = sender + 1) begin
            Commitment c = nodes[sender].getMyCommitment();
            for (Integer receiver = 0; receiver < valueOf(NumNodes); receiver = receiver + 1) begin
                if (sender != receiver) begin
                    nodes[receiver].receiveCommitment(fromInteger(sender), c);
                end
            end
        end
        $display("[COORDINATOR] Exchanged commitments");
        commitmentsExchanged <= True;
        state <= COORD_EXCHANGE_SHARES;
    endrule

    // Exchange shares between nodes
    Reg#(Bool) sharesExchanged <- mkReg(False);

    rule exchangeShares (state == COORD_EXCHANGE_SHARES && !sharesExchanged);
        // Each node sends its share to every other node
        for (Integer sender = 0; sender < valueOf(NumNodes); sender = sender + 1) begin
            for (Integer receiver = 0; receiver < valueOf(NumNodes); receiver = receiver + 1) begin
                Scalar share = nodes[sender].getShareFor(fromInteger(receiver));
                nodes[receiver].receiveShare(fromInteger(sender), share);
            end
        end
        $display("[COORDINATOR] Exchanged shares");
        sharesExchanged <= True;
        state <= COORD_DONE;
    endrule

    // Check if all nodes are done
    rule checkDone (state == COORD_DONE && !done);
        Bool allDone = True;
        for (Integer i = 0; i < valueOf(NumNodes); i = i + 1) begin
            if (!nodes[i].isDone()) allDone = False;
        end

        if (allDone) begin
            $display("[COORDINATOR] All nodes completed DKG");
            $display("[COORDINATOR] Total cycles: %0d", totalCycles);
            done <= True;
        end
    endrule

    // ========================================================================
    // Interface Methods
    // ========================================================================

    method Action startProtocol() if (state == COORD_IDLE);
        $display("========================================");
        $display("FROST DKG BLUESPEC IMPLEMENTATION");
        $display("Nodes: %0d, Threshold: %0d", valueOf(NumNodes), valueOf(Threshold));
        $display("========================================");
        state <= COORD_START;
        totalCycles <= 0;
        commitmentsExchanged <= False;
        sharesExchanged <= False;
        done <= False;
    endmethod

    method Bool protocolDone();
        return done;
    endmethod

    method UInt#(32) getTotalCycles();
        return totalCycles;
    endmethod

    method Scalar getFinalKey(NodeId node) if (done);
        return nodes[node].getSecretShare();
    endmethod

    method Commitment getGroupKey() if (done);
        return nodes[0].getGroupKey();  // All nodes have same group key
    endmethod

endmodule

endpackage
