//! Decide to enter bootloader based on special RAM location.
//!
//! On the nRF52 the GPREGRET memory location is preserved on a soft reset. This
//! allows the kernel to set this before resetting and resume in the bootloader.

use kernel::utilities::cells::VolatileCell;
use kernel::utilities::StaticRef;

/// Magic value for the GPREGRET register that tells our bootloader to stay in
/// bootloader mode. This value is not the same as the Adafruit nRF52 bootloader
/// because we don't need them to conflict and we want to be able to chain nRF52
/// bootloaders.
///
/// This value is used by the kernel to set the flag so that the bootloader is
/// entered after a soft reset.
const DFU_MAGIC_TOCK_BOOTLOADER1: u8 = 0x90;
/// Second magic value for the GPREGRET register that tells our bootloader to
/// stay in bootloader mode. This value is set by the bootloader after deciding
/// _not_ to stay in the bootloader just in case we want to chain bootloaders.
/// That is, if there are two Tock bootloaders flashed on a chip:
///
/// ```
/// Address
/// 0x0:     Tock Bootloader
/// 0x10000: Tock Bootloader (second)
/// 0x20000: Other code (or nothing)
/// ```
///
/// This is an unusual situation, and is intended to only happen when
/// updating/changing bootloaders. To make it easy to skip through the first but
/// stay in the second, we use this magic value.
const DFU_MAGIC_TOCK_BOOTLOADER2: u8 = 0x91;

/// Magic value for the double reset memory location indicating we should stay
/// in the bootloader. This value (and name) is taken from the Adafruit nRF52
/// bootloader.
const DFU_DBL_RESET_MAGIC: u32 = 0x5A1AD5;

/// Memory location we use as a flag for detecting a double reset.
///
/// I have no idea why we use address 0x20007F7C, but that is what the Adafruit
/// nRF52 bootloader uses, so I copied it.
const DOUBLE_RESET_MEMORY_LOCATION: StaticRef<VolatileCell<u32>> =
    unsafe { StaticRef::new(0x20007F7C as *const VolatileCell<u32>) };

pub struct BootloaderEntryGpRegRet {
    nrf_power: &'static nrf52::power::Power<'static>,
    double_reset: StaticRef<VolatileCell<u32>>,
}

impl BootloaderEntryGpRegRet {
    pub fn new(nrf_power: &'static nrf52::power::Power<'static>) -> BootloaderEntryGpRegRet {
        BootloaderEntryGpRegRet {
            nrf_power,
            double_reset: DOUBLE_RESET_MEMORY_LOCATION,
        }
    }
}

impl bootloader::interfaces::BootloaderEntry for BootloaderEntryGpRegRet {
    fn stay_in_bootloader(&self) -> bool {
        // Check if the retention flag matches the special variable indicating
        // we should stay in the bootloader. This would be set by the kernel
        // before doing a reset to indicate we should reboot into the
        // bootloader. We also allow bootloader chaining
        if self.nrf_power.get_gpregret() >= DFU_MAGIC_TOCK_BOOTLOADER1 {
            // Clear flag so we do not get stuck in the bootloader.
            self.nrf_power.set_gpregret(0);

            return true;
        }

        // Check if this is the second bootloader. If so, we want to stay in the
        // bootloader unconditionally.
        if self.nrf_power.get_gpregret() >= DFU_MAGIC_TOCK_BOOTLOADER2 {
            // Clear flag so we do not get stuck in the bootloader.
            self.nrf_power.set_gpregret(0);

            return true;
        }

        // If the retention flag is not set, then we check for the double reset
        // memory location. If this is set to a magic value, then we got two
        // resets in a short amount of time and we want to go into the
        // bootloader.
        if self.double_reset.get() == DFU_DBL_RESET_MAGIC {
            self.double_reset.set(0);
            return true;
        }

        // If neither magic value is set, then we need to check if we just got
        // the first of a double reset. We do this by setting our flag and
        // entering a busy loop. If the busy loop finishes then we must not have
        // gotten a second reset and we go to the kernel. If the busy loop
        // doesn't finish because we got a reset in the middle, then the
        // bootloader will restart and the check above should trigger.
        self.double_reset.set(DFU_DBL_RESET_MAGIC);
        for _ in 0..2000000 {
            cortexm4::support::nop();
        }
        self.double_reset.set(0);

        // Set so that we will stick in the second bootloader if they are
        // chained.
        self.nrf_power.set_gpregret(DFU_MAGIC_TOCK_BOOTLOADER2);

        // Default to jumping out of the bootloader.
        false
    }
}
