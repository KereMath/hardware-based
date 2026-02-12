// FROST DKG Common Types and Interfaces
// Bluespec SystemVerilog (BSV)

package FrostTypes;

// ============================================================================
// Type Definitions
// ============================================================================

typedef 252 ScalarBits;
typedef 255 PointBits;
typedef Bit#(ScalarBits) Scalar;
typedef Bit#(PointBits) FieldElement;

// Ed25519 Point (Extended Twisted Edwards Coordinates)
typedef struct {
    FieldElement x;
    FieldElement y;
    FieldElement z;
    FieldElement t;
} Ed25519Point deriving (Bits, Eq);

// FROST Commitment (polynomial coefficient commitment)
typedef struct {
    FieldElement x;
    FieldElement y;
} Commitment deriving (Bits, Eq);

// ZK Schnorr Proof
typedef struct {
    FieldElement r_x;
    FieldElement r_y;
    Scalar z;
} SchnorrProof deriving (Bits, Eq);

// Node configuration
typedef 4 NumNodes;
typedef 2 Threshold;
typedef Bit#(TLog#(NumNodes)) NodeId;

// ============================================================================
// Interfaces
// ============================================================================

// Scalar Multiplication Interface: R = [k]P
interface ScalarMult;
    method Action start(Scalar k, Ed25519Point p);
    method ActionValue#(Ed25519Point) getResult();
    method Bool isReady();
endinterface

// Point Addition Interface: R = P + Q
interface PointAdd;
    method Action start(Ed25519Point p, Ed25519Point q);
    method ActionValue#(Ed25519Point) getResult();
    method Bool isReady();
endinterface

// Polynomial Evaluation Interface: y = f(x) where f(x) = a0 + a1*x + a2*x^2
interface PolyEval;
    method Action start(Scalar x, Scalar a0, Scalar a1, Scalar a2);
    method ActionValue#(Scalar) getResult();
    method Bool isReady();
endinterface

// VSS Verification Interface
interface VssVerify;
    method Action start(
        Scalar share,
        Scalar index,
        Commitment c0,
        Commitment c1,
        Commitment c2
    );
    method ActionValue#(Bool) getResult();
    method Bool isReady();
endinterface

// ZK Schnorr Prove Interface
interface ZkSchnorrProve;
    method Action start(Scalar secret, Commitment commitment, Bit#(256) context);
    method ActionValue#(SchnorrProof) getResult();
    method Bool isReady();
endinterface

// ZK Schnorr Verify Interface
interface ZkSchnorrVerify;
    method Action start(SchnorrProof proof, Commitment commitment, Bit#(256) context);
    method ActionValue#(Bool) getResult();
    method Bool isReady();
endinterface

// FROST Node Interface
interface FrostNode;
    method Action startDkg();
    method Bool isDone();
    method Scalar getSecretShare();
    method Commitment getGroupKey();

    // Communication with other nodes
    method Commitment getMyCommitment();
    method Action receiveCommitment(NodeId from, Commitment c);
    method Scalar getShareFor(NodeId node);
    method Action receiveShare(NodeId from, Scalar share);
endinterface

// ============================================================================
// Utility Functions
// ============================================================================

// Ed25519 base point G
function Ed25519Point basePoint();
    return Ed25519Point {
        x: 255'd15112221891218833716476647996989161020559857364886120180555412087366036343862,
        y: 255'd46316835694926478169428394003475163141307993866256225615783033603165251855960,
        z: 255'd1,
        t: 255'd1
    };
endfunction

// Identity point (point at infinity)
function Ed25519Point identityPoint();
    return Ed25519Point {
        x: 255'd0,
        y: 255'd1,
        z: 255'd1,
        t: 255'd0
    };
endfunction

// Convert point to commitment (drop Z and T coordinates)
function Commitment pointToCommitment(Ed25519Point p);
    return Commitment {
        x: p.x,
        y: p.y
    };
endfunction

endpackage
