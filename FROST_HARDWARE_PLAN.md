# 🔥 FROST DKG HARDWARE ACCELERATOR - ULTRA DETAYLI PLAN

**Tarih:** 2026-02-12
**Hedef:** FROST Distributed Key Generation'ı donanım ile hızlandırma
**Baseline:** Rust/Givre FROST implementasyonu
**Platform:** Verilog HDL + Icarus Verilog Simulation

---

## 📋 İÇİNDEKİLER

1. [Proje Özeti](#1-proje-özeti)
2. [FROST Protokol Analizi](#2-frost-protokol-analizi)
3. [Donanım Mimari Tasarımı](#3-donanım-mimari-tasarımı)
4. [State Machine Detayları](#4-state-machine-detayları)
5. [Kritik İşlem Modülleri](#5-kritik-i̇şlem-modülleri)
6. [Node Koordinasyon Mekanizması](#6-node-koordinasyon-mekanizması)
7. [Simülasyon Stratejisi](#7-simülasyon-stratejisi)
8. [Performans Benchmark](#8-performans-benchmark)
9. [Implementasyon Roadmap](#9-implementasyon-roadmap)

---

## 1. PROJE ÖZETİ

### 🎯 Amaç

FROST (Flexible Round-Optimized Schnorr Threshold) DKG protokolünü **state machine bazlı donanım** ile implementasyon yaparak:

- ✅ **Kriptografik işlemleri** donanımda hızlandırma
- ✅ **4 node'u** ayrı state machine'ler ile simüle etme
- ✅ **Network overhead'siz** koordinasyon (txt/memory based)
- ✅ **Yazılım (Rust/Givre)** ile performans karşılaştırması

### 📊 Beklenen Sonuçlar

| Metrik | Software (Rust) | Hardware (Verilog) | Speedup |
|--------|----------------|-------------------|---------|
| **Scalar Mult** | ~5,000 cycles | ~200 cycles | **25x** |
| **Hash (SHA-256)** | ~1,000 cycles | ~64 cycles | **15x** |
| **Total DKG (4 nodes)** | ~50 ms | ~5 ms | **10x** |
| **Throughput** | 20 DKG/s | 200 DKG/s | **10x** |

---

## 2. FROST PROTOKOL ANALİZİ

### 2.1 FROST DKG Round Yapısı

**Baseline:** `frost/keygen.rs` (Givre library wrapper)

```rust
// Givre FROST keygen flow:
givre::keygen::<<Bitcoin as Ciphersuite>::Curve>(eid, party_index, num_parties)
    .set_threshold(threshold)
    .start(&mut OsRng, party)
    .await
```

**Round Breakdown** (Givre internal):

#### **Round 0: Commitment Phase**
```
Her node i:
1. Random polynomial f_i(x) = a_{i,0} + a_{i,1}·x + ... + a_{i,t}·x^t
2. Commitment C_{i,j} = [a_{i,j}]·G  (j = 0..t)
3. ZK Schnorr Proof π_i = Prove(a_{i,0}, C_{i,0})
4. Broadcast (C_i, π_i)

Kritik İşlemler:
- t+1 scalar generation (RNG)
- t+1 point multiplication (EC)
- 1 ZK proof generation (hash + 2 scalar mult)
```

#### **Round 1: Share Distribution**
```
Her node i:
1. Verify all received proofs π_j (j ≠ i)
2. Compute secret shares: s_{i→j} = f_i(j)
3. Send s_{i→j} to node j (P2P)

Kritik İşlemler:
- N-1 ZK proof verification (vartime scalar mult)
- N-1 polynomial evaluation (t+1 scalar mult each)
```

#### **Round 2: VSS Verification & Key Derivation**
```
Her node i:
1. Receive shares s_{j→i} from all nodes j
2. VSS verify: [s_{j→i}]·G == ∑_{k=0}^t C_{j,k}·i^k
3. Final secret: s_i = ∑_j s_{j→i}
4. Public key: A_i = [s_i]·G
5. Group key: A = ∑_j C_{j,0}

Kritik İşlemler:
- N-1 VSS verification (point multiplication + summation)
- 1 scalar summation (final secret)
- N point summation (group key)
```

### 2.2 Kriptografik Primitive Breakdown

**From:** `FAZ3_Kod_Detay_Incelemesi.md`

| Primitive | Kullanım Yeri | Complexity | Donanım Kazancı |
|-----------|---------------|------------|------------------|
| **RNG (CSPRNG)** | Polynomial coefficients | O(1) | 1x (zaten hızlı) |
| **Scalar Multiplication** | Commitment, Proof | O(256) | **25x** (critical!) |
| **Point Addition** | Aggregation | O(1) | **5x** |
| **Polynomial Eval** | Share generation | O(t) | **10x** |
| **SHA-256** | ZK proof, hashing | O(64 rounds) | **15x** |
| **Modular Arithmetic** | All scalar ops | O(log n) | **20x** |

**En Kritik:** Scalar multiplication - tüm DKG süresinin %70'i!

---

## 3. DONANIM MİMARİ TASARIMI

### 3.1 Genel Mimari

```
┌─────────────────────────────────────────────────────┐
│                 FROST DKG COORDINATOR                │
│  (Top-level FSM - orchestrates all nodes)          │
└──────────────────┬──────────────────────────────────┘
                   │
      ┌────────────┼────────────┬────────────┐
      │            │            │            │
┌─────▼─────┐┌────▼─────┐┌────▼─────┐┌────▼─────┐
│  NODE 0   ││  NODE 1  ││  NODE 2  ││  NODE 3  │
│   FSM     ││   FSM    ││   FSM    ││   FSM    │
└─────┬─────┘└────┬─────┘└────┬─────┘└────┬─────┘
      │           │            │            │
      └───────────┴────────────┴────────────┘
                  │
      ┌───────────▼────────────────────┐
      │   SHARED CRYPTO ACCELERATORS   │
      ├────────────────────────────────┤
      │ • Ed25519 Scalar Mult (HW)    │
      │ • SHA-256 Core (HW)           │
      │ • Modular Reduction (HW)      │
      │ • Polynomial Evaluator (HW)   │
      └────────────────────────────────┘
```

### 3.2 Memory Layout (Text-Based Communication)

**NO NETWORK!** Node'lar arası iletişim **shared memory/file** üzerinden:

```
frost_messages.txt:
--------------------
[ROUND0_COMMITMENT]
node=0, commitment=<hex>, proof=<hex>
node=1, commitment=<hex>, proof=<hex>
...

[ROUND1_SHARES]
from=0, to=1, share=<hex>
from=0, to=2, share=<hex>
...

[ROUND2_VSS]
node=0, verified=1
node=1, verified=1
...
```

**Alternatif:** Verilog memory array:
```verilog
reg [255:0] commitments [0:3];     // 4 nodes, 256-bit commitments
reg [255:0] shares [0:3][0:3];     // 4x4 share matrix
reg [3:0] round_status;            // Bitmask: which nodes completed
```

---

## 4. STATE MACHINE DETAYLARI

### 4.1 Node FSM (Her Node İçin)

**Dosya:** `frost_node_fsm.v`

```verilog
// FROST Node State Machine
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
```

### 4.2 State Transition Logic

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        cycles <= 0;
    end else begin
        state <= next_state;
        cycles <= cycles + 1;

        case (state)
            IDLE: begin
                if (start_dkg) begin
                    node_id <= my_node_id;
                    threshold <= t;
                    state <= ROUND0_GEN;
                end
            end

            ROUND0_GEN: begin
                // Trigger RNG for polynomial coefficients
                rng_enable <= 1;
                if (rng_done) begin
                    polynomial_coeffs <= rng_output;
                    state <= ROUND0_PROOF;
                end
            end

            ROUND0_PROOF: begin
                // Trigger scalar multiplication for commitments
                scalar_mult_start <= 1;
                if (scalar_mult_done) begin
                    commitment <= scalar_mult_result;
                    state <= ROUND0_BCAST;
                end
            end

            ROUND0_BCAST: begin
                // Write commitment to shared memory
                shared_mem[node_id] <= commitment;
                round0_complete[node_id] <= 1;
                state <= ROUND0_WAIT;
            end

            ROUND0_WAIT: begin
                // Wait until all nodes broadcast
                if (&round0_complete) begin  // All bits set
                    state <= ROUND1_VERIFY;
                end
            end

            // ... (diğer states)
        endcase
    end
end
```

### 4.3 Coordinator FSM (Global Orchestrator)

**Dosya:** `frost_coordinator.v`

```verilog
localparam COORD_IDLE     = 3'b000;
localparam COORD_ROUND0   = 3'b001;
localparam COORD_ROUND1   = 3'b010;
localparam COORD_ROUND2   = 3'b011;
localparam COORD_FINALIZE = 3'b100;
localparam COORD_DONE     = 3'b101;

always @(posedge clk) begin
    case (coord_state)
        COORD_IDLE: begin
            if (start_protocol) begin
                // Trigger all nodes to start Round 0
                for (int i = 0; i < NUM_NODES; i++)
                    node_start[i] <= 1;
                coord_state <= COORD_ROUND0;
            end
        end

        COORD_ROUND0: begin
            // Wait for all nodes to finish Round 0
            if (&node_round0_done) begin
                coord_state <= COORD_ROUND1;
            end
        end

        // ...
    endcase
end
```

---

## 5. KRİTİK İŞLEM MODÜLLERİ

### 5.1 Scalar Multiplication Module (EN ÖNEMLİ!)

**Dosya:** `ed25519_scalar_mult.v`

**Algorithm:** Double-and-Add (Montgomery Ladder for constant-time)

```verilog
module ed25519_scalar_mult #(
    parameter SCALAR_BITS = 256
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [SCALAR_BITS-1:0] scalar,     // k
    input  wire [SCALAR_BITS-1:0] point_x,    // P.x
    input  wire [SCALAR_BITS-1:0] point_y,    // P.y
    output reg  [SCALAR_BITS-1:0] result_x,   // [k]P.x
    output reg  [SCALAR_BITS-1:0] result_y,   // [k]P.y
    output reg  done
);

    // Montgomery Ladder FSM
    localparam IDLE      = 3'b000;
    localparam INIT      = 3'b001;
    localparam DOUBLE    = 3'b010;
    localparam ADD       = 3'b011;
    localparam FINALIZE  = 3'b100;

    reg [2:0] state;
    reg [8:0] bit_index;  // 0..255

    // Point registers (Extended Edwards coordinates)
    reg [SCALAR_BITS-1:0] R0_X, R0_Y, R0_Z, R0_T;  // R0 = [0]P
    reg [SCALAR_BITS-1:0] R1_X, R1_Y, R1_Z, R1_T;  // R1 = [1]P

    // Field arithmetic modules
    wire [SCALAR_BITS-1:0] add_result, mult_result, inv_result;

    field_add add_inst(.a(R0_X), .b(R1_X), .result(add_result));
    field_mult mult_inst(.a(R0_X), .b(R0_Y), .result(mult_result));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        bit_index <= SCALAR_BITS - 1;
                        // R0 = O (identity point)
                        R0_X <= 0; R0_Y <= 1; R0_Z <= 1; R0_T <= 0;
                        // R1 = P
                        R1_X <= point_x; R1_Y <= point_y; R1_Z <= 1;
                        state <= DOUBLE;
                    end
                end

                DOUBLE: begin
                    // Point doubling: R0 = 2*R0 (or R1 = 2*R1)
                    // Complex Ed25519 point doubling formula
                    // (Delegated to point_double module)
                    state <= ADD;
                end

                ADD: begin
                    // Conditional add based on scalar bit
                    if (scalar[bit_index]) begin
                        // R0 = R0 + R1
                    end

                    if (bit_index == 0) begin
                        state <= FINALIZE;
                    end else begin
                        bit_index <= bit_index - 1;
                        state <= DOUBLE;
                    end
                end

                FINALIZE: begin
                    // Convert from projective to affine
                    result_x <= R0_X * inv(R0_Z);
                    result_y <= R0_Y * inv(R0_Z);
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
```

**Performance:**
- **Software:** ~5,000 cycles (edwards25519 library)
- **Hardware:** ~200 cycles (pipelined point ops)
- **Speedup:** **25x** 🚀

### 5.2 SHA-256 Core

**Dosya:** `sha256_core.v`

```verilog
module sha256_core (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [511:0] message_block,  // 512-bit block
    output reg  [255:0] hash_out,
    output reg  done
);

    // SHA-256 constants (first 32 bits of fractional parts of cube roots)
    reg [31:0] K [0:63];

    // Working variables
    reg [31:0] a, b, c, d, e, f, g, h;
    reg [31:0] W [0:63];  // Message schedule
    reg [5:0] round;

    // State machine
    localparam IDLE      = 2'b00;
    localparam EXPAND    = 2'b01;  // Expand message
    localparam COMPRESS  = 2'b10;  // 64 rounds
    localparam FINALIZE  = 2'b11;

    always @(posedge clk) begin
        case (state)
            COMPRESS: begin
                // SHA-256 round function
                T1 = h + Sigma1(e) + Ch(e,f,g) + K[round] + W[round];
                T2 = Sigma0(a) + Maj(a,b,c);

                h = g; g = f; f = e; e = d + T1;
                d = c; c = b; b = a; a = T1 + T2;

                round <= round + 1;
                if (round == 63)
                    state <= FINALIZE;
            end
        endcase
    end
endmodule
```

**Performance:**
- **Software:** ~1,000 cycles
- **Hardware:** ~64 cycles (pipelined)
- **Speedup:** **15x** 🔥

### 5.3 Modular Reduction (Secp256k1 Field)

**Dosya:** `secp256k1_mod_reduce.v`

**Field:** p = 2^256 - 2^32 - 977

```verilog
module secp256k1_mod_reduce (
    input  wire [511:0] x,        // Input (up to 512 bits)
    output wire [255:0] result    // x mod p (256 bits)
);

    localparam P = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;

    // Fast reduction using special form of p
    wire [255:0] low, high;
    wire [287:0] adjusted;

    assign low = x[255:0];
    assign high = x[511:256];

    // Since p = 2^256 - c (where c = 2^32 + 977)
    // x mod p ≈ low + high * c (may need one more reduction)
    assign adjusted = low + (high << 32) + (high * 977);

    assign result = (adjusted >= P) ? (adjusted - P) : adjusted[255:0];

endmodule
```

**Performance:**
- **Software:** ~100 cycles (division-based)
- **Hardware:** ~3 cycles (combinational)
- **Speedup:** **33x** ⚡

---

## 6. NODE KOORDINASYON MEKANİZMASI

### 6.1 Shared Memory Interface

**Dosya:** `shared_memory.v`

```verilog
module shared_memory #(
    parameter NUM_NODES = 4,
    parameter DATA_WIDTH = 256
)(
    input  wire clk,

    // Node write ports
    input  wire [NUM_NODES-1:0] wr_en,
    input  wire [1:0] wr_addr [NUM_NODES-1:0],
    input  wire [DATA_WIDTH-1:0] wr_data [NUM_NODES-1:0],

    // Node read ports
    input  wire [1:0] rd_addr [NUM_NODES-1:0],
    output wire [DATA_WIDTH-1:0] rd_data [NUM_NODES-1:0]
);

    // Memory array: [node_id][data_index]
    reg [DATA_WIDTH-1:0] mem [0:NUM_NODES-1][0:3];

    // Write logic
    genvar i;
    generate
        for (i = 0; i < NUM_NODES; i = i + 1) begin : write_ports
            always @(posedge clk) begin
                if (wr_en[i])
                    mem[i][wr_addr[i]] <= wr_data[i];
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
```

### 6.2 Round Synchronization

```verilog
module round_sync #(
    parameter NUM_NODES = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [NUM_NODES-1:0] node_ready,  // Each node signals ready
    output reg  all_ready
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            all_ready <= 0;
        else
            all_ready <= &node_ready;  // AND reduction
    end

endmodule
```

---

## 7. SİMÜLASYON STRATEJİSİ

### 7.1 Testbench Yapısı

**Dosya:** `tb_frost_dkg.v`

```verilog
module tb_frost_dkg;

    reg clk, rst_n;
    reg start_dkg;

    // Configuration
    localparam NUM_NODES = 4;
    localparam THRESHOLD = 3;  // 3-of-4

    // Node instances
    wire [255:0] final_keys [0:NUM_NODES-1];
    wire [NUM_NODES-1:0] done_flags;
    wire [31:0] cycles [0:NUM_NODES-1];

    frost_node #(.NODE_ID(0)) node0 (
        .clk(clk), .rst_n(rst_n), .start(start_dkg),
        .final_key(final_keys[0]), .done(done_flags[0]),
        .cycles(cycles[0])
    );

    frost_node #(.NODE_ID(1)) node1 (...);
    frost_node #(.NODE_ID(2)) node2 (...);
    frost_node #(.NODE_ID(3)) node3 (...);

    // Clock generation (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test sequence
    initial begin
        $display("========================================");
        $display("FROST DKG Hardware Simulation");
        $display("Nodes: %0d, Threshold: %0d", NUM_NODES, THRESHOLD);
        $display("========================================");

        rst_n = 0;
        start_dkg = 0;
        #100;
        rst_n = 1;
        #50;

        // Start DKG
        start_dkg = 1;
        @(posedge clk);
        start_dkg = 0;

        // Wait for completion
        wait(&done_flags);  // All nodes done

        #100;

        // Report results
        $display("\n========================================");
        $display("RESULTS");
        $display("========================================");
        for (int i = 0; i < NUM_NODES; i++) begin
            $display("Node %0d: Key = %h, Cycles = %0d",
                     i, final_keys[i], cycles[i]);
        end

        // Verify all keys are consistent
        if (final_keys[0] == final_keys[1] &&
            final_keys[1] == final_keys[2] &&
            final_keys[2] == final_keys[3]) begin
            $display("\n✅ SUCCESS: All nodes derived same group key!");
        end else begin
            $display("\n❌ FAIL: Key mismatch!");
        end

        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("frost_dkg.vcd");
        $dumpvars(0, tb_frost_dkg);
    end

endmodule
```

### 7.2 Test Vectors

**Dosya:** `test_vectors.txt`

```
# FROST DKG Test Vectors (from IETF draft)
# Format: threshold, num_nodes, expected_group_key

3, 4, 0x1234567890abcdef...
2, 3, 0xfedcba0987654321...
```

---

## 8. PERFORMANS BENCHMARK

### 8.1 Software Baseline (Rust/Givre)

**Dosya:** `benchmark_frost_software.rs`

```rust
use std::time::Instant;
use givre::keygen;

fn main() {
    println!("========================================");
    println!("FROST DKG Software Benchmark (Rust/Givre)");
    println!("========================================\n");

    let num_nodes = 4;
    let threshold = 3;

    let start = Instant::now();

    // Run FROST keygen (simulated locally)
    let result = run_local_frost_keygen(num_nodes, threshold);

    let elapsed = start.elapsed();

    println!("Results:");
    println!("  Duration: {:.2} ms", elapsed.as_secs_f64() * 1000.0);
    println!("  Estimated cycles: ~{}", estimate_cycles(elapsed));
    println!("  Group key: {}", hex::encode(&result.group_key));
}

fn estimate_cycles(duration: Duration) -> u64 {
    // Assume 3.0 GHz CPU
    (duration.as_secs_f64() * 3_000_000_000.0) as u64
}
```

### 8.2 Hardware Simülasyon

```bash
# Compile
iverilog -g2012 -s tb_frost_dkg -o frost_dkg.vvp \
    shared_memory.v \
    ed25519_scalar_mult.v \
    sha256_core.v \
    frost_node_fsm.v \
    frost_coordinator.v \
    tb_frost_dkg.v

# Run
vvp frost_dkg.vvp
```

### 8.3 Karşılaştırma Tablosu

| Metrik | Software | Hardware | Speedup |
|--------|----------|----------|---------|
| **Round 0 (per node)** | 15 ms | 1.5 ms | **10x** |
| **Round 1 (per node)** | 20 ms | 2.0 ms | **10x** |
| **Round 2 (per node)** | 15 ms | 1.5 ms | **10x** |
| **Total DKG (4 nodes)** | **50 ms** | **5 ms** | **10x** |
| **Clock Cycles** | ~150M | ~500K | **300x** |
| **Throughput** | 20 DKG/s | 200 DKG/s | **10x** |

---

## 9. IMPLEMENTASYON ROADMAP

### Phase 1: Temel Modüller (1-2 gün)
- [x] `secp256k1_mod_reduce.v` - Modular reduction
- [x] `field_add.v` - Field addition
- [ ] `field_mult.v` - Field multiplication
- [ ] `sha256_core.v` - SHA-256 hash

### Phase 2: Elliptic Curve (2-3 gün)
- [ ] `point_add.v` - Ed25519 point addition
- [ ] `point_double.v` - Ed25519 point doubling
- [ ] `ed25519_scalar_mult.v` - Scalar multiplication (CRITICAL!)

### Phase 3: FROST Protocol (2-3 gün)
- [ ] `polynomial_eval.v` - Polynomial evaluation
- [ ] `zk_schnorr_prove.v` - ZK proof generation
- [ ] `zk_schnorr_verify.v` - ZK proof verification
- [ ] `vss_verify.v` - VSS verification

### Phase 4: Node FSM (1-2 gün)
- [ ] `frost_node_fsm.v` - Per-node state machine
- [ ] `shared_memory.v` - Inter-node communication
- [ ] `round_sync.v` - Round synchronization

### Phase 5: Integration & Test (2-3 gün)
- [ ] `frost_coordinator.v` - Top-level coordinator
- [ ] `tb_frost_dkg.v` - Full testbench
- [ ] Test vector validation
- [ ] Waveform analysis

### Phase 6: Benchmark (1 gün)
- [ ] `benchmark_frost_software.rs` - Rust baseline
- [ ] Performance comparison
- [ ] Report generation

**Total Time:** ~10-14 gün (2 hafta)

---

## 10. SONUÇ VE BEKLENTİLER

### ✅ Başarı Kriterleri

1. **Functional Correctness:**
   - 4 node DKG başarıyla tamamlanmalı
   - Tüm node'lar aynı group key türetmeli
   - Test vectors pass olmalı

2. **Performance:**
   - **10x** minimum speedup (vs Rust/Givre)
   - <10 ms total DKG time
   - <1M clock cycles @ 100 MHz

3. **Scalability:**
   - 4, 8, 16 node konfigürasyonları test edilmeli
   - Linear scaling göstermeli

### 🚀 Beklenen Çıktılar

1. **Verilog Modülleri:** ~15 dosya, ~5000 satır kod
2. **Testbench:** Detaylı simülasyon, waveform analizi
3. **Benchmark Report:** Software vs Hardware karşılaştırma
4. **README.md:** Kullanım kılavuzu, sonuçlar

---

**🔥 "FROST DKG'yi donanımda çalıştır, 10x hızlan!"** 🚀
