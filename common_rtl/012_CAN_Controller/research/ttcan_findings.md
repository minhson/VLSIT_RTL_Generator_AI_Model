# TTCAN findings for TBD-015 and TBD-016 (search of 2026-11-06)

ISO 11898-4:2004 (paid) was not found in a free form. The sources below were found; the status says how far each can be trusted.

| ID | Statement | Source | Status |
|---|---|---|---|
| T-101 | Level 1 reference message: data byte 0 bit 7 Next_is_Gap, bit 6 reserved, bits 5 to 0 Cycle_Count; the other bytes are free | BME-MIT 2023, course slides `AKH_04_TTCAN_Elmelet.pdf` (https://www.mit.bme.hu/system/files/oktatas/targyak/12128/AKH_04_TTCAN_Elmelet.pdf), slide 15, read from the PDF text | LIKELY (secondary, course material that cites ISO 11898-4) |
| T-102 | Level 2 reference message: 4 bytes of time information (Next_is_Gap, Cycle_Count, NTU_Res, Disc_Bit, Master_Ref_Mark measured in global time) and 4 free bytes | Same slides 16 and 17 (the bit positions are in a figure that is not in the text) | LIKELY for the field list, bit positions not given |
| T-103 | Level 2: byte 1 = NTU_Res (7 bits) and Disc_Bit (bit 0), bytes 2 and 3 = Master_Ref_Mark low and high | Search summary of the 2002 CiA conference paper by Mueller (www2.can-cia.org/fileadmin/resources/documents/proceedings/2002_mueller.pdf); the paper itself could not be fetched (certificate error, 404 on the main host) | UNVERIFIED |
| T-104 | Disc_Bit signals a deliberate discontinuity of the global time; reference messages with it are not used for the clock calibration | Bosch TTCAN manual 1.6 (REF-010) 5.6 and the 2002 Hartwich paper summary | CONFIRMED for the Bosch manual |
| T-105 | S3 (severe error) must be notified, is not recovered automatically, and is handled like a BusOff | AUTOSAR SRS TTCAN R23-11, SRS_TtCan_41008, 41009, 41013 (read from the local copy); they refer to ISO 11898-4:2004 chapter 9 failure handling | CONFIRMED (for AUTOSAR) |
| T-106 | ISO 11898-4 knows the error conditions CAN_Bus_Off and Watch_Trigger_Reached, both leading to S3; without them the station stays in S0 | A patent (US 9514073) that cites the standard, seen only through a search summary | UNVERIFIED |
| T-107 | Tx_Underflow is error level 1, Tx_Overflow is level 2, configuration error, application watchdog and watch trigger are level 3 | Bosch TTCAN manual 1.6 (REF-010) 5.1.2, 5.1.3, 5.7 | CONFIRMED for this IP |

The PDF of the course slides (1.4 MB) was saved by the fetch tool in the session `tool-results` folder, outside git.
