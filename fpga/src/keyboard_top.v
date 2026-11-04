// Board pin assignment: ../PIN_ASSIGNMENT.md and KeyboardPercussion.cst.
// Ethernet LEFT / PCIe DOWN: drums+BLE start LEFT; HallPad starts RIGHT.
`timescale 1ns / 1ps

// HallPad TLV320DAC3100 speaker integration, source release, 50 MHz only.
// Calibration presets are tied to the captured physical board/profile1.
// CODEC is the I2S clock MASTER: AUD_BCLK and AUD_WCLK are FPGA INPUTS.
// FPGA supplies 12.5 MHz MCLK. Codec PLL/dividers produce nominal
// 47999.8779296875 Hz (50 MHz source assumed); no FPGA PLL or PCM bus CDC.
// All internal logic uses clk; external audio clocks are synchronized by i2s_tx.
// Key0 acknowledges/retries a codec fault; Key1 reloads presets and codec.
// AUDIO_TEST_MODE=2: 35 independent sine voices for spectrum verification.
// AUDIO_TEST_MODE=1 requests a quiet 440 Hz diagnostic tone without Hall input;
// this explicit build mode keeps musical events/voices held in recovery.
// PA_EN always disables the unrelated NEO dock amplifier (active LOW).
// KEYBOARD_RGB is the 35-key HallPad chain; WS2812 remains the dock status pixel.
module keyboard_top #(
    parameter integer SCLK_HALF_CYCLES = 50,
    parameter integer POWERUP_CYCLES = 50000,
    parameter integer STARTUP_RESET_CYCLES = 500000,
    parameter integer HALL_IIR_SHIFT = 2,
    parameter integer JOYSTICK_IIR_SHIFT = 4,
    parameter [209:0] KEY_NOTE_MAP = {
        // Per-row musical mirror matches F407 Audio_Update; sensor IDs stay fixed.
        6'd1, 6'd2, 6'd3, 6'd4, 6'd5, 6'd6, 6'd7,
        6'd8, 6'd9, 6'd10, 6'd11, 6'd12, 6'd13, 6'd14,
        6'd15, 6'd16, 6'd17, 6'd18, 6'd19, 6'd20, 6'd21,
        6'd22, 6'd23, 6'd24, 6'd25, 6'd26, 6'd27, 6'd28,
        6'd29, 6'd30, 6'd31, 6'd32, 6'd33, 6'd34, 6'd35
    },
    parameter integer CAPTURE_LOG2 = 5,
    parameter integer MAX_SPREAD = 16,
    parameter integer CHECK_CAPTURE_SPREAD = 0,
    parameter integer MIN_SPAN = 128,
    parameter integer ARM_DELTA = 8,
    parameter integer TICK_CYCLES = 5000,
    parameter integer RELEASE_TH = 800,
    parameter integer START_TH = 1200,
    parameter integer PRESS_TH = 2400,
    parameter integer PRESS_SAMPLES = 2,
    parameter integer RELEASE_SAMPLES = 2,
    parameter integer VELOCITY_BIN_TICKS = 10,
    parameter integer VELOCITY_TIMEOUT_TICKS = 400,
    parameter integer FIFO_DEPTH = 128,
    parameter integer RECOVERY_CYCLES = 16,
    parameter integer BUTTON_DEBOUNCE_CYCLES = 500000,
    parameter integer ADC_PROFILE = 1,
    parameter integer USE_PRESET = 1,
    parameter integer AUDIO_TEST_MODE = 0,
    parameter [7:0] AUDIO_DIGITAL_VOLUME = 8'h00,
    parameter integer CODEC_RESET_HOLD_CYCLES = 5000000,
    parameter integer CODEC_RESET_RELEASE_CYCLES = 250000,
    parameter integer CODEC_SOFT_RESET_CYCLES = 250000,
    parameter integer CODEC_PLL_SETTLE_CYCLES = 1000000,
    parameter integer CODEC_ANALOG_SETTLE_CYCLES = 5000000,
    parameter integer CODEC_RETRY_DELAY_CYCLES = 25000000,
    parameter integer AUDIO_CLOCK_TIMEOUT_CYCLES = 50000,
    parameter [7:0] LIGHT_BRIGHTNESS = 8'd10,
    parameter [2:0] LIGHT_INITIAL_COLOR = 3'd0,
    parameter integer LIGHT_STEP_CYCLES = 5000000,
    parameter integer LIGHT_CHORD_CYCLES = 1000000,
    parameter integer UI_CLK_HZ = 50000000,
    parameter integer UI_SPI_HALF_CYCLES = 5,
    parameter integer ENC_AB_CYCLES = 5000,
    parameter integer ENC_SW_CYCLES = 500000,
    parameter integer ENC_EDGES_PER_STEP = 4,
    parameter integer ENC_REVERSE = 0,
    parameter integer BLE_BAUD = 115200,
    parameter integer BLE_POWERUP_MS = 2000,
    parameter [63:0] BLE_DEVICE_ID = 0,
    parameter integer ENC_LONG_CYCLES = 100000000
) (
    input wire clk,
    input wire rst_n,
    input wire [1:0] Key_in,
    input wire ENC_A,
    input wire ENC_B,
    input wire ENC_SW_N,
    input wire BLE_UART_RX,
    output wire BLE_UART_TX,
    // Two independent MPU6050 I2C buses on the external RJ45 adapter.
    // SDA/SCL open drain; PLG inputs are synchronized/debounced status levels.
    inout wire DRUM0_SCL,DRUM0_SDA,DRUM1_SCL,DRUM1_SDA,
    input wire DRUM0_PLG,DRUM1_PLG,
    output wire DRUM0_RGB,DRUM1_RGB,
    input wire SD_MISO,output wire SD_MOSI,SD_CLK,SD_CS_N,
    input wire ADC_MISO_1,
    input wire ADC_MISO_2,
    input wire ADC_MISO_3,
    output wire ADC_MOSI,
    output wire ADC_SCLK,
    output wire ADC_CS,
    input wire AUD_BCLK,
    input wire AUD_WCLK,
    output wire AUD_MCLK,
    output wire AUD_DIN,
    output wire AUD_RESET,
    inout wire AUD_SCL,
    inout wire AUD_SDA,
    output wire PA_EN,
    output wire WS2812,
    output wire KEYBOARD_RGB,
    output wire LCD_CS,
    output wire LCD_CLK,
    output wire LCD_MOSI,
    output wire LCD_DC,
    output wire LCD_RES,
    output wire LCD_BLK
);

    // synthesis translate_off
    initial begin
        if ((USE_PRESET != 0 && ADC_PROFILE != 1) ||
            (AUDIO_TEST_MODE < 0 || AUDIO_TEST_MODE > 2))
            $fatal(1, "HallPad presets require ADC_PROFILE=1; test mode must be 0..2");
    end
    // synthesis translate_on

    // Asynchronous assertion, two-clock synchronous release. Only the engine
    // gets bridge recovery reset; resetting the bridge itself would deadlock it.
    wire sys_rst_n;
    keyboard_startup_reset #(.HOLD_CYCLES(STARTUP_RESET_CYCLES)) u_startup_reset (
        .clk(clk),.external_rst_n(rst_n),.sys_rst_n(sys_rst_n)
    );
    wire confirm_pulse, restart_pulse;
    keyboard_button #(.DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES)) u_confirm_button (
        .clk(clk), .rst_n(sys_rst_n), .button_n(Key_in[0]), .press_pulse(confirm_pulse)
    );
    keyboard_button #(.DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES)) u_restart_button (
        .clk(clk), .rst_n(sys_rst_n), .button_n(Key_in[1]), .press_pulse(restart_pulse)
    );

    // UI control runs independently of ADC/audio readiness and LCD bandwidth.
    // Changes apply to the live sound/light controls immediately; the renderer
    // coalesces them into a coherent next display snapshot.
    wire ui_step_valid, ui_step_up, ui_short_press, ui_long_press;

    wire [4:0] ui_selected;
    wire [2:0] ui_main_view;
    wire [9:0] monitor_peak_bin_x,monitor_peak_bin_y;
    wire [17:0] monitor_peak_magnitude_x,monitor_peak_magnitude_y;
    wire monitor_lissajous_pixel,monitor_lissajous_valid,monitor_lissajous_lock;
    wire [7:0] monitor_lissajous_frame;
    wire [13:0] monitor_lissajous_address;
    wire [1:0] ui_menu_level;
    wire [1:0] practice_screen,practice_countdown;
    wire [34:0] practice_guide_mask,practice_yellow,practice_green,practice_red;
    wire practice_guide_long,practice_guide_holding,practice_guide_armed,practice_guide_due;
    wire [1:0] ui_audio_input_mask;
    wire monitor_scope_valid,monitor_spectrum_valid,monitor_scope_lock,monitor_spectrum_lock;
    wire [7:0] monitor_scope_frame,monitor_spectrum_frame;
    wire [7:0] monitor_scope_address,monitor_spectrum_address,monitor_scope_y,monitor_spectrum_height;
    wire [1:0] ui_light_mode;
    wire [3:0] ui_timbre_sel;
    wire ui_metro_enable;
    wire [6:0] ui_echo_percent,ui_joy_percent;
    wire [3:0] ui_metro_beats, ui_metro_unit;
    wire [7:0] ui_metro_bpm;
    wire [21:0] pitch_gain;
    wire signed [15:0] physical_bend;
    wire [6:0] physical_modulation;
    wire [255:0] ble_extended_config;
    wire signed [15:0] ble_bend;
    wire [6:0] ble_modulation;
    reg [15:0] ble_ms_div;
    wire ble_ms_tick=ble_ms_div==UI_CLK_HZ/1000-1;
    always @(posedge clk or negedge sys_rst_n) begin
        if(!sys_rst_n) ble_ms_div<=0;
        else ble_ms_div<=ble_ms_tick ? 16'd0:ble_ms_div+1'b1;
    end
    // Physical bus 0 = right, bus 1 = left. PLG is active low.
    // Keep insertion independent of sensor communication / calibration.

    reg [1:0] drum_plug_meta,drum_plug_sync,drum_plug_level;
    reg [2:0] drum_plug_count0,drum_plug_count1;
    always @(posedge clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            drum_plug_meta<=2'b11;drum_plug_sync<=2'b11;drum_plug_level<=2'b11;
            drum_plug_count0<=0;drum_plug_count1<=0;
        end else begin
            drum_plug_meta<={DRUM1_PLG,DRUM0_PLG};
            drum_plug_sync<=drum_plug_meta;
            if(ble_ms_tick) begin
                if(drum_plug_sync[0]==drum_plug_level[0]) drum_plug_count0<=0;
                else if(drum_plug_count0==4) begin drum_plug_level[0]<=drum_plug_sync[0];drum_plug_count0<=0;end
                else drum_plug_count0<=drum_plug_count0+1'b1;
                if(drum_plug_sync[1]==drum_plug_level[1]) drum_plug_count1<=0;
                else if(drum_plug_count1==4) begin drum_plug_level[1]<=drum_plug_sync[1];drum_plug_count1<=0;end
                else drum_plug_count1<=drum_plug_count1+1'b1;
            end
        end
    end

    wire sample_tick;
    wire [34:0] physical_key_mask,merged_physical_mask;
    wire offline_mapping_active,offline_result_valid;
    wire [34:0] offline_key_enabled,offline_fixed_mode;
    wire [244:0] offline_key_midi,offline_fixed_velocity;
    wire [139:0] offline_key_timbre;
    wire [383:0] offline_result_packet;
    wire [255:0] offline_result_text;
    wire offline_active,offline_enter,offline_command_valid,offline_command_ready,offline_command_done;
    wire [7:0] offline_command_type,offline_command_length,offline_payload_addr,offline_payload_data,offline_command_code;
    wire [2:0] offline_run_phase;
    wire [7:0] offline_selection;
    wire [7:0] offline_ui_state,offline_ui_error;
    wire [63:0] offline_name;
    wire [8:0] offline_song_count;
    wire sd_ready,sd_done,sd_error,sd_request,sd_read_valid;
    wire [31:0] sd_lba,offline_file_size;
    wire [8:0] sd_read_address;
    wire [7:0] sd_read_byte,sd_error_code,catalog_error,offline_file_byte;
    wire catalog_mounted,catalog_failed,offline_open,offline_file_valid,offline_file_ready,offline_file_done,offline_cancel;
    wire catalog_idle,preview_open,preview_active,preview_mode,preview_short,title_current;
    wire [7:0] preview_revision;
    wire [127:0] bundle_ascii_title;wire bundle_ascii_valid;
    wire bundle_raw_cancel;
    wire bundle_valid,bundle_ready,bundle_done,bundle_raw_ready,bundle_playback,bundle_choosing,bundle_failed,bundle_title_valid,bundle_title_ink;
    wire [7:0] bundle_byte,bundle_state;
    wire [31:0] bundle_size,bundle_skipped;
    wire [63:0] bundle_text;
    wire [5:0] bundle_title_count;wire [4:0] bundle_title_row,bundle_title_column;
    wire [4:0] bundle_title_index;
    wire [34:0] offline_auto_mask;wire [6:0] offline_auto_velocity;
    wire [35:0] remote_key_mask;
    wire sd_locked,sd_remount,sd_bridge_read,sd_bridge_write;
    wire [31:0] sd_bridge_lba;wire [8:0] sd_write_address;wire [7:0] sd_write_byte;
    wire sd_probe,sd_probing,sd_hotreset,sd_missing,sd_probe_due;
    wire sd_bridge_allowed=catalog_idle && !sd_probing && !sd_probe_due && !sd_hotreset && !preview_active && (!offline_active || offline_ui_state==1 || offline_ui_state==6 || offline_ui_state==7) && !offline_mapping_active && offline_run_phase!=1 && offline_run_phase!=2;
    wire sd_catalog_rst_n=sys_rst_n && !sd_remount && !sd_hotreset;
    hallpad_sd_hotplug u_sd_hotplug(.clk(clk),.rst_n(sys_rst_n),.ms_tick(ble_ms_tick),
      .can_probe((catalog_idle || bundle_choosing) && !preview_active && !sd_locked && !preview_open && !offline_open),
      .card_ready(sd_ready),.card_done(sd_done),.card_error(sd_error),.catalog_failed(catalog_failed),.mounted(catalog_mounted),
      .probe_due(sd_probe_due),.probe(sd_probe),.probing(sd_probing),.reset_card(sd_hotreset),.missing(sd_missing));
    logger_sd_spi u_sd(.clk(clk),.rst_n(sys_rst_n && !sd_hotreset),.miso(SD_MISO),.sck(SD_CLK),.mosi(SD_MOSI),.cs_n(SD_CS_N),
        .ready(sd_ready),.error(sd_error),.request(sd_bridge_write && sd_locked),.read_request(sd_locked ? sd_bridge_read:(sd_probe || sd_request)),.lba(sd_locked ? sd_bridge_lba:(sd_probing ? 32'd0:sd_lba)),
        .read_valid(sd_read_valid),.read_address(sd_read_address),.read_byte(sd_read_byte),
        .data_address(sd_write_address),.data_byte(sd_write_byte),.done(sd_done),.error_code(sd_error_code),.debug_cmd(),.debug_r1());
    hallpad_sd_catalog u_catalog(.clk(clk),.rst_n(sd_catalog_rst_n),.block_ready(sd_ready && !sd_locked && !sd_probing),.block_done(sd_done),.block_error(sd_error),
        .block_request(sd_request),.block_lba(sd_lba),.read_valid(sd_read_valid && !sd_locked && !sd_probing),.read_address(sd_read_address),.read_byte(sd_read_byte),
        .file_idle(catalog_idle),.open_file(offline_open || preview_open),.selection(offline_selection),.mounted(catalog_mounted),.failed(catalog_failed),.error_code(catalog_error),
        .song_count(offline_song_count),.song_name(offline_name),.file_size(offline_file_size),
        .data_valid(offline_file_valid),.data_byte(offline_file_byte),.data_ready(bundle_raw_ready),.file_done(offline_file_done),.cancel(offline_cancel || bundle_raw_cancel));
    hallpad_title_preview u_preview(.clk(clk),.rst_n(sd_catalog_rst_n),.active(offline_active && !sd_locked),.mounted(catalog_mounted),
      .catalog_idle(catalog_idle),.catalog_done(offline_file_done),.ui_state(offline_ui_state),.selection(offline_selection),.song_count(offline_song_count),
      .short_press(ui_short_press && !bundle_choosing),.long_press(ui_long_press),.preview_open(preview_open),.preview_active(preview_active),.loader_short(preview_short),.title_current(title_current),.revision(preview_revision));
    hallpad_hpg3 u_bundle(.clk(clk),.rst_n(sd_catalog_rst_n),.open_file(offline_open || preview_open),.cancel(offline_cancel),.preview_only(preview_active && !offline_open),.preview_mode(preview_mode),.ascii_title(bundle_ascii_title),.ascii_title_valid(bundle_ascii_valid),
      .step_valid(ui_step_valid),.step_up(ui_step_up),.short_press(ui_short_press),
      .raw_size(offline_file_size),.raw_valid(offline_file_valid),.raw_byte(offline_file_byte),.raw_ready(bundle_raw_ready),.raw_cancel(bundle_raw_cancel),.raw_done(offline_file_done),
      .data_valid(bundle_valid),.data_byte(bundle_byte),.data_ready(bundle_ready),.data_done(bundle_done),.data_size(bundle_size),
      .playback(bundle_playback),.choosing(bundle_choosing),.failed(bundle_failed),.choice_state(bundle_state),.choice_text(bundle_text),.skipped(bundle_skipped),
      .title_valid(bundle_title_valid),.title_count(bundle_title_count),.title_index(bundle_title_index),.title_row(bundle_title_row),.title_column(bundle_title_column),.title_ink(bundle_title_ink));
    hallpad_offline_ctrl u_offline(.clk(clk),.rst_n(sys_rst_n),.enter(offline_enter && !sd_locked),.step_valid(ui_step_valid && !bundle_choosing && !sd_locked),.step_up(ui_step_up),
        .short_press(preview_short && !sd_locked),.long_press(ui_long_press),.active(offline_active),.selection(offline_selection),
        .keys_released(physical_key_mask==0 && remote_key_mask==0),.mapping_active(offline_mapping_active),.map_enabled(offline_key_enabled),.map_fixed(offline_fixed_mode),.map_midi(offline_key_midi),.map_velocity(offline_fixed_velocity),.map_timbre(offline_key_timbre),.result_valid(offline_result_valid),.result_packet(offline_result_packet),.result_text(offline_result_text),.ui_state(offline_ui_state),.ui_error(offline_ui_error),.mounted(catalog_mounted),.card_failed(sd_missing || catalog_failed || (bundle_failed && !preview_mode)),.card_error(sd_missing ? 8'he6:bundle_failed ? 8'he5:catalog_error),
        .song_count(offline_song_count),.open_file(offline_open),.file_size(bundle_size),.file_valid(bundle_valid && !preview_active),
        .file_byte(bundle_byte),.file_ready(bundle_ready),.file_done(bundle_done && !preview_active),.file_cancel(offline_cancel),
        .command_valid(offline_command_valid),.command_ready(offline_command_ready),.command_type(offline_command_type),
        .command_length(offline_command_length),.payload_addr(offline_payload_addr),.payload_data(offline_payload_data),
        .command_done(offline_command_done),.command_code(offline_command_code),.run_phase(offline_run_phase));
    wire [15:0] response_us;
    wire response_valid,response_busy,response_probe_armed,response_rendered;
    wire [5:0] response_probe_key;
    wire [7:0] response_probe_revision;
    wire [127:0] drum_config;
    wire [95:0] drum_cal_status;
    wire [15:0] drum_bus_error;
    wire [31:0] drum_bus_info;
    wire drum_cal_ready,drum_cal_local,drum_cal_remote,drum_light_hit,drum_light_stick;
    wire [47:0] drum_light_config;
    wire [31:0] drum_color_config;
    wire [87:0] drum_effect_config;
    wire drum_effect_active;

    // Only drum MPU buses and drum RGB share this fixed 5 ms timebase.
    wire drum_read_launch,drum_slot_abort,drum_rgb_launch,drum_rgb_window;
    wire [17:0] drum_slot_phase;
    drum_slot5ms u_drum_schedule(.clk(clk),.rst_n(sys_rst_n),.read_launch(drum_read_launch),
        .abort_bus(drum_slot_abort),.rgb_launch(drum_rgb_launch),.rgb_window(drum_rgb_window),.phase(drum_slot_phase));
    reg [1:0] drum_inserted_last;
    always @(posedge clk or negedge sys_rst_n)
        if(!sys_rst_n)drum_inserted_last<=0;
        else drum_inserted_last<={!drum_plug_level[0],!drum_plug_level[1]};
    drum_strip_lights #(.CHORD_CYCLES(LIGHT_CHORD_CYCLES)) u_drum_lights(.slot_launch(drum_rgb_launch),.slot_window(drum_rgb_window),.clk(clk),.rst_n(sys_rst_n),.ms_tick(ble_ms_tick),
        .hit(drum_light_hit),.stick(drum_light_stick),.settings(drum_light_config),.color_settings(drum_color_config),
        .force_refresh({!drum_plug_level[0],!drum_plug_level[1]} & ~drum_inserted_last),.effect_config(drum_effect_config),.effect_active(drum_effect_active),.serialL(DRUM1_RGB),.serialR(DRUM0_RGB));
    wire drum_edit_valid,drum_edit_ready,drum_edit_stick,drum_edit_up;
    wire [1:0] drum_edit_direction;
    wire drum_sim_valid,drum_sim_ready,drum_sim_stick,drum_hit_valid,drum_hit_ready;
    wire [1:0] drum_sim_direction,drum_online,drum_calibrated;
    wire [6:0] drum_sim_velocity;
    wire [95:0] drum_hit_data;
    wire drum_session_valid,drum_ready,drum_frame_overrun,drum_error;
    wire [31:0] drum_session_id,device_uptime;
    wire signed [23:0] drum_pcm_wide;

    wire [63:0] ui_config_data,ble_parameter_data;
    wire [31:0] ui_config_revision;
    wire [35:0] custom_key_enabled,custom_fixed_mode;
    wire [251:0] custom_key_midi,custom_fixed_velocity;
    wire [143:0] custom_key_timbre;
    wire [35:0] saved_key_enabled,saved_fixed_mode;
    wire [251:0] saved_key_midi,saved_fixed_velocity;
    wire [143:0] saved_key_timbre;
    assign custom_key_enabled=offline_mapping_active ? {saved_key_enabled[35],offline_key_enabled}:saved_key_enabled;
    assign custom_fixed_mode=offline_mapping_active ? {saved_fixed_mode[35],offline_fixed_mode}:saved_fixed_mode;
    assign custom_key_midi=offline_mapping_active ? {saved_key_midi[251:245],offline_key_midi}:saved_key_midi;
    assign custom_fixed_velocity=offline_mapping_active ? {saved_fixed_velocity[251:245],offline_fixed_velocity}:saved_fixed_velocity;
    assign custom_key_timbre=offline_mapping_active ? {saved_key_timbre[143:140],offline_key_timbre}:saved_key_timbre;
    wire ble_parameter_ready,ble_parameter_commit,ble_parameter_done,ble_parameter_error,ble_panic,ble_clear_remote;
    wire input_route_valid,input_route_ready,input_route_done,input_route_error,input_route_cancel;
    wire [1:0] input_route_target;
    wire mclk_ready,codec_configured,codec_playing,codec_error;
    hallpad_remote_pitch #(.NORMALIZED_PHYSICAL(1)) u_remote_pitch(.clk(clk),.rst_n(sys_rst_n),.sample_tick(sample_tick),.enabled(ble_extended_config[32] && !ble_panic),.bend(ble_bend),.modulation(ble_modulation),.range_cents(ble_extended_config[11:0]),.physical_gain(22'd1048576),.physical_bend(physical_bend),.physical_modulation(physical_modulation),.pitch_gain(pitch_gain));

    wire ble_remote_valid,ble_remote_ready,ble_remote_snapshot,ble_remote_on;
    wire [5:0] ble_remote_key;
    wire [6:0] ble_remote_velocity;
    wire [35:0] ble_remote_target_mask;
    wire [251:0] ble_remote_target_velocity;
    wire merge_overflow,ble_rx_overflow,light_tap_overflow;
    wire recovery_active;
    reg diagnostic_fault;
    wire [3:0] engine_active_timbre;
    wire engine_timbre_switching;
    reg [34:0] panic_block_mask;
    wire light_event_valid,remote_light_valid;
    wire [5:0] light_event_key,remote_light_key;


    wire ui_editing,ui_language_cn;
    wire [6:0] ui_volume_percent;
    wire [5:0] ui_light_brightness;
    rotary_encoder #(
        .AB_STABLE_CYCLES(ENC_AB_CYCLES), .SW_STABLE_CYCLES(ENC_SW_CYCLES),
        .EDGES_PER_STEP(ENC_EDGES_PER_STEP), .REVERSE(ENC_REVERSE),
        .LONG_PRESS_CYCLES(ENC_LONG_CYCLES)
    ) u_encoder (
        .clk(clk), .rst_n(sys_rst_n), .enc_a(ENC_A), .enc_b(ENC_B),
        .enc_sw_n(ENC_SW_N), .step_valid(ui_step_valid), .step_up(ui_step_up),
        .short_press(ui_short_press), .long_press(ui_long_press),
        .invalid_count()
    );
    keyboard_menu_ctrl #(
        .DEFAULT_VOLUME(50), .DEFAULT_BRIGHTNESS(LIGHT_BRIGHTNESS),
        .AUDIO_ROUTE_HANDSHAKE(1),.ROUTE_TIMEOUT_CYCLES(UI_CLK_HZ/2)
    ) u_menu (
        .clk(clk), .rst_n(sys_rst_n), .step_valid(ui_step_valid && !offline_active), .step_up(ui_step_up),
        .short_press(ui_short_press && !offline_active), .long_press(ui_long_press && !offline_active),
        .main_view(ui_main_view),.menu_level(ui_menu_level),
        .selected(ui_selected), .editing(ui_editing), .volume_percent(ui_volume_percent),
        .light_brightness(ui_light_brightness), .timbre_sel(ui_timbre_sel),
        .echo_percent(ui_echo_percent), .joy_percent(ui_joy_percent),
        .metro_enable(ui_metro_enable),
        .metro_beats(ui_metro_beats), .metro_unit(ui_metro_unit), .metro_bpm(ui_metro_bpm),
        .drum_config(drum_config),.drum_cal_request(drum_cal_local),.offline_enter(offline_enter),.drum_edit_valid(drum_edit_valid),.drum_edit_ready(drum_edit_ready),
        .drum_edit_stick(drum_edit_stick),.drum_edit_direction(drum_edit_direction),.drum_edit_up(drum_edit_up),
        .remote_commit(ble_parameter_commit),.remote_config(ble_parameter_data),
        .remote_ready(ble_parameter_ready),.remote_done(ble_parameter_done),.remote_error(ble_parameter_error),
        .route_valid(input_route_valid),.route_target_mask(input_route_target),.route_ready(input_route_ready),
        .route_done(input_route_done),.route_error(input_route_error || codec_error),.route_cancel(input_route_cancel),.config_data(ui_config_data),.config_revision(ui_config_revision),
        .audio_input_mask(ui_audio_input_mask),.light_mode(ui_light_mode), .language_cn(ui_language_cn), .changed()
    );
    wire lcd_init_done, lcd_draw_valid, lcd_draw_ready, lcd_fill_mode;
    wire lcd_pixel_valid, lcd_pixel_ready, lcd_draw_done, lcd_draw_error;
    wire [7:0] lcd_x0, lcd_y0, lcd_x1, lcd_y1;
    wire [15:0] lcd_fill_color, lcd_pixel_rgb565;
    keyboard_menu_renderer #(.ENABLE_PRACTICE(1)) u_menu_renderer (
        .song_selection(offline_selection),.song_count(offline_song_count),.title_revision(preview_revision),.title_pending(offline_song_count!=0 && (preview_active || !title_current || (offline_ui_state==2 && !bundle_title_valid && !bundle_ascii_valid))),.ascii_title(bundle_ascii_title),.ascii_title_valid(bundle_ascii_valid && title_current),.playback_mode(bundle_playback),.bundle_choosing(bundle_choosing),.bundle_text(bundle_text),.bundle_skipped(bundle_skipped),
        .title_valid(bundle_title_valid && title_current),.title_count(bundle_title_count),.title_index(bundle_title_index),.title_row(bundle_title_row),.title_column(bundle_title_column),.title_ink(bundle_title_ink),
        .offline_result_text(offline_result_text),.response_us(response_us),.response_valid(response_valid),.response_busy(response_busy),
        .drum_active(drum_cal_status[25:24]),.drum_pose_fault(drum_cal_status[65:64]),.drum_config(drum_config),.drum_online(drum_online),.drum_calibrated(drum_calibrated),.drum_cal_state(drum_cal_status[55:48]),.drum_bus_error(drum_bus_error),.drum_bus_info(drum_bus_info),.drum_inserted(drum_cal_status[1:0]),.offline_active(offline_active),.offline_state(bundle_choosing ? bundle_state:offline_ui_state),.offline_error(offline_ui_error),.offline_name(offline_name),
        .practice_screen(practice_screen),.practice_countdown(practice_countdown),
        .clk(clk), .rst_n(sys_rst_n), .init_done(lcd_init_done),
        .main_view(ui_main_view),.menu_level(ui_menu_level),
        .lissajous_pixel(monitor_lissajous_pixel),.lissajous_valid(monitor_lissajous_valid),
        .lissajous_frame(monitor_lissajous_frame),.lissajous_address(monitor_lissajous_address),
        .lissajous_lock(monitor_lissajous_lock),
        .scope_valid(monitor_scope_valid),.spectrum_valid(monitor_spectrum_valid),
        .scope_frame(monitor_scope_frame),.spectrum_frame(monitor_spectrum_frame),
        .scope_y(monitor_scope_y),.spectrum_height(monitor_spectrum_height),
        .scope_address(monitor_scope_address),.spectrum_address(monitor_spectrum_address),
        .scope_lock(monitor_scope_lock),.spectrum_lock(monitor_spectrum_lock),
        .selected(ui_selected), .editing(ui_editing), .volume_percent(ui_volume_percent),
        .light_brightness(ui_light_brightness), .timbre_sel(ui_timbre_sel),
        .echo_percent(ui_echo_percent), .joy_percent(ui_joy_percent),
        .metro_enable(ui_metro_enable),
        .metro_beats(ui_metro_beats), .metro_unit(ui_metro_unit), .metro_bpm(ui_metro_bpm),
        .audio_input_mask(ui_audio_input_mask),.light_mode(ui_light_mode), .language_cn(ui_language_cn), .draw_valid(lcd_draw_valid), .draw_ready(lcd_draw_ready),
        .x0(lcd_x0), .y0(lcd_y0), .x1(lcd_x1), .y1(lcd_y1),
        .fill_mode(lcd_fill_mode), .fill_color(lcd_fill_color),
        .pixel_valid(lcd_pixel_valid), .pixel_ready(lcd_pixel_ready),
        .pixel_rgb565(lcd_pixel_rgb565), .draw_done(lcd_draw_done), .draw_error(lcd_draw_error)
    );
    // Relative to the tested MADCTL=08 baseline: (x,y) -> (239-y,x).
    // MX|MV|BGR = 0x68 rotates the complete menu clockwise by 90 degrees.
    gc9a01_driver #(.CLK_HZ(UI_CLK_HZ), .SCLK_HALF_CYCLES(UI_SPI_HALF_CYCLES),
                    .MADCTL(8'h68)) u_lcd (
        .clk(clk), .rst_n(sys_rst_n), .backlight_en(1'b1),
        .draw_valid(lcd_draw_valid), .draw_ready(lcd_draw_ready),
        .x0(lcd_x0), .y0(lcd_y0), .x1(lcd_x1), .y1(lcd_y1),
        .fill_mode(lcd_fill_mode), .fill_color(lcd_fill_color),
        .pixel_valid(lcd_pixel_valid), .pixel_ready(lcd_pixel_ready),
        .pixel_rgb565(lcd_pixel_rgb565), .init_done(lcd_init_done), .busy(),
        .draw_done(lcd_draw_done), .draw_error(lcd_draw_error),
        .LCD_CS(LCD_CS), .LCD_CLK(LCD_CLK), .LCD_MOSI(LCD_MOSI), .LCD_DC(LCD_DC),
        .LCD_RES(LCD_RES), .LCD_BLK(LCD_BLK)
    );

    wire adc_fault,adc_restart;
    wire scan_rst_n=sys_rst_n && !adc_restart;
    localparam integer ADC_WATCHDOG_CYCLES =
        (POWERUP_CYCLES+16*(34*SCLK_HALF_CYCLES+3)*8>500000) ?
        POWERUP_CYCLES+16*(34*SCLK_HALF_CYCLES+3)*8:500000;
    wire filtered_valid, filtered_is_joystick, filtered_scan_done;
    wire [1:0] filtered_chip;
    wire [3:0] filtered_channel;
    wire [11:0] filtered_data, filtered_raw_data;
    wire [2:0] filtered_tag_error;
    adc_data_top #(
        .SCLK_HALF_CYCLES(SCLK_HALF_CYCLES), .POWERUP_CYCLES(POWERUP_CYCLES),
        .HALL_IIR_SHIFT(HALL_IIR_SHIFT), .JOYSTICK_IIR_SHIFT(JOYSTICK_IIR_SHIFT),
        .ADC_PROFILE(ADC_PROFILE)
    ) u_adc (
        .clk(clk), .rst_n(scan_rst_n), .bypass(1'b0),
        .ADC_MISO_1(ADC_MISO_1), .ADC_MISO_2(ADC_MISO_2), .ADC_MISO_3(ADC_MISO_3),
        .ADC_MOSI(ADC_MOSI), .ADC_SCLK(ADC_SCLK), .ADC_CS(ADC_CS),
        .filtered_valid(filtered_valid), .filtered_chip(filtered_chip),
        .filtered_channel(filtered_channel), .filtered_data(filtered_data),
        .filtered_raw_data(filtered_raw_data), .filtered_is_joystick(filtered_is_joystick),
        .filtered_scan_done(filtered_scan_done), .filtered_tag_error(filtered_tag_error)
    );

    wire key_valid, key_note_valid, mapped_scan_done, map_error;
    wire [5:0] key_id, note_sel;
    wire [11:0] key_data, key_raw_data;
    wire [2:0] mapped_tag_error;
    // Calibrated X/Y performance controls use the existing common DDS pitch gain.
    wire joystick_valid, joystick_axis;
    wire [11:0] joystick_data;
    joystick_pitch_bend u_pitch_bend (
        .clk(clk),.rst_n(scan_rst_n),.sample_tick(sample_tick),.joy_percent(ui_joy_percent),
        .joy_valid(joystick_valid),.joy_axis(joystick_axis),.joy_data(joystick_data),
        .bend(physical_bend),.modulation(physical_modulation),.center_ready()
    );
    key_channel_map #(.KEY_NOTE_MAP(KEY_NOTE_MAP), .ADC_PROFILE(ADC_PROFILE)) u_map (
        .clk(clk), .rst_n(scan_rst_n), .filtered_valid(filtered_valid),
        .filtered_chip(filtered_chip), .filtered_channel(filtered_channel),
        .filtered_data(filtered_data), .filtered_raw_data(filtered_raw_data),
        .filtered_is_joystick(filtered_is_joystick),
        .filtered_scan_done(filtered_scan_done), .filtered_tag_error(filtered_tag_error),
        .key_valid(key_valid), .key_id(key_id), .key_note_valid(key_note_valid),
        .note_sel(note_sel), .key_data(key_data), .key_raw_data(key_raw_data),
        .joystick_valid(joystick_valid), .joystick_axis(joystick_axis),
        .joystick_data(joystick_data), .joystick_raw_data(),
        .mapped_scan_done(mapped_scan_done), .mapped_tag_error(mapped_tag_error),
        .map_error(map_error)
    );

    adc_stream_guard #(.TIMEOUT_CYCLES(ADC_WATCHDOG_CYCLES)) u_adc_guard (
        .clk(clk),.rst_n(sys_rst_n),.key_valid(key_valid),.key_id(key_id),
        .scan_done(mapped_scan_done),.fault(adc_fault),.restart(adc_restart)
    );
    wire preset_start, preset_done, preset_error;
    wire load_valid, load_decreasing;
    wire [5:0] load_key_id;
    wire [11:0] load_baseline, load_span;
    key_calibration_preset u_preset (
        .clk(clk), .rst_n(sys_rst_n), .start(preset_start),
        .busy(), .done(preset_done), .error(preset_error),
        .load_valid(load_valid), .load_key_id(load_key_id),
        .load_baseline(load_baseline), .load_span(load_span),
        .load_decreasing(load_decreasing)
    );
    wire setup_hold, cal_clear, cal_cmd_valid, recover_pulse;
    wire [1:0] cal_cmd;
    wire [5:0] cal_key_id;
    wire [2:0] ui_state;
    wire calibration_done, controller_error;
    wire [34:0] baseline_valid_mask, calibrated_mask, cal_armed_mask;
    wire [34:0] cal_busy_mask, cal_failed_mask;
    wire calibrated_valid, calibrated_note_valid, cal_error;
    wire [5:0] calibrated_key_id, calibrated_note_sel;
    wire [11:0] key_travel;
    wire raw_press_evidence;
    key_calibrate #(
        .CAPTURE_LOG2(CAPTURE_LOG2), .MAX_SPREAD(MAX_SPREAD),
        .CHECK_CAPTURE_SPREAD(CHECK_CAPTURE_SPREAD),
        .MIN_SPAN(MIN_SPAN), .ARM_DELTA(ARM_DELTA), .ENABLE_PRESET_LOAD(USE_PRESET)
    ) u_calibrate (
        .clk(clk), .rst_n(sys_rst_n), .key_valid(key_valid), .key_id(key_id),
        .key_note_valid(key_note_valid), .note_sel(note_sel),
        .key_data(key_data), .key_raw_data(key_raw_data),
        .mapped_scan_done(mapped_scan_done), .mapped_tag_error(mapped_tag_error),
        .map_error(map_error), .cal_clear(cal_clear), .cal_cmd_valid(cal_cmd_valid),
        .cal_cmd(cal_cmd), .cal_key_id(cal_key_id),
        .load_valid(load_valid), .load_key_id(load_key_id),
        .load_baseline(load_baseline), .load_span(load_span),
        .load_decreasing(load_decreasing),
        .calibrated_valid(calibrated_valid), .calibrated_key_id(calibrated_key_id),
        .calibrated_note_valid(calibrated_note_valid), .calibrated_note_sel(calibrated_note_sel),
        .key_travel(key_travel), .raw_press_evidence(raw_press_evidence), .calibrated_data(), .calibrated_raw_data(),
        .calibrated_scan_done(), .calibrated_tag_error(), .calibrated_map_error(),
        .baseline_valid_mask(baseline_valid_mask), .calibrated_mask(calibrated_mask),
        .armed_mask(cal_armed_mask), .busy_mask(cal_busy_mask),
        .failed_mask(cal_failed_mask), .cal_error(cal_error)
    );
    keyboard_cal_ctrl #(
        .RELEASE_TH(RELEASE_TH), .RELEASE_DRAIN_CYCLES(RECOVERY_CYCLES), .USE_PRESET(USE_PRESET)
    ) u_cal_ctrl (
        .clk(clk), .rst_n(sys_rst_n), .restart_pulse(restart_pulse),
        .preset_start(preset_start), .preset_done(preset_done),
        .preset_error(preset_error | ((USE_PRESET != 0) && (ADC_PROFILE != 1))),
        .confirm_pulse(confirm_pulse), .baseline_valid_mask(baseline_valid_mask),
        .calibrated_mask(calibrated_mask), .cal_armed_mask(cal_armed_mask),
        .cal_busy_mask(cal_busy_mask), .cal_failed_mask(cal_failed_mask), .cal_error(cal_error),
        .calibrated_valid(calibrated_valid), .calibrated_key_id(calibrated_key_id),
        .key_travel(key_travel), .setup_hold(setup_hold), .cal_clear(cal_clear),
        .cal_cmd_valid(cal_cmd_valid), .cal_cmd(cal_cmd), .cal_key_id(cal_key_id),
        .recover_pulse(recover_pulse), .ui_state(ui_state), .current_key(),
        .calibration_done(calibration_done), .controller_error(controller_error)
    );

    wire event_state_clear, event_valid, event_on, event_input_error;
    wire [5:0] event_key_id, event_note_sel;
    wire [6:0] event_velocity;

    key_event #(
        .REQUIRE_RAW_PRESS(1),
        .TICK_CYCLES(TICK_CYCLES), .RELEASE_TH(RELEASE_TH), .START_TH(START_TH),
        .PRESS_TH(PRESS_TH), .PRESS_SAMPLES(PRESS_SAMPLES), .RELEASE_SAMPLES(RELEASE_SAMPLES),
        .VELOCITY_BIN_TICKS(VELOCITY_BIN_TICKS), .VELOCITY_TIMEOUT_TICKS(VELOCITY_TIMEOUT_TICKS)
    ) u_event (
        .clk(clk), .rst_n(sys_rst_n), .state_clear(event_state_clear),
        .calibrated_valid(calibrated_valid), .calibrated_key_id(calibrated_key_id),
        .calibrated_note_valid(calibrated_note_valid), .calibrated_note_sel(calibrated_note_sel),
        .key_travel(key_travel), .raw_press_evidence(raw_press_evidence), .event_valid(event_valid), .event_on(event_on),
        .event_key_id(event_key_id), .event_note_sel(event_note_sel), .event_velocity(event_velocity),
        .key_down_mask(physical_key_mask), .key_armed_mask(),
        .measuring_mask(), .input_error(event_input_error)
    );

    // PANIC does not reset the physical key detector or codec. Every key must
    // show an actual release sample before a subsequent physical ON is allowed.
    always @(posedge clk or negedge sys_rst_n) begin
        if(!sys_rst_n) panic_block_mask<=0;
        else if(ble_panic) panic_block_mask<={35{1'b1}};
        else if(calibrated_valid && calibrated_key_id<35 && key_travel<=RELEASE_TH) panic_block_mask[calibrated_key_id]<=0;
    end
    hallpad_light_tap u_light_tap(.clk(clk),.rst_n(sys_rst_n),.clear(ble_panic),
        .physical_valid(event_valid && event_on && custom_key_enabled[event_key_id] && !event_state_clear && !ble_panic && !panic_block_mask[event_key_id]),
        .physical_key(event_key_id),.remote_valid(remote_light_valid),.remote_key(remote_light_key),
        .valid(light_event_valid),.key(light_event_key),.overflow(light_tap_overflow));

    // Keep each accepted event/key/enable together across the light fanout stage.
    // Captured events finish even if calibration or panic blocks later events.
    reg lighting_event_valid,lighting_event_enable;
    reg [5:0] lighting_event_key;
    always @(posedge clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin lighting_event_valid<=0;lighting_event_enable<=0;lighting_event_key<=0;end
        else begin
            lighting_event_valid<=light_event_valid;
            lighting_event_enable<=!setup_hold && !ble_panic;
            lighting_event_key<=light_event_key;
        end
    end

    // Tap physical NOTE_ON before the audio queue. Light timing never waits
    // for an audio frame, a free voice, or FIFO readiness. Calibration/recovery
    // suppress only new triggers. Accepted waves finish independently of audio
    // recovery, with their tick phase and pending arrivals retained.
    wire [839:0] lighting_raw_pixels, lighting_pixels;

    // Preserve the validated palette/chord/arrival scheduler. App speed drives
    // its shared phase; width/decay shape a retained-color brightness envelope.
    wire [34:0] lighting_arrivals;
    wire [314:0] lighting_intensities;
    wire [104:0] lighting_palette;
    keyboard_ripple #(
        .BRIGHTNESS(8'd255), .INITIAL_COLOR(LIGHT_INITIAL_COLOR),
        .STEP_CYCLES(LIGHT_STEP_CYCLES), .CHORD_CYCLES(LIGHT_CHORD_CYCLES),
        .RUNTIME_SPEED(1)
    ) u_lighting (
        .clk(clk), .rst_n(sys_rst_n), .enable(lighting_event_enable),
        .event_valid(lighting_event_valid), .event_on(1'b1),
        .event_key_id(lighting_event_key), .pixels_rgb(lighting_raw_pixels),.palette_indices(lighting_palette),
        .ms_tick(ble_ms_tick), .speed(ble_extended_config[174:160]),
        .arrivals(lighting_arrivals)
    );
    keyboard_ripple_envelope u_light_envelope (
        .clk(clk), .rst_n(sys_rst_n), .ms_tick(ble_ms_tick),
        .arrivals(lighting_arrivals), .speed(ble_extended_config[174:160]),
        .width(12'd1000), .decay_ms(ble_extended_config[236:224]),
        .intensities(lighting_intensities)
    );
    keyboard_light_runtime #(.INITIAL_COLOR(LIGHT_INITIAL_COLOR),.USE_CUSTOM_COLOR(1),
                             .USE_RIPPLE_ENVELOPE(1),.USE_PALETTE_SOURCE(1),.USE_PRACTICE_GUIDE(1)) u_light_runtime (
        .clk(clk), .rst_n(sys_rst_n), .solid_rgb(ble_extended_config[151:128]),.ripple_pixels(lighting_raw_pixels),
        .ripple_intensities(lighting_intensities),
        .brightness(ui_light_brightness), .light_mode(ui_light_mode),
        .practice_yellow(offline_active && bundle_playback ? 35'd0:practice_yellow),.practice_green(offline_active && bundle_playback ? 35'd0:practice_green),.practice_red(offline_active && bundle_playback ? 35'd0:practice_red),
        .practice_active(offline_active ? (offline_run_phase==1 || offline_run_phase==2):(practice_screen!=0 || |practice_yellow || |practice_green || |practice_red)),.practice_mask(offline_active && bundle_playback ? offline_auto_mask:practice_guide_mask),
        .practice_long(!(offline_active && bundle_playback) && practice_guide_long),.practice_holding(!(offline_active && bundle_playback) && practice_guide_holding),
        .palette_indices(lighting_palette),.pixels_rgb(lighting_pixels), .frame_update()
    );
    // Assist frames contain only the current target keys; the runtime
    // publishes them atomically without a separate 840-bit overlay bank.
    keyboard_rgb_chain #(.LED_COUNT(35)) u_keyboard_rgb (
        .clk(clk), .rst_n(sys_rst_n), .pixels_rgb(lighting_pixels),
        .serial_out(KEYBOARD_RGB)
    );

    wire fifo_clear, fifo_diag_clear, queue_valid, queue_ready, queue_on;
    wire [5:0] queue_key_id, queue_note_sel;
    wire [6:0] queue_velocity;
    wire overflow_sticky;


    wire merged_valid,merged_ready,merged_on,audio_fifo_full;
    wire [5:0] merged_key,merged_note;
    wire [6:0] merged_velocity;
    assign merged_ready=!audio_fifo_full || (queue_valid && queue_ready);
    wire playback_merge_ready;
    reg playback_owner;reg [35:0] playback_sent;
    wire [34:0] playback_desired=offline_active && bundle_playback ? offline_auto_mask:35'd0;
    wire playback_send=playback_owner && {1'b0,playback_desired}!=playback_sent;
    wire [251:0] playback_velocities={7'd0,{35{offline_auto_velocity}}};
    assign ble_remote_ready=playback_merge_ready && !playback_owner;
    always @(posedge clk or negedge sys_rst_n)begin
      if(!sys_rst_n)begin playback_owner<=0;playback_sent<=0;end
      else begin
       if(offline_active && bundle_playback && (offline_run_phase==1 || offline_run_phase==2))begin playback_owner<=1;if(!playback_owner)playback_sent<=remote_key_mask;end
       else if(playback_sent==0 && remote_key_mask==0 && playback_merge_ready)playback_owner<=0;
       if(ble_clear_remote || ble_panic || recovery_active)playback_sent<=0;
       else if(playback_send && playback_merge_ready)playback_sent<={1'b0,playback_desired};
      end
    end
    hallpad_event_merge #(.KEY_NOTE_MAP(KEY_NOTE_MAP)) u_event_merge(
        .key_config_valid(1'b1),.key_enabled(custom_key_enabled),.key_fixed_mode(custom_fixed_mode),.key_fixed_velocity(custom_fixed_velocity),
        .clk(clk),.rst_n(sys_rst_n),.clear(recovery_active || ble_panic),.clear_remote(ble_clear_remote && !playback_owner),
        .physical_valid(event_valid && !event_state_clear && (!event_on || !panic_block_mask[event_key_id])),
        .physical_on(event_on),.physical_key(event_key_id),.physical_note(event_note_sel),.physical_velocity(event_velocity),
        .remote_valid(playback_owner ? playback_send:ble_remote_valid),.remote_ready(playback_merge_ready),.remote_snapshot(playback_owner ? 1'b1:ble_remote_snapshot),
        .remote_key(ble_remote_key),.remote_on(ble_remote_on),.remote_velocity(ble_remote_velocity),
        .remote_target_mask(playback_owner ? {1'b0,playback_desired}:ble_remote_target_mask),.remote_target_velocity(playback_owner ? playback_velocities:ble_remote_target_velocity),
        .physical_mask(merged_physical_mask),.remote_mask(remote_key_mask),.out_valid(merged_valid),.out_ready(merged_ready),
        .out_on(merged_on),.out_key(merged_key),.out_note(merged_note),.out_velocity(merged_velocity),
        .overflow(merge_overflow),.light_valid(remote_light_valid),.light_key(remote_light_key));

    key_event_fifo #(.DEPTH(FIFO_DEPTH)) u_fifo (
        .clk(clk), .rst_n(sys_rst_n), .fifo_clear(fifo_clear), .diag_clear(fifo_diag_clear),
        .in_event_valid(merged_valid && merged_ready), .in_event_on(merged_on), .in_event_key_id(merged_key),
        .in_event_note_sel(merged_note), .in_event_velocity(merged_velocity),
        .out_event_valid(queue_valid), .out_event_ready(queue_ready), .out_event_on(queue_on),
        .out_event_key_id(queue_key_id), .out_event_note_sel(queue_note_sel),
        .out_event_velocity(queue_velocity), .fifo_empty(), .fifo_full(audio_fifo_full),
        .fifo_level(), .overflow(), .overflow_sticky(overflow_sticky),
        .dropped_count()
    );

    wire [215:0] voice_note;
    wire [251:0] voice_velocity;
    wire [287:0] voice_revision;
    wire [35:0] voice_gate;
    wire engine_rst_n, bridge_input_error;
    wire overflow_fault;



    wire audio_clock_good, audio_clock_error, audio_ready;
    wire codec_restart = restart_pulse || (confirm_pulse && codec_error) || input_route_cancel;
    wire musical_hold = setup_hold || adc_fault || !codec_configured || codec_error ||
                        !audio_clock_good || (AUDIO_TEST_MODE != 0);
    wire [35:0] voice_active;
    wire engine_frame_overrun,engine_ready;
    voice_ctrl_bridge #(.VOICE_COUNT(36), .RECOVERY_CYCLES(RECOVERY_CYCLES)) u_bridge (
        .clk(clk), .rst_n(sys_rst_n),
        .event_valid(queue_valid), .event_ready(queue_ready), .event_on(queue_on),
        .event_key_id(queue_key_id), .event_note_sel(queue_note_sel), .event_velocity(queue_velocity),
        .fifo_overflow_sticky(overflow_sticky), .recover_request(musical_hold | recover_pulse | engine_frame_overrun | merge_overflow),
        .mute_request(ble_panic),
        .voice_note(voice_note), .voice_velocity(voice_velocity), .voice_gate(voice_gate),
        .voice_revision(voice_revision),
        .recovery_active(recovery_active), .engine_rst_n(engine_rst_n),
        .fifo_clear(fifo_clear), .event_state_clear(event_state_clear), .fifo_diag_clear(fifo_diag_clear),
        .input_error(bridge_input_error), .event_ignored(), .overflow_fault(overflow_fault)
    );

    wire signed [15:0] engine_pcm;
    wire signed [23:0] engine_pcm_wide;

    wire [323:0] user_envelope_gain;
    wire [35:0] user_envelope_gate;
    hallpad_key_envelope u_user_envelope(.clk(clk),.rst_n(engine_rst_n),.ms_tick(ble_ms_tick),.gates(voice_gate),.attack_ms(ble_extended_config[76:64]),.release_ms(ble_extended_config[109:96]),.gains(user_envelope_gain),.extended_gates(user_envelope_gate));
    audio_engine_top #(.USE_EXTERNAL_TICK(1),.USER_ENVELOPE(1)) u_engine (
        .key_config_valid(1'b1),.key_midi(custom_key_midi),.key_timbre(custom_key_timbre),
        .clk(clk), .rst_n(engine_rst_n), .external_sample_tick(sample_tick),
        .timbre_sel(ui_timbre_sel), .pitch_gain(pitch_gain),
        .voice_active(voice_active),.voice_note(voice_note),.voice_velocity(voice_velocity),
        .user_gain(user_envelope_gain),.voice_gate(user_envelope_gate),.voice_revision(voice_revision),
        .frame_overrun(engine_frame_overrun),.engine_ready(engine_ready),
        .active_timbre_out(engine_active_timbre),.timbre_switching(engine_timbre_switching),
        .probe_armed(response_probe_armed),.probe_key(response_probe_key),.probe_revision(response_probe_revision),.probe_rendered(response_rendered),
        .pcm_out(engine_pcm), .pcm_wide(engine_pcm_wide), .pcm_valid()
    );

    audio_clock_gen u_audio_clock (
        .clk(clk), .rst_n(sys_rst_n), .AUD_MCLK(AUD_MCLK), .clock_ready(mclk_ready)
    );

    // Test tone is deliberately independent of Hall calibration/scan health.
    // It still requires explicit AUDIO_TEST_MODE=1, codec init and live clocks.
    wire signed [15:0] test_tone;
    generate if (AUDIO_TEST_MODE == 1) begin : g_test_tone
        wire [31:0] test_phase;
        wire signed [15:0] test_sine;
        dds_phase u_test_phase (.clk(clk), .rst_n(sys_rst_n && !codec_error),
            .sample_tick(sample_tick), .note_sel(6'd20), .pitch_gain(22'd1048576), .phase_acc(test_phase));
        sine_lut u_test_sine (.phase_acc(test_phase), .sine_out(test_sine));
        assign test_tone = test_sine >>> 2;
    end else if(AUDIO_TEST_MODE == 2)begin:g_poly35_test
        poly35_selftest u_poly35_test(.clk(clk),.rst_n(sys_rst_n && !codec_error),
            .sample_tick(sample_tick),.pitch_gain(pitch_gain),.pcm_out(test_tone));
    end else begin : g_no_test_tone
        assign test_tone = 16'sd0;
    end endgenerate

    wire play_request = mclk_ready && audio_clock_good && audio_ready && !codec_error &&
                        ((AUDIO_TEST_MODE != 0) || (calibration_done && (ble_panic || (!recovery_active && engine_ready))));
    tlv320dac3100_init #(
        .RESET_HOLD_CYCLES(CODEC_RESET_HOLD_CYCLES),
        .RESET_RELEASE_CYCLES(CODEC_RESET_RELEASE_CYCLES),
        .SOFT_RESET_CYCLES(CODEC_SOFT_RESET_CYCLES),
        .PLL_SETTLE_CYCLES(CODEC_PLL_SETTLE_CYCLES),
        .ANALOG_SETTLE_CYCLES(CODEC_ANALOG_SETTLE_CYCLES),
        .RETRY_DELAY_CYCLES(CODEC_RETRY_DELAY_CYCLES),
        .DIGITAL_VOLUME(AUDIO_DIGITAL_VOLUME)
    ) u_codec (
        .clk(clk), .rst_n(sys_rst_n), .restart(codec_restart),
        .play_enable(play_request), .audio_clock_good(audio_clock_good),
        .audio_input_mask(ui_audio_input_mask),.mute_all(ble_panic),.volume_percent(ui_volume_percent),
        .route_valid(input_route_valid),.route_target_mask(input_route_target),.route_ready(input_route_ready),
        .route_done(input_route_done),.route_error(input_route_error),
        .hard_fault(audio_clock_error), .scl(AUD_SCL), .sda(AUD_SDA),
        .codec_reset_n(AUD_RESET), .configured(codec_configured),
        .playing(codec_playing), .error(codec_error), .error_code()
    );

    // Every source of frames is the returned DAC word clock, including the
    // engine/bridge tick; no independent free-running 48 kHz sample counter.
    // TX proves complete zero frames while the DAC is still digitally muted.
    // codec_playing must NOT gate this signal or it would depend on itself.
    wire audio_mute = ble_panic || !codec_configured || !mclk_ready || !audio_clock_good ||
                     codec_error || ((AUDIO_TEST_MODE == 0) && (adc_fault || recovery_active || !engine_ready));
    drumsticks_top u_drumsticks(.read_launch(drum_read_launch),.slot_abort(drum_slot_abort),
        .clk(clk),.rst_n(sys_rst_n),.audio_rst_n(engine_rst_n && !ble_panic && AUDIO_TEST_MODE==0),
        .drum_view(ui_main_view==3),.cal_request(drum_cal_local || drum_cal_remote),
        .inserted({!drum_plug_level[0],!drum_plug_level[1]}),.cal_ready(drum_cal_ready),.cal_status(drum_cal_status),
        .light_hit(drum_light_hit),.light_stick(drum_light_stick),.audio_enabled(!audio_mute && AUDIO_TEST_MODE==0 && drum_ready && !drum_frame_overrun),.ms_tick(ble_ms_tick),.sample_tick(sample_tick),.uptime_ms(device_uptime),
        .stick0_scl(DRUM0_SCL),.stick0_sda(DRUM0_SDA),.stick1_scl(DRUM1_SCL),.stick1_sda(DRUM1_SDA),
        .drum_config(drum_config),.sim_valid(drum_sim_valid),.sim_stick(drum_sim_stick),.sim_direction(drum_sim_direction),.sim_velocity(drum_sim_velocity),.sim_ready(drum_sim_ready),
        .session_valid(drum_session_valid),.session_id(drum_session_id),.telemetry_valid(drum_hit_valid),.telemetry_ready(drum_hit_ready),.telemetry_data(drum_hit_data),
        .pcm_wide(drum_pcm_wide),.pcm_valid(),.ready(drum_ready),.frame_overrun(drum_frame_overrun),.online(drum_online),.calibrated(drum_calibrated),.diagnostic_error(drum_error),.bus_error(drum_bus_error),.bus_info(drum_bus_info));
    // Preserve 24-bit headroom until the existing shared volume/limiter. Two
    // register stages keep the new adder out of the effects input critical path.
    wire signed [23:0] audible_drum_pcm=drum_frame_overrun ? 24'sd0:drum_pcm_wide;
    reg signed [24:0] keyboard_drum_sum;
    reg signed [23:0] musical_pcm;
    always @(posedge clk or negedge engine_rst_n) begin
        if(!engine_rst_n) begin keyboard_drum_sum<=0;musical_pcm<=0;end
        else begin
            keyboard_drum_sum<=$signed({engine_pcm_wide[23],engine_pcm_wide})+$signed({audible_drum_pcm[23],audible_drum_pcm});
            if(keyboard_drum_sum[24:23]==2'b01) musical_pcm<=24'sh7fffff;
            else if(keyboard_drum_sum[24:23]==2'b10) musical_pcm<=24'sh800000;
            else musical_pcm<=keyboard_drum_sum[23:0];
        end
    end
    wire signed [23:0] source_pcm = (AUDIO_TEST_MODE != 0) ? {{8{test_tone[15]}},test_tone} : musical_pcm;
    wire signed [23:0] effected_pcm;
    wire score_external_mode,score_trigger,score_accent,score_clear;
    audio_effects u_effects (.external_mode(score_external_mode),.external_trigger(score_trigger),.external_accent(score_accent),.external_clear(score_clear),.clk(clk), .rst_n(sys_rst_n && !recovery_active && !codec_error && !ble_panic), .sample_tick(sample_tick), .pcm_in(source_pcm), .echo_percent(ui_echo_percent), .metro_enable(ui_metro_enable), .metro_beats(ui_metro_beats), .metro_unit(ui_metro_unit), .metro_bpm(ui_metro_bpm), .pcm_out(effected_pcm), .beat_pulse(), .beat_accent());
    wire signed [15:0] volume_pcm;
    audio_volume u_volume (
        .clk(clk), .rst_n(sys_rst_n && !recovery_active && !codec_error && !ble_panic), .sample_tick(sample_tick),
        .volume_percent(ui_audio_input_mask==3 ? 7'd100:ui_volume_percent), .pcm_in(effected_pcm),
        .pcm_out(volume_pcm), .applied_gain()
    );
    keyboard_response_monitor u_response(
        .clk(clk),.rst_n(sys_rst_n),
        .enabled(codec_playing && !audio_mute && ui_audio_input_mask[0] && ui_volume_percent!=0 && AUDIO_TEST_MODE==0),
        .clear(fifo_clear || merge_overflow || engine_frame_overrun || ble_remote_valid),
        .trigger(event_valid && event_on && !event_state_clear && !ble_panic &&
                 custom_key_enabled[event_key_id] && !panic_block_mask[event_key_id]),
        .trigger_key(event_key_id),
        .accepted(queue_valid && queue_ready && queue_on && queue_velocity!=0),
        .accepted_key(queue_key_id),.accepted_revision(voice_revision[queue_key_id*8+:8]+8'd1),
        .rendered(response_rendered),.sample_tick(sample_tick),
        .probe_key(response_probe_key),.probe_revision(response_probe_revision),.probe_armed(response_probe_armed),
        .busy(response_busy),.valid(response_valid),.elapsed_us(response_us));
    // Shared qualified PCM tap. No return path into audio.
    wire signed [15:0] monitor_pcm=audio_mute || !codec_playing || !ui_audio_input_mask[0] ? 16'sd0:volume_pcm;
    audio_lissajous u_lissajous(
        .clk(clk),.rst_n(sys_rst_n && audio_clock_good && !codec_error),
        .enable(ui_main_view==4 && !offline_active),.sample_tick(sample_tick),
        .peak_bin_x(monitor_peak_bin_x),.peak_bin_y(monitor_peak_bin_y),
        .peak_magnitude_x(monitor_peak_magnitude_x),.peak_magnitude_y(monitor_peak_magnitude_y),
        .read_address(monitor_lissajous_address),
        .display_lock(monitor_lissajous_lock),.pixel(monitor_lissajous_pixel),
        .valid(monitor_lissajous_valid),.frame_id(monitor_lissajous_frame));
    audio_visualizer u_visualizer(
        .clk(clk),.rst_n(sys_rst_n && audio_clock_good && !codec_error),
        .sample_tick(sample_tick),.pcm_in(monitor_pcm),
        .scope_address(monitor_scope_address),.spectrum_address(monitor_spectrum_address),
        .scope_lock(monitor_scope_lock),.spectrum_lock(monitor_spectrum_lock),
        .scope_y(monitor_scope_y),.spectrum_height(monitor_spectrum_height),
        .scope_valid(monitor_scope_valid),.spectrum_valid(monitor_spectrum_valid),
        .scope_frame(monitor_scope_frame),.spectrum_frame(monitor_spectrum_frame),.analysis_overrun(),
        .peak_bin_x(monitor_peak_bin_x),.peak_bin_y(monitor_peak_bin_y),
        .peak_magnitude_x(monitor_peak_magnitude_x),.peak_magnitude_y(monitor_peak_magnitude_y));
    i2s_tx #(.CLOCK_TIMEOUT_CYCLES(AUDIO_CLOCK_TIMEOUT_CYCLES)) u_audio_tx (
        .clk(clk), .rst_n(sys_rst_n), .monitor_enable(codec_configured && !codec_restart),
        .mute(audio_mute || !ui_audio_input_mask[0]), .pcm_in(volume_pcm),
        .AUD_BCLK(AUD_BCLK), .AUD_WCLK(AUD_WCLK), .AUD_DIN(AUD_DIN),
        .sample_tick(sample_tick), .audio_ready(audio_ready),
        .clock_good(audio_clock_good), .clock_error(audio_clock_error)
    );
    hallpad_ble_top #(.SCORE_BEAT_SUPPORTED(AUDIO_TEST_MODE==0),.KEY_NOTE_MAP(KEY_NOTE_MAP),.CLK_HZ(UI_CLK_HZ),.BAUD(BLE_BAUD),.POWERUP_MS(BLE_POWERUP_MS),
        .REMOTE_KEYS_SUPPORTED(AUDIO_TEST_MODE==0),.AUDIO_MIX_SUPPORTED(AUDIO_TEST_MODE==0),.PRACTICE_SUPPORTED(AUDIO_TEST_MODE==0),.DEVICE_ID(BLE_DEVICE_ID)) u_ble(
        .practice_guide_mask(practice_guide_mask),.practice_yellow(practice_yellow),.practice_green(practice_green),.practice_red(practice_red),.practice_guide_long(practice_guide_long),
        .practice_guide_holding(practice_guide_holding),.practice_guide_armed(practice_guide_armed),
        .practice_guide_due(practice_guide_due),.practice_screen(practice_screen),.practice_countdown(practice_countdown),
        .drum_config(drum_config),.offline_auto_play(bundle_playback),.offline_auto_mask(offline_auto_mask),.offline_auto_velocity(offline_auto_velocity),.offline_busy(offline_active && offline_ui_state!=1 && offline_ui_state!=6 && offline_ui_state!=7),.offline_playback_owner(playback_owner),.offline_fixed_mode(offline_fixed_mode),.offline_fixed_velocity(offline_fixed_velocity),.offline_key_timbre(offline_key_timbre),.offline_mapping_active(offline_mapping_active),.offline_key_enabled(offline_key_enabled),.offline_key_midi(offline_key_midi),.offline_result_valid(offline_result_valid),.offline_result_packet(offline_result_packet),.offline_active(offline_active),.offline_command_valid(offline_command_valid),.offline_command_ready(offline_command_ready),.offline_command_type(offline_command_type),.offline_command_length(offline_command_length),.offline_payload_addr(offline_payload_addr),.offline_payload_data(offline_payload_data),.offline_command_done(offline_command_done),.offline_command_code(offline_command_code),.offline_run_phase(offline_run_phase),.drum_cal_status(drum_cal_status),.drum_cal_ready(drum_cal_ready),.drum_cal_request(drum_cal_remote),.drum_light_config(drum_light_config),.drum_color_config(drum_color_config),.drum_effect_config(drum_effect_config),.drum_effect_active(drum_effect_active),.drum_edit_valid(drum_edit_valid),.drum_edit_ready(drum_edit_ready),.drum_edit_stick(drum_edit_stick),.drum_edit_direction(drum_edit_direction),.drum_edit_up(drum_edit_up),.drum_allowed(!audio_mute && AUDIO_TEST_MODE==0 && drum_ready && !drum_frame_overrun),.drum_sim_valid(drum_sim_valid),.drum_sim_ready(drum_sim_ready),.drum_sim_stick(drum_sim_stick),.drum_sim_direction(drum_sim_direction),.drum_sim_velocity(drum_sim_velocity),
        .drum_hit_valid(drum_hit_valid),.drum_hit_ready(drum_hit_ready),.drum_hit_data(drum_hit_data),.drum_session_valid(drum_session_valid),.drum_session_id(drum_session_id),.device_uptime(device_uptime),
        .clk(clk),.rst_n(sys_rst_n),.uart_rx(BLE_UART_RX),.uart_tx(BLE_UART_TX),.adc_valid(key_valid),.adc_key(key_id),.adc_value(key_raw_data),.extended_config(ble_extended_config),.remote_bend(ble_bend),.remote_modulation(ble_modulation),
        .key_enabled(saved_key_enabled),.key_fixed_mode(saved_fixed_mode),.key_midi(saved_key_midi),.key_fixed_velocity(saved_fixed_velocity),.key_timbre(saved_key_timbre),.config_data(ui_config_data),.config_revision(ui_config_revision),.parameter_ready(ble_parameter_ready),.parameter_done(ble_parameter_done),.parameter_error(ble_parameter_error),
        .parameter_commit(ble_parameter_commit),.parameter_data(ble_parameter_data),
        .sd_bridge_allowed(sd_bridge_allowed),.sd_block_ready(sd_ready),.sd_block_done(sd_done),.sd_block_error(sd_error),
        .sd_locked(sd_locked),.sd_remount(sd_remount),.sd_bridge_read(sd_bridge_read),.sd_bridge_write(sd_bridge_write),.sd_bridge_lba(sd_bridge_lba),
        .sd_read_valid(sd_read_valid),.sd_read_address(sd_read_address),.sd_read_byte(sd_read_byte),.sd_write_address(sd_write_address),.sd_write_byte(sd_write_byte),
        .score_sample_tick(sample_tick),.score_audio_available(AUDIO_TEST_MODE==0 && codec_playing && audio_clock_good && !audio_mute && !recovery_active && !codec_error),.score_external_mode(score_external_mode),.score_trigger(score_trigger),.score_accent(score_accent),.score_clear(score_clear),
        .remote_allowed(calibration_done && !musical_hold && !recovery_active && !ble_panic),
        .remote_valid(ble_remote_valid),.remote_ready(ble_remote_ready),.remote_snapshot(ble_remote_snapshot),
        .remote_key(ble_remote_key),.remote_on(ble_remote_on),.remote_velocity(ble_remote_velocity),
        .remote_target_mask(ble_remote_target_mask),.remote_target_velocity(ble_remote_target_velocity),
        .clear_remote(ble_clear_remote),.panic_latched(ble_panic),
        .physical_key_mask(physical_key_mask),.remote_key_mask(remote_key_mask),.voice_active(voice_active),
        .state_flags({18'd0,!drum_plug_level[0],!drum_plug_level[1],drum_calibrated,drum_online,engine_timbre_switching,engine_ready,recovery_active,calibration_done,audio_clock_good,codec_playing,codec_configured,1'b0}),
        .error_bits({23'd0,drum_frame_overrun,drum_error,1'b0,engine_frame_overrun,(overflow_sticky || merge_overflow),(event_input_error || bridge_input_error),((|filtered_tag_error) || map_error),audio_clock_error,codec_error}),
        .audio_source(AUDIO_TEST_MODE!=0 ? 8'd2:ui_audio_input_mask==2 ? 8'd1:8'd0),.active_timbre({12'd0,engine_active_timbre}),.rx_overflow(ble_rx_overflow));
    assign PA_EN = 1'b1;

    // Isolated bad ADC samples do not invent OFF events. The stream guard
    // mutes/restarts after sustained loss; diagnostic history stays visible
    // until a button acknowledges it, with same-edge new errors taking priority.
    always @(posedge clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            diagnostic_fault <= 1'b0;
        else if ((|filtered_tag_error) || map_error || event_input_error || bridge_input_error || merge_overflow || light_tap_overflow)
            diagnostic_fault <= 1'b1;
        else if (confirm_pulse || restart_pulse)
            diagnostic_fault <= 1'b0;
    end
    keyboard_status_led u_status_led (
        .clk(clk), .rst_n(sys_rst_n),
        .ui_state((AUDIO_TEST_MODE != 0) ? ((audio_ready && codec_playing) ? 3'd5 : 3'd2) :
                  ((calibration_done && !(audio_ready && codec_playing)) ? 3'd2 : ui_state)),
        .fault(adc_fault | diagnostic_fault | controller_error | overflow_sticky | overflow_fault |
               codec_error | audio_clock_error),
        .WS2812(WS2812)
    );

endmodule

// Configuration-time initialized counter guarantees reset even if the reset
// pin is already high when the FPGA starts. External reset still asserts
// immediately; all consumers leave reset synchronously after a 10 ms hold.
module keyboard_startup_reset #(parameter integer HOLD_CYCLES=500000)(
    input wire clk,external_rst_n,output wire sys_rst_n
);
    localparam integer CW=HOLD_CYCLES<2 ? 1 : $clog2(HOLD_CYCLES+1);
    reg [CW-1:0] startup_count=0;
    (* syn_preserve = 1, syn_async_reg = "true" *) reg [1:0] external_sync=0;
    always @(posedge clk or negedge external_rst_n)begin
        if(!external_rst_n)external_sync<=0;
        else external_sync<={external_sync[0],1'b1};
    end
    (* syn_preserve = 1 *) reg [1:0] reset_sync=0;
    assign sys_rst_n=reset_sync[1];
    always @(posedge clk or negedge external_rst_n)begin
        if(!external_rst_n)begin startup_count<=0;reset_sync<=0;end
        else if(!external_sync[1])begin startup_count<=0;reset_sync<=0;end
        else if(startup_count<HOLD_CYCLES)begin
            startup_count<=startup_count+1'b1;reset_sync<=0;
        end else reset_sync<={reset_sync[0],1'b1};
    end

endmodule
