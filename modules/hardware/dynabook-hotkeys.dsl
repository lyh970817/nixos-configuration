/*
 * Dynabook Portege X30W-K hotkey enable SSDT.
 * The EC hotkey queries (_Q84/_Q85 = Fn+F6, _Q86/_Q87 = Fn+F7) route through
 * VALZ.SGSE, which only emits ACPI video brightness notifies when the
 * firmware mailbox flags SYSE (pipeline enable) and HPEN (hotkey panel
 * enable) are set. Windows vendor software sets these; nothing does on
 * Linux. This table defines an inert device with HPST, a manually callable
 * setter for those flags. _INI is defined for completeness but the kernel
 * does not run _INI on tables loaded at runtime via configfs, so the NixOS
 * module below invokes \_SB.DYHK.HPST explicitly through /proc/acpi/call.
 */
DefinitionBlock ("", "SSDT", 2, "DYNBK", "HOTKEY", 0x00000001)
{
    External (\SYSE, FieldUnitObj)
    External (\VALF, FieldUnitObj)
    External (\HPEN, FieldUnitObj)

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
                \HPEN = One
            }

            Method (_INI, 0, NotSerialized)
            {
                HPST ()
            }
        }
    }
}
