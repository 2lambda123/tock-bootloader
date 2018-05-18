# Remove built-in rules and variables
# n.b. no-op for make --version < 4.0
MAKEFLAGS += -r
MAKEFLAGS += -R

MAKEFILE_COMMON_PATH := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

TOOLCHAIN ?= arm-none-eabi

CARGO ?= cargo
# This will hopefully move into Cargo.toml (or Cargo.toml.local) eventually
RUSTFLAGS_FOR_CARGO_LINKING := "-C link-arg=-nostartfiles -C link-arg=-Tlayout.ld"

CC        := $(TOOLCHAIN)-gcc
SIZE      ?= $(TOOLCHAIN)-size
OBJCOPY   ?= $(TOOLCHAIN)-objcopy
OBJDUMP   ?= $(TOOLCHAIN)-objdump
OBJDUMP_FLAGS += --disassemble-all --source --disassembler-options=force-thumb -C --section-headers

# http://stackoverflow.com/questions/10858261/abort-makefile-if-variable-not-set
# Check that given variables are set and all have non-empty values,
# die with an error otherwise.
#
# Params:
#   1. Variable name(s) to test.
#   2. (optional) Error message to print.
check_defined = \
    $(strip $(foreach 1,$1, \
        $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
    $(if $(value $1),, \
      $(error Undefined $1$(if $2, ($2))))


$(call check_defined, PLATFORM)

# If environment variable V is non-empty, be verbose
ifneq ($(V),)
Q=
VERBOSE = --verbose
else
Q=@
VERBOSE =
endif

# Check that gcc version is new enough (> 5.1) - used during linking
CC_VERSION_MAJOR := $(shell $(TOOLCHAIN)-gcc -dumpversion | cut -d '.' -f1)
ifeq (1,$(shell expr $(CC_VERSION_MAJOR) \>= 6))
  # no-op
else
  ifneq (5,$(CC_VERSION_MAJOR))
    $(info CC=$(CC))
    $(info $$(CC) -dumpversion: $(shell $(CC) -dumpversion))
    $(error Your compiler is too old. Need gcc version > 5.1)
  endif
    CC_VERSION_MINOR := $(shell $(CC) -dumpversion | cut -d '.' -f2)
  ifneq (1,$(shell expr $(CC_VERSION_MINOR) \> 1))
    $(info CC=$(CC))
    $(info $$(CC) -dumpversion: $(shell $(CC) -dumpversion))
    $(error Your compiler is too old. Need gcc version > 5.1)
  endif
endif

ifneq ($(shell rustup component list | grep rust-src),rust-src (installed))
  $(shell rustup component add rust-src)
endif
ifneq ($(shell rustup target list | grep "$(TARGET) (installed)"),$(TARGET) (installed))
  $(shell rustup target add $(TARGET))
endif

# Need some dummy value here
export TOCK_KERNEL_VERSION=5

# Dump configuration for verbose builds
ifneq ($(V),)
  $(info )
  $(info **************************************************)
  $(info TOCK KERNEL BUILD SYSTEM -- VERBOSE BUILD)
  $(info **************************************************)
  $(info Config:)
  $(info MAKEFLAGS=$(MAKEFLAGS))
  $(info OBJCOPY=$(OBJCOPY))
  $(info PLATFORM=$(PLATFORM))
  $(info TARGET=$(TARGET))
  $(info TOOLCHAIN=$(TOOLCHAIN))
  $(info )
  $(info $(OBJCOPY) --version = $(shell $(OBJCOPY) --version))
  $(info rustc --version = $(shell rustc --version))
  $(info **************************************************)
  $(info )
endif

.PHONY: all
all:	target/$(TARGET)/release/$(PLATFORM).bin

.PHONY: lst
lst:	target/$(TARGET)/release/$(PLATFORM).lst

target:
	@mkdir -p target

.PHONY: doc
doc: | target
	$(Q)RUSTDOCFLAGS=--document-private-items $(CARGO) doc $(VERBOSE) --release --target=$(TARGET)

target/$(TARGET)/release/$(PLATFORM).elf: target/$(TARGET)/release/$(PLATFORM)
	$(Q)cp target/$(TARGET)/release/$(PLATFORM) target/$(TARGET)/release/$(PLATFORM).elf

target/$(TARGET)/release/$(PLATFORM).lst: target/$(TARGET)/release/$(PLATFORM).elf
	$(Q)$(OBJDUMP) $(OBJDUMP_FLAGS) $< > target/$(TARGET)/release/$(PLATFORM).lst

.PHONY: target/$(TARGET)/release/$(PLATFORM)
target/$(TARGET)/release/$(PLATFORM):
	$(Q)RUSTFLAGS=$(RUSTFLAGS_FOR_CARGO_LINKING) $(CARGO) build --target=$(TARGET) $(VERBOSE) --release
	$(Q)$(SIZE) $@

target/$(TARGET)/release/$(PLATFORM).hex: target/$(TARGET)/release/$(PLATFORM).elf
	$(Q)$(OBJCOPY) -Oihex $^ $@

target/$(TARGET)/release/$(PLATFORM).bin: target/$(TARGET)/release/$(PLATFORM).elf
	$(Q)$(OBJCOPY) -Obinary $^ $@

# `make check` runs the Rust compiler but does not actually output the final
# binary. This makes checking for Rust errors much faster.
.PHONY: check
check:
	$(Q)RUSTFLAGS=$(RUSTFLAGS_FOR_CARGO_LINKING) $(CARGO) check --target=$(TARGET) $(VERBOSE) --release

.PHONY: clean
clean::
	$(Q)$(CARGO) clean $(VERBOSE)
