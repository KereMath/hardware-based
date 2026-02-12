// FROST Protocol Modules (Polynomial Evaluation, VSS, ZK Proofs)
// Bluespec SystemVerilog (BSV)

package FrostProtocol;

import FrostTypes::*;
import Ed25519::*;
import FIFOF::*;
import Vector::*;

// ============================================================================
// Polynomial Evaluation: f(x) = a0 + a1*x + a2*x^2
// Using Horner's method: f(x) = a0 + x(a1 + x*a2)
// ============================================================================

module mkPolyEval(PolyEval);
    Reg#(Bool) busy <- mkReg(False);
    Reg#(Scalar) result <- mkRegU;

    method Action start(Scalar x, Scalar a0, Scalar a1, Scalar a2) if (!busy);
        busy <= True;
        // Horner's method: a0 + x*(a1 + x*a2)
        Scalar temp = a1 + (x * a2);
        result <= a0 + (x * temp);
    endmethod

    method ActionValue#(Scalar) getResult() if (busy);
        busy <= False;
        return result;
    endmethod

    method Bool isReady();
        return !busy;
    endmethod
endmodule

// ============================================================================
// VSS Verification: Check [share] * G == C0 + [index] * C1 + [index^2] * C2
// Simplified mock for simulation
// ============================================================================

module mkVssVerify(VssVerify);
    Reg#(Bool) busy <- mkReg(False);
    Reg#(Bool) valid <- mkReg(False);
    Reg#(UInt#(4)) counter <- mkReg(0);

    rule doVerify (busy && counter < 10);
        counter <= counter + 1;
    endrule

    rule finishVerify (busy && counter == 10);
        busy <= False;
        counter <= 0;
        valid <= True;  // Mock: always valid
    endrule

    method Action start(Scalar share, Scalar index, Commitment c0, Commitment c1, Commitment c2) if (!busy);
        busy <= True;
        counter <= 0;
        // Real implementation would:
        // 1. Compute LHS = [share]G
        // 2. Compute RHS = C0 + [index]C1 + [index^2]C2
        // 3. Check LHS == RHS
        // Mock: just set valid = true
    endmethod

    method ActionValue#(Bool) getResult() if (!busy);
        return valid;
    endmethod

    method Bool isReady();
        return !busy;
    endmethod
endmodule

// ============================================================================
// ZK Schnorr Proof Generation (Mock)
// ============================================================================

module mkZkSchnorrProve(ZkSchnorrProve);
    Reg#(Bool) busy <- mkReg(False);
    Reg#(SchnorrProof) proof <- mkRegU;
    Reg#(UInt#(3)) counter <- mkReg(0);

    rule doProve (busy && counter < 5);
        counter <= counter + 1;
    endrule

    rule finishProve (busy && counter == 5);
        busy <= False;
        counter <= 0;
    endrule

    method Action start(Scalar secret, Commitment commitment, Bit#(256) context) if (!busy);
        busy <= True;
        counter <= 0;
        // Mock proof: XOR secret with commitment
        proof <= SchnorrProof {
            r_x: commitment.x ^ {8{secret[31:0]}},
            r_y: commitment.y ^ {8{secret[31:0]}},
            z: secret
        };
    endmethod

    method ActionValue#(SchnorrProof) getResult() if (!busy);
        return proof;
    endmethod

    method Bool isReady();
        return !busy;
    endmethod
endmodule

// ============================================================================
// ZK Schnorr Proof Verification (Mock)
// ============================================================================

module mkZkSchnorrVerify(ZkSchnorrVerify);
    Reg#(Bool) busy <- mkReg(False);
    Reg#(Bool) valid <- mkReg(False);
    Reg#(UInt#(3)) counter <- mkReg(0);

    rule doVerify (busy && counter < 5);
        counter <= counter + 1;
    endrule

    rule finishVerify (busy && counter == 5);
        busy <= False;
        counter <= 0;
        valid <= True;  // Mock: always valid
    endrule

    method Action start(SchnorrProof proof, Commitment commitment, Bit#(256) context) if (!busy);
        busy <= True;
        counter <= 0;
        // Mock: always accept
    endmethod

    method ActionValue#(Bool) getResult() if (!busy);
        return valid;
    endmethod

    method Bool isReady();
        return !busy;
    endmethod
endmodule

endpackage
