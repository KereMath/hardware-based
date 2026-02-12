# FROST DKG Bluespec Makefile

# Bluespec compiler
BSC = bsc

# Compilation flags
BSCFLAGS = -aggressive-conditions -check-assert -show-schedule -show-module-use
SIMFLAGS = -sim -g mkTbFrost -u

# Source files
SOURCES = FrostTypes.bsv Ed25519.bsv FrostProtocol.bsv FrostNode.bsv FrostCoordinator.bsv TbFrost.bsv

# Verilog generation flags
VERILOGFLAGS = -verilog -g mkFrostCoordinator -u

# Build directory
BUILD_DIR = build
VERILOG_DIR = verilog

.PHONY: all sim verilog clean help

all: sim

# Simulate
sim: $(SOURCES)
	@echo "========================================="
	@echo "Compiling Bluespec for simulation..."
	@echo "========================================="
	mkdir -p $(BUILD_DIR)
	$(BSC) $(BSCFLAGS) $(SIMFLAGS) -bdir $(BUILD_DIR) -simdir $(BUILD_DIR) -info-dir $(BUILD_DIR) $(SOURCES)
	@echo ""
	@echo "========================================="
	@echo "Linking simulation executable..."
	@echo "========================================="
	$(BSC) -sim -e mkTbFrost -bdir $(BUILD_DIR) -simdir $(BUILD_DIR) -o $(BUILD_DIR)/frost_sim
	@echo ""
	@echo "========================================="
	@echo "Running FROST DKG simulation..."
	@echo "========================================="
	./$(BUILD_DIR)/frost_sim

# Generate Verilog
verilog: $(SOURCES)
	@echo "========================================="
	@echo "Generating Verilog from Bluespec..."
	@echo "========================================="
	mkdir -p $(VERILOG_DIR)
	$(BSC) $(BSCFLAGS) $(VERILOGFLAGS) -vdir $(VERILOG_DIR) -bdir $(BUILD_DIR) -info-dir $(BUILD_DIR) $(SOURCES)
	@echo ""
	@echo "✓ Verilog files generated in $(VERILOG_DIR)/"
	@echo ""
	@echo "Generated files:"
	@ls -lh $(VERILOG_DIR)/*.v

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR) $(VERILOG_DIR)
	rm -f *.bo *.ba
	@echo "Build artifacts cleaned"

# Help
help:
	@echo "FROST DKG Bluespec Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make sim      - Compile and run simulation (default)"
	@echo "  make verilog  - Generate Verilog from Bluespec"
	@echo "  make clean    - Remove build artifacts"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo "Requirements:"
	@echo "  - Bluespec Compiler (bsc) must be installed"
	@echo "  - Set BSC environment variable if needed"
