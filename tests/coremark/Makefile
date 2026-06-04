# =============================================================================
#  CoreMark for self-built RV32IM 7-stage pipeline CPU
# =============================================================================
#  使用方法：
#    1) 把 CoreMark 源码放进 src/ （见 README）
#    2) make           # 编译 -> build/imem.hex
#    3) 仿真台读 build/imem.hex
#
#  覆盖工具链 prefix：  make RISCV_PREFIX=riscv32-unknown-elf-
# =============================================================================

RISCV_PREFIX ?= riscv-none-elf-
PYTHON       ?= python3

CC      := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
OBJDUMP := $(RISCV_PREFIX)objdump
SIZE    := $(RISCV_PREFIX)size

# ---------------------------------------------------------------------------
SRC_DIR   := src
PORT_DIR  := port
BUILD     := build
SCRIPTS   := scripts

COREMARK_SRCS := $(SRC_DIR)/core_main.c \
                 $(SRC_DIR)/core_list_join.c \
                 $(SRC_DIR)/core_matrix.c \
                 $(SRC_DIR)/core_state.c \
                 $(SRC_DIR)/core_util.c

PORT_SRCS := $(PORT_DIR)/core_portme.c \
             $(PORT_DIR)/syscalls.c

ASM_SRCS  := $(PORT_DIR)/crt0.S

# ---------------------------------------------------------------------------
ARCH      := -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medlow
OPT       := -O2
WARN      := -Wall -Wno-unused-variable -Wno-unused-but-set-variable -Wno-implicit-function-declaration
INC       := -I$(SRC_DIR) -I$(PORT_DIR)
ITERS     ?= 10
DEFS      := -DITERATIONS=$(ITERS) -DPERFORMANCE_RUN=1 -DFLAGS_STR=\"-O2\ -march=rv32im\"

# 选 libc：默认 picolibc（Ubuntu apt 装的最方便）；可覆盖：
#   make LIBC=newlib_nano   # xpack 默认这套
#   make LIBC=newlib        # 普通 newlib，最大兼容
LIBC      ?= picolibc

ifeq ($(LIBC),picolibc)
  LIBC_SPEC := --specs=picolibc.specs
  LIBS      := -lc
else ifeq ($(LIBC),newlib_nano)
  LIBC_SPEC := --specs=nano.specs
  LIBS      := -lc -lgcc -lnosys
else
  LIBC_SPEC :=
  LIBS      := -lc -lgcc -lnosys
endif

CFLAGS    := $(ARCH) $(OPT) $(WARN) $(INC) $(DEFS) \
             -ffunction-sections -fdata-sections \
             -fno-builtin-printf \
             $(LIBC_SPEC)

LDFLAGS   := $(ARCH) -nostartfiles \
             -T $(PORT_DIR)/link.ld \
             -Wl,--gc-sections \
             -Wl,-Map=$(BUILD)/coremark.map \
             $(LIBC_SPEC)

# ---------------------------------------------------------------------------
C_OBJS   := $(patsubst %.c, $(BUILD)/%.o, $(COREMARK_SRCS) $(PORT_SRCS))
ASM_OBJS := $(patsubst %.S, $(BUILD)/%.o, $(ASM_SRCS))
OBJS     := $(ASM_OBJS) $(C_OBJS)

# ---------------------------------------------------------------------------
.PHONY: all clean dump size check_src

all: check_src $(BUILD)/imem.hex $(BUILD)/dmem.hex $(BUILD)/coremark.dis size

check_src:
	@test -f $(SRC_DIR)/core_main.c || { \
	  echo "ERROR: CoreMark source missing at $(SRC_DIR)/."; \
	  echo "Run:  git clone https://github.com/eembc/coremark.git $(SRC_DIR)"; \
	  echo "      (or: copy core_*.c + coremark.h into $(SRC_DIR)/)"; \
	  exit 1; \
	}

$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: %.S
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/coremark.elf: $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) $(LIBS) -o $@

# IROM: 只取 .text（Harvard：CPU 不能从 IROM 读数据，rodata 也得放 DRAM）
$(BUILD)/coremark.text.bin: $(BUILD)/coremark.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@

# DRAM: .rodata + .data（仿真台 $readmemh 到 dram_mem，索引 0 = DRAM_BASE）
$(BUILD)/coremark.data.bin: $(BUILD)/coremark.elf
	$(OBJCOPY) -O binary --only-section=.rodata --only-section=.data $< $@

$(BUILD)/imem.hex: $(BUILD)/coremark.text.bin $(SCRIPTS)/bin2hex.py
	$(PYTHON) $(SCRIPTS)/bin2hex.py $< $@

$(BUILD)/dmem.hex: $(BUILD)/coremark.data.bin $(SCRIPTS)/bin2hex.py
	$(PYTHON) $(SCRIPTS)/bin2hex.py $< $@

$(BUILD)/coremark.dis: $(BUILD)/coremark.elf
	$(OBJDUMP) -d -S $< > $@

dump: $(BUILD)/coremark.dis

size: $(BUILD)/coremark.elf
	@$(SIZE) $<

clean:
	rm -rf $(BUILD)
