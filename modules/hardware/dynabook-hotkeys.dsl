/*
 * Dynabook Portege X30W-K hotkey enable SSDT.
 * The EC hotkey queries (_Q84/_Q85 = Fn+F6, _Q86/_Q87 = Fn+F7) route through
 * VALZ.SGSE. Setting the firmware mailbox flag SYSE enables the hotkey pipeline
 * (the codes are pushed into the VALZ INFO() FIFO), and VALF gates the
 * driver-visible event. Windows vendor software sets these; nothing does on
 * Linux. This table defines an inert device with HPST, a manually callable
 * setter for those flags.
 *
 * HPEN (hotkey panel enable) is intentionally NOT set. It makes the firmware
 * additionally emit acpi_video brightness notifies for Fn+F6/F7, which now
 * duplicate the KEY_BRIGHTNESSDOWN/UP events the toshiba_acpi_dnbk driver
 * reports from the same FIFO codes (0x140/0x141) — the two paths together
 * double-step brightness. Leaving HPEN clear routes brightness solely through
 * the driver keymap.
 *
 * _INI is defined for completeness but the kernel does not run _INI on tables
 * loaded at runtime via configfs, so the NixOS module invokes \_SB.DYHK.HPST
 * explicitly through /proc/acpi/call.
 */
DefinitionBlock ("", "SSDT", 2, "DYNBK", "HOTKEY", 0x00000001)
{
    External (\SYSE, FieldUnitObj)
    External (\VALF, FieldUnitObj)

    Scope (\_SB)
    {
        Device (DYHK)
        {
            Name (_HID, "DYHK0001")
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }

            Method (HPST, 0, NotSerialized)
            {
                \SYSE = One
                \VALF = One
                /* Explicit return so the enable script's reply check does not
                 * depend on the value of the last store. */
                Return (One)
            }

            Method (_INI, 0, NotSerialized)
            {
                HPST ()
            }
        }
    }
}
