# `gq_gmc` API Reference

Python library for communicating with GQ GMC Geiger Counters over USB serial.  
Protocol: [GQ-RFC1201](http://www.gqelectronicsllc.com/download/GQ-RFC1201.txt).  
Tested on: GQ GMC-500. Supported models: GMC-280, GMC-300, GMC-320, GMC-500.

---

## Table of Contents

- [Module-level State](#module-level-state)
- [Constants](#constants)
  - [Defaults](#defaults)
  - [Flash and Configuration Sizes](#flash-and-configuration-sizes)
  - [Configuration Register Addresses](#configuration-register-addresses)
- [Device Connection](#device-connection)
  - [`open_device()`](#open_device)
  - [`set_verbose_level()`](#set_verbose_level)
- [Device Information](#device-information)
  - [`get_device_type()`](#get_device_type)
  - [`get_serial_number()`](#get_serial_number)
- [Measurements](#measurements)
  - [`get_cpm()`](#get_cpm)
  - [`get_voltage()`](#get_voltage)
  - [`get_temperature()`](#get_temperature)
  - [`get_gyro()`](#get_gyro)
  - [`set_heartbeat()`](#set_heartbeat)
- [History Data](#history-data)
  - [`get_data()`](#get_data)
  - [`parse_data_file()`](#parse_data_file)
- [Device Configuration](#device-configuration)
  - [`get_config()`](#get_config)
  - [`list_config()`](#list_config)
  - [`write_config()`](#write_config)
  - [`get_unit_conversion_from_device()`](#get_unit_conversion_from_device)
- [Date and Time](#date-and-time)
  - [`get_date_and_time()`](#get_date_and_time)
  - [`set_date_and_time()`](#set_date_and_time)
- [Device Control](#device-control)
  - [`set_power()`](#set_power)
  - [`send_key()`](#send_key)
  - [`factory_reset()`](#factory_reset)
  - [`reboot()`](#reboot)
  - [`firmware_update()`](#firmware_update)
- [Unit Conversion](#unit-conversion)
  - [`convert_cpm_to_usievert()`](#convert_cpm_to_usievert)
- [Internal Helpers](#internal-helpers)
  - [`clear_port()`](#clear_port)
  - [`command_returned_ok()`](#command_returned_ok)
  - [`check_device_type()`](#check_device_type)
  - [`print_data()`](#print_data)
  - [`dump_data()`](#dump_data)
  - [`exit_gracefully()`](#exit_gracefully)

---

## Module-level State

The module uses a set of global variables to track connection and device state. These are initialised at import time and mutated by `open_device()` and related calls.

| Variable | Type | Description |
|---|---|---|
| `m_device` | `serial.Serial \| None` | Active serial connection. `None` until `open_device()` succeeds. |
| `m_device_type` | `str \| None` | Full version string returned by the device (e.g. `"GMC-500Re 1.03"`). |
| `m_device_name` | `str \| None` | Seven-character model prefix (e.g. `"GMC-500"`). Used to look up flash/config sizes. |
| `m_config` | `dict \| None` | Parsed configuration values. Populated by `get_config()` and cached thereafter. |
| `m_config_data` | `ctypes.Array \| None` | Raw configuration buffer from the device. Populated by `get_config()`. |
| `m_verbose` | `int` | Verbosity level. `0` = silent, `1` = minimal, `2` = full (default). |
| `m_terminate` | `bool` | Set to `True` by `exit_gracefully()` to stop the heartbeat loop. |

---

## Constants

### Defaults

| Constant | Value | Description |
|---|---|---|
| `DEFAULT_CONFIG` | `'~/.gq-gmc-control.conf'` | Path to the user configuration file. |
| `DEFAULT_BIN_FILE` | `'gq-gmc-log.bin'` | Default output filename for raw flash dumps. |
| `DEFAULT_CSV_FILE` | `'gq-gmc-log.csv'` | Default output filename for parsed CSV data. |
| `DEFAULT_PORT` | `'/dev/gq-gmc'` (Linux/macOS) / `'COM99'` (Windows) | Default serial port. |
| `DEFAULT_BAUD_RATE` | `115200` | Serial baud rate. |
| `DEFAULT_CPM_TO_SIEVERT` | `'1000,6.50'` | Fallback CPM→uSv/h conversion factor string. |
| `DEFAULT_OUTPUT_IN_CPM` | `False` | Output in CPM/CPS by default. |
| `DEFAULT_NO_PARSE` | `False` | Parse downloaded binary data by default. |
| `DEFAULT_SKIP_CHECK` | `False` | Run device-type check on connect by default. |
| `DEFAULT_UNIT_CONVERSION_FROM_DEVICE` | `False` | Use built-in conversion factor by default. |
| `DEFAULT_DEVICE_TYPE` | `None` | Auto-detect device type by default. |
| `DEFAULT_FLASH_SIZE` | `0x00100000` (1 MiB) | Fallback flash size when device type is unknown. |
| `DEFAULT_CONFIGURATION_SIZE` | `0x100` (256 bytes) | Fallback configuration buffer size. |
| `DEFAULT_VERBOSE_LEVEL` | `2` | Default verbosity (full output). |

### Flash and Configuration Sizes

Per-model lookup tables used by `get_data()` and `get_config()` / `write_config()`.

```python
FLASH_SIZE = {
    'GMC-280': 0x00010000,   # 64 KiB
    'GMC-300': 0x00010000,   # 64 KiB
    'GMC-320': 0x00100000,   # 1 MiB
    'GMC-500': 0x00100000,   # 1 MiB
}

CONFIGURATION_BUFFER_SIZE = {
    'GMC-280': 0x100,   # 256 bytes
    'GMC-300': 0x100,
    'GMC-320': 0x100,
    'GMC-500': 0x200,   # 512 bytes
}
```

### Configuration Register Addresses

Byte offsets within the configuration buffer for the GMC-500+. These are used when reading and writing calibration and Wi-Fi parameters.

| Constant | Address | Description |
|---|---|---|
| `ADDRESS_CALIBRATE1_CPM` | `0x09` | Calibration point 1 — CPM value (2 bytes, big-endian) |
| `ADDRESS_CALIBRATE1_SV` | `0x0b` | Calibration point 1 — Sievert value (4 bytes, big-endian float) |
| `ADDRESS_CALIBRATE2_CPM` | `0x0f` | Calibration point 2 — CPM value |
| `ADDRESS_CALIBRATE2_SV` | `0x11` | Calibration point 2 — Sievert value |
| `ADDRESS_CALIBRATE3_CPM` | `0x15` | Calibration point 3 — CPM value |
| `ADDRESS_CALIBRATE3_SV` | `0x17` | Calibration point 3 — Sievert value |
| `ADDRESS_WIFI_ON_OFF` | `0x00` | Wi-Fi enabled flag (`0xff` = on) |
| `ADDRESS_WIFI_SSID` | `0x45` | Wi-Fi SSID (16 bytes) |
| `ADDRESS_WIFI_PASSWORD` | `0x85` | Wi-Fi password (16 bytes) |
| `ADDRESS_SERVER_WEBSITE` | `0xc5` | Server website string (32 bytes) |
| `ADDRESS_USER_ID` | `0x106` | User ID string (5 bytes) |
| `ADDRESS_COUNTER_ID` | `0x126` | Counter ID string (16 bytes) |

> **Note:** The source file contains two sets of address constants. The second block (GMC-500+ values shown above) silently overwrites the first and is the active set.

---

## Device Connection

### `open_device()`

```python
def open_device(
    port: str | None = None,
    baud_rate: int = 115200,
    skip_check: bool = False,
    device_type: str | None = None,
    allow_fail: bool = False,
) -> int
```

Opens the serial port and initialises the module state. Must be called before any device command.

**Parameters**

| Name | Default | Description |
|---|---|---|
| `port` | `DEFAULT_PORT` | Serial port path (e.g. `'/dev/ttyUSB0'`, `'COM3'`). |
| `baud_rate` | `115200` | Baud rate for the serial connection. |
| `skip_check` | `False` | If `True`, skip the `<GETVER>>` device-type check after connecting. |
| `device_type` | `None` | Override auto-detected model name (`'GMC-280'`, `'GMC-300'`, `'GMC-320'`, or `'GMC-500'`). Applied after `check_device_type()` if `skip_check` is `False`. |
| `allow_fail` | `False` | If `True`, suppress the "No device found" error message on connection failure. |

**Returns** `0` on success, `-1` if the port cannot be opened or the device is unsupported.

**Side effects** Sets `m_device`, `m_device_type`, and `m_device_name`. Calls `clear_port()` after opening.

---

### `set_verbose_level()`

```python
def set_verbose_level(verbose: int) -> None
```

Sets the module verbosity level, which controls how much is printed to stdout.

| Value | Behaviour |
|---|---|
| `0` | Silent — no status messages. |
| `1` | Minimal — progress messages only. |
| `2` | Full — all status and debug messages (default). |

---

## Device Information

### `get_device_type()`

```python
def get_device_type() -> str
```

Sends `<GETVER>>` and reads the 14-byte version string from the device.

**Returns** A string such as `"GMC-500Re 1.03"`, or `''` on error.

---

### `get_serial_number()`

```python
def get_serial_number() -> str
```

Sends `<GETSERIAL>>` and reads 7 bytes, formatted as a 14-character uppercase hex string.

**Returns** e.g. `"0102030405060A"`, or `''` if fewer than 7 bytes are received.

---

## Measurements

### `get_cpm()`

```python
def get_cpm(cpm_to_usievert: tuple[int, float] | None = None) -> str
```

Sends `<GETCPM>>` and reads a 4-byte count value.

> **Known bug:** The value is currently unpacked as `struct.unpack("<i", cpm)` (little-endian signed). The correct encoding per GQ-RFC1201 is big-endian unsigned. The code emits a `WARNING: Clearly wrong!` message to stdout acknowledging this.

**Parameters**

| Name | Description |
|---|---|
| `cpm_to_usievert` | Optional `(cpm_reference, usievert_value)` conversion tuple. If provided, the result is expressed in uSv/h. |

**Returns** A formatted string: `"1234 CPM"` or `"0.0082 uSv/h"`.

---

### `get_voltage()`

```python
def get_voltage() -> str
```

Sends `<GETVOLT>>` and reads 3 bytes interpreted as `value / 10.0` volts.

**Returns** e.g. `"4.2 V"`, or `''` on error.

---

### `get_temperature()`

```python
def get_temperature() -> bytes
```

Sends `<GETTEMP>>` and reads 4 bytes: integer part, decimal part, sign byte, and a dummy byte.

**Returns** A UTF-8 encoded string such as `"23.5 °C"`, or `''` on error.

---

### `get_gyro()`

```python
def get_gyro() -> str
```

Sends `<GETGYRO>>` and reads 7 bytes: three signed 16-bit big-endian values (x, y, z) plus a dummy byte.

**Returns** e.g. `"x:12, y:-4, z:7"`, or `''` on error.

---

### `set_heartbeat()`

```python
def set_heartbeat(enable: bool, cpm_to_usievert: tuple[int, float] | None = None) -> int | None
```

Enables or disables the device heartbeat, which streams one CPS reading per second.

**Parameters**

| Name | Description |
|---|---|
| `enable` | `True` to start the heartbeat loop; `False` to send `<HEARTBEAT0>>` and drain the buffer. |
| `cpm_to_usievert` | Optional conversion tuple. When provided, each reading is printed in uSv/h instead of CPS. |

**Behaviour when `enable=True`**

Sends `<HEARTBEAT1>>`, then enters a blocking loop reading 2-byte big-endian unsigned values (mask `0x3fff`). Installs `SIGINT`/`SIGTERM` handlers that set `m_terminate = True` to exit the loop gracefully. Always sends `<HEARTBEAT0>>` in a `finally` block before returning.

**Returns** `-1` if no device is connected.

---

## History Data

### `get_data()`

```python
def get_data(
    address: int = 0x000000,
    length: int | None = None,
    out_file: str = DEFAULT_BIN_FILE,
) -> int | None
```

Downloads flash memory from the device in 4096-byte pages using `<SPIR...>>` and writes the raw bytes to a file.

**Parameters**

| Name | Default | Description |
|---|---|---|
| `address` | `0x000000` | Start address in flash memory. |
| `length` | `FLASH_SIZE[m_device_name]` | Number of bytes to read. Defaults to the full flash size for the detected model. |
| `out_file` | `'gq-gmc-log.bin'` | Path to the output binary file. |

**Returns** `-1` if no device is connected, otherwise `None`.

---

### `parse_data_file()`

```python
def parse_data_file(
    in_file: str = DEFAULT_BIN_FILE,
    out_file: str = DEFAULT_CSV_FILE,
    cpm_to_usievert: tuple[int, float] | None = None,
) -> None
```

Parses a binary flash dump into a CSV file. Can be called without a connected device.

**Parameters**

| Name | Default | Description |
|---|---|---|
| `in_file` | `'gq-gmc-log.bin'` | Path to the binary file produced by `get_data()`. |
| `out_file` | `'gq-gmc-log.csv'` | Path for the resulting CSV file. |
| `cpm_to_usievert` | `None` | Optional conversion tuple. When provided, count values are written in uSv/h. |

**Binary format**

The flash stream uses `0x55 0xaa` as a two-byte command prefix:

| Sequence | Meaning |
|---|---|
| `55 aa 00` + 9 bytes | Set count type and timestamp. Bytes 0–5: `yy mm dd HH MM SS`; byte 8: save mode (see below). |
| `55 aa 01` + 2 bytes | Two-byte count value. |
| `55 aa 02` + 3 bytes | Three-byte count value. |
| `55 aa 03` + 4 bytes | Four-byte count value. |
| `55 aa 04` + 1 length byte + N bytes | User note. |
| Single byte `< 0x55` | One-byte count value in the current data type. |
| `0xff` × 100 | End-of-data sentinel. |

**Save modes** (byte 8 of the `00` command):

| Value | Data type | Interval |
|---|---|---|
| `0` | — | Off |
| `1` | CPS | Every second |
| `2` | CPM | Every minute |
| `3` | CPM | Every hour |
| `4` | CPS | Every second (threshold) |
| `5` | CPM | Every minute (threshold) |

**CSV output columns:** `value,unit,timestamp,mode` for timestamp rows; `value,unit` for data rows.

---

## Device Configuration

### `get_config()`

```python
def get_config() -> int | None
```

Sends `<GETCFG>>` and reads the full configuration buffer. Parses calibration, Wi-Fi, and server fields into `m_config` and stores the raw buffer in `m_config_data`.

**Returns** `-1` on failure, otherwise `None`. Results are cached; subsequent calls to `list_config()`, `write_config()`, and `get_unit_conversion_from_device()` will use the cached values unless `m_config_data` is `None`.

**Populated `m_config` keys:**

| Key | Type | Description |
|---|---|---|
| `cal1_cpm` | `int` | Calibration point 1 — CPM reference value |
| `cal1_sv` | `float` | Calibration point 1 — Sievert value |
| `cal2_cpm` | `int` | Calibration point 2 — CPM reference value |
| `cal2_sv` | `float` | Calibration point 2 — Sievert value |
| `cal3_cpm` | `int` | Calibration point 3 — CPM reference value |
| `cal3_sv` | `float` | Calibration point 3 — Sievert value |
| `server_website` | `str` | Remote server hostname (32 bytes) |
| `server_url` | `str` | Remote server URL path (32 bytes) |
| `user_id` | `str` | User ID (5 bytes) |
| `counter_id` | `str` | Counter ID (16 bytes) |
| `wifi_active` | `bool` | `True` if byte at `ADDRESS_WIFI_ON_OFF` is `0xff` |
| `wifi_ssid` | `str` | Wi-Fi SSID (16 bytes) |
| `wifi_password` | `str` | Wi-Fi password (16 bytes) |

---

### `list_config()`

```python
def list_config() -> None
```

Prints all parsed configuration values from `m_config` to stdout. Calls `get_config()` first if the cache is empty.

---

### `write_config()`

```python
def write_config(parameters: list[str]) -> None
```

Updates one or more calibration values in the device configuration. The full configuration buffer is read, modified in memory, erased on device (`<ECFG>>`), rewritten byte-by-byte (`<WCFG...>>`), and committed (`<CFGUPDATE>>`).

> **Note:** Only tested on GMC-500. Uses a 2-byte address for GMC-500; 1-byte address for other models.

**Parameters**

`parameters` — a list of `"name=value"` strings. Supported names:

| Name | Value type | Example |
|---|---|---|
| `cal1-cpm` | `int` | `"cal1-cpm=1000"` |
| `cal1-sv` | `float` | `"cal1-sv=6.50"` |
| `cal2-cpm` | `int` | `"cal2-cpm=2000"` |
| `cal2-sv` | `float` | `"cal2-sv=13.00"` |
| `cal3-cpm` | `int` | `"cal3-cpm=3000"` |
| `cal3-sv` | `float` | `"cal3-sv=19.50"` |

Unrecognised names are skipped with a `WARNING` message.

---

### `get_unit_conversion_from_device()`

```python
def get_unit_conversion_from_device() -> tuple[int, float]
```

Computes the CPM→uSv/h conversion factor by averaging the three calibration points stored on the device.

**Returns** `(1000, average_usievert_per_1000_cpm)` — a tuple suitable for passing as `cpm_to_usievert`.

---

## Date and Time

### `get_date_and_time()`

```python
def get_date_and_time() -> str
```

Sends `<GETDATETIME>>` and reads 7 bytes: year (2-digit), month, day, hour, minute, second, dummy.

**Returns** A string formatted as `"yy/mm/dd HH:MM:SS"`, or `''` on error.

---

### `set_date_and_time()`

```python
def set_date_and_time(date_time: datetime.datetime) -> int | None
```

Sends `<SETDATETIME...>>` with the 6-byte date/time payload (year offset from 2000, month, day, hour, minute, second).

**Parameters**

| Name | Description |
|---|---|
| `date_time` | A `datetime.datetime` object. The year is encoded as `year - 2000`. |

**Returns** `-1` if no device is connected. Prints a `WARNING` if the device does not acknowledge.

---

## Device Control

### `set_power()`

```python
def set_power(on: bool = True) -> int | None
```

Sends `<POWERON>>` or `<POWEROFF>>`.

**Returns** `-1` if no device is connected.

---

### `send_key()`

```python
def send_key(key: str) -> int | None
```

Emulates a physical button press.

| `key` value | Command sent |
|---|---|
| `'S1'` | `<KEY0>>` |
| `'S2'` | `<KEY1>>` |
| `'S3'` | `<KEY2>>` |
| `'S4'` | `<KEY3>>` |

Comparison is case-insensitive. **Returns** `-1` if no device is connected.

---

### `factory_reset()`

```python
def factory_reset() -> int | None
```

Sends `<FACTORYRESET>>` and waits for the `0xaa` acknowledgement byte.

**Returns** `-1` if no device is connected. Prints a `WARNING` if the device does not acknowledge.

---

### `reboot()`

```python
def reboot() -> int | None
```

Sends `<REBOOT>>`. No acknowledgement is expected.

**Returns** `-1` if no device is connected.

---

### `firmware_update()`

```python
def firmware_update() -> None
```

**Not implemented.** Prints `ERROR: option not yet available` and returns.

---

## Unit Conversion

### `convert_cpm_to_usievert()`

```python
def convert_cpm_to_usievert(
    cpm: int | float,
    unit: str,
    cpm_to_usievert: tuple[int, float] | None,
) -> tuple[float | int, str]
```

Converts a radiation count value to uSv/h using a linear calibration factor.

**Parameters**

| Name | Description |
|---|---|
| `cpm` | The raw count value. |
| `unit` | `'CPS'`, `'CPM'`, or `'CPH'`. Determines the time-normalisation factor. |
| `cpm_to_usievert` | `(reference_cpm, usievert_at_reference)` — e.g. `(1000, 6.50)` means 1000 CPM = 6.50 uSv/h. Pass `None` to return the value unchanged. |

**Returns** `(converted_value, 'uSv/h')`, or `(cpm, unit)` unchanged if `cpm_to_usievert` is `None` or the unit is unrecognised.

**Conversion formulae:**

| Input unit | Formula |
|---|---|
| `CPS` | `cpm × (usievert / ref_cpm) × 60` |
| `CPM` | `cpm × (usievert / ref_cpm)` |
| `CPH` | `cpm × (usievert / ref_cpm) / 60` |

---

## Internal Helpers

These functions are used internally and are not part of the public API.

### `clear_port()`

```python
def clear_port() -> None
```

Writes `">>"` to cancel any in-progress command, then reads and discards bytes until the port is empty (timeout). Called by `open_device()` and `get_data()`.

---

### `command_returned_ok()`

```python
def command_returned_ok() -> bool
```

Reads up to 10 bytes looking for the `0xaa` acknowledgement byte. Returns `True` if found, `False` otherwise. Used by `write_config()`, `set_date_and_time()`, `factory_reset()`.

---

### `check_device_type()`

```python
def check_device_type() -> int
```

Calls `get_device_type()` and validates the result. Sets `m_device_type` and `m_device_name`. Returns `0` on success, `-1` if the device is not found or unsupported. Emits a `WARNING` for GMC models not in the supported list.

---

### `print_data()`

```python
def print_data(
    out_file,
    data_type: str,
    c_str: bytes,
    size: int = 1,
    cpm_to_usievert: tuple[int, float] | None = None,
) -> str | None
```

Converts a 1–4 byte big-endian count value to a CSV-formatted string (`"value,unit"`). Returns `None` if the data type is empty, or an error string if `size >= 5`. Used internally by `parse_data_file()`.

---

### `dump_data()`

```python
def dump_data(data) -> None
```

Debug helper. Prints each byte of a buffer as `0xNN 0xVV (TODO)`. Not called in normal operation.

---

### `exit_gracefully()`

```python
def exit_gracefully(signum, frame) -> None
```

Signal handler installed by `set_heartbeat(True)`. Sets `m_terminate = True` to break the heartbeat loop.
