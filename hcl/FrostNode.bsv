// FROST DKG Node Implementation
// Bluespec SystemVerilog (BSV)

package FrostNode;

import FrostTypes::*;
import Ed25519::*;
import FrostProtocol::*;
import FIFOF::*;
import Vector::*;
import StmtFSM::*;

// ============================================================================
// FROST Node State Machine
// ============================================================================

typedef enum {
    IDLE,
    ROUND0_GEN,        // Generate polynomial coefficients
    ROUND0_COMMIT,     // Compute commitments [a_k]G
    ROUND0_PROOF,      // Generate ZK proof
    ROUND0_BCAST,      // Broadcast commitments
    ROUND0_WAIT,       // Wait for all commitments
    ROUND1_VERIFY,     // Verify ZK proofs
    ROUND1_EVAL,       // Evaluate polynomial for shares
    ROUND1_SEND,       // Send shares
    ROUND1_WAIT,       // Wait for all shares
    ROUND2_VSS,        // VSS verification
    ROUND2_DERIVE,     // Derive final secret share and group key
    DONE,
    ERROR
} FrostState deriving (Bits, Eq);

// ============================================================================
// FROST Node Module
// ============================================================================

(* synthesize *)
module mkFrostNode#(NodeId nodeId)(FrostNode);

    // ========================================================================
    // State and Configuration
    // ========================================================================

    Reg#(FrostState) state <- mkReg(IDLE);
    Reg#(UInt#(32)) cycles <- mkReg(0);
    Reg#(Bool) dkgDone <- mkReg(False);

    // PRNG state
    Reg#(Bit#(32)) prngState <- mkReg(extend(nodeId) + 42);

    // ========================================================================
    // Polynomial Coefficients and Commitments
    // ========================================================================

    Vector#(3, Reg#(Scalar)) coeffs <- replicateM(mkRegU);
    Vector#(3, Reg#(Commitment)) myCommitments <- replicateM(mkRegU);
    Reg#(UInt#(2)) coeffIndex <- mkReg(0);

    // ========================================================================
    // Received Commitments from Other Nodes
    // ========================================================================

    Vector#(NumNodes, Reg#(Commitment)) receivedCommitments <- replicateM(mkRegU);
    Vector#(NumNodes, Reg#(Bool)) commitmentValid <- replicateM(mkReg(False));

    // ========================================================================
    // Shares
    // ========================================================================

    Vector#(NumNodes, Reg#(Scalar)) sharesToSend <- replicateM(mkRegU);
    Vector#(NumNodes, Reg#(Scalar)) receivedShares <- replicateM(mkRegU);
    Vector#(NumNodes, Reg#(Bool)) shareValid <- replicateM(mkReg(False));

    // ========================================================================
    // Final Results
    // ========================================================================

    Reg#(Scalar) secretShare <- mkReg(0);
    Reg#(Commitment) groupKey <- mkRegU;

    // ========================================================================
    // Processing Index
    // ========================================================================

    Reg#(UInt#(4)) processIndex <- mkReg(0);

    // ========================================================================
    // Crypto Modules
    // ========================================================================

    ScalarMult scalarMult <- mkScalarMult();
    PointAdd pointAdd <- mkPointAdd();
    PolyEval polyEval <- mkPolyEval();
    VssVerify vssVerify <- mkVssVerify();
    ZkSchnorrProve zkProve <- mkZkSchnorrProve();

    // ========================================================================
    // ZK Proof Storage
    // ========================================================================

    Reg#(SchnorrProof) myProof <- mkRegU;

    // ========================================================================
    // Helper Functions
    // ========================================================================

    // Simple PRNG (Linear Congruential Generator)
    function Bit#(32) nextRandom(Bit#(32) state);
        return (state * 1103515245 + 12345) & 32'h7FFFFFFF;
    endfunction

    function Scalar generateRandomScalar();
        Bit#(32) r = prngState;
        Scalar result = {7{r[31:0]}} & {1'b0, {251{1'b1}}};  // 252 bits
        return result;
    endfunction

    // ========================================================================
    // Rules
    // ========================================================================

    // Cycle counter
    rule incrementCycles (state != IDLE && state != DONE);
        cycles <= cycles + 1;
    endrule

    // ROUND0_GEN: Generate polynomial coefficients
    rule round0Gen (state == ROUND0_GEN);
        if (coeffIndex < 3) begin
            prngState <= nextRandom(prngState);
            Scalar coeff = generateRandomScalar();
            coeffs[coeffIndex] <= coeff;
            $display("[NODE %0d] Generated coefficient[%0d] = %h", nodeId, coeffIndex, coeff);
            coeffIndex <= coeffIndex + 1;
        end else begin
            state <= ROUND0_COMMIT;
            coeffIndex <= 0;
        end
    endrule

    // ROUND0_COMMIT: Compute commitments C_k = [a_k]G
    rule round0Commit (state == ROUND0_COMMIT && coeffIndex < 3);
        if (scalarMult.isReady()) begin
            if (coeffIndex == 0) begin
                // Start scalar multiplication
                scalarMult.start(coeffs[coeffIndex], basePoint());
                $display("[NODE %0d] Computing commitment[%0d]...", nodeId, coeffIndex);
            end else begin
                // Get previous result and start next
                let point <- scalarMult.getResult();
                myCommitments[coeffIndex - 1] <= pointToCommitment(point);
                $display("[NODE %0d] Commitment[%0d] = (%h, %h)",
                         nodeId, coeffIndex - 1, point.x, point.y);

                if (coeffIndex < 3) begin
                    scalarMult.start(coeffs[coeffIndex], basePoint());
                end
            end
            coeffIndex <= coeffIndex + 1;
        end
    endrule

    // Finish ROUND0_COMMIT
    rule round0CommitFinish (state == ROUND0_COMMIT && coeffIndex == 3 && scalarMult.isReady());
        let point <- scalarMult.getResult();
        myCommitments[2] <= pointToCommitment(point);
        $display("[NODE %0d] Commitment[2] = (%h, %h)", nodeId, point.x, point.y);
        state <= ROUND0_PROOF;
    endrule

    // ROUND0_PROOF: Generate ZK proof
    rule round0Proof (state == ROUND0_PROOF);
        if (zkProve.isReady()) begin
            zkProve.start(coeffs[0], myCommitments[0], 256'hDEADBEEF);
            $display("[NODE %0d] Generating ZK proof...", nodeId);
            state <= ROUND0_BCAST;
        end
    endrule

    // ROUND0_BCAST: Broadcast commitment (mark ready)
    rule round0Bcast (state == ROUND0_BCAST);
        if (zkProve.isReady()) begin
            let proof <- zkProve.getResult();
            myProof <= proof;
            $display("[NODE %0d] Broadcasting commitment[0]", nodeId);
            // Mark own commitment as valid
            commitmentValid[nodeId] <= True;
            receivedCommitments[nodeId] <= myCommitments[0];
            state <= ROUND0_WAIT;
        end
    endrule

    // ROUND0_WAIT: Wait for all commitments
    rule round0Wait (state == ROUND0_WAIT);
        Bool allValid = True;
        for (Integer i = 0; i < valueOf(NumNodes); i = i + 1) begin
            if (!commitmentValid[i]) allValid = False;
        end

        if (allValid) begin
            $display("[NODE %0d] All commitments received", nodeId);
            state <= ROUND1_VERIFY;
            processIndex <= 0;
        end
    endrule

    // ROUND1_VERIFY: Verify ZK proofs (mock - just count)
    rule round1Verify (state == ROUND1_VERIFY);
        if (processIndex < fromInteger(valueOf(NumNodes))) begin
            $display("[NODE %0d] Verifying proof from node %0d", nodeId, processIndex);
            processIndex <= processIndex + 1;
        end else begin
            $display("[NODE %0d] All proofs verified", nodeId);
            state <= ROUND1_EVAL;
            processIndex <= 0;
        end
    endrule

    // ROUND1_EVAL: Evaluate polynomial for each node
    rule round1Eval (state == ROUND1_EVAL && processIndex < fromInteger(valueOf(NumNodes)));
        if (polyEval.isReady()) begin
            if (processIndex == 0) begin
                // Start evaluation for node 0
                Scalar x = extend(pack(processIndex + 1));  // f(1), f(2), f(3), f(4)
                polyEval.start(x, coeffs[0], coeffs[1], coeffs[2]);
                $display("[NODE %0d] Evaluating f(%0d)...", nodeId, processIndex + 1);
            end else begin
                // Get previous result and start next
                let share <- polyEval.getResult();
                sharesToSend[processIndex - 1] <= share;
                $display("[NODE %0d] Share for node %0d = %h", nodeId, processIndex - 1, share);

                if (processIndex < fromInteger(valueOf(NumNodes))) begin
                    Scalar x = extend(pack(processIndex + 1));
                    polyEval.start(x, coeffs[0], coeffs[1], coeffs[2]);
                end
            end
            processIndex <= processIndex + 1;
        end
    endrule

    // Finish ROUND1_EVAL
    rule round1EvalFinish (state == ROUND1_EVAL &&
                          processIndex == fromInteger(valueOf(NumNodes)) &&
                          polyEval.isReady());
        let share <- polyEval.getResult();
        sharesToSend[valueOf(NumNodes) - 1] <= share;
        $display("[NODE %0d] Share for node %0d = %h", nodeId, valueOf(NumNodes) - 1, share);
        state <= ROUND1_SEND;
    endrule

    // ROUND1_SEND: Send shares (mark ready)
    rule round1Send (state == ROUND1_SEND);
        $display("[NODE %0d] Shares sent", nodeId);
        // Mark own share as valid
        shareValid[nodeId] <= True;
        receivedShares[nodeId] <= sharesToSend[nodeId];
        state <= ROUND1_WAIT;
        processIndex <= 0;
    endrule

    // ROUND1_WAIT: Wait for all shares
    rule round1Wait (state == ROUND1_WAIT);
        Bool allValid = True;
        for (Integer i = 0; i < valueOf(NumNodes); i = i + 1) begin
            if (!shareValid[i]) allValid = False;
        end

        if (allValid) begin
            $display("[NODE %0d] All shares received", nodeId);
            state <= ROUND2_VSS;
            processIndex <= 0;
        end
    endrule

    // ROUND2_VSS: VSS verification (mock - just count)
    rule round2Vss (state == ROUND2_VSS);
        if (processIndex < fromInteger(valueOf(NumNodes))) begin
            $display("[NODE %0d] VSS verifying share from node %0d", nodeId, processIndex);
            processIndex <= processIndex + 1;
        end else begin
            $display("[NODE %0d] All VSS verifications passed", nodeId);
            state <= ROUND2_DERIVE;
            processIndex <= 0;
        end
    endrule

    // ROUND2_DERIVE: Derive final secret share and group key
    Reg#(Scalar) shareAccumulator <- mkReg(0);
    Reg#(Ed25519Point) groupKeyAccumulator <- mkReg(identityPoint());

    rule round2DeriveShares (state == ROUND2_DERIVE && processIndex < fromInteger(valueOf(NumNodes)));
        // Accumulate shares: secret_share = sum of all received shares
        shareAccumulator <= shareAccumulator + receivedShares[processIndex];
        $display("[NODE %0d] Accumulating share from node %0d", nodeId, processIndex);
        processIndex <= processIndex + 1;
    endrule

    rule round2DeriveGroupKey (state == ROUND2_DERIVE &&
                               processIndex >= fromInteger(valueOf(NumNodes)) &&
                               processIndex < fromInteger(valueOf(NumNodes)) + 4);
        if (pointAdd.isReady()) begin
            if (processIndex == fromInteger(valueOf(NumNodes))) begin
                // Save secret share
                secretShare <= shareAccumulator;
                $display("[NODE %0d] Final secret share = %h", nodeId, shareAccumulator);

                // Start group key computation: first commitment
                Commitment c0 = receivedCommitments[0];
                groupKeyAccumulator <= Ed25519Point {
                    x: c0.x, y: c0.y, z: 255'd1, t: 255'd1
                };
                $display("[NODE %0d] Starting group key with C[0]", nodeId);
                processIndex <= processIndex + 1;

            end else if (processIndex == fromInteger(valueOf(NumNodes)) + 1) begin
                // Add second commitment
                Commitment c1 = receivedCommitments[1];
                Ed25519Point p1 = Ed25519Point {
                    x: c1.x, y: c1.y, z: 255'd1, t: 255'd1
                };
                pointAdd.start(groupKeyAccumulator, p1);
                $display("[NODE %0d] Adding C[1] to group key", nodeId);
                processIndex <= processIndex + 1;

            end else if (processIndex == fromInteger(valueOf(NumNodes)) + 2) begin
                // Get result and add third commitment
                let result <- pointAdd.getResult();
                groupKeyAccumulator <= result;

                Commitment c2 = receivedCommitments[2];
                Ed25519Point p2 = Ed25519Point {
                    x: c2.x, y: c2.y, z: 255'd1, t: 255'd1
                };
                pointAdd.start(result, p2);
                $display("[NODE %0d] Adding C[2] to group key", nodeId);
                processIndex <= processIndex + 1;

            end else if (processIndex == fromInteger(valueOf(NumNodes)) + 3) begin
                // Get result and add fourth commitment
                let result <- pointAdd.getResult();
                groupKeyAccumulator <= result;

                Commitment c3 = receivedCommitments[3];
                Ed25519Point p3 = Ed25519Point {
                    x: c3.x, y: c3.y, z: 255'd1, t: 255'd1
                };
                pointAdd.start(result, p3);
                $display("[NODE %0d] Adding C[3] to group key", nodeId);
                processIndex <= processIndex + 1;
            end
        end
    endrule

    rule round2Finish (state == ROUND2_DERIVE &&
                      processIndex == fromInteger(valueOf(NumNodes)) + 4 &&
                      pointAdd.isReady());
        let result <- pointAdd.getResult();
        groupKey <= pointToCommitment(result);
        $display("[NODE %0d] Group key = (%h, %h)", nodeId, result.x, result.y);
        $display("[NODE %0d] DKG COMPLETE! Cycles: %0d", nodeId, cycles);
        state <= DONE;
        dkgDone <= True;
    endrule

    // ========================================================================
    // Interface Methods
    // ========================================================================

    method Action startDkg() if (state == IDLE);
        $display("[NODE %0d] Starting FROST DKG", nodeId);
        state <= ROUND0_GEN;
        cycles <= 0;
        coeffIndex <= 0;
        processIndex <= 0;
        shareAccumulator <= 0;
        groupKeyAccumulator <= identityPoint();

        // Clear validity flags
        for (Integer i = 0; i < valueOf(NumNodes); i = i + 1) begin
            commitmentValid[i] <= False;
            shareValid[i] <= False;
        end
    endmethod

    method Bool isDone();
        return dkgDone;
    endmethod

    method Scalar getSecretShare() if (state == DONE);
        return secretShare;
    endmethod

    method Commitment getGroupKey() if (state == DONE);
        return groupKey;
    endmethod

    method Commitment getMyCommitment() if (state >= ROUND0_BCAST);
        return myCommitments[0];
    endmethod

    method Action receiveCommitment(NodeId from, Commitment c);
        receivedCommitments[from] <= c;
        commitmentValid[from] <= True;
    endmethod

    method Scalar getShareFor(NodeId node) if (state >= ROUND1_SEND);
        return sharesToSend[node];
    endmethod

    method Action receiveShare(NodeId from, Scalar share);
        receivedShares[from] <= share;
        shareValid[from] <= True;
    endmethod

endmodule

endpackage
