/**
 * RoboCore-1 HAL Usage Example
 * 
 * Example: 4-axis robot arm controller
 * - 4 joints, each with encoder feedback and PID position control
 * - CAN FD for command/status with controller
 * - EtherCAT for real-time sync with master
 * - DMA for zero-copy process data updates
 */

#define ROBOCORE_HAL_IMPLEMENTATION
#include "robocore1_hal.h"

/* ---- Application Configuration ---- */
#define NUM_JOINTS      4
#define PWM_PERIOD      10000   /* 10kHz PWM */
#define CAN_CMD_ID      0x100   /* Command frame ID */
#define CAN_STATUS_ID   0x101   /* Status frame ID */

/* Joint state */
static int32_t  joint_target[NUM_JOINTS];
static int32_t  joint_position[NUM_JOINTS];
static int32_t  joint_output[NUM_JOINTS];

/* PID tuning for each joint */
static const rc1_pid_config_t joint_pid[NUM_JOINTS] = {
    { .kp = 1000, .ki = 100, .kd = 50,  .out_max = 8000 },  /* Joint 0 */
    { .kp = 1200, .ki = 120, .kd = 60,  .out_max = 8000 },  /* Joint 1 */
    { .kp = 800,  .ki = 80,  .kd = 40,  .out_max = 8000 },  /* Joint 2 */
    { .kp = 600,  .ki = 60,  .kd = 30,  .out_max = 8000 },  /* Joint 3 */
};

/* ---- IRQ Handler ---- */
void irq_handler(void) {
    uint16_t irq = rc1_irq_get_active();

    /* CAN RX — receive position commands from controller */
    if (irq & RC1_IRQ_CAN_RX) {
        rc1_can_frame_t frame;
        if (rc1_can_recv(&frame) == RC1_OK) {
            if (frame.id == CAN_CMD_ID && frame.dlc == 8) {
                /* 4 joints × 2 bytes each = 8 bytes */
                for (int i = 0; i < NUM_JOINTS; i++) {
                    joint_target[i] = (int16_t)(frame.data[i*2] |
                                               (frame.data[i*2+1] << 8));
                    rc1_pid_set_target(i, joint_target[i]);
                }
            }
        }
    }

    /* E-stop — safe state entered */
    if (irq & RC1_IRQ_ESTOP) {
        /* Set all PWM to 0 immediately */
        for (int i = 0; i < NUM_JOINTS; i++)
            rc1_pwm_set_duty(i, 0);
        rc1_pid_disable(0xFF);
    }

    /* CAN bus-off — attempt recovery */
    if (irq & RC1_IRQ_CAN_BUSOFF) {
        /* Log fault, wait for bus recovery */
    }

    rc1_irq_clear(irq);
    rc1_wd_pet(0xF);
}

/* ---- Send status over CAN ---- */
static void send_status(void) {
    uint8_t data[8];
    for (int i = 0; i < NUM_JOINTS; i++) {
        int16_t pos = (int16_t)joint_position[i];
        data[i*2]   = pos & 0xFF;
        data[i*2+1] = (pos >> 8) & 0xFF;
    }
    rc1_can_send_simple(CAN_STATUS_ID, data, 8);
}

/* ---- Main ---- */
int main(void) {
    rc1_err_t err;

    /* 1. Initialize HAL — verify chip, enable watchdogs */
    err = rc1_init();
    if (err != RC1_OK) {
        /* Boot failed — halt */
        while (1) {}
    }

    /* 2. Configure PWM — all joints to 0% duty */
    for (int i = 0; i < NUM_JOINTS; i++) {
        rc1_pwm_set(i, PWM_PERIOD, 0);
    }

    /* 3. Clear encoder positions */
    for (int i = 0; i < NUM_JOINTS; i++) {
        rc1_enc_clear_position(i);
    }

    /* 4. Configure PID for each joint */
    for (int i = 0; i < NUM_JOINTS; i++) {
        rc1_pid_configure(i, &joint_pid[i]);
        rc1_pid_set_target(i, 0);
    }

    /* 5. Enable PID channels 0-3 */
    rc1_pid_enable(0x0F);

    /* 6. Setup DMA for EtherCAT process data
     *    EtherCAT SYNC0 triggers automatic encoder→PD copy
     *    No CPU involvement in the real-time data path */
    rc1_dma_setup_ethercat_cycle(
        0,                          /* DMA channel 0 */
        RC1_BASE_ENC + 0x04,        /* src: encoder position register */
        RC1_BASE_EC  + 0x10,        /* dst: EtherCAT PD write data */
        NUM_JOINTS                  /* len: 4 words */
    );

    /* 7. Enable IRQs */
    rc1_irq_enable(RC1_IRQ_CAN_RX | RC1_IRQ_ESTOP | RC1_IRQ_CAN_BUSOFF);

    /* 8. Main loop — read back positions and send CAN status */
    uint32_t loop_count = 0;
    while (1) {
        /* Pet watchdog every loop */
        rc1_wd_pet(0xF);

        /* Read encoder positions */
        for (int i = 0; i < NUM_JOINTS; i++) {
            rc1_enc_get_position(i, &joint_position[i]);
        }

        /* Read PID outputs — feed to PWM */
        for (int i = 0; i < NUM_JOINTS; i++) {
            rc1_pid_get_output(i, &joint_output[i]);
            uint32_t duty = (uint32_t)(joint_output[i] < 0 ?
                            -joint_output[i] : joint_output[i]);
            if (duty > PWM_PERIOD) duty = PWM_PERIOD;
            rc1_pwm_set_duty(i, duty);
        }

        /* Send CAN status every 10 loops (~10ms) */
        if (loop_count % 10 == 0) {
            send_status();
        }

        loop_count++;

        /* Simple delay — 1ms */
        for (volatile int d = 0; d < 10000; d++) {}
    }

    return 0;
}
