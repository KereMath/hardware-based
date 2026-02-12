// Ed25519 Elliptic Curve Operations (Mock for fast simulation)
// Bluespec SystemVerilog (BSV)

package Ed25519;

import FrostTypes::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;

// ============================================================================
// Scalar Multiplication: R = [k]P (Mock for simulation)
// ============================================================================

module mkScalarMult(ScalarMult);
    Reg#(Bool) busy <- mkReg(False);
    Reg#(Ed25519Point) result <- mkRegU;
    Reg#(UInt#(4)) counter <- mkReg(0);

    rule doCompute (busy && counter < 10);
        counter <= counter + 1;
    endrule

    rule finishCompute (busy && counter == 10);
        busy <= False;
        counter <= 0;
    endrule

    method Action start(Scalar k, Ed25519Point p) if (!busy);
        busy <= True;
        counter <= 0;
        // Mock: XOR scalar with point to get deterministic result
        result <= Ed25519Point {
            x: truncate(k) ^ p.x ^ 255'hDEADBEEFCAFEBABE,
            y: {k[251:0], 3'b0} ^ p.y ^ 255'h0123456789ABCDEF,
            z: 255'd1,
            t: (truncate(k) & p.x) | 255'hF0F0F0F0F0F0F0F0
        };
    endmethod

    method ActionValue#(Ed25519Point) getResult() if (!busy);
        return result;
    endmethod

    method Bool isReady();
        return !busy;
    endmethod
endmodule

// ============================================================================
// Point Addition: R = P + Q (Mock for simulation)
// ============================================================================

module mkPointAdd(PointAdd);
    Reg#(Bool) busy <- mkReg(False);
    Reg#(Ed25519Point) result <- mkRegU;
    Reg#(UInt#(3)) counter <- mkReg(0);

    rule doCompute (busy && counter < 5);
        counter <= counter + 1;
    endrule

    rule finishCompute (busy && counter == 5);
        busy <= False;
        counter <= 0;
    endrule

    method Action start(Ed25519Point p, Ed25519Point q) if (!busy);
        busy <= True;
        counter <= 0;
        // Mock: XOR coordinates to get non-zero result
        result <= Ed25519Point {
            x: p.x ^ q.x ^ 255'h12345678,
            y: p.y ^ q.y ^ 255'h87654321,
            z: 255'd1,
            t: (p.x ^ q.y) & 255'hFFFFFFFF
        };
    endmethod

    method ActionValue#(Ed25519Point) getResult() if (!busy);
        return result;
    endmethod

    method Bool isReady();
        return !busy;
    endmethod
endmodule

// ============================================================================
// Point Doubling: R = 2*P (Mock for simulation)
// ============================================================================

interface PointDouble;
    method Action start(Ed25519Point p);
    method ActionValue#(Ed25519Point) getResult();
    method Bool isReady();
endinterface

module mkPointDouble(PointDouble);
    Reg#(Bool) busy <- mkReg(False);
    Reg#(Ed25519Point) result <- mkRegU;
    Reg#(UInt#(3)) counter <- mkReg(0);

    rule doCompute (busy && counter < 5);
        counter <= counter + 1;
    endrule

    rule finishCompute (busy && counter == 5);
        busy <= False;
        counter <= 0;
    endrule

    method Action start(Ed25519Point p) if (!busy);
        busy <= True;
        counter <= 0;
        // Mock: shift and XOR
        result <= Ed25519Point {
            x: {p.x[253:0], 1'b0} ^ 255'hABCDEF01,
            y: {p.y[253:0], 1'b0} ^ 255'h10FEDCBA,
            z: 255'd1,
            t: p.x & p.y
        };
    endmethod

    method ActionValue#(Ed25519Point) getResult() if (!busy);
        return result;
    endmethod

    method Bool isReady();
        return !busy;
    endmethod
endmodule

endpackage
