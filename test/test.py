# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer


# Design uses prescale=109, so baud period = 109 * 2 * clk_period
# clk_period = 10 ns  →  baud_period = 2180 ns
BAUD_PERIOD_NS = 2180


async def uart_send_byte(dut, data: int):
    """Send one UART byte (8N1, LSB first) on ui_in[0]."""
    # START bit — drive ui_in[0] low, keep bits [7:1] unchanged
    current = int(dut.ui_in.value)

    dut.ui_in.value = current & 0xFE   # clear bit 0
    await Timer(BAUD_PERIOD_NS, unit="ns")

    # 8 data bits, LSB first
    for i in range(8):
        current = int(dut.ui_in.value)
        bit = (data >> i) & 1
        if bit:
            dut.ui_in.value = current | 0x01
        else:
            dut.ui_in.value = current & 0xFE
        await Timer(BAUD_PERIOD_NS, unit="ns")

    # STOP bit — drive ui_in[0] high
    dut.ui_in.value = int(dut.ui_in.value) | 0x01
    await Timer(BAUD_PERIOD_NS, unit="ns")


async def send_packet(dut, b0, b1, b2, b3):
    """Send a 4-byte packet and wait for the ACK on TX (uo_out[0])."""
    dut._log.info(f"Sending packet: 0x{b0:02X} 0x{b1:02X} 0x{b2:02X} 0x{b3:02X}")
    await uart_send_byte(dut, b0)
    await uart_send_byte(dut, b1)
    await uart_send_byte(dut, b2)
    await uart_send_byte(dut, b3)

    # Wait for ACK start-bit (TX = uo_out[0] goes low)
    for _ in range(50000):
        await RisingEdge(dut.clk)
        if int(dut.uo_out.value) & 0x01 == 0:
            dut._log.info("ACK start bit detected on TX")
            break

    # Let the full ACK byte transmit (11 baud periods)
    await Timer(BAUD_PERIOD_NS * 11, unit="ns")


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    clock = Clock(dut.clk, 10, unit="ns")   # 100 MHz
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value    = 1
    dut.ui_in.value  = 0xFF   # UART idle = high
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 20)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 5)

    dut._log.info("Test project behavior")

    # uio_oe should be all outputs (0xFF) after reset
    assert int(dut.uio_oe.value) == 0xFF, \
        f"uio_oe expected 0xFF, got 0x{int(dut.uio_oe.value):02X}"
    dut._log.info("PASS: uio_oe == 0xFF")

    # Test 1: decimal 1  (0x00_00_00_01)
    await send_packet(dut, 0x00, 0x00, 0x00, 0x01)
    dut._log.info(f"After packet 1 – uo_out=0x{int(dut.uo_out.value):02X}  uio_out=0x{int(dut.uio_out.value):02X}")

    # Test 2: decimal 123456  (0x00_01_E2_40)
    await send_packet(dut, 0x00, 0x01, 0xE2, 0x40)
    dut._log.info(f"After packet 2 – uo_out=0x{int(dut.uo_out.value):02X}  uio_out=0x{int(dut.uio_out.value):02X}")

    # Test 3: decimal 123456789  (0x07_5B_CD_15)
    await send_packet(dut, 0x07, 0x5B, 0xCD, 0x15)
    dut._log.info(f"After packet 3 – uo_out=0x{int(dut.uo_out.value):02X}  uio_out=0x{int(dut.uio_out.value):02X}")

    # Test 4: all zeros
    await send_packet(dut, 0x00, 0x00, 0x00, 0x00)
    dut._log.info(f"After packet 4 – uo_out=0x{int(dut.uo_out.value):02X}  uio_out=0x{int(dut.uio_out.value):02X}")

    # uio_oe must still be 0xFF throughout
    assert int(dut.uio_oe.value) == 0xFF, \
        f"uio_oe changed! Expected 0xFF, got 0x{int(dut.uio_oe.value):02X}"

    dut._log.info("All tests passed")
